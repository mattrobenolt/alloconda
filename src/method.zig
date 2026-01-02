const std = @import("std");
const builtin = std.builtin;
const fmt = std.fmt;
const mem = std.mem;
const meta = std.meta;

const errors = @import("errors.zig");
const PyError = errors.PyError;
const ffi = @import("ffi.zig");
const c = ffi.c;
const cstr = ffi.cstr;
const cPtr = ffi.cPtr;
const pyNoneOwned = ffi.pyNoneOwned;
const PyErr = ffi.PyErr;
const PyTuple = ffi.PyTuple;
const PyDict = ffi.PyDict;
const PyUnicode = ffi.PyUnicode;
const types = @import("types.zig");
const Object = types.Object;
const fromPy = types.fromPy;
const toPy = types.toPy;
const isOptionalType = types.isOptionalType;

/// Kinds of Python method bindings.
pub const MethodKind = enum {
    function,
    instance,
    classmethod,
    staticmethod,

    pub fn includesSelf(kind: @This()) bool {
        return switch (kind) {
            .instance, .classmethod => true,
            .function, .staticmethod => false,
        };
    }
};

/// Options for configuring a Python method binding.
pub const MethodOptions = struct {
    name: ?[:0]const u8 = null,
    doc: ?[:0]const u8 = null,
    args: ?[]const [:0]const u8 = null,

    pub const init: @This() = .{};
};

/// Wrap a Zig function as a Python function.
pub fn function(
    comptime func: anytype,
    comptime options: MethodOptions,
) MethodSpec(@TypeOf(func), .function) {
    return .{
        .func = func,
        .options = options,
    };
}

/// Wrap a Zig function as a Python instance method.
pub fn method(
    comptime func: anytype,
    comptime options: MethodOptions,
) MethodSpec(@TypeOf(func), .instance) {
    return .{
        .func = func,
        .options = options,
    };
}

/// Wrap a Zig function as a Python classmethod.
pub fn classmethod(
    comptime func: anytype,
    comptime options: MethodOptions,
) MethodSpec(@TypeOf(func), .classmethod) {
    return .{
        .func = func,
        .options = options,
    };
}

/// Wrap a Zig function as a Python staticmethod.
pub fn staticmethod(
    comptime func: anytype,
    comptime options: MethodOptions,
) MethodSpec(@TypeOf(func), .staticmethod) {
    return .{
        .func = func,
        .options = options,
    };
}

fn MethodSpec(comptime Func: type, comptime method_kind: MethodKind) type {
    return struct {
        pub const is_method_spec = true;
        pub const kind = method_kind;
        func: Func,
        options: MethodOptions = .init,
    };
}

/// Build an array of PyMethodDef from a struct of methods.
pub fn buildMethodDefs(comptime methods: anytype) [methodCount(methods) + 1]c.PyMethodDef {
    @setEvalBranchQuota(100000);
    const info = @typeInfo(@TypeOf(methods));
    if (info != .@"struct") {
        @compileError("methods must be a struct literal");
    }

    const fields = info.@"struct".fields;
    var defs: [fields.len + 1]c.PyMethodDef = undefined;

    inline for (fields, 0..) |field, i| {
        const spec = @field(methods, field.name);
        const Func = @TypeOf(spec.func);
        const kind = @TypeOf(spec).kind;
        defs[i] = buildMethodDef(field.name, Func, kind, spec);
    }

    defs[fields.len] = .{ .ml_name = null, .ml_meth = null, .ml_flags = 0, .ml_doc = null };
    return defs;
}

/// Build a tp_call slot for a __call__ method spec.
pub fn callSlotFromSpec(
    comptime Func: type,
    comptime kind: MethodKind,
    comptime spec: MethodSpec(Func, kind),
) ?*anyopaque {
    if (kind != .instance) {
        @compileError("__call__ must be defined with alloconda.method");
    }

    const func = spec.func;
    const options = spec.options;
    validateArgNames(func, options.args, true);

    const Wrapper = CallWrapperType(func, options.args, true);
    return @ptrCast(@constCast(&Wrapper.call));
}

fn buildMethodDef(
    comptime field_name: []const u8,
    comptime Func: type,
    comptime kind: MethodKind,
    comptime spec: MethodSpec(Func, kind),
) c.PyMethodDef {
    const func = spec.func;
    const options = spec.options;
    if (@typeInfo(@TypeOf(func)) != .@"fn") {
        @compileError("method func must be a function");
    }

    const name = options.name orelse cstr(field_name);
    const include_self = kind.includesSelf();
    validateArgNames(func, options.args, include_self);
    const Wrapper = WrapperType(func, options.args, include_self);

    return .{
        .ml_name = name,
        .ml_meth = @ptrCast(&Wrapper.call),
        .ml_flags = methodFlags(func, options.args, kind),
        .ml_doc = cPtr(options.doc),
    };
}

fn CallWrapperType(
    comptime func: anytype,
    comptime arg_names: ?[]const [:0]const u8,
    comptime include_self: bool,
) type {
    return struct {
        fn call(
            self: ?*c.PyObject,
            args: ?*c.PyObject,
            kwargs: ?*c.PyObject,
        ) callconv(.c) ?*c.PyObject {
            if (arg_names) |names| {
                return callImplKw(func, self, args, kwargs, names, include_self) catch |err| {
                    errors.setPythonError(err);
                    return null;
                };
            }

            if (kwargs) |kw| {
                var pos: c.Py_ssize_t = 0;
                if (PyDict.next(kw, &pos)) |entry| {
                    const key_slice = PyUnicode.slice(entry.key) catch |err| {
                        errors.setPythonError(err);
                        return null;
                    };
                    errors.setPythonError(setUnexpectedKeywordError(key_slice));
                    return null;
                }
            }

            return callImpl(func, self, args, include_self) catch |err| {
                errors.setPythonError(err);
                return null;
            };
        }
    };
}

fn WrapperType(
    comptime func: anytype,
    comptime arg_names: ?[]const [:0]const u8,
    comptime include_self: bool,
) type {
    const has_keywords = arg_names != null;
    if (has_keywords) {
        return struct {
            fn call(
                self: ?*c.PyObject,
                args: ?*c.PyObject,
                kwargs: ?*c.PyObject,
            ) callconv(.c) ?*c.PyObject {
                return callImplKw(func, self, args, kwargs, arg_names.?, include_self) catch |err| {
                    errors.setPythonError(err);
                    return null;
                };
            }
        };
    }
    return struct {
        fn call(
            self: ?*c.PyObject,
            args: ?*c.PyObject,
        ) callconv(.c) ?*c.PyObject {
            return callImpl(func, self, args, include_self) catch |err| {
                errors.setPythonError(err);
                return null;
            };
        }
    };
}

fn methodFlags(
    comptime func: anytype,
    comptime arg_names: ?[]const [:0]const u8,
    comptime kind: MethodKind,
) c_int {
    const fn_info = @typeInfo(@TypeOf(func)).@"fn";
    const include_self = kind.includesSelf();
    const arg_count = if (include_self) fn_info.params.len - 1 else fn_info.params.len;
    const base = if (arg_count == 0 and arg_names == null) c.METH_NOARGS else c.METH_VARARGS;
    var flags: c_int = if (arg_names == null) base else base | c.METH_KEYWORDS;
    switch (kind) {
        .classmethod => flags |= c.METH_CLASS,
        .staticmethod => flags |= c.METH_STATIC,
        else => {},
    }
    return flags;
}

fn callImpl(
    comptime func: anytype,
    self_obj: ?*c.PyObject,
    args: ?*c.PyObject,
    comptime include_self: bool,
) PyError!?*c.PyObject {
    const fn_info = @typeInfo(@TypeOf(func)).@"fn";
    const params = fn_info.params;

    const ParamTypes = comptime paramTypes(params);
    const arg_offset: usize = if (include_self) 1 else 0;
    const arg_count = params.len - arg_offset;

    if (arg_count == 0) {
        var tuple: meta.Tuple(ParamTypes) = undefined;
        if (include_self) {
            const self_val = try fromPy(ParamTypes[0], self_obj);
            tuple[0] = self_val;
        }
        return callAndConvert(func, tuple);
    }

    const ArgTypes = comptime argTypes(ParamTypes, arg_offset);
    const min_args = comptime requiredParamCount(ArgTypes);
    const max_args = ArgTypes.len;

    const args_obj = args;
    const got: usize = if (args_obj) |obj| try PyTuple.size(obj) else 0;

    if (got < min_args or got > max_args) {
        return setArgCountError(min_args, max_args, got);
    }

    var tuple: meta.Tuple(ParamTypes) = undefined;
    if (include_self) {
        const self_val = try fromPy(ParamTypes[0], self_obj);
        tuple[0] = self_val;
    }

    inline for (ArgTypes, 0..) |T, i| {
        const param_index = i + arg_offset;
        if (i < got) {
            const item = try PyTuple.getItem(args_obj.?, i);
            const value = try fromPy(T, item);
            tuple[param_index] = value;
        } else {
            if (comptime isOptionalType(T)) {
                tuple[param_index] = null;
            } else {
                return setArgCountError(min_args, max_args, got);
            }
        }
    }

    return callAndConvert(func, tuple);
}

fn callImplKw(
    comptime func: anytype,
    self_obj: ?*c.PyObject,
    args: ?*c.PyObject,
    kwargs: ?*c.PyObject,
    comptime arg_names: []const [:0]const u8,
    comptime include_self: bool,
) PyError!?*c.PyObject {
    const fn_info = @typeInfo(@TypeOf(func)).@"fn";
    const params = fn_info.params;

    const ParamTypes = comptime paramTypes(params);
    const arg_offset: usize = if (include_self) 1 else 0;
    const ArgTypes = comptime argTypes(ParamTypes, arg_offset);
    const min_args = comptime requiredParamCount(ArgTypes);

    if (ArgTypes.len != arg_names.len) {
        @compileError("arg_names must match parameter count");
    }

    var tuple: meta.Tuple(ParamTypes) = undefined;
    if (include_self) {
        const self_val = try fromPy(ParamTypes[0], self_obj);
        tuple[0] = self_val;
    }

    var values: [ArgTypes.len]?*c.PyObject = .{null} ** ArgTypes.len;
    var filled: [ArgTypes.len]bool = .{false} ** ArgTypes.len;

    const args_obj = args;
    const got: usize = if (args_obj) |obj| try PyTuple.size(obj) else 0;

    if (got > ArgTypes.len) {
        return setArgCountError(min_args, ArgTypes.len, got);
    }

    for (values[0..got], 0..) |*slot, i| {
        const item = try PyTuple.getItem(args_obj.?, i);
        slot.* = item;
        filled[i] = true;
    }

    if (kwargs) |kw| {
        var pos: c.Py_ssize_t = 0;
        while (PyDict.next(kw, &pos)) |entry| {
            const key_slice = try PyUnicode.slice(entry.key);
            var matched = false;

            inline for (arg_names, 0..) |name, i| {
                if (mem.eql(u8, key_slice, name)) {
                    if (filled[i]) {
                        return setDuplicateArgError(name);
                    }
                    values[i] = entry.value;
                    filled[i] = true;
                    matched = true;
                    break;
                }
            }

            if (!matched) {
                return setUnexpectedKeywordError(key_slice);
            }
        }
    }

    inline for (ArgTypes, 0..) |T, i| {
        const param_index = i + arg_offset;
        if (values[i]) |item| {
            const value = try fromPy(T, item);
            tuple[param_index] = value;
        } else if (comptime isOptionalType(T)) {
            tuple[param_index] = null;
        } else {
            return setMissingArgError(arg_names[i]);
        }
    }

    return callAndConvert(func, tuple);
}

fn callAndConvert(comptime func: anytype, args_tuple: anytype) ?*c.PyObject {
    const fn_info = @typeInfo(@TypeOf(func)).@"fn";
    const ret_type = fn_info.return_type orelse @compileError("method must return a value");
    const ret_info = @typeInfo(ret_type);

    if (ret_info == .error_union) {
        const payload = ret_info.error_union.payload;
        if (payload == void) {
            _ = @call(.auto, func, args_tuple) catch |err| {
                errors.setPythonError(err);
                return null;
            };
            return pyNoneOwned();
        }

        const value = @call(.auto, func, args_tuple) catch |err| {
            errors.setPythonError(err);
            return null;
        };
        return toPy(payload, value) catch |err| {
            errors.setPythonError(err);
            return null;
        };
    }

    if (ret_info == .error_set) {
        const err = @call(.auto, func, args_tuple);
        errors.setPythonError(err);
        return null;
    }

    if (ret_type == void) {
        _ = @call(.auto, func, args_tuple);
        return pyNoneOwned();
    }

    const value = @call(.auto, func, args_tuple);
    // Optional return values cannot signal errors; enforce error unions instead.
    if (comptime isOptionalType(ret_type)) {
        if (value == null and errors.errorOccurred()) {
            PyErr.clear();
            errors.setError(.RuntimeError, "optional returns cannot signal errors; use PyError!T");
            return null;
        }
    }
    return toPy(ret_type, value) catch |err| {
        errors.setPythonError(err);
        return null;
    };
}

// ============================================================================
// Compile-time helpers
// ============================================================================

fn paramTypes(comptime params: []const builtin.Type.Fn.Param) []const type {
    var result: [params.len]type = undefined;
    inline for (params, 0..) |param, i| {
        result[i] = param.type orelse @compileError("method parameters must have a type");
    }
    return result[0..];
}

fn argTypes(comptime all_types: []const type, comptime offset: usize) []const type {
    if (offset > all_types.len) {
        @compileError("argument offset out of range");
    }
    return all_types[offset..];
}

fn validateArgNames(
    comptime func: anytype,
    comptime arg_names: ?[]const [:0]const u8,
    comptime include_self: bool,
) void {
    const params = @typeInfo(@TypeOf(func)).@"fn".params;

    if (include_self) {
        if (params.len == 0) {
            @compileError("include_self requires a self parameter");
        }
        const self_type = params[0].type orelse @compileError("self parameter must have a type");
        if (!isSelfParam(self_type)) {
            @compileError("self parameter must be alloconda.Object or ?alloconda.Object");
        }
    }

    if (arg_names) |names| {
        const expected = if (include_self) params.len - 1 else params.len;
        if (names.len != expected) {
            @compileError("arg_names must match parameter count");
        }

        inline for (names, 0..) |name, i| {
            if (name.len == 0) {
                @compileError("arg_names entries must be non-empty");
            }
            inline for (names[0..i]) |prev| {
                if (mem.eql(u8, name, prev)) {
                    @compileError("arg_names entries must be unique");
                }
            }
        }
    }
}

fn isSelfParam(comptime T: type) bool {
    if (T == Object) return true;
    if (isOptionalType(T)) return @typeInfo(T).optional.child == Object;
    return false;
}

pub fn requiredParamCount(comptime param_types: []const type) usize {
    var first_optional: ?usize = null;
    inline for (param_types, 0..) |T, i| {
        if (isOptionalType(T)) {
            if (first_optional == null) {
                first_optional = i;
            }
        } else if (first_optional != null) {
            @compileError("optional parameters must be trailing");
        }
    }
    return first_optional orelse param_types.len;
}

pub fn methodCount(comptime methods: anytype) usize {
    const info = @typeInfo(@TypeOf(methods));
    if (info != .@"struct") {
        @compileError("methods must be a struct literal");
    }
    return info.@"struct".fields.len;
}

// ============================================================================
// Error message helpers
// ============================================================================

fn setArgCountError(min_expected: usize, max_expected: usize, got: usize) PyError {
    var buf: [128]u8 = undefined;
    const fallback: [:0]const u8 = "argument count mismatch";
    const msg = if (min_expected == max_expected)
        fmt.bufPrintZ(
            &buf,
            "expected {d} arguments, got {d}",
            .{ min_expected, got },
        ) catch fallback
    else
        fmt.bufPrintZ(
            &buf,
            "expected {d} to {d} arguments, got {d}",
            .{ min_expected, max_expected, got },
        ) catch fallback;
    return errors.raise(.TypeError, msg);
}

fn setDuplicateArgError(name: []const u8) PyError {
    var buf: [128]u8 = undefined;
    const fallback: [:0]const u8 = "duplicate argument";
    const msg = fmt.bufPrintZ(
        &buf,
        "got multiple values for argument '{s}'",
        .{name},
    ) catch fallback;
    return errors.raise(.TypeError, msg);
}

fn setMissingArgError(name: []const u8) PyError {
    var buf: [128]u8 = undefined;
    const fallback: [:0]const u8 = "missing required argument";
    const msg = fmt.bufPrintZ(
        &buf,
        "missing required argument '{s}'",
        .{name},
    ) catch fallback;
    return errors.raise(.TypeError, msg);
}

fn setUnexpectedKeywordError(name: []const u8) PyError {
    var buf: [128]u8 = undefined;
    const fallback: [:0]const u8 = "unexpected keyword argument";
    const msg = fmt.bufPrintZ(
        &buf,
        "got unexpected keyword argument '{s}'",
        .{name},
    ) catch fallback;
    return errors.raise(.TypeError, msg);
}
