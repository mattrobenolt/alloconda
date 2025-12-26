const std = @import("std");
const fmt = std.fmt;
const math = std.math;
const mem = std.mem;
const Allocator = mem.Allocator;
const big_int = math.big.int;

const errors = @import("errors.zig");
const raise = errors.raise;
const PyError = errors.PyError;
const ffi = @import("ffi.zig");
const c = ffi.c;
const allocator = ffi.allocator;
const PyObject = ffi.PyObject;
const PyImport = ffi.PyImport;
const PyList = ffi.PyList;
const PyTuple = ffi.PyTuple;
const PyDict = ffi.PyDict;
const PyBytes = ffi.PyBytes;
const PyUnicode = ffi.PyUnicode;
const PyBuffer = ffi.PyBuffer;
const PyLong = ffi.PyLong;
const PyFloat = ffi.PyFloat;
const PyBool = ffi.PyBool;

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
            PyObject.decRef(self.ptr);
        }
    }

    /// Increment the reference count and return an owned Object.
    pub fn incref(self: Object) Object {
        PyObject.incRef(self.ptr);
        return .{ .ptr = self.ptr, .owns_ref = true };
    }

    /// Convert to a Zig value.
    pub fn as(self: Object, comptime T: type) PyError!T {
        return fromPy(T, self.ptr);
    }

    /// Convert a Zig value into a new Python object.
    pub fn from(comptime T: type, value: T) PyError!Object {
        const obj = try toPy(T, value);
        return .owned(obj);
    }

    pub fn toPyObject(self: Object) PyError!*c.PyObject {
        if (!self.owns_ref) PyObject.incRef(self.ptr);
        return self.ptr;
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
    pub fn unicodeSlice(self: Object) PyError![]const u8 {
        return PyUnicode.slice(self.ptr);
    }

    /// Borrow the byte slice for a bytes object.
    pub fn bytesSlice(self: Object) PyError![]const u8 {
        return PyBytes.slice(self.ptr);
    }

    /// Convert the object to truthiness.
    pub fn isTrue(self: Object) PyError!bool {
        return PyObject.isTrue(self.ptr);
    }

    /// Return the string representation of an object.
    pub fn str(self: Object) PyError!Object {
        return .owned(try PyObject.str(self.ptr));
    }

    /// Call with no arguments.
    pub fn call0(self: Object) PyError!Object {
        return .owned(try PyObject.callNoArgs(self.ptr));
    }

    /// Call with one argument.
    pub fn call1(self: Object, comptime T: type, arg: T) PyError!Object {
        var arg_obj: ?*c.PyObject = try toPy(T, arg);
        errdefer if (arg_obj) |obj| PyObject.decRef(obj);

        const tuple = try PyTuple.new(1);
        defer PyObject.decRef(tuple);

        try PyTuple.setItem(tuple, 0, arg_obj.?);
        arg_obj = null;

        return .owned(try PyObject.callObject(self.ptr, tuple));
    }

    /// Call with two arguments.
    pub fn call2(self: Object, comptime T0: type, arg0: T0, comptime T1: type, arg1: T1) PyError!Object {
        var arg0_obj: ?*c.PyObject = try toPy(T0, arg0);
        errdefer if (arg0_obj) |obj| PyObject.decRef(obj);

        var arg1_obj: ?*c.PyObject = try toPy(T1, arg1);
        errdefer if (arg1_obj) |obj| PyObject.decRef(obj);

        const tuple = try PyTuple.new(2);
        defer PyObject.decRef(tuple);

        try PyTuple.setItem(tuple, 0, arg0_obj.?);
        arg0_obj = null;

        try PyTuple.setItem(tuple, 1, arg1_obj.?);
        arg1_obj = null;

        return .owned(try PyObject.callObject(self.ptr, tuple));
    }

    /// Get an attribute by name.
    pub fn getAttr(self: Object, name: [:0]const u8) PyError!Object {
        return .owned(try PyObject.getAttrString(self.ptr, name));
    }

    /// Set an attribute by name.
    pub fn setAttr(self: Object, name: [:0]const u8, comptime T: type, value: T) PyError!void {
        const value_obj = try toPy(T, value);
        defer PyObject.decRef(value_obj);
        try PyObject.setAttrString(self.ptr, name, value_obj);
    }

    /// Call a method with no arguments.
    pub fn callMethod0(self: Object, name: [:0]const u8) PyError!Object {
        const meth = try self.getAttr(name);
        defer meth.deinit();
        return meth.call0();
    }

    /// Call a method with one argument.
    pub fn callMethod1(self: Object, name: [:0]const u8, comptime T: type, arg: T) PyError!Object {
        const meth = try self.getAttr(name);
        defer meth.deinit();
        return meth.call1(T, arg);
    }

    /// Call a method with two arguments.
    pub fn callMethod2(
        self: Object,
        name: [:0]const u8,
        comptime T0: type,
        arg0: T0,
        comptime T1: type,
        arg1: T1,
    ) PyError!Object {
        const meth = try self.getAttr(name);
        defer meth.deinit();
        return meth.call2(T0, arg0, T1, arg1);
    }
};

/// Wrapper for Python bytes objects.
pub const Bytes = struct {
    obj: Object,

    /// Create bytes from a slice.
    pub fn fromSlice(data: []const u8) PyError!Bytes {
        return .owned(try PyBytes.fromSlice(data));
    }

    pub fn fromObject(obj: Object) PyError!Bytes {
        if (!obj.isBytes()) return raise(.TypeError, "expected bytes");
        return .{ .obj = .borrowed(obj.ptr) };
    }

    pub fn toPyObject(self: Bytes) PyError!*c.PyObject {
        return self.obj.toPyObject();
    }

    pub fn toObject(self: Bytes) PyError!Object {
        const obj = try self.toPyObject();
        return .owned(obj);
    }

    /// Borrow a bytes object without changing refcount.
    pub fn borrowed(ptr: *c.PyObject) Bytes {
        return .{ .obj = .borrowed(ptr) };
    }

    /// Own a bytes object reference.
    pub fn owned(ptr: *c.PyObject) Bytes {
        return .{ .obj = .owned(ptr) };
    }

    /// Release the reference if owned.
    pub fn deinit(self: Bytes) void {
        self.obj.deinit();
    }

    /// Return the byte length.
    pub fn len(self: Bytes) PyError!usize {
        return PyBytes.size(self.obj.ptr);
    }

    /// Borrow the underlying bytes as a slice.
    pub fn slice(self: Bytes) PyError![]const u8 {
        return PyBytes.slice(self.obj.ptr);
    }
};

/// Wrapper for Python buffer protocol.
pub const Buffer = struct {
    view: c.Py_buffer,

    /// Request a buffer view (read-only).
    pub fn init(obj: Object) PyError!Buffer {
        const view = try PyBuffer.get(obj.ptr, c.PyBUF_SIMPLE);
        return .{ .view = view };
    }

    pub fn fromObject(obj: Object) PyError!Buffer {
        if (!checkBuffer(obj.ptr)) return raise(.TypeError, "expected buffer");
        return init(obj);
    }

    /// Release the buffer view.
    pub fn release(self: *Buffer) void {
        PyBuffer.release(&self.view);
    }

    /// Return the byte length.
    pub fn len(self: *const Buffer) usize {
        return @intCast(self.view.len);
    }

    /// Borrow the underlying bytes as a slice.
    pub fn slice(self: *const Buffer) []const u8 {
        const ptr: [*]const u8 = @ptrCast(self.view.buf);
        return ptr[0..self.len()];
    }
};

/// Wrapper for arbitrary-precision Python integers.
pub const BigInt = struct {
    value: big_int.Managed,

    pub fn deinit(self: *BigInt) void {
        self.value.deinit();
    }

    pub fn fromObject(obj: Object) PyError!BigInt {
        if (!obj.isLong()) return raise(.TypeError, "expected int");

        const text_obj = try PyObject.str(obj.ptr);
        defer PyObject.decRef(text_obj);
        const text = try PyUnicode.slice(text_obj);
        var managed = big_int.Managed.init(allocator) catch return raise(.MemoryError, "out of memory");

        errdefer managed.deinit();
        managed.setString(10, text) catch |err| {
            return switch (err) {
                error.OutOfMemory => raise(.MemoryError, "out of memory"),
                error.InvalidCharacter, error.InvalidBase => raise(.ValueError, "invalid integer string"),
            };
        };
        return .{ .value = managed };
    }

    pub fn toPyObject(self: BigInt) PyError!*c.PyObject {
        const text = self.value.toConst().toStringAlloc(allocator, 10, .lower) catch {
            return raise(.MemoryError, "out of memory");
        };
        defer allocator.free(text);
        const buf = allocator.alloc(u8, text.len + 1) catch {
            return raise(.MemoryError, "out of memory");
        };
        defer allocator.free(buf);
        @memcpy(buf[0..text.len], text);
        buf[text.len] = 0;
        const text_z: [:0]const u8 = buf[0..text.len :0];
        return PyLong.fromString(text_z);
    }

    pub fn toObject(self: BigInt) PyError!Object {
        const obj = try self.toPyObject();
        return .owned(obj);
    }
};

/// Unified Python int representation: fast 64-bit or allocated bigint.
pub const Int = union(enum) {
    small: Long,
    big: BigInt,

    pub fn deinit(self: *Int) void {
        switch (self.*) {
            .big => |*big| big.deinit(),
            .small => {},
        }
    }

    pub fn fromObject(obj: Object) PyError!Int {
        if (!obj.isLong()) return raise(.TypeError, "expected int");
        const parsed = try PyLong.asLongLongAndOverflow(obj.ptr);
        if (parsed.overflow == 0) {
            return .{ .small = .{ .signed = @intCast(parsed.value) } };
        }
        if (parsed.overflow > 0) {
            const unsigned_value = PyLong.asUnsignedLongLong(obj.ptr) catch {
                c.PyErr_Clear();
                const big = try BigInt.fromObject(obj);
                return .{ .big = big };
            };
            return .{ .small = .{ .unsigned = unsigned_value } };
        }
        const big = try BigInt.fromObject(obj);
        return .{ .big = big };
    }

    pub fn toPyObject(value: Int) PyError!*c.PyObject {
        return switch (value) {
            .small => |small| Long.toPyObject(small),
            .big => |big| big.toPyObject(),
        };
    }

    pub fn toObject(value: Int) PyError!Object {
        const obj = try value.toPyObject();
        return .owned(obj);
    }
};

/// Result of parsing a Python int into a 64-bit signed/unsigned value.
pub const Long = union(enum) {
    signed: i64,
    unsigned: u64,

    pub fn fromObject(obj: Object) PyError!Long {
        if (!obj.isLong()) return raise(.TypeError, "expected int");
        const parsed = try PyLong.asLongLongAndOverflow(obj.ptr);
        if (parsed.overflow == 0) {
            return .{ .signed = @intCast(parsed.value) };
        }
        if (parsed.overflow > 0) {
            const unsigned_value = try PyLong.asUnsignedLongLong(obj.ptr);
            return .{ .unsigned = unsigned_value };
        }
        return raise(.OverflowError, "integer out of range");
    }

    pub fn unsignedMask(obj: Object) PyError!u64 {
        if (!obj.isLong()) return raise(.TypeError, "expected int");
        return PyLong.asUnsignedLongLongMask(obj.ptr);
    }

    pub fn toPyObject(value: Long) PyError!*c.PyObject {
        return switch (value) {
            .signed => |v| PyLong.fromLongLong(v),
            .unsigned => |v| PyLong.fromUnsignedLongLong(v),
        };
    }

    pub fn toObject(value: Long) PyError!Object {
        const obj = try value.toPyObject();
        return .owned(obj);
    }

    pub fn fromString(text: [:0]const u8) PyError!Object {
        return .owned(try PyLong.fromString(text));
    }
};

/// Wrapper for Python list objects.
pub const List = struct {
    obj: Object,

    /// Borrow a list without changing refcount.
    pub fn borrowed(ptr: *c.PyObject) List {
        return .{ .obj = .borrowed(ptr) };
    }

    pub fn fromObject(obj: Object) PyError!List {
        if (!obj.isList()) return raise(.TypeError, "expected list");
        return .{ .obj = .borrowed(obj.ptr) };
    }

    pub fn toPyObject(self: List) PyError!*c.PyObject {
        return self.obj.toPyObject();
    }

    pub fn toObject(self: List) PyError!Object {
        const obj = try self.toPyObject();
        return .owned(obj);
    }

    /// Own a list reference.
    pub fn owned(ptr: *c.PyObject) List {
        return .{ .obj = .owned(ptr) };
    }

    /// Create a new list with the given size.
    pub fn init(size: usize) PyError!List {
        const list_obj = try PyList.new(size);
        return .owned(list_obj);
    }

    /// Create a new list from a Zig slice.
    pub fn fromSlice(comptime T: type, values: []const T) PyError!List {
        var list: List = try .init(values.len);
        errdefer list.deinit();
        for (values, 0..) |v, i| try list.set(T, i, v);
        return list;
    }

    /// Release the reference if owned.
    pub fn deinit(self: List) void {
        self.obj.deinit();
    }

    /// Get the list length.
    pub fn len(self: List) PyError!usize {
        return PyList.size(self.obj.ptr);
    }

    /// Borrow the item at the given index.
    pub fn get(self: List, index: usize) PyError!Object {
        const item = try PyList.getItem(self.obj.ptr, index);
        return .borrowed(item);
    }

    /// Set the item at the given index.
    pub fn set(self: List, comptime T: type, index: usize, value: T) PyError!void {
        const value_obj = try toPy(T, value);
        errdefer PyObject.decRef(value_obj);
        try PyList.setItem(self.obj.ptr, index, value_obj);
    }

    /// Append an item to the list.
    pub fn append(self: List, comptime T: type, value: T) PyError!void {
        const value_obj = try toPy(T, value);
        defer PyObject.decRef(value_obj);
        try PyList.append(self.obj.ptr, value_obj);
    }

    /// Convert this list into an owned Zig slice.
    pub fn toSlice(self: List, comptime T: type, gpa: Allocator) PyError![]T {
        const size = try self.len();
        const buffer = gpa.alloc(T, size) catch {
            return raise(.MemoryError, "out of memory");
        };
        errdefer gpa.free(buffer);
        for (0..size) |i| {
            const item = try self.get(i);
            const value = try fromPy(T, item.ptr);
            buffer[i] = value;
        }
        return buffer;
    }
};

/// Wrapper for Python dict objects.
pub const Dict = struct {
    obj: Object,

    /// Borrow a dict without changing refcount.
    pub fn borrowed(ptr: *c.PyObject) Dict {
        return .{ .obj = .borrowed(ptr) };
    }

    pub fn fromObject(obj: Object) PyError!Dict {
        if (!obj.isDict()) return raise(.TypeError, "expected dict");
        return .{ .obj = .borrowed(obj.ptr) };
    }

    pub fn toPyObject(self: Dict) PyError!*c.PyObject {
        return self.obj.toPyObject();
    }

    pub fn toObject(self: Dict) PyError!Object {
        const obj = try self.toPyObject();
        return .owned(obj);
    }

    /// Own a dict reference.
    pub fn owned(ptr: *c.PyObject) Dict {
        return .{ .obj = .owned(ptr) };
    }

    /// Create a new dict.
    pub fn init() PyError!Dict {
        const dict_obj = try PyDict.new();
        return .owned(dict_obj);
    }

    /// Create a dict from key/value entries.
    pub fn fromEntries(
        comptime K: type,
        comptime V: type,
        entries: []const struct { key: K, value: V },
    ) PyError!Dict {
        var dict: Dict = try .init();
        errdefer dict.deinit();
        for (entries) |entry| {
            try dict.setItem(K, entry.key, V, entry.value);
        }
        return dict;
    }

    /// Release the reference if owned.
    pub fn deinit(self: Dict) void {
        self.obj.deinit();
    }

    /// Get the dict length.
    pub fn len(self: Dict) PyError!usize {
        return PyDict.size(self.obj.ptr);
    }

    /// Borrow a value by key.
    pub fn getItem(self: Dict, comptime K: type, key: K) PyError!?Object {
        const key_obj = try toPy(K, key);
        defer PyObject.decRef(key_obj);
        const item = try PyDict.getItemWithError(self.obj.ptr, key_obj);
        if (item == null) return null;
        return .borrowed(item.?);
    }

    /// Set a key to a value.
    pub fn setItem(self: Dict, comptime K: type, key: K, comptime V: type, value: V) PyError!void {
        const key_obj = try toPy(K, key);
        defer PyObject.decRef(key_obj);
        const value_obj = try toPy(V, value);
        defer PyObject.decRef(value_obj);
        try PyDict.setItem(self.obj.ptr, key_obj, value_obj);
    }

    /// Create an iterator over dict entries (borrowed references).
    pub fn iter(self: Dict) DictIter {
        return .{ .dict = self.obj.ptr };
    }

    fn Entry(comptime K: type, comptime V: type) type {
        return struct { key: K, value: V };
    }

    /// Convert this dict into an owned slice of key/value pairs.
    pub fn toEntries(
        self: Dict,
        comptime K: type,
        comptime V: type,
        gpa: Allocator,
    ) PyError![]Entry(K, V) {
        const size = try self.len();
        const buffer = gpa.alloc(Entry(K, V), size) catch {
            return raise(.MemoryError, "out of memory");
        };
        errdefer gpa.free(buffer);

        var it = self.iter();
        var i: usize = 0;
        while (it.next()) |entry| {
            if (i >= size) break;
            const key = try fromPy(K, entry.key.ptr);
            const value = try fromPy(V, entry.value.ptr);
            buffer[i] = .{ .key = key, .value = value };
            i += 1;
        }
        return buffer[0..i];
    }
};

/// Iterator over dict entries using PyDict_Next.
pub const DictIter = struct {
    dict: *c.PyObject,
    pos: c.Py_ssize_t = 0,

    /// Borrowed dict key/value pair.
    pub const Entry = struct {
        key: Object,
        value: Object,
    };

    pub fn fromObject(obj: Object) PyError!@This() {
        if (!obj.isDict()) return raise(.TypeError, "expected dict");
        return .{ .dict = obj.ptr };
    }

    pub fn fromPtr(ptr: *c.PyObject) PyError!@This() {
        return .fromObject(.borrowed(ptr));
    }

    /// Return the next borrowed entry, or null when complete.
    pub fn next(self: *@This()) ?Entry {
        const entry = PyDict.next(self.dict, &self.pos) orelse return null;
        return .{
            .key = .borrowed(entry.key),
            .value = .borrowed(entry.value),
        };
    }
};

/// Wrapper for Python tuple objects.
pub const Tuple = struct {
    obj: Object,

    /// Borrow a tuple without changing refcount.
    pub fn borrowed(ptr: *c.PyObject) Tuple {
        return .{ .obj = .borrowed(ptr) };
    }

    pub fn fromObject(obj: Object) PyError!Tuple {
        if (!obj.isTuple()) return raise(.TypeError, "expected tuple");
        return .{ .obj = .borrowed(obj.ptr) };
    }

    pub fn toPyObject(self: Tuple) PyError!*c.PyObject {
        return self.obj.toPyObject();
    }

    pub fn toObject(self: Tuple) PyError!Object {
        const obj = try self.toPyObject();
        return .owned(obj);
    }

    /// Own a tuple reference.
    pub fn owned(ptr: *c.PyObject) Tuple {
        return .{ .obj = .owned(ptr) };
    }

    /// Create a new tuple with the given size.
    pub fn init(size: usize) PyError!Tuple {
        const tuple_obj = try PyTuple.new(size);
        return .owned(tuple_obj);
    }

    /// Create a new tuple from a Zig slice.
    pub fn fromSlice(comptime T: type, values: []const T) PyError!Tuple {
        const tuple_obj = try PyTuple.new(values.len);
        errdefer PyObject.decRef(tuple_obj);
        for (values, 0..) |v, i| {
            var item_obj: ?*c.PyObject = try toPy(T, v);
            errdefer if (item_obj) |obj| PyObject.decRef(obj);
            try PyTuple.setItem(tuple_obj, i, item_obj.?);
            item_obj = null;
        }
        return .owned(tuple_obj);
    }

    /// Release the reference if owned.
    pub fn deinit(self: Tuple) void {
        self.obj.deinit();
    }

    /// Get the tuple length.
    pub fn len(self: Tuple) PyError!usize {
        return PyTuple.size(self.obj.ptr);
    }

    /// Borrow the item at the given index.
    pub fn get(self: Tuple, index: usize) PyError!Object {
        const item = try PyTuple.getItem(self.obj.ptr, index);
        return .borrowed(item);
    }

    /// Set the item at the given index.
    pub fn set(self: Tuple, comptime T: type, index: usize, value: T) PyError!void {
        const value_obj = try toPy(T, value);
        errdefer PyObject.decRef(value_obj);
        try PyTuple.setItem(self.obj.ptr, index, value_obj);
    }

    /// Convert this tuple into an owned Zig slice.
    pub fn toSlice(self: Tuple, comptime T: type, gpa: Allocator) PyError![]T {
        const size = try self.len();
        const buffer = gpa.alloc(T, size) catch return raise(.MemoryError, "out of memory");
        errdefer gpa.free(buffer);
        for (0..size) |i| {
            const item = try self.get(i);
            const value = try fromPy(T, item.ptr);
            buffer[i] = value;
        }
        return buffer;
    }
};

/// RAII guard for the Python GIL.
pub const GIL = struct {
    state: c.PyGILState_STATE,

    /// Acquire the GIL and return a guard.
    pub fn acquire() @This() {
        return .{ .state = c.PyGILState_Ensure() };
    }

    /// Release the GIL for this guard.
    pub fn deinit(self: *const @This()) void {
        c.PyGILState_Release(self.state);
    }
};

/// Return true if the object is Python None.
inline fn checkNone(obj: *c.PyObject) bool {
    if (@hasDecl(c, "Py_IsNone")) {
        return c.Py_IsNone(obj) != 0;
    }
    return obj == ffi.pyNone();
}

/// Return true if the object is a Unicode string.
inline fn checkUnicode(obj: *c.PyObject) bool {
    return c.PyUnicode_Check(obj) != 0;
}

/// Return true if the object is a bytes object.
inline fn checkBytes(obj: *c.PyObject) bool {
    return c.PyBytes_Check(obj) != 0;
}

/// Return true if the object is a bool.
inline fn checkBool(obj: *c.PyObject) bool {
    // Avoid using PyBool_Check macro which relies on _PyObject_CAST_CONST
    // that Zig can't translate on Python 3.10. Instead, compare type directly.
    const obj_type = c.Py_TYPE(obj);
    return obj_type == &c.PyBool_Type;
}

/// Return true if the object is an int.
inline fn checkLong(obj: *c.PyObject) bool {
    return c.PyLong_Check(obj) != 0;
}

/// Return true if the object is a Buffer.
inline fn checkBuffer(obj: *c.PyObject) bool {
    return c.PyObject_CheckBuffer(obj) != 0;
}

/// Return true if the object is a float.
inline fn checkFloat(obj: *c.PyObject) bool {
    return c.PyFloat_Check(obj) != 0;
}

/// Return true if the object is a list.
inline fn checkList(obj: *c.PyObject) bool {
    return c.PyList_Check(obj) != 0;
}

/// Return true if the object is a tuple.
inline fn checkTuple(obj: *c.PyObject) bool {
    return c.PyTuple_Check(obj) != 0;
}

/// Return true if the object is a dict.
inline fn checkDict(obj: *c.PyObject) bool {
    return c.PyDict_Check(obj) != 0;
}

/// Import a module by name.
pub fn importModule(name: [:0]const u8) PyError!Object {
    return .owned(try PyImport.importModule(name));
}

/// Convert a Python object to a Zig value.
pub fn fromPy(comptime T: type, obj: ?*c.PyObject) PyError!T {
    // Non-optional types require a valid object.
    const ptr = obj orelse {
        if (comptime isOptionalType(T)) return @as(T, null);
        return raise(.TypeError, "missing argument");
    };

    // None maps to null for optional types.
    if (comptime isOptionalType(T)) {
        if (checkNone(ptr)) return @as(T, null);
        const Child = @typeInfo(T).optional.child;
        const value = try fromPy(Child, ptr);
        return @as(T, value);
    }

    return switch (T) {
        // Wrapper types
        Object => Object.borrowed(ptr),
        Bytes => try Bytes.fromObject(.borrowed(ptr)),
        BigInt => try BigInt.fromObject(.borrowed(ptr)),
        Long => try Long.fromObject(.borrowed(ptr)),
        Int => try Int.fromObject(.borrowed(ptr)),
        Buffer => try Buffer.fromObject(.borrowed(ptr)),
        List => try List.fromObject(.borrowed(ptr)),
        Tuple => try Tuple.fromObject(.borrowed(ptr)),
        Dict => try Dict.fromObject(.borrowed(ptr)),
        // String slices
        []const u8 => try Object.borrowed(ptr).unicodeSlice(),
        [:0]const u8 => {
            const slice = try Object.borrowed(ptr).unicodeSlice();
            return slice[0..slice.len :0];
        },
        // Boolean
        bool => try Object.borrowed(ptr).isTrue(),
        // Numeric types fall through to typeInfo-based handling
        else => switch (@typeInfo(T)) {
            .int => |info| switch (info.signedness) {
                .signed => {
                    const value = try PyLong.asLongLong(ptr);
                    return math.cast(T, value) orelse {
                        return raise(.OverflowError, "integer out of range");
                    };
                },
                .unsigned => {
                    const value = try PyLong.asUnsignedLongLong(ptr);
                    return math.cast(T, value) orelse {
                        return raise(.OverflowError, "integer out of range");
                    };
                },
            },
            .float => {
                return @floatCast(try PyFloat.asDouble(ptr));
            },
            else => @compileError(fmt.comptimePrint(
                "unsupported parameter type: {s}",
                .{@typeName(T)},
            )),
        },
    };
}

/// Convert a Zig value to a Python object.
pub fn toPy(comptime T: type, value: T) PyError!*c.PyObject {
    // Handle optional: null -> None, otherwise unwrap.
    if (comptime isOptionalType(T)) {
        if (value) |v| {
            const Child = @typeInfo(T).optional.child;
            return toPy(Child, v);
        }
        PyObject.incRef(ffi.pyNone());
        return ffi.pyNone();
    }

    return switch (T) {
        // Raw PyObject pointers pass through.
        *c.PyObject => value,
        // Wrapper types - transfer or share ownership appropriately.
        Object => value.toPyObject(),
        Bytes => value.toPyObject(),
        BigInt => value.toPyObject(),
        Long => value.toPyObject(),
        Int => value.toPyObject(),
        List => value.toPyObject(),
        Tuple => value.toPyObject(),
        Dict => value.toPyObject(),
        // String slices.
        []const u8, [:0]const u8 => PyUnicode.fromSlice(value),
        // Boolean.
        bool => PyBool.fromBool(value),
        // Numeric types fall through to typeInfo-based handling.
        else => switch (@typeInfo(T)) {
            .int => |info| switch (info.signedness) {
                .signed => PyLong.fromLongLong(@intCast(value)),
                .unsigned => PyLong.fromUnsignedLongLong(@intCast(value)),
            },
            .float => PyFloat.fromDouble(@floatCast(value)),
            else => @compileError(fmt.comptimePrint(
                "unsupported return type: {s}",
                .{@typeName(T)},
            )),
        },
    };
}

/// Borrow Python None as an Object.
pub fn none() Object {
    return .borrowed(ffi.pyNone());
}

/// Check if a type is optional.
pub fn isOptionalType(comptime T: type) bool {
    return @typeInfo(T) == .optional;
}
