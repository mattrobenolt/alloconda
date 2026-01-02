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
const pyNotImplementedOwned = ffi.pyNotImplementedOwned;
const PyErr = ffi.PyErr;
const PyObject = ffi.PyObject;
const PyLong = ffi.PyLong;
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

/// Build a tp_new slot for a __new__ method spec.
pub fn newSlotFromSpec(
    comptime Func: type,
    comptime kind: MethodKind,
    comptime spec: MethodSpec(Func, kind),
) ?*anyopaque {
    validateNewSpec(Func, kind, spec, "__new__");
    const Wrapper = NewWrapperType(spec.func, spec.options.args);
    return @ptrCast(@constCast(&Wrapper.call));
}

/// Build a tp_finalize/tp_del slot for a __del__ method spec.
pub fn delSlotFromSpec(
    comptime Func: type,
    comptime kind: MethodKind,
    comptime spec: MethodSpec(Func, kind),
) ?*anyopaque {
    validateUnarySpec(Func, kind, spec, "__del__");
    const Wrapper = DelWrapperType(spec.func);
    return @ptrCast(@constCast(&Wrapper.call));
}

/// Build a tp_init slot for a __init__ method spec.
pub fn initSlotFromSpec(
    comptime Func: type,
    comptime kind: MethodKind,
    comptime spec: MethodSpec(Func, kind),
) ?*anyopaque {
    validateInitSpec(Func, kind, spec, "__init__");
    const Wrapper = InitWrapperType(spec.func, spec.options.args);
    return @ptrCast(@constCast(&Wrapper.call));
}

/// Build a tp_getattro slot from __getattribute__/__getattr__ specs.
pub fn getAttrSlotFromSpecs(comptime Specs: type) ?*anyopaque {
    const has_any = comptime hasSpec(Specs.getattribute) or hasSpec(Specs.getattr);
    if (!has_any) return null;
    validateGetAttrSpecs(Specs);
    const Wrapper = GetAttrWrapperType(Specs);
    return @ptrCast(@constCast(&Wrapper.call));
}

/// Build a tp_setattro slot from __setattr__/__delattr__ specs.
pub fn setAttrSlotFromSpecs(comptime Specs: type) ?*anyopaque {
    const has_any = comptime hasSpec(Specs.set) or hasSpec(Specs.del);
    if (!has_any) return null;
    validateSetAttrSpecs(Specs);
    const Wrapper = SetAttrWrapperType(Specs);
    return @ptrCast(@constCast(&Wrapper.call));
}

/// Build a tp_descr_get slot for a __get__ method spec.
pub fn descrGetSlotFromSpec(
    comptime Func: type,
    comptime kind: MethodKind,
    comptime spec: MethodSpec(Func, kind),
    comptime name: []const u8,
) ?*anyopaque {
    validateTernarySpec(Func, kind, spec, name);
    const Wrapper = DescrGetWrapperType(spec.func);
    return @ptrCast(@constCast(&Wrapper.call));
}

/// Build a tp_descr_set slot from __set__/__delete__ specs.
pub fn descrSetSlotFromSpecs(comptime Specs: type) ?*anyopaque {
    const has_any = comptime hasSpec(Specs.set) or hasSpec(Specs.del);
    if (!has_any) return null;
    validateDescrSpecs(Specs);
    const Wrapper = DescrSetWrapperType(Specs);
    return @ptrCast(@constCast(&Wrapper.call));
}

/// Build a unary slot (self) that returns a Python object.
pub fn unarySlotFromSpec(
    comptime Func: type,
    comptime kind: MethodKind,
    comptime spec: MethodSpec(Func, kind),
    comptime name: []const u8,
) ?*anyopaque {
    validateUnarySpec(Func, kind, spec, name);
    const Wrapper = UnaryWrapperType(spec.func);
    return @ptrCast(@constCast(&Wrapper.call));
}

/// Build a binary slot (self, arg) that returns a Python object.
pub fn binarySlotFromSpec(
    comptime Func: type,
    comptime kind: MethodKind,
    comptime spec: MethodSpec(Func, kind),
    comptime name: []const u8,
) ?*anyopaque {
    validateBinarySpec(Func, kind, spec, name);
    const Wrapper = BinaryWrapperType(spec.func);
    return @ptrCast(@constCast(&Wrapper.call));
}

/// Build a __len__-style slot (self) that returns Py_ssize_t.
pub fn lenSlotFromSpec(
    comptime Func: type,
    comptime kind: MethodKind,
    comptime spec: MethodSpec(Func, kind),
    comptime name: []const u8,
) ?*anyopaque {
    validateUnarySpec(Func, kind, spec, name);
    const Wrapper = LenWrapperType(spec.func);
    return @ptrCast(@constCast(&Wrapper.call));
}

/// Build a __hash__-style slot (self) that returns Py_hash_t.
pub fn hashSlotFromSpec(
    comptime Func: type,
    comptime kind: MethodKind,
    comptime spec: MethodSpec(Func, kind),
    comptime name: []const u8,
) ?*anyopaque {
    validateUnarySpec(Func, kind, spec, name);
    const Wrapper = HashWrapperType(spec.func);
    return @ptrCast(@constCast(&Wrapper.call));
}

/// Build a __bool__-style slot (self) that returns c_int.
pub fn boolSlotFromSpec(
    comptime Func: type,
    comptime kind: MethodKind,
    comptime spec: MethodSpec(Func, kind),
    comptime name: []const u8,
) ?*anyopaque {
    validateUnarySpec(Func, kind, spec, name);
    const Wrapper = BoolWrapperType(spec.func);
    return @ptrCast(@constCast(&Wrapper.call));
}

/// Build a __contains__-style slot (self, value) that returns c_int.
pub fn boolBinarySlotFromSpec(
    comptime Func: type,
    comptime kind: MethodKind,
    comptime spec: MethodSpec(Func, kind),
    comptime name: []const u8,
) ?*anyopaque {
    validateBinarySpec(Func, kind, spec, name);
    const Wrapper = BoolBinaryWrapperType(spec.func);
    return @ptrCast(@constCast(&Wrapper.call));
}

/// Build a ternary slot (self, arg0, arg1) that returns a Python object.
pub fn powSlotFromSpec(
    comptime Func: type,
    comptime kind: MethodKind,
    comptime spec: MethodSpec(Func, kind),
    comptime name: []const u8,
) ?*anyopaque {
    validateTernarySpec(Func, kind, spec, name);
    const Wrapper = PowWrapperType(spec.func);
    return @ptrCast(@constCast(&Wrapper.call));
}

/// Build a sequence item slot (self, index) that returns a Python object.
pub fn seqItemSlotFromSpec(
    comptime Func: type,
    comptime kind: MethodKind,
    comptime spec: MethodSpec(Func, kind),
    comptime name: []const u8,
) ?*anyopaque {
    validateBinarySpec(Func, kind, spec, name);
    const Wrapper = SeqItemWrapperType(spec.func);
    return @ptrCast(@constCast(&Wrapper.call));
}

/// Build a sequence repeat slot (self, count) that returns a Python object.
pub fn seqRepeatSlotFromSpec(
    comptime Func: type,
    comptime kind: MethodKind,
    comptime spec: MethodSpec(Func, kind),
    comptime name: []const u8,
) ?*anyopaque {
    validateBinarySpec(Func, kind, spec, name);
    const Wrapper = SeqRepeatWrapperType(spec.func);
    return @ptrCast(@constCast(&Wrapper.call));
}

/// Build a sequence assign slot (self, index, value) for set/del.
pub fn seqAssItemSlotFromSpecs(comptime Specs: type) ?*anyopaque {
    const has_any = comptime hasSpec(Specs.set) or hasSpec(Specs.del);
    if (!has_any) return null;
    validateSequenceSpecs(Specs);
    const Wrapper = SeqAssItemWrapperType(Specs);
    return @ptrCast(@constCast(&Wrapper.call));
}

/// Build a tp_richcompare slot from a set of comparison method specs.
pub fn richCompareSlotFromSpecs(comptime Specs: type) ?*anyopaque {
    const has_any = comptime hasSpec(Specs.eq) or hasSpec(Specs.ne) or hasSpec(Specs.lt) or
        hasSpec(Specs.le) or hasSpec(Specs.gt) or hasSpec(Specs.ge);
    if (!has_any) return null;
    validateCompareSpecs(Specs);
    const Wrapper = RichCompareWrapperType(Specs);
    return @ptrCast(@constCast(&Wrapper.call));
}

pub const MappingSlots = struct {
    length: ?*anyopaque = null,
    subscript: ?*anyopaque = null,
    ass_subscript: ?*anyopaque = null,
};

pub const NumberSlots = struct {
    add: ?*anyopaque = null,
    sub: ?*anyopaque = null,
    mul: ?*anyopaque = null,
    truediv: ?*anyopaque = null,
    floordiv: ?*anyopaque = null,
    mod: ?*anyopaque = null,
    pow: ?*anyopaque = null,
    divmod: ?*anyopaque = null,
    matmul: ?*anyopaque = null,
    neg: ?*anyopaque = null,
    pos: ?*anyopaque = null,
    abs: ?*anyopaque = null,
    invert: ?*anyopaque = null,
    and_op: ?*anyopaque = null,
    or_op: ?*anyopaque = null,
    xor_op: ?*anyopaque = null,
    lshift: ?*anyopaque = null,
    rshift: ?*anyopaque = null,
    as_int: ?*anyopaque = null,
    as_float: ?*anyopaque = null,
    as_index: ?*anyopaque = null,
    bool_slot: ?*anyopaque = null,
    inplace_add: ?*anyopaque = null,
    inplace_sub: ?*anyopaque = null,
    inplace_mul: ?*anyopaque = null,
    inplace_truediv: ?*anyopaque = null,
    inplace_floordiv: ?*anyopaque = null,
    inplace_mod: ?*anyopaque = null,
    inplace_pow: ?*anyopaque = null,
    inplace_and: ?*anyopaque = null,
    inplace_or: ?*anyopaque = null,
    inplace_xor: ?*anyopaque = null,
    inplace_lshift: ?*anyopaque = null,
    inplace_rshift: ?*anyopaque = null,
    inplace_matmul: ?*anyopaque = null,
};

/// Build mapping slots from subscript specs.
pub fn mappingSlotsFromSpecs(comptime Specs: type) MappingSlots {
    const has_any = comptime hasSpec(Specs.get) or hasSpec(Specs.set) or hasSpec(Specs.del) or
        hasSpec(Specs.len);
    if (!has_any) return .{};
    validateMappingSpecs(Specs);

    return .{
        .length = if (comptime hasSpec(Specs.len)) blk: {
            const spec = Specs.len;
            const Func = @TypeOf(spec.func);
            const kind = @TypeOf(spec).kind;
            break :blk lenSlotFromSpec(Func, kind, spec, "__len__");
        } else null,
        .subscript = if (comptime hasSpec(Specs.get)) blk: {
            const spec = Specs.get;
            const Func = @TypeOf(spec.func);
            const kind = @TypeOf(spec).kind;
            break :blk binarySlotFromSpec(Func, kind, spec, "__getitem__");
        } else null,
        .ass_subscript = if (comptime hasSpec(Specs.set) or hasSpec(Specs.del))
            assSubscriptSlotFromSpecs(Specs)
        else
            null,
    };
}

/// Build number slots from arithmetic specs.
pub fn numberSlotsFromSpecs(comptime Specs: type) NumberSlots {
    const has_any = comptime hasSpec(Specs.add) or hasSpec(Specs.sub) or hasSpec(Specs.mul) or
        hasSpec(Specs.truediv) or hasSpec(Specs.floordiv) or hasSpec(Specs.mod) or
        hasSpec(Specs.pow) or hasSpec(Specs.divmod) or hasSpec(Specs.matmul) or
        hasSpec(Specs.neg) or hasSpec(Specs.pos) or hasSpec(Specs.abs) or
        hasSpec(Specs.invert) or hasSpec(Specs.and_op) or hasSpec(Specs.or_op) or
        hasSpec(Specs.xor_op) or hasSpec(Specs.lshift) or hasSpec(Specs.rshift) or
        hasSpec(Specs.as_int) or hasSpec(Specs.as_float) or hasSpec(Specs.as_index) or
        hasSpec(Specs.bool_method) or hasSpec(Specs.iadd) or hasSpec(Specs.isub) or
        hasSpec(Specs.imul) or hasSpec(Specs.itruediv) or hasSpec(Specs.ifloordiv) or
        hasSpec(Specs.imod) or hasSpec(Specs.ipow) or hasSpec(Specs.iand) or
        hasSpec(Specs.ior) or hasSpec(Specs.ixor) or hasSpec(Specs.ilshift) or
        hasSpec(Specs.irshift) or hasSpec(Specs.imatmul);
    if (!has_any) return .{};
    validateNumberSpecs(Specs);

    return .{
        .add = if (comptime hasSpec(Specs.add)) blk: {
            const spec = Specs.add;
            const Func = @TypeOf(spec.func);
            const kind = @TypeOf(spec).kind;
            break :blk binarySlotFromSpec(Func, kind, spec, "__add__");
        } else null,
        .sub = if (comptime hasSpec(Specs.sub)) blk: {
            const spec = Specs.sub;
            const Func = @TypeOf(spec.func);
            const kind = @TypeOf(spec).kind;
            break :blk binarySlotFromSpec(Func, kind, spec, "__sub__");
        } else null,
        .mul = if (comptime hasSpec(Specs.mul)) blk: {
            const spec = Specs.mul;
            const Func = @TypeOf(spec.func);
            const kind = @TypeOf(spec).kind;
            break :blk binarySlotFromSpec(Func, kind, spec, "__mul__");
        } else null,
        .truediv = if (comptime hasSpec(Specs.truediv)) blk: {
            const spec = Specs.truediv;
            const Func = @TypeOf(spec.func);
            const kind = @TypeOf(spec).kind;
            break :blk binarySlotFromSpec(Func, kind, spec, "__truediv__");
        } else null,
        .floordiv = if (comptime hasSpec(Specs.floordiv)) blk: {
            const spec = Specs.floordiv;
            const Func = @TypeOf(spec.func);
            const kind = @TypeOf(spec).kind;
            break :blk binarySlotFromSpec(Func, kind, spec, "__floordiv__");
        } else null,
        .mod = if (comptime hasSpec(Specs.mod)) blk: {
            const spec = Specs.mod;
            const Func = @TypeOf(spec.func);
            const kind = @TypeOf(spec).kind;
            break :blk binarySlotFromSpec(Func, kind, spec, "__mod__");
        } else null,
        .pow = if (comptime hasSpec(Specs.pow)) blk: {
            const spec = Specs.pow;
            const Func = @TypeOf(spec.func);
            const kind = @TypeOf(spec).kind;
            break :blk powSlotFromSpec(Func, kind, spec, "__pow__");
        } else null,
        .divmod = if (comptime hasSpec(Specs.divmod)) blk: {
            const spec = Specs.divmod;
            const Func = @TypeOf(spec.func);
            const kind = @TypeOf(spec).kind;
            break :blk binarySlotFromSpec(Func, kind, spec, "__divmod__");
        } else null,
        .matmul = if (comptime hasSpec(Specs.matmul)) blk: {
            const spec = Specs.matmul;
            const Func = @TypeOf(spec.func);
            const kind = @TypeOf(spec).kind;
            break :blk binarySlotFromSpec(Func, kind, spec, "__matmul__");
        } else null,
        .neg = if (comptime hasSpec(Specs.neg)) blk: {
            const spec = Specs.neg;
            const Func = @TypeOf(spec.func);
            const kind = @TypeOf(spec).kind;
            break :blk unarySlotFromSpec(Func, kind, spec, "__neg__");
        } else null,
        .pos = if (comptime hasSpec(Specs.pos)) blk: {
            const spec = Specs.pos;
            const Func = @TypeOf(spec.func);
            const kind = @TypeOf(spec).kind;
            break :blk unarySlotFromSpec(Func, kind, spec, "__pos__");
        } else null,
        .abs = if (comptime hasSpec(Specs.abs)) blk: {
            const spec = Specs.abs;
            const Func = @TypeOf(spec.func);
            const kind = @TypeOf(spec).kind;
            break :blk unarySlotFromSpec(Func, kind, spec, "__abs__");
        } else null,
        .invert = if (comptime hasSpec(Specs.invert)) blk: {
            const spec = Specs.invert;
            const Func = @TypeOf(spec.func);
            const kind = @TypeOf(spec).kind;
            break :blk unarySlotFromSpec(Func, kind, spec, "__invert__");
        } else null,
        .and_op = if (comptime hasSpec(Specs.and_op)) blk: {
            const spec = Specs.and_op;
            const Func = @TypeOf(spec.func);
            const kind = @TypeOf(spec).kind;
            break :blk binarySlotFromSpec(Func, kind, spec, "__and__");
        } else null,
        .or_op = if (comptime hasSpec(Specs.or_op)) blk: {
            const spec = Specs.or_op;
            const Func = @TypeOf(spec.func);
            const kind = @TypeOf(spec).kind;
            break :blk binarySlotFromSpec(Func, kind, spec, "__or__");
        } else null,
        .xor_op = if (comptime hasSpec(Specs.xor_op)) blk: {
            const spec = Specs.xor_op;
            const Func = @TypeOf(spec.func);
            const kind = @TypeOf(spec).kind;
            break :blk binarySlotFromSpec(Func, kind, spec, "__xor__");
        } else null,
        .lshift = if (comptime hasSpec(Specs.lshift)) blk: {
            const spec = Specs.lshift;
            const Func = @TypeOf(spec.func);
            const kind = @TypeOf(spec).kind;
            break :blk binarySlotFromSpec(Func, kind, spec, "__lshift__");
        } else null,
        .rshift = if (comptime hasSpec(Specs.rshift)) blk: {
            const spec = Specs.rshift;
            const Func = @TypeOf(spec.func);
            const kind = @TypeOf(spec).kind;
            break :blk binarySlotFromSpec(Func, kind, spec, "__rshift__");
        } else null,
        .as_int = if (comptime hasSpec(Specs.as_int)) blk: {
            const spec = Specs.as_int;
            const Func = @TypeOf(spec.func);
            const kind = @TypeOf(spec).kind;
            break :blk unarySlotFromSpec(Func, kind, spec, "__int__");
        } else null,
        .as_float = if (comptime hasSpec(Specs.as_float)) blk: {
            const spec = Specs.as_float;
            const Func = @TypeOf(spec.func);
            const kind = @TypeOf(spec).kind;
            break :blk unarySlotFromSpec(Func, kind, spec, "__float__");
        } else null,
        .as_index = if (comptime hasSpec(Specs.as_index)) blk: {
            const spec = Specs.as_index;
            const Func = @TypeOf(spec.func);
            const kind = @TypeOf(spec).kind;
            break :blk unarySlotFromSpec(Func, kind, spec, "__index__");
        } else null,
        .bool_slot = if (comptime hasSpec(Specs.bool_method)) blk: {
            const spec = Specs.bool_method;
            const Func = @TypeOf(spec.func);
            const kind = @TypeOf(spec).kind;
            break :blk boolSlotFromSpec(Func, kind, spec, "__bool__");
        } else null,
        .inplace_add = if (comptime hasSpec(Specs.iadd)) blk: {
            const spec = Specs.iadd;
            const Func = @TypeOf(spec.func);
            const kind = @TypeOf(spec).kind;
            break :blk binarySlotFromSpec(Func, kind, spec, "__iadd__");
        } else null,
        .inplace_sub = if (comptime hasSpec(Specs.isub)) blk: {
            const spec = Specs.isub;
            const Func = @TypeOf(spec.func);
            const kind = @TypeOf(spec).kind;
            break :blk binarySlotFromSpec(Func, kind, spec, "__isub__");
        } else null,
        .inplace_mul = if (comptime hasSpec(Specs.imul)) blk: {
            const spec = Specs.imul;
            const Func = @TypeOf(spec.func);
            const kind = @TypeOf(spec).kind;
            break :blk binarySlotFromSpec(Func, kind, spec, "__imul__");
        } else null,
        .inplace_truediv = if (comptime hasSpec(Specs.itruediv)) blk: {
            const spec = Specs.itruediv;
            const Func = @TypeOf(spec.func);
            const kind = @TypeOf(spec).kind;
            break :blk binarySlotFromSpec(Func, kind, spec, "__itruediv__");
        } else null,
        .inplace_floordiv = if (comptime hasSpec(Specs.ifloordiv)) blk: {
            const spec = Specs.ifloordiv;
            const Func = @TypeOf(spec.func);
            const kind = @TypeOf(spec).kind;
            break :blk binarySlotFromSpec(Func, kind, spec, "__ifloordiv__");
        } else null,
        .inplace_mod = if (comptime hasSpec(Specs.imod)) blk: {
            const spec = Specs.imod;
            const Func = @TypeOf(spec.func);
            const kind = @TypeOf(spec).kind;
            break :blk binarySlotFromSpec(Func, kind, spec, "__imod__");
        } else null,
        .inplace_pow = if (comptime hasSpec(Specs.ipow)) blk: {
            const spec = Specs.ipow;
            const Func = @TypeOf(spec.func);
            const kind = @TypeOf(spec).kind;
            break :blk powSlotFromSpec(Func, kind, spec, "__ipow__");
        } else null,
        .inplace_and = if (comptime hasSpec(Specs.iand)) blk: {
            const spec = Specs.iand;
            const Func = @TypeOf(spec.func);
            const kind = @TypeOf(spec).kind;
            break :blk binarySlotFromSpec(Func, kind, spec, "__iand__");
        } else null,
        .inplace_or = if (comptime hasSpec(Specs.ior)) blk: {
            const spec = Specs.ior;
            const Func = @TypeOf(spec.func);
            const kind = @TypeOf(spec).kind;
            break :blk binarySlotFromSpec(Func, kind, spec, "__ior__");
        } else null,
        .inplace_xor = if (comptime hasSpec(Specs.ixor)) blk: {
            const spec = Specs.ixor;
            const Func = @TypeOf(spec.func);
            const kind = @TypeOf(spec).kind;
            break :blk binarySlotFromSpec(Func, kind, spec, "__ixor__");
        } else null,
        .inplace_lshift = if (comptime hasSpec(Specs.ilshift)) blk: {
            const spec = Specs.ilshift;
            const Func = @TypeOf(spec.func);
            const kind = @TypeOf(spec).kind;
            break :blk binarySlotFromSpec(Func, kind, spec, "__ilshift__");
        } else null,
        .inplace_rshift = if (comptime hasSpec(Specs.irshift)) blk: {
            const spec = Specs.irshift;
            const Func = @TypeOf(spec.func);
            const kind = @TypeOf(spec).kind;
            break :blk binarySlotFromSpec(Func, kind, spec, "__irshift__");
        } else null,
        .inplace_matmul = if (comptime hasSpec(Specs.imatmul)) blk: {
            const spec = Specs.imatmul;
            const Func = @TypeOf(spec.func);
            const kind = @TypeOf(spec).kind;
            break :blk binarySlotFromSpec(Func, kind, spec, "__imatmul__");
        } else null,
    };
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

fn InitWrapperType(
    comptime func: anytype,
    comptime arg_names: ?[]const [:0]const u8,
) type {
    return struct {
        fn call(
            self: ?*c.PyObject,
            args: ?*c.PyObject,
            kwargs: ?*c.PyObject,
        ) callconv(.c) c_int {
            const result = if (arg_names) |names|
                callImplKw(func, self, args, kwargs, names, true) catch |err| {
                    errors.setPythonError(err);
                    return -1;
                }
            else blk: {
                if (kwargs) |kw| {
                    var pos: c.Py_ssize_t = 0;
                    if (PyDict.next(kw, &pos)) |entry| {
                        const key_slice = PyUnicode.slice(entry.key) catch |err| {
                            errors.setPythonError(err);
                            return -1;
                        };
                        errors.setPythonError(setUnexpectedKeywordError(key_slice));
                        return -1;
                    }
                }
                break :blk callImpl(func, self, args, true) catch |err| {
                    errors.setPythonError(err);
                    return -1;
                };
            };

            const obj = result orelse return -1;
            defer PyObject.decRef(obj);
            if (obj != ffi.pyNone()) {
                errors.setError(.TypeError, "__init__() must return None");
                return -1;
            }
            return 0;
        }
    };
}

fn NewWrapperType(
    comptime func: anytype,
    comptime arg_names: ?[]const [:0]const u8,
) type {
    return struct {
        fn call(
            type_obj: ?*c.PyObject,
            args: ?*c.PyObject,
            kwargs: ?*c.PyObject,
        ) callconv(.c) ?*c.PyObject {
            if (arg_names) |names| {
                return callImplKw(func, type_obj, args, kwargs, names, true) catch |err| {
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

            return callImpl(func, type_obj, args, true) catch |err| {
                errors.setPythonError(err);
                return null;
            };
        }
    };
}

fn tupleFromArgs(comptime N: usize, args: [N]?*c.PyObject) PyError!*c.PyObject {
    const tuple = try PyTuple.new(N);
    errdefer PyObject.decRef(tuple);

    inline for (args, 0..) |item, i| {
        const obj = item orelse return errors.raise(.TypeError, "missing argument");
        PyObject.incRef(obj);
        try PyTuple.setItem(tuple, i, obj);
    }

    return tuple;
}

fn tupleFromArgsAllowNulls(comptime N: usize, args: [N]?*c.PyObject) PyError!*c.PyObject {
    const tuple = try PyTuple.new(N);
    errdefer PyObject.decRef(tuple);

    inline for (args, 0..) |item, i| {
        if (item) |obj| {
            PyObject.incRef(obj);
            try PyTuple.setItem(tuple, i, obj);
        } else {
            const none_obj = pyNoneOwned();
            try PyTuple.setItem(tuple, i, none_obj);
        }
    }

    return tuple;
}

/// Call a unary slot (self) by forwarding to the Zig method (__repr__, __len__, etc.).
/// Python passes raw PyObject* slot arguments; we reuse the normal method dispatch.
fn callSlotUnary(
    comptime func: anytype,
    self_obj: ?*c.PyObject,
) PyError!?*c.PyObject {
    return callImpl(func, self_obj, null, true);
}

/// Call a binary slot (self, arg) by packing args into a tuple and dispatching.
/// This matches slots like __add__, __getattr__, __contains__, etc.
fn callSlotBinary(
    comptime func: anytype,
    self_obj: ?*c.PyObject,
    arg0: ?*c.PyObject,
) PyError!?*c.PyObject {
    const args_obj = try tupleFromArgs(1, .{arg0});
    defer PyObject.decRef(args_obj);
    return callImpl(func, self_obj, args_obj, true);
}

/// Call a ternary slot (self, arg0, arg1) using a positional tuple.
/// Used for slots like __setitem__ and descriptor __set__.
fn callSlotTernary(
    comptime func: anytype,
    self_obj: ?*c.PyObject,
    arg0: ?*c.PyObject,
    arg1: ?*c.PyObject,
) PyError!?*c.PyObject {
    const args_obj = try tupleFromArgs(2, .{ arg0, arg1 });
    defer PyObject.decRef(args_obj);
    return callImpl(func, self_obj, args_obj, true);
}

/// Call an index-based slot where Python passes a Py_ssize_t index.
/// We box the index into a Python int before dispatching to the Zig method.
fn callSlotBinaryIndex(
    comptime func: anytype,
    self_obj: ?*c.PyObject,
    index: c.Py_ssize_t,
) PyError!?*c.PyObject {
    var index_obj: ?*c.PyObject = try PyLong.fromLongLong(index);
    errdefer if (index_obj) |obj| PyObject.decRef(obj);

    const args_obj = try PyTuple.new(1);
    errdefer PyObject.decRef(args_obj);

    try PyTuple.setItem(args_obj, 0, index_obj.?);
    index_obj = null;

    return callImpl(func, self_obj, args_obj, true);
}

fn tupleFromIndexValue(
    index: c.Py_ssize_t,
    value: ?*c.PyObject,
) PyError!*c.PyObject {
    var index_obj: ?*c.PyObject = try PyLong.fromLongLong(index);
    errdefer if (index_obj) |obj| PyObject.decRef(obj);

    const count: usize = if (value == null) 1 else 2;
    const tuple = try PyTuple.new(count);
    errdefer PyObject.decRef(tuple);

    try PyTuple.setItem(tuple, 0, index_obj.?);
    index_obj = null;

    if (value) |item| {
        PyObject.incRef(item);
        try PyTuple.setItem(tuple, 1, item);
    }

    return tuple;
}

fn UnaryWrapperType(comptime func: anytype) type {
    return struct {
        fn call(self: ?*c.PyObject) callconv(.c) ?*c.PyObject {
            return callSlotUnary(func, self) catch |err| {
                errors.setPythonError(err);
                return null;
            };
        }
    };
}

fn BinaryWrapperType(comptime func: anytype) type {
    return struct {
        fn call(self: ?*c.PyObject, arg: ?*c.PyObject) callconv(.c) ?*c.PyObject {
            return callSlotBinary(func, self, arg) catch |err| {
                errors.setPythonError(err);
                return null;
            };
        }
    };
}

fn LenWrapperType(comptime func: anytype) type {
    return struct {
        fn call(self: ?*c.PyObject) callconv(.c) c.Py_ssize_t {
            const result = callSlotUnary(func, self) catch |err| {
                errors.setPythonError(err);
                return -1;
            };
            const obj = result orelse return -1;
            defer PyObject.decRef(obj);

            const len = c.PyLong_AsSsize_t(obj);
            if (len < 0 and errors.errorOccurred()) return -1;
            if (len < 0) {
                errors.setError(.ValueError, "length must be non-negative");
                return -1;
            }
            return len;
        }
    };
}

fn HashWrapperType(comptime func: anytype) type {
    return struct {
        fn call(self: ?*c.PyObject) callconv(.c) c.Py_hash_t {
            const result = callSlotUnary(func, self) catch |err| {
                errors.setPythonError(err);
                return -1;
            };
            const obj = result orelse return -1;
            defer PyObject.decRef(obj);

            const value = c.PyLong_AsSsize_t(obj);
            if (value == -1 and errors.errorOccurred()) return -1;
            var hash_val: c.Py_hash_t = @intCast(value);
            if (hash_val == -1) hash_val = -2;
            return hash_val;
        }
    };
}

fn BoolWrapperType(comptime func: anytype) type {
    return struct {
        fn call(self: ?*c.PyObject) callconv(.c) c_int {
            const result = callSlotUnary(func, self) catch |err| {
                errors.setPythonError(err);
                return -1;
            };
            const obj = result orelse return -1;
            defer PyObject.decRef(obj);

            const is_true = PyObject.isTrue(obj) catch |err| {
                errors.setPythonError(err);
                return -1;
            };
            return if (is_true) 1 else 0;
        }
    };
}

fn BoolBinaryWrapperType(comptime func: anytype) type {
    return struct {
        fn call(self: ?*c.PyObject, arg: ?*c.PyObject) callconv(.c) c_int {
            const result = callSlotBinary(func, self, arg) catch |err| {
                errors.setPythonError(err);
                return -1;
            };
            const obj = result orelse return -1;
            defer PyObject.decRef(obj);

            const is_true = PyObject.isTrue(obj) catch |err| {
                errors.setPythonError(err);
                return -1;
            };
            return if (is_true) 1 else 0;
        }
    };
}

fn DelWrapperType(comptime func: anytype) type {
    return struct {
        fn call(self: ?*c.PyObject) callconv(.c) void {
            const result = callSlotUnary(func, self) catch |err| {
                errors.setPythonError(err);
                if (errors.errorOccurred()) {
                    PyErr.writeUnraisable(self orelse ffi.pyNone());
                }
                return;
            };
            if (result) |obj| PyObject.decRef(obj);
            if (errors.errorOccurred()) {
                PyErr.writeUnraisable(self orelse ffi.pyNone());
            }
        }
    };
}

fn SeqItemWrapperType(comptime func: anytype) type {
    return struct {
        fn call(self: ?*c.PyObject, index: c.Py_ssize_t) callconv(.c) ?*c.PyObject {
            return callSlotBinaryIndex(func, self, index) catch |err| {
                errors.setPythonError(err);
                return null;
            };
        }
    };
}

fn SeqRepeatWrapperType(comptime func: anytype) type {
    return struct {
        fn call(self: ?*c.PyObject, count: c.Py_ssize_t) callconv(.c) ?*c.PyObject {
            return callSlotBinaryIndex(func, self, count) catch |err| {
                errors.setPythonError(err);
                return null;
            };
        }
    };
}

fn SeqAssItemWrapperType(comptime Specs: type) type {
    return struct {
        fn call(
            self: ?*c.PyObject,
            index: c.Py_ssize_t,
            value: ?*c.PyObject,
        ) callconv(.c) c_int {
            if (value) |val| {
                if (comptime hasSpec(Specs.set)) {
                    const spec = Specs.set;
                    const func = spec.func;
                    const args_obj = tupleFromIndexValue(index, val) catch |err| {
                        errors.setPythonError(err);
                        return -1;
                    };
                    defer PyObject.decRef(args_obj);
                    const result = callImpl(func, self, args_obj, true) catch |err| {
                        errors.setPythonError(err);
                        return -1;
                    };
                    if (result) |obj| PyObject.decRef(obj);
                    return 0;
                }
                errors.setError(.TypeError, "item assignment not supported");
                return -1;
            }

            if (comptime hasSpec(Specs.del)) {
                const spec = Specs.del;
                const func = spec.func;
                const args_obj = tupleFromIndexValue(index, null) catch |err| {
                    errors.setPythonError(err);
                    return -1;
                };
                defer PyObject.decRef(args_obj);
                const result = callImpl(func, self, args_obj, true) catch |err| {
                    errors.setPythonError(err);
                    return -1;
                };
                if (result) |obj| PyObject.decRef(obj);
                return 0;
            }

            errors.setError(.TypeError, "item deletion not supported");
            return -1;
        }
    };
}

fn tupleFromArgsAllowNoneLast(arg0: ?*c.PyObject, arg1: ?*c.PyObject) PyError!*c.PyObject {
    const first = arg0 orelse return errors.raise(.TypeError, "missing argument");
    const tuple = try PyTuple.new(2);
    errdefer PyObject.decRef(tuple);

    PyObject.incRef(first);
    try PyTuple.setItem(tuple, 0, first);

    if (arg1) |obj| {
        PyObject.incRef(obj);
        try PyTuple.setItem(tuple, 1, obj);
    } else {
        const none_obj = pyNoneOwned();
        try PyTuple.setItem(tuple, 1, none_obj);
    }

    return tuple;
}

/// Call the pow slot (self, exp, mod) where mod may be NULL; map NULL to None.
fn callSlotPow(
    comptime func: anytype,
    self_obj: ?*c.PyObject,
    arg0: ?*c.PyObject,
    arg1: ?*c.PyObject,
) PyError!?*c.PyObject {
    const args_obj = try tupleFromArgsAllowNoneLast(arg0, arg1);
    defer PyObject.decRef(args_obj);
    return callImpl(func, self_obj, args_obj, true);
}

fn PowWrapperType(comptime func: anytype) type {
    return struct {
        fn call(
            self: ?*c.PyObject,
            arg0: ?*c.PyObject,
            arg1: ?*c.PyObject,
        ) callconv(.c) ?*c.PyObject {
            return callSlotPow(func, self, arg0, arg1) catch |err| {
                errors.setPythonError(err);
                return null;
            };
        }
    };
}

fn returnNotImplemented() ?*c.PyObject {
    return pyNotImplementedOwned();
}

fn RichCompareWrapperType(comptime Specs: type) type {
    return struct {
        fn call(
            self: ?*c.PyObject,
            other: ?*c.PyObject,
            op: c_int,
        ) callconv(.c) ?*c.PyObject {
            return switch (op) {
                c.Py_EQ => compareCall(Specs.eq, self, other),
                c.Py_NE => compareCall(Specs.ne, self, other),
                c.Py_LT => compareCall(Specs.lt, self, other),
                c.Py_LE => compareCall(Specs.le, self, other),
                c.Py_GT => compareCall(Specs.gt, self, other),
                c.Py_GE => compareCall(Specs.ge, self, other),
                else => returnNotImplemented(),
            };
        }
    };
}

fn compareCall(
    comptime spec: anytype,
    self_obj: ?*c.PyObject,
    other_obj: ?*c.PyObject,
) ?*c.PyObject {
    if (comptime !hasSpec(spec)) return returnNotImplemented();
    const func = spec.func;
    return callSlotBinary(func, self_obj, other_obj) catch |err| {
        errors.setPythonError(err);
        return null;
    };
}

fn AssSubscriptWrapperType(comptime Specs: type) type {
    return struct {
        fn call(
            self: ?*c.PyObject,
            key: ?*c.PyObject,
            value: ?*c.PyObject,
        ) callconv(.c) c_int {
            if (value) |val| {
                if (comptime hasSpec(Specs.set)) {
                    const spec = Specs.set;
                    const func = spec.func;
                    const result = callSlotTernary(func, self, key, val) catch |err| {
                        errors.setPythonError(err);
                        return -1;
                    };
                    if (result) |obj| PyObject.decRef(obj);
                    return 0;
                }
                errors.setError(.TypeError, "item assignment not supported");
                return -1;
            }

            if (comptime hasSpec(Specs.del)) {
                const spec = Specs.del;
                const func = spec.func;
                const result = callSlotBinary(func, self, key) catch |err| {
                    errors.setPythonError(err);
                    return -1;
                };
                if (result) |obj| PyObject.decRef(obj);
                return 0;
            }

            errors.setError(.TypeError, "item deletion not supported");
            return -1;
        }
    };
}

fn GetAttrWrapperType(comptime Specs: type) type {
    return struct {
        fn call(self: ?*c.PyObject, name: ?*c.PyObject) callconv(.c) ?*c.PyObject {
            if (comptime hasSpec(Specs.getattribute)) {
                const spec = Specs.getattribute;
                const result = callSlotBinary(spec.func, self, name) catch |err| {
                    errors.setPythonError(err);
                    return null;
                };
                if (result) |obj| return obj;
                if (comptime hasSpec(Specs.getattr)) {
                    if (PyErr.exceptionMatches(.AttributeError)) {
                        PyErr.clear();
                        return callSlotBinary(Specs.getattr.func, self, name) catch |err| {
                            errors.setPythonError(err);
                            return null;
                        };
                    }
                }
                return null;
            }

            if (comptime hasSpec(Specs.getattr)) {
                const self_ptr = self orelse {
                    errors.setError(.TypeError, "missing self");
                    return null;
                };
                const name_ptr = name orelse {
                    errors.setError(.TypeError, "missing attribute name");
                    return null;
                };
                const self_obj: Object = .borrowed(self_ptr);
                const name_obj: Object = .borrowed(name_ptr);
                const result = self_obj.genericGetAttr(name_obj) catch {
                    if (PyErr.exceptionMatches(.AttributeError)) {
                        PyErr.clear();
                        return callSlotBinary(Specs.getattr.func, self, name) catch |err| {
                            errors.setPythonError(err);
                            return null;
                        };
                    }
                    return null;
                };
                return result.ptr;
            }

            return null;
        }
    };
}

fn SetAttrWrapperType(comptime Specs: type) type {
    return struct {
        fn call(
            self: ?*c.PyObject,
            name: ?*c.PyObject,
            value: ?*c.PyObject,
        ) callconv(.c) c_int {
            if (value) |val| {
                if (comptime hasSpec(Specs.set)) {
                    const spec = Specs.set;
                    const func = spec.func;
                    const result = callSlotTernary(func, self, name, val) catch |err| {
                        errors.setPythonError(err);
                        return -1;
                    };
                    if (result) |obj| PyObject.decRef(obj);
                    return 0;
                }
                const self_ptr = self orelse {
                    errors.setError(.TypeError, "missing self");
                    return -1;
                };
                const name_ptr = name orelse {
                    errors.setError(.TypeError, "missing attribute name");
                    return -1;
                };
                const self_obj: Object = .borrowed(self_ptr);
                const name_obj: Object = .borrowed(name_ptr);
                const value_obj: Object = .borrowed(val);
                self_obj.genericSetAttr(name_obj, value_obj) catch |err| {
                    errors.setPythonError(err);
                    return -1;
                };
                return 0;
            }

            if (comptime hasSpec(Specs.del)) {
                const spec = Specs.del;
                const func = spec.func;
                const result = callSlotBinary(func, self, name) catch |err| {
                    errors.setPythonError(err);
                    return -1;
                };
                if (result) |obj| PyObject.decRef(obj);
                return 0;
            }

            const self_ptr = self orelse {
                errors.setError(.TypeError, "missing self");
                return -1;
            };
            const name_ptr = name orelse {
                errors.setError(.TypeError, "missing attribute name");
                return -1;
            };
            const self_obj: Object = .borrowed(self_ptr);
            const name_obj: Object = .borrowed(name_ptr);
            self_obj.genericDelAttr(name_obj) catch |err| {
                errors.setPythonError(err);
                return -1;
            };
            return 0;
        }
    };
}

fn DescrGetWrapperType(comptime func: anytype) type {
    return struct {
        fn call(
            self: ?*c.PyObject,
            obj: ?*c.PyObject,
            type_obj: ?*c.PyObject,
        ) callconv(.c) ?*c.PyObject {
            const args_obj = tupleFromArgsAllowNulls(2, .{ obj, type_obj }) catch |err| {
                errors.setPythonError(err);
                return null;
            };
            defer PyObject.decRef(args_obj);
            return callImpl(func, self, args_obj, true) catch |err| {
                errors.setPythonError(err);
                return null;
            };
        }
    };
}

fn DescrSetWrapperType(comptime Specs: type) type {
    return struct {
        fn call(
            self: ?*c.PyObject,
            obj: ?*c.PyObject,
            value: ?*c.PyObject,
        ) callconv(.c) c_int {
            if (value) |val| {
                if (comptime hasSpec(Specs.set)) {
                    const spec = Specs.set;
                    const func = spec.func;
                    const args_obj = tupleFromArgsAllowNulls(2, .{ obj, val }) catch |err| {
                        errors.setPythonError(err);
                        return -1;
                    };
                    defer PyObject.decRef(args_obj);
                    const result = callImpl(func, self, args_obj, true) catch |err| {
                        errors.setPythonError(err);
                        return -1;
                    };
                    if (result) |obj_result| PyObject.decRef(obj_result);
                    return 0;
                }
                errors.setError(.TypeError, "descriptor assignment not supported");
                return -1;
            }

            if (comptime hasSpec(Specs.del)) {
                const spec = Specs.del;
                const func = spec.func;
                const args_obj = tupleFromArgsAllowNulls(1, .{obj}) catch |err| {
                    errors.setPythonError(err);
                    return -1;
                };
                defer PyObject.decRef(args_obj);
                const result = callImpl(func, self, args_obj, true) catch |err| {
                    errors.setPythonError(err);
                    return -1;
                };
                if (result) |obj_result| PyObject.decRef(obj_result);
                return 0;
            }

            errors.setError(.TypeError, "descriptor deletion not supported");
            return -1;
        }
    };
}

fn assSubscriptSlotFromSpecs(comptime Specs: type) ?*anyopaque {
    const has_any = comptime hasSpec(Specs.set) or hasSpec(Specs.del);
    if (!has_any) return null;
    const Wrapper = AssSubscriptWrapperType(Specs);
    return @ptrCast(@constCast(&Wrapper.call));
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

fn hasSpec(comptime value: anytype) bool {
    const info = @typeInfo(@TypeOf(value));
    return info == .@"struct" and @hasDecl(@TypeOf(value), "is_method_spec");
}

fn requireInstanceMethod(comptime kind: MethodKind, comptime name: []const u8) void {
    if (kind != .instance) {
        @compileError(fmt.comptimePrint(
            "{s} must be defined with alloconda.method",
            .{name},
        ));
    }
}

fn requireClassMethod(comptime kind: MethodKind, comptime name: []const u8) void {
    if (kind != .classmethod) {
        @compileError(fmt.comptimePrint(
            "{s} must be defined with alloconda.classmethod",
            .{name},
        ));
    }
}

fn requireParamCount(comptime Func: type, comptime expected: usize, comptime name: []const u8) void {
    const params = @typeInfo(Func).@"fn".params;
    if (params.len != expected) {
        @compileError(fmt.comptimePrint(
            "{s} expects {d} parameters (got {d})",
            .{ name, expected, params.len },
        ));
    }
}

fn requireMinParamCount(comptime Func: type, comptime expected: usize, comptime name: []const u8) void {
    const params = @typeInfo(Func).@"fn".params;
    if (params.len < expected) {
        @compileError(fmt.comptimePrint(
            "{s} expects at least {d} parameters (got {d})",
            .{ name, expected, params.len },
        ));
    }
}

fn validateUnarySpec(
    comptime Func: type,
    comptime kind: MethodKind,
    comptime spec: MethodSpec(Func, kind),
    comptime name: []const u8,
) void {
    if (@typeInfo(Func) != .@"fn") {
        @compileError("method func must be a function");
    }
    requireInstanceMethod(kind, name);
    requireParamCount(Func, 1, name);
    validateArgNames(spec.func, spec.options.args, true);
}

fn validateBinarySpec(
    comptime Func: type,
    comptime kind: MethodKind,
    comptime spec: MethodSpec(Func, kind),
    comptime name: []const u8,
) void {
    if (@typeInfo(Func) != .@"fn") {
        @compileError("method func must be a function");
    }
    requireInstanceMethod(kind, name);
    requireParamCount(Func, 2, name);
    validateArgNames(spec.func, spec.options.args, true);
}

fn validateTernarySpec(
    comptime Func: type,
    comptime kind: MethodKind,
    comptime spec: MethodSpec(Func, kind),
    comptime name: []const u8,
) void {
    if (@typeInfo(Func) != .@"fn") {
        @compileError("method func must be a function");
    }
    requireInstanceMethod(kind, name);
    requireParamCount(Func, 3, name);
    validateArgNames(spec.func, spec.options.args, true);
}

fn validateInitSpec(
    comptime Func: type,
    comptime kind: MethodKind,
    comptime spec: MethodSpec(Func, kind),
    comptime name: []const u8,
) void {
    if (@typeInfo(Func) != .@"fn") {
        @compileError("method func must be a function");
    }
    requireInstanceMethod(kind, name);
    requireMinParamCount(Func, 1, name);
    validateArgNames(spec.func, spec.options.args, true);
}

fn validateNewSpec(
    comptime Func: type,
    comptime kind: MethodKind,
    comptime spec: MethodSpec(Func, kind),
    comptime name: []const u8,
) void {
    if (@typeInfo(Func) != .@"fn") {
        @compileError("method func must be a function");
    }
    requireClassMethod(kind, name);
    requireMinParamCount(Func, 1, name);
    validateArgNames(spec.func, spec.options.args, true);
}

fn validateCompareSpecs(comptime Specs: type) void {
    if (comptime hasSpec(Specs.eq)) {
        const spec = Specs.eq;
        validateBinarySpec(@TypeOf(spec.func), @TypeOf(spec).kind, spec, "__eq__");
    }
    if (comptime hasSpec(Specs.ne)) {
        const spec = Specs.ne;
        validateBinarySpec(@TypeOf(spec.func), @TypeOf(spec).kind, spec, "__ne__");
    }
    if (comptime hasSpec(Specs.lt)) {
        const spec = Specs.lt;
        validateBinarySpec(@TypeOf(spec.func), @TypeOf(spec).kind, spec, "__lt__");
    }
    if (comptime hasSpec(Specs.le)) {
        const spec = Specs.le;
        validateBinarySpec(@TypeOf(spec.func), @TypeOf(spec).kind, spec, "__le__");
    }
    if (comptime hasSpec(Specs.gt)) {
        const spec = Specs.gt;
        validateBinarySpec(@TypeOf(spec.func), @TypeOf(spec).kind, spec, "__gt__");
    }
    if (comptime hasSpec(Specs.ge)) {
        const spec = Specs.ge;
        validateBinarySpec(@TypeOf(spec.func), @TypeOf(spec).kind, spec, "__ge__");
    }
}

fn validateMappingSpecs(comptime Specs: type) void {
    if (comptime hasSpec(Specs.get)) {
        const spec = Specs.get;
        validateBinarySpec(@TypeOf(spec.func), @TypeOf(spec).kind, spec, "__getitem__");
    }
    if (comptime hasSpec(Specs.set)) {
        const spec = Specs.set;
        validateTernarySpec(@TypeOf(spec.func), @TypeOf(spec).kind, spec, "__setitem__");
    }
    if (comptime hasSpec(Specs.del)) {
        const spec = Specs.del;
        validateBinarySpec(@TypeOf(spec.func), @TypeOf(spec).kind, spec, "__delitem__");
    }
    if (comptime hasSpec(Specs.len)) {
        const spec = Specs.len;
        validateUnarySpec(@TypeOf(spec.func), @TypeOf(spec).kind, spec, "__len__");
    }
}

fn validateGetAttrSpecs(comptime Specs: type) void {
    if (comptime hasSpec(Specs.getattribute)) {
        const spec = Specs.getattribute;
        validateBinarySpec(@TypeOf(spec.func), @TypeOf(spec).kind, spec, "__getattribute__");
    }
    if (comptime hasSpec(Specs.getattr)) {
        const spec = Specs.getattr;
        validateBinarySpec(@TypeOf(spec.func), @TypeOf(spec).kind, spec, "__getattr__");
    }
}

fn validateSetAttrSpecs(comptime Specs: type) void {
    if (comptime hasSpec(Specs.set)) {
        const spec = Specs.set;
        validateTernarySpec(@TypeOf(spec.func), @TypeOf(spec).kind, spec, "__setattr__");
    }
    if (comptime hasSpec(Specs.del)) {
        const spec = Specs.del;
        validateBinarySpec(@TypeOf(spec.func), @TypeOf(spec).kind, spec, "__delattr__");
    }
}

fn validateDescrSpecs(comptime Specs: type) void {
    if (comptime hasSpec(Specs.set)) {
        const spec = Specs.set;
        validateTernarySpec(@TypeOf(spec.func), @TypeOf(spec).kind, spec, "__set__");
    }
    if (comptime hasSpec(Specs.del)) {
        const spec = Specs.del;
        validateBinarySpec(@TypeOf(spec.func), @TypeOf(spec).kind, spec, "__delete__");
    }
}

fn validateSequenceSpecs(comptime Specs: type) void {
    if (comptime hasSpec(Specs.get)) {
        const spec = Specs.get;
        validateBinarySpec(@TypeOf(spec.func), @TypeOf(spec).kind, spec, "__getitem__");
    }
    if (comptime hasSpec(Specs.set)) {
        const spec = Specs.set;
        validateTernarySpec(@TypeOf(spec.func), @TypeOf(spec).kind, spec, "__setitem__");
    }
    if (comptime hasSpec(Specs.del)) {
        const spec = Specs.del;
        validateBinarySpec(@TypeOf(spec.func), @TypeOf(spec).kind, spec, "__delitem__");
    }
    if (comptime hasSpec(Specs.contains)) {
        const spec = Specs.contains;
        validateBinarySpec(@TypeOf(spec.func), @TypeOf(spec).kind, spec, "__contains__");
    }
    if (comptime hasSpec(Specs.concat)) {
        const spec = Specs.concat;
        validateBinarySpec(@TypeOf(spec.func), @TypeOf(spec).kind, spec, "__add__");
    }
    if (comptime hasSpec(Specs.repeat)) {
        const spec = Specs.repeat;
        validateBinarySpec(@TypeOf(spec.func), @TypeOf(spec).kind, spec, "__mul__");
    }
    if (comptime hasSpec(Specs.inplace_concat)) {
        const spec = Specs.inplace_concat;
        validateBinarySpec(@TypeOf(spec.func), @TypeOf(spec).kind, spec, "__iadd__");
    }
    if (comptime hasSpec(Specs.inplace_repeat)) {
        const spec = Specs.inplace_repeat;
        validateBinarySpec(@TypeOf(spec.func), @TypeOf(spec).kind, spec, "__imul__");
    }
}

fn validateNumberSpecs(comptime Specs: type) void {
    if (comptime hasSpec(Specs.add)) {
        const spec = Specs.add;
        validateBinarySpec(@TypeOf(spec.func), @TypeOf(spec).kind, spec, "__add__");
    }
    if (comptime hasSpec(Specs.sub)) {
        const spec = Specs.sub;
        validateBinarySpec(@TypeOf(spec.func), @TypeOf(spec).kind, spec, "__sub__");
    }
    if (comptime hasSpec(Specs.mul)) {
        const spec = Specs.mul;
        validateBinarySpec(@TypeOf(spec.func), @TypeOf(spec).kind, spec, "__mul__");
    }
    if (comptime hasSpec(Specs.truediv)) {
        const spec = Specs.truediv;
        validateBinarySpec(@TypeOf(spec.func), @TypeOf(spec).kind, spec, "__truediv__");
    }
    if (comptime hasSpec(Specs.floordiv)) {
        const spec = Specs.floordiv;
        validateBinarySpec(@TypeOf(spec.func), @TypeOf(spec).kind, spec, "__floordiv__");
    }
    if (comptime hasSpec(Specs.mod)) {
        const spec = Specs.mod;
        validateBinarySpec(@TypeOf(spec.func), @TypeOf(spec).kind, spec, "__mod__");
    }
    if (comptime hasSpec(Specs.pow)) {
        const spec = Specs.pow;
        validateTernarySpec(@TypeOf(spec.func), @TypeOf(spec).kind, spec, "__pow__");
    }
    if (comptime hasSpec(Specs.divmod)) {
        const spec = Specs.divmod;
        validateBinarySpec(@TypeOf(spec.func), @TypeOf(spec).kind, spec, "__divmod__");
    }
    if (comptime hasSpec(Specs.matmul)) {
        const spec = Specs.matmul;
        validateBinarySpec(@TypeOf(spec.func), @TypeOf(spec).kind, spec, "__matmul__");
    }
    if (comptime hasSpec(Specs.neg)) {
        const spec = Specs.neg;
        validateUnarySpec(@TypeOf(spec.func), @TypeOf(spec).kind, spec, "__neg__");
    }
    if (comptime hasSpec(Specs.pos)) {
        const spec = Specs.pos;
        validateUnarySpec(@TypeOf(spec.func), @TypeOf(spec).kind, spec, "__pos__");
    }
    if (comptime hasSpec(Specs.abs)) {
        const spec = Specs.abs;
        validateUnarySpec(@TypeOf(spec.func), @TypeOf(spec).kind, spec, "__abs__");
    }
    if (comptime hasSpec(Specs.invert)) {
        const spec = Specs.invert;
        validateUnarySpec(@TypeOf(spec.func), @TypeOf(spec).kind, spec, "__invert__");
    }
    if (comptime hasSpec(Specs.and_op)) {
        const spec = Specs.and_op;
        validateBinarySpec(@TypeOf(spec.func), @TypeOf(spec).kind, spec, "__and__");
    }
    if (comptime hasSpec(Specs.or_op)) {
        const spec = Specs.or_op;
        validateBinarySpec(@TypeOf(spec.func), @TypeOf(spec).kind, spec, "__or__");
    }
    if (comptime hasSpec(Specs.xor_op)) {
        const spec = Specs.xor_op;
        validateBinarySpec(@TypeOf(spec.func), @TypeOf(spec).kind, spec, "__xor__");
    }
    if (comptime hasSpec(Specs.lshift)) {
        const spec = Specs.lshift;
        validateBinarySpec(@TypeOf(spec.func), @TypeOf(spec).kind, spec, "__lshift__");
    }
    if (comptime hasSpec(Specs.rshift)) {
        const spec = Specs.rshift;
        validateBinarySpec(@TypeOf(spec.func), @TypeOf(spec).kind, spec, "__rshift__");
    }
    if (comptime hasSpec(Specs.as_int)) {
        const spec = Specs.as_int;
        validateUnarySpec(@TypeOf(spec.func), @TypeOf(spec).kind, spec, "__int__");
    }
    if (comptime hasSpec(Specs.as_float)) {
        const spec = Specs.as_float;
        validateUnarySpec(@TypeOf(spec.func), @TypeOf(spec).kind, spec, "__float__");
    }
    if (comptime hasSpec(Specs.as_index)) {
        const spec = Specs.as_index;
        validateUnarySpec(@TypeOf(spec.func), @TypeOf(spec).kind, spec, "__index__");
    }
    if (comptime hasSpec(Specs.bool_method)) {
        const spec = Specs.bool_method;
        validateUnarySpec(@TypeOf(spec.func), @TypeOf(spec).kind, spec, "__bool__");
    }
    if (comptime hasSpec(Specs.iadd)) {
        const spec = Specs.iadd;
        validateBinarySpec(@TypeOf(spec.func), @TypeOf(spec).kind, spec, "__iadd__");
    }
    if (comptime hasSpec(Specs.isub)) {
        const spec = Specs.isub;
        validateBinarySpec(@TypeOf(spec.func), @TypeOf(spec).kind, spec, "__isub__");
    }
    if (comptime hasSpec(Specs.imul)) {
        const spec = Specs.imul;
        validateBinarySpec(@TypeOf(spec.func), @TypeOf(spec).kind, spec, "__imul__");
    }
    if (comptime hasSpec(Specs.itruediv)) {
        const spec = Specs.itruediv;
        validateBinarySpec(@TypeOf(spec.func), @TypeOf(spec).kind, spec, "__itruediv__");
    }
    if (comptime hasSpec(Specs.ifloordiv)) {
        const spec = Specs.ifloordiv;
        validateBinarySpec(@TypeOf(spec.func), @TypeOf(spec).kind, spec, "__ifloordiv__");
    }
    if (comptime hasSpec(Specs.imod)) {
        const spec = Specs.imod;
        validateBinarySpec(@TypeOf(spec.func), @TypeOf(spec).kind, spec, "__imod__");
    }
    if (comptime hasSpec(Specs.ipow)) {
        const spec = Specs.ipow;
        validateTernarySpec(@TypeOf(spec.func), @TypeOf(spec).kind, spec, "__ipow__");
    }
    if (comptime hasSpec(Specs.iand)) {
        const spec = Specs.iand;
        validateBinarySpec(@TypeOf(spec.func), @TypeOf(spec).kind, spec, "__iand__");
    }
    if (comptime hasSpec(Specs.ior)) {
        const spec = Specs.ior;
        validateBinarySpec(@TypeOf(spec.func), @TypeOf(spec).kind, spec, "__ior__");
    }
    if (comptime hasSpec(Specs.ixor)) {
        const spec = Specs.ixor;
        validateBinarySpec(@TypeOf(spec.func), @TypeOf(spec).kind, spec, "__ixor__");
    }
    if (comptime hasSpec(Specs.ilshift)) {
        const spec = Specs.ilshift;
        validateBinarySpec(@TypeOf(spec.func), @TypeOf(spec).kind, spec, "__ilshift__");
    }
    if (comptime hasSpec(Specs.irshift)) {
        const spec = Specs.irshift;
        validateBinarySpec(@TypeOf(spec.func), @TypeOf(spec).kind, spec, "__irshift__");
    }
    if (comptime hasSpec(Specs.imatmul)) {
        const spec = Specs.imatmul;
        validateBinarySpec(@TypeOf(spec.func), @TypeOf(spec).kind, spec, "__imatmul__");
    }
}

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
