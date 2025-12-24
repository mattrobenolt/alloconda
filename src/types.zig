const std = @import("std");
const fmt = std.fmt;
const math = std.math;
const mem = std.mem;
const Allocator = mem.Allocator;

const errors = @import("errors.zig");
const raise = errors.raise;
const ffi = @import("ffi.zig");
const c = ffi.c;

/// Wrapper for a Python object with ownership tracking.
pub const Object = struct {
    ptr: *c.PyObject,
    owns_ref: bool,

    /// Borrow a PyObject without changing refcount.
    pub fn borrowed(ptr: *c.PyObject) Object {
        return .{ .ptr = ptr, .owns_ref = false };
    }

    /// Own a PyObject reference.
    pub fn owned(ptr: *c.PyObject) Object {
        return .{ .ptr = ptr, .owns_ref = true };
    }

    /// Release the reference if owned.
    pub fn deinit(self: Object) void {
        if (self.owns_ref) {
            c.Py_DecRef(self.ptr);
        }
    }

    /// Increment the reference count and return an owned Object.
    pub fn incref(self: Object) Object {
        c.Py_IncRef(self.ptr);
        return .{ .ptr = self.ptr, .owns_ref = true };
    }

    /// Convert to a Zig value.
    pub fn as(self: Object, comptime T: type) ?T {
        return fromPy(T, self.ptr);
    }

    /// Check if the object is callable.
    pub fn isCallable(self: Object) bool {
        return c.PyCallable_Check(self.ptr) != 0;
    }

    /// Check if the object is None.
    pub fn isNone(self: Object) bool {
        return checkNone(self.ptr);
    }

    /// Check if the object is a Unicode string.
    pub fn isUnicode(self: Object) bool {
        return checkUnicode(self.ptr);
    }

    /// Check if the object is a bytes object.
    pub fn isBytes(self: Object) bool {
        return checkBytes(self.ptr);
    }

    /// Check if the object is a bool.
    pub fn isBool(self: Object) bool {
        return checkBool(self.ptr);
    }

    /// Check if the object is an int.
    pub fn isLong(self: Object) bool {
        return checkLong(self.ptr);
    }

    /// Check if the object is a float.
    pub fn isFloat(self: Object) bool {
        return checkFloat(self.ptr);
    }

    /// Check if the object is a list.
    pub fn isList(self: Object) bool {
        return checkList(self.ptr);
    }

    /// Check if the object is a tuple.
    pub fn isTuple(self: Object) bool {
        return checkTuple(self.ptr);
    }

    /// Check if the object is a dict.
    pub fn isDict(self: Object) bool {
        return checkDict(self.ptr);
    }

    /// Borrow the UTF-8 slice for a Unicode object.
    pub fn unicodeSlice(self: Object) ?[]const u8 {
        return sliceUnicode(self.ptr);
    }

    /// Borrow the byte slice for a bytes object.
    pub fn bytesSlice(self: Object) ?[]const u8 {
        return sliceBytes(self.ptr);
    }

    /// Convert the object to truthiness.
    pub fn isTrue(self: Object) ?bool {
        return objectIsTrue(self.ptr);
    }

    /// Call with no arguments.
    pub fn call0(self: Object) ?Object {
        if (@hasDecl(c, "PyObject_CallNoArgs")) {
            const result = c.PyObject_CallNoArgs(self.ptr);
            if (result == null) return null;
            return Object.owned(result);
        }

        const tuple = c.PyTuple_New(0) orelse return null;
        const result = c.PyObject_CallObject(self.ptr, tuple);
        c.Py_DecRef(tuple);
        if (result == null) return null;
        return Object.owned(result);
    }

    /// Call with one argument.
    pub fn call1(self: Object, arg: anytype) ?Object {
        const arg_obj = toPy(@TypeOf(arg), arg) orelse return null;
        const tuple = c.PyTuple_New(1) orelse {
            c.Py_DecRef(arg_obj);
            return null;
        };

        if (c.PyTuple_SetItem(tuple, 0, arg_obj) != 0) {
            c.Py_DecRef(arg_obj);
            c.Py_DecRef(tuple);
            return null;
        }

        const result = c.PyObject_CallObject(self.ptr, tuple);
        c.Py_DecRef(tuple);
        if (result == null) return null;
        return Object.owned(result);
    }

    /// Call with two arguments.
    pub fn call2(self: Object, arg0: anytype, arg1: anytype) ?Object {
        const arg0_obj = toPy(@TypeOf(arg0), arg0) orelse return null;
        const arg1_obj = toPy(@TypeOf(arg1), arg1) orelse {
            c.Py_DecRef(arg0_obj);
            return null;
        };
        const tuple = c.PyTuple_New(2) orelse {
            c.Py_DecRef(arg0_obj);
            c.Py_DecRef(arg1_obj);
            return null;
        };

        if (c.PyTuple_SetItem(tuple, 0, arg0_obj) != 0) {
            c.Py_DecRef(arg0_obj);
            c.Py_DecRef(arg1_obj);
            c.Py_DecRef(tuple);
            return null;
        }

        if (c.PyTuple_SetItem(tuple, 1, arg1_obj) != 0) {
            c.Py_DecRef(arg1_obj);
            c.Py_DecRef(tuple);
            return null;
        }

        const result = c.PyObject_CallObject(self.ptr, tuple);
        c.Py_DecRef(tuple);
        if (result == null) return null;
        return Object.owned(result);
    }

    /// Get an attribute by name.
    pub fn getAttr(self: Object, name: [:0]const u8) ?Object {
        const result = c.PyObject_GetAttrString(self.ptr, @ptrCast(name.ptr));
        if (result == null) return null;
        return Object.owned(result);
    }

    /// Set an attribute by name.
    pub fn setAttr(self: Object, name: [:0]const u8, value: anytype) bool {
        const value_obj = toPy(@TypeOf(value), value) orelse return false;
        if (c.PyObject_SetAttrString(self.ptr, @ptrCast(name.ptr), value_obj) != 0) {
            c.Py_DecRef(value_obj);
            return false;
        }
        c.Py_DecRef(value_obj);
        return true;
    }

    /// Call a method with no arguments.
    pub fn callMethod0(self: Object, name: [:0]const u8) ?Object {
        const meth = self.getAttr(name) orelse return null;
        defer meth.deinit();
        return meth.call0();
    }

    /// Call a method with one argument.
    pub fn callMethod1(self: Object, name: [:0]const u8, arg: anytype) ?Object {
        const meth = self.getAttr(name) orelse return null;
        defer meth.deinit();
        return meth.call1(arg);
    }

    /// Call a method with two arguments.
    pub fn callMethod2(self: Object, name: [:0]const u8, arg0: anytype, arg1: anytype) ?Object {
        const meth = self.getAttr(name) orelse return null;
        defer meth.deinit();
        return meth.call2(arg0, arg1);
    }
};

/// Wrapper for Python bytes objects.
pub const Bytes = struct {
    obj: Object,

    /// Create bytes from a slice.
    pub fn fromSlice(data: []const u8) ?Bytes {
        const obj = c.PyBytes_FromStringAndSize(data.ptr, @intCast(data.len)) orelse return null;
        return Bytes.owned(obj);
    }

    /// Borrow a bytes object without changing refcount.
    pub fn borrowed(ptr: *c.PyObject) Bytes {
        return .{ .obj = Object.borrowed(ptr) };
    }

    /// Own a bytes object reference.
    pub fn owned(ptr: *c.PyObject) Bytes {
        return .{ .obj = Object.owned(ptr) };
    }

    /// Release the reference if owned.
    pub fn deinit(self: Bytes) void {
        self.obj.deinit();
    }

    /// Return the byte length.
    pub fn len(self: Bytes) ?usize {
        const size = c.PyBytes_Size(self.obj.ptr);
        if (size < 0) return null;
        return @intCast(size);
    }

    /// Borrow the underlying bytes as a slice.
    pub fn slice(self: Bytes) ?[]const u8 {
        var byte_len: c.Py_ssize_t = 0;
        var raw: [*c]u8 = null;
        if (c.PyBytes_AsStringAndSize(self.obj.ptr, &raw, &byte_len) != 0) return null;
        const ptr: [*]const u8 = @ptrCast(raw);
        return ptr[0..@intCast(byte_len)];
    }
};

/// Wrapper for Python list objects.
pub const List = struct {
    obj: Object,

    /// Borrow a list without changing refcount.
    pub fn borrowed(ptr: *c.PyObject) List {
        return .{ .obj = Object.borrowed(ptr) };
    }

    /// Own a list reference.
    pub fn owned(ptr: *c.PyObject) List {
        return .{ .obj = Object.owned(ptr) };
    }

    /// Create a new list with the given size.
    pub fn init(size: usize) ?List {
        const list_obj = c.PyList_New(@intCast(size)) orelse return null;
        return List.owned(list_obj);
    }

    /// Release the reference if owned.
    pub fn deinit(self: List) void {
        self.obj.deinit();
    }

    /// Get the list length.
    pub fn len(self: List) ?usize {
        const size = c.PyList_Size(self.obj.ptr);
        if (size < 0) return null;
        return @intCast(size);
    }

    /// Borrow the item at the given index.
    pub fn get(self: List, index: usize) ?Object {
        const item = c.PyList_GetItem(self.obj.ptr, @intCast(index)) orelse return null;
        return Object.borrowed(item);
    }

    /// Set the item at the given index.
    pub fn set(self: List, index: usize, value: anytype) bool {
        const value_obj = toPy(@TypeOf(value), value) orelse return false;
        if (c.PyList_SetItem(self.obj.ptr, @intCast(index), value_obj) != 0) {
            c.Py_DecRef(value_obj);
            return false;
        }
        return true;
    }

    /// Append an item to the list.
    pub fn append(self: List, value: anytype) bool {
        const value_obj = toPy(@TypeOf(value), value) orelse return false;
        defer c.Py_DecRef(value_obj);
        return c.PyList_Append(self.obj.ptr, value_obj) == 0;
    }
};

/// Wrapper for Python dict objects.
pub const Dict = struct {
    obj: Object,

    /// Borrow a dict without changing refcount.
    pub fn borrowed(ptr: *c.PyObject) Dict {
        return .{ .obj = Object.borrowed(ptr) };
    }

    /// Own a dict reference.
    pub fn owned(ptr: *c.PyObject) Dict {
        return .{ .obj = Object.owned(ptr) };
    }

    /// Create a new dict.
    pub fn init() ?Dict {
        const dict_obj = c.PyDict_New() orelse return null;
        return Dict.owned(dict_obj);
    }

    /// Release the reference if owned.
    pub fn deinit(self: Dict) void {
        self.obj.deinit();
    }

    /// Get the dict length.
    pub fn len(self: Dict) ?usize {
        const size = c.PyDict_Size(self.obj.ptr);
        if (size < 0) return null;
        return @intCast(size);
    }

    /// Borrow a value by key.
    pub fn getItem(self: Dict, key: anytype) ?Object {
        const key_obj = toPy(@TypeOf(key), key) orelse return null;
        defer c.Py_DecRef(key_obj);
        const item = c.PyDict_GetItemWithError(self.obj.ptr, key_obj);
        if (item == null) {
            return null;
        }
        return Object.borrowed(item);
    }

    /// Set a key to a value.
    pub fn setItem(self: Dict, key: anytype, value: anytype) bool {
        const key_obj = toPy(@TypeOf(key), key) orelse return false;
        defer c.Py_DecRef(key_obj);
        const value_obj = toPy(@TypeOf(value), value) orelse return false;
        defer c.Py_DecRef(value_obj);
        return c.PyDict_SetItem(self.obj.ptr, key_obj, value_obj) == 0;
    }

    /// Create an iterator over dict entries (borrowed references).
    pub fn iter(self: Dict) DictIter {
        return .{ .dict = self.obj.ptr };
    }
};

/// Borrowed dict key/value pair.
pub const DictEntry = struct {
    key: Object,
    value: Object,
};

/// Iterator over dict entries using PyDict_Next.
pub const DictIter = struct {
    dict: *c.PyObject,
    pos: c.Py_ssize_t = 0,

    /// Return the next borrowed entry, or null when complete.
    pub fn next(self: *DictIter) ?DictEntry {
        var key: ?*c.PyObject = null;
        var value: ?*c.PyObject = null;
        if (c.PyDict_Next(self.dict, &self.pos, &key, &value) == 0) return null;
        return .{
            .key = Object.borrowed(key orelse return null),
            .value = Object.borrowed(value orelse return null),
        };
    }
};

/// Wrapper for Python tuple objects.
pub const Tuple = struct {
    obj: Object,

    /// Borrow a tuple without changing refcount.
    pub fn borrowed(ptr: *c.PyObject) Tuple {
        return .{ .obj = Object.borrowed(ptr) };
    }

    /// Own a tuple reference.
    pub fn owned(ptr: *c.PyObject) Tuple {
        return .{ .obj = Object.owned(ptr) };
    }

    /// Release the reference if owned.
    pub fn deinit(self: Tuple) void {
        self.obj.deinit();
    }

    /// Get the tuple length.
    pub fn len(self: Tuple) ?usize {
        const size = c.PyTuple_Size(self.obj.ptr);
        if (size < 0) return null;
        return @intCast(size);
    }

    /// Borrow the item at the given index.
    pub fn get(self: Tuple, index: usize) ?Object {
        const item = c.PyTuple_GetItem(self.obj.ptr, @intCast(index)) orelse return null;
        return Object.borrowed(item);
    }
};

/// RAII guard for the Python GIL.
pub const GIL = struct {
    state: c.PyGILState_STATE,

    /// Acquire the GIL and return a guard.
    pub fn acquire() GIL {
        return .{ .state = c.PyGILState_Ensure() };
    }

    /// Release the GIL for this guard.
    pub fn deinit(self: *GIL) void {
        c.PyGILState_Release(self.state);
    }
};

// ============================================================================
// Type checking functions (operate on raw *c.PyObject)
// ============================================================================

/// Return true if the object is Python None.
pub fn checkNone(obj: *c.PyObject) bool {
    if (@hasDecl(c, "Py_IsNone")) {
        return c.Py_IsNone(obj) != 0;
    }
    return obj == ffi.pyNone();
}

/// Return true if the object is a Unicode string.
pub fn checkUnicode(obj: *c.PyObject) bool {
    return c.PyUnicode_Check(obj) != 0;
}

/// Return true if the object is a bytes object.
pub fn checkBytes(obj: *c.PyObject) bool {
    return c.PyBytes_Check(obj) != 0;
}

/// Return true if the object is a bool.
pub fn checkBool(obj: *c.PyObject) bool {
    // Avoid using PyBool_Check macro which relies on _PyObject_CAST_CONST
    // that Zig can't translate on Python 3.10. Instead, compare type directly.
    const obj_type = c.Py_TYPE(obj);
    return obj_type == &c.PyBool_Type;
}

/// Return true if the object is an int.
pub fn checkLong(obj: *c.PyObject) bool {
    return c.PyLong_Check(obj) != 0;
}

/// Return true if the object is a float.
pub fn checkFloat(obj: *c.PyObject) bool {
    return c.PyFloat_Check(obj) != 0;
}

/// Return true if the object is a list.
pub fn checkList(obj: *c.PyObject) bool {
    return c.PyList_Check(obj) != 0;
}

/// Return true if the object is a tuple.
pub fn checkTuple(obj: *c.PyObject) bool {
    return c.PyTuple_Check(obj) != 0;
}

/// Return true if the object is a dict.
pub fn checkDict(obj: *c.PyObject) bool {
    return c.PyDict_Check(obj) != 0;
}

// ============================================================================
// Slice extraction (operate on raw *c.PyObject)
// ============================================================================

/// Borrow the UTF-8 slice for a Unicode object.
pub fn sliceUnicode(obj: *c.PyObject) ?[]const u8 {
    var len: c.Py_ssize_t = 0;
    const raw = c.PyUnicode_AsUTF8AndSize(obj, &len) orelse return null;
    const ptr: [*]const u8 = @ptrCast(raw);
    return ptr[0..@intCast(len)];
}

/// Borrow the byte slice for a bytes object.
pub fn sliceBytes(obj: *c.PyObject) ?[]const u8 {
    var len: c.Py_ssize_t = 0;
    var raw: [*c]u8 = null;
    if (c.PyBytes_AsStringAndSize(obj, &raw, &len) != 0) return null;
    const ptr: [*]const u8 = @ptrCast(raw);
    return ptr[0..@intCast(len)];
}

// ============================================================================
// Object utilities
// ============================================================================

/// Borrow Python None as an Object.
pub fn none() Object {
    return Object.borrowed(ffi.pyNone());
}

/// Return the string representation of an object.
pub fn objectStr(obj: *c.PyObject) ?Object {
    const value = c.PyObject_Str(obj) orelse return null;
    return Object.owned(value);
}

/// Convert an object to truthiness.
pub fn objectIsTrue(obj: *c.PyObject) ?bool {
    const value = c.PyObject_IsTrue(obj);
    if (value < 0) return null;
    return value != 0;
}

/// Convert a float object to f64.
pub fn floatAsDouble(obj: *c.PyObject) ?f64 {
    const value = c.PyFloat_AsDouble(obj);
    if (c.PyErr_Occurred() != null) return null;
    return value;
}

/// Create a long from a base-10 string.
pub fn longFromString(text: [:0]const u8) ?Object {
    const value = c.PyLong_FromString(@ptrCast(text.ptr), null, 10) orelse return null;
    return Object.owned(value);
}

/// Create a dict iterator for low-level loops.
pub fn dictIter(dict: *c.PyObject) DictIter {
    return .{ .dict = dict };
}

/// Advance a dict iteration with PyDict_Next.
pub fn dictNext(
    dict: *c.PyObject,
    pos: *c.Py_ssize_t,
    key: *?*c.PyObject,
    value: *?*c.PyObject,
) bool {
    return c.PyDict_Next(dict, pos, key, value) != 0;
}

/// Convert a Zig value to a Python object and wrap it.
pub fn toObject(value: anytype) ?Object {
    const obj = toPy(@TypeOf(value), value) orelse return null;
    return Object.owned(obj);
}

/// Import a module by name.
pub fn importModule(name: [:0]const u8) ?Object {
    const obj = c.PyImport_ImportModule(@ptrCast(name.ptr));
    if (obj == null) return null;
    return Object.owned(obj);
}

// ============================================================================
// Collection conversions
// ============================================================================

/// Convert a Python list into an owned slice.
pub fn listToSlice(comptime T: type, gpa: Allocator, list: List) ?[]T {
    const size = list.len() orelse return null;
    const buffer = gpa.alloc(T, size) catch {
        raise(.MemoryError, "out of memory");
        return null;
    };
    for (0..size) |i| {
        const item = list.get(i) orelse {
            gpa.free(buffer);
            return null;
        };
        const value = fromPy(T, item.ptr) orelse {
            gpa.free(buffer);
            return null;
        };
        buffer[i] = value;
    }
    return buffer;
}

/// Convert a Python tuple into an owned slice.
pub fn tupleToSlice(comptime T: type, gpa: Allocator, tuple: Tuple) ?[]T {
    const size = tuple.len() orelse return null;
    const buffer = gpa.alloc(T, size) catch {
        raise(.MemoryError, "out of memory");
        return null;
    };
    for (0..size) |i| {
        const item = tuple.get(i) orelse {
            gpa.free(buffer);
            return null;
        };
        const value = fromPy(T, item.ptr) orelse {
            gpa.free(buffer);
            return null;
        };
        buffer[i] = value;
    }
    return buffer;
}

/// Convert a Python dict into an owned slice of key/value pairs.
pub fn dictToEntries(
    comptime K: type,
    comptime V: type,
    gpa: Allocator,
    dict: Dict,
) ?[]struct { key: K, value: V } {
    const size = dict.len() orelse return null;
    const Entry = struct { key: K, value: V };
    const buffer = gpa.alloc(Entry, size) catch {
        raise(.MemoryError, "out of memory");
        return null;
    };
    var it = dict.iter();
    var i: usize = 0;
    while (it.next()) |entry| {
        if (i >= size) break;
        const key = fromPy(K, entry.key.ptr) orelse {
            gpa.free(buffer);
            return null;
        };
        const value = fromPy(V, entry.value.ptr) orelse {
            gpa.free(buffer);
            return null;
        };
        buffer[i] = .{ .key = key, .value = value };
        i += 1;
    }
    return buffer[0..i];
}

/// Convert a Zig slice into a Python list.
pub fn toList(comptime T: type, values: []const T) ?List {
    var list = List.init(values.len) orelse return null;
    for (values, 0..) |v, i| {
        if (!list.set(i, v)) {
            list.deinit();
            return null;
        }
    }
    return list;
}

/// Convert a Zig slice into a Python tuple.
pub fn toTuple(comptime T: type, values: []const T) ?Tuple {
    const tuple_obj = c.PyTuple_New(@intCast(values.len)) orelse return null;
    for (values, 0..) |v, i| {
        const item_obj = toPy(T, v) orelse {
            c.Py_DecRef(tuple_obj);
            return null;
        };
        if (c.PyTuple_SetItem(tuple_obj, @intCast(i), item_obj) != 0) {
            c.Py_DecRef(item_obj);
            c.Py_DecRef(tuple_obj);
            return null;
        }
    }
    return Tuple.owned(tuple_obj);
}

/// Convert a Zig slice of entries into a Python dict.
pub fn toDict(
    comptime K: type,
    comptime V: type,
    entries: []const struct { key: K, value: V },
) ?Dict {
    var dict = Dict.init() orelse return null;
    for (entries) |entry| {
        if (!dict.setItem(entry.key, entry.value)) {
            dict.deinit();
            return null;
        }
    }
    return dict;
}

// ============================================================================
// Python <-> Zig type conversions
// ============================================================================

/// Convert a Python object to a Zig value.
pub fn fromPy(comptime T: type, obj: ?*c.PyObject) ?T {
    // Non-optional types require a valid object
    const ptr = obj orelse {
        // For optional types, null means null
        if (comptime isOptionalType(T)) return null;
        _ = c.PyErr_SetString(c.PyExc_TypeError, "missing argument");
        return null;
    };

    // None maps to null for optional types
    if (comptime isOptionalType(T)) {
        if (checkNone(ptr)) return @as(T, null);
        const Child = @typeInfo(T).optional.child;
        return fromPy(Child, ptr);
    }

    switch (T) {
        // Wrapper types
        Object => return Object.borrowed(ptr),
        Bytes => {
            if (c.PyBytes_Check(ptr) == 0) {
                raise(.TypeError, "expected bytes");
                return null;
            }
            return Bytes.borrowed(ptr);
        },
        List => {
            if (c.PyList_Check(ptr) == 0) {
                raise(.TypeError, "expected list");
                return null;
            }
            return List.borrowed(ptr);
        },
        Tuple => {
            if (c.PyTuple_Check(ptr) == 0) {
                raise(.TypeError, "expected tuple");
                return null;
            }
            return Tuple.borrowed(ptr);
        },
        Dict => {
            if (c.PyDict_Check(ptr) == 0) {
                raise(.TypeError, "expected dict");
                return null;
            }
            return Dict.borrowed(ptr);
        },
        // String slices
        []const u8 => {
            var len: c.Py_ssize_t = 0;
            const raw = c.PyUnicode_AsUTF8AndSize(ptr, &len) orelse return null;
            const cptr: [*]const u8 = @ptrCast(raw);
            return cptr[0..@intCast(len)];
        },
        [:0]const u8 => {
            var len: c.Py_ssize_t = 0;
            const raw = c.PyUnicode_AsUTF8AndSize(ptr, &len) orelse return null;
            const cptr: [*:0]const u8 = @ptrCast(raw);
            return cptr[0..@intCast(len) :0];
        },
        // Boolean
        bool => {
            const result = c.PyObject_IsTrue(ptr);
            if (result < 0) return null;
            return result != 0;
        },
        // Numeric types fall through to typeInfo-based handling
        else => switch (@typeInfo(T)) {
            .int => |int_info| {
                if (int_info.signedness == .signed) {
                    const value = c.PyLong_AsLongLong(ptr);
                    if (c.PyErr_Occurred() != null) return null;
                    return math.cast(T, value) orelse {
                        raise(.OverflowError, "integer out of range");
                        return null;
                    };
                }
                const value = c.PyLong_AsUnsignedLongLong(ptr);
                if (c.PyErr_Occurred() != null) return null;
                return math.cast(T, value) orelse {
                    raise(.OverflowError, "integer out of range");
                    return null;
                };
            },
            .float => {
                const value = c.PyFloat_AsDouble(ptr);
                if (c.PyErr_Occurred() != null) return null;
                return @floatCast(value);
            },
            else => @compileError(fmt.comptimePrint(
                "unsupported parameter type: {s}",
                .{@typeName(T)},
            )),
        },
    }
}

/// Convert a Zig value to a Python object.
pub fn toPy(comptime T: type, value: T) ?*c.PyObject {
    // Handle optional: null -> None, otherwise unwrap
    if (comptime isOptionalType(T)) {
        if (value) |v| {
            const Child = @typeInfo(T).optional.child;
            return toPy(Child, v);
        }
        return c.Py_BuildValue("");
    }

    switch (T) {
        // Raw PyObject pointers pass through
        ?*c.PyObject, *c.PyObject => return value,
        // Wrapper types - transfer or share ownership appropriately
        Object => {
            if (!value.owns_ref) {
                c.Py_IncRef(value.ptr);
            }
            return value.ptr;
        },
        Bytes => {
            if (!value.obj.owns_ref) {
                c.Py_IncRef(value.obj.ptr);
            }
            return value.obj.ptr;
        },
        List => {
            if (!value.obj.owns_ref) {
                c.Py_IncRef(value.obj.ptr);
            }
            return value.obj.ptr;
        },
        Tuple => {
            if (!value.obj.owns_ref) {
                c.Py_IncRef(value.obj.ptr);
            }
            return value.obj.ptr;
        },
        Dict => {
            if (!value.obj.owns_ref) {
                c.Py_IncRef(value.obj.ptr);
            }
            return value.obj.ptr;
        },
        // String slices
        []const u8, [:0]const u8 => {
            return c.PyUnicode_FromStringAndSize(value.ptr, @intCast(value.len));
        },
        // Boolean
        bool => return c.PyBool_FromLong(if (value) 1 else 0),
        // Numeric types fall through to typeInfo-based handling
        else => switch (@typeInfo(T)) {
            .int => |int_info| {
                if (int_info.signedness == .signed) {
                    return c.PyLong_FromLongLong(@intCast(value));
                }
                return c.PyLong_FromUnsignedLongLong(@intCast(value));
            },
            .float => return c.PyFloat_FromDouble(@floatCast(value)),
            else => @compileError(fmt.comptimePrint(
                "unsupported return type: {s}",
                .{@typeName(T)},
            )),
        },
    }
}

// ============================================================================
// Helper utilities
// ============================================================================

/// Check if a type is optional.
pub fn isOptionalType(comptime T: type) bool {
    return @typeInfo(T) == .optional;
}
