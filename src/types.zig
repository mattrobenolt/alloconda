const std = @import("std");
const fmt = std.fmt;
const math = std.math;
const mem = std.mem;
const Allocator = mem.Allocator;
const big_int = math.big.int;

const errors = @import("errors.zig");
const raise = errors.raise;
const ffi = @import("ffi.zig");
const c = ffi.c;
const allocator = ffi.allocator;

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

    /// Convert a Zig value into a new Python object.
    pub fn from(comptime T: type, value: T) ?Object {
        const obj = toPy(T, value) orelse return null;
        return .owned(obj);
    }

    pub fn toPyObject(self: Object) ?*c.PyObject {
        if (!self.owns_ref) {
            c.Py_IncRef(self.ptr);
        }
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
    pub fn unicodeSlice(self: Object) ?[]const u8 {
        var len: c.Py_ssize_t = 0;
        const raw = c.PyUnicode_AsUTF8AndSize(self.ptr, &len) orelse return null;
        const ptr: [*]const u8 = @ptrCast(raw);
        return ptr[0..@intCast(len)];
    }

    /// Borrow the byte slice for a bytes object.
    pub fn bytesSlice(self: Object) ?[]const u8 {
        var len: c.Py_ssize_t = 0;
        var raw: [*c]u8 = null;
        if (c.PyBytes_AsStringAndSize(self.ptr, &raw, &len) != 0) return null;
        const ptr: [*]const u8 = @ptrCast(raw);
        return ptr[0..@intCast(len)];
    }

    /// Convert the object to truthiness.
    pub fn isTrue(self: Object) ?bool {
        const value = c.PyObject_IsTrue(self.ptr);
        if (value < 0) return null;
        return value != 0;
    }

    /// Return the string representation of an object.
    pub fn str(self: Object) ?Object {
        const value = c.PyObject_Str(self.ptr) orelse return null;
        return .owned(value);
    }

    /// Call with no arguments.
    pub fn call0(self: Object) ?Object {
        if (@hasDecl(c, "PyObject_CallNoArgs")) {
            const result = c.PyObject_CallNoArgs(self.ptr);
            if (result == null) return null;
            return .owned(result);
        }

        const tuple = c.PyTuple_New(0) orelse return null;
        const result = c.PyObject_CallObject(self.ptr, tuple);
        c.Py_DecRef(tuple);
        if (result == null) return null;
        return .owned(result);
    }

    /// Call with one argument.
    pub fn call1(self: Object, comptime T: type, arg: T) ?Object {
        const arg_obj = toPy(T, arg) orelse return null;
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
        return .owned(result);
    }

    /// Call with two arguments.
    pub fn call2(self: Object, comptime T0: type, arg0: T0, comptime T1: type, arg1: T1) ?Object {
        const arg0_obj = toPy(T0, arg0) orelse return null;
        const arg1_obj = toPy(T1, arg1) orelse {
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
        return .owned(result);
    }

    /// Get an attribute by name.
    pub fn getAttr(self: Object, name: [:0]const u8) ?Object {
        const result = c.PyObject_GetAttrString(self.ptr, @ptrCast(name.ptr));
        if (result == null) return null;
        return .owned(result);
    }

    /// Set an attribute by name.
    pub fn setAttr(self: Object, name: [:0]const u8, comptime T: type, value: T) bool {
        const value_obj = toPy(T, value) orelse return false;
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
    pub fn callMethod1(self: Object, name: [:0]const u8, comptime T: type, arg: T) ?Object {
        const meth = self.getAttr(name) orelse return null;
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
    ) ?Object {
        const meth = self.getAttr(name) orelse return null;
        defer meth.deinit();
        return meth.call2(T0, arg0, T1, arg1);
    }
};

/// Wrapper for Python bytes objects.
pub const Bytes = struct {
    obj: Object,

    /// Create bytes from a slice.
    pub fn fromSlice(data: []const u8) ?Bytes {
        const obj = c.PyBytes_FromStringAndSize(data.ptr, @intCast(data.len)) orelse return null;
        return .owned(obj);
    }

    pub fn fromObject(obj: Object) ?Bytes {
        if (!obj.isBytes()) {
            raise(.TypeError, "expected bytes");
            return null;
        }
        return .{ .obj = .borrowed(obj.ptr) };
    }

    pub fn toPyObject(self: Bytes) ?*c.PyObject {
        return self.obj.toPyObject();
    }

    pub fn toObject(self: Bytes) ?Object {
        const obj = self.toPyObject() orelse return null;
        return .owned(obj);
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

/// Wrapper for Python buffer protocol.
pub const Buffer = struct {
    view: c.Py_buffer,

    /// Request a buffer view (read-only).
    pub fn init(obj: Object) ?Buffer {
        var view: c.Py_buffer = undefined;
        if (c.PyObject_GetBuffer(obj.ptr, &view, c.PyBUF_SIMPLE) != 0) {
            return null;
        }
        return .{ .view = view };
    }

    pub fn fromObject(obj: Object) ?Buffer {
        if (!checkBuffer(obj.ptr)) {
            raise(.TypeError, "expected buffer");
            return null;
        }
        return init(obj);
    }

    /// Release the buffer view.
    pub fn release(self: *Buffer) void {
        c.PyBuffer_Release(&self.view);
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

    pub fn fromObject(obj: Object) ?BigInt {
        if (!obj.isLong()) {
            raise(.TypeError, "expected int");
            return null;
        }
        const text_obj = c.PyObject_Str(obj.ptr) orelse return null;
        defer c.Py_DecRef(text_obj);
        var len: c.Py_ssize_t = 0;
        const raw = c.PyUnicode_AsUTF8AndSize(text_obj, &len) orelse return null;
        const ptr: [*]const u8 = @ptrCast(raw);
        const text: []const u8 = ptr[0..@intCast(len)];
        var managed = big_int.Managed.init(allocator) catch {
            raise(.MemoryError, "out of memory");
            return null;
        };
        errdefer managed.deinit();
        managed.setString(10, text) catch |err| {
            switch (err) {
                error.OutOfMemory => {
                    raise(.MemoryError, "out of memory");
                },
                error.InvalidCharacter, error.InvalidBase => {
                    raise(.ValueError, "invalid integer string");
                },
            }
            return null;
        };
        return .{ .value = managed };
    }

    pub fn toPyObject(self: BigInt) ?*c.PyObject {
        const text = self.value.toConst().toStringAlloc(allocator, 10, .lower) catch {
            raise(.MemoryError, "out of memory");
            return null;
        };
        defer allocator.free(text);
        const buf = allocator.alloc(u8, text.len + 1) catch {
            raise(.MemoryError, "out of memory");
            return null;
        };
        defer allocator.free(buf);
        @memcpy(buf[0..text.len], text);
        buf[text.len] = 0;
        return c.PyLong_FromString(@ptrCast(buf.ptr), null, 10);
    }

    pub fn toObject(self: BigInt) ?Object {
        const obj = self.toPyObject() orelse return null;
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

    pub fn fromObject(obj: Object) ?Int {
        if (!obj.isLong()) {
            raise(.TypeError, "expected int");
            return null;
        }
        var overflow: c_int = 0;
        const signed_value = c.PyLong_AsLongLongAndOverflow(obj.ptr, &overflow);
        if (c.PyErr_Occurred() != null) return null;
        if (overflow == 0) {
            return .{ .small = .{ .signed = @intCast(signed_value) } };
        }
        if (overflow > 0) {
            const unsigned_value = c.PyLong_AsUnsignedLongLong(obj.ptr);
            if (c.PyErr_Occurred() != null) {
                c.PyErr_Clear();
                const big = BigInt.fromObject(obj) orelse return null;
                return .{ .big = big };
            }
            return .{ .small = .{ .unsigned = @intCast(unsigned_value) } };
        }
        const big = BigInt.fromObject(obj) orelse return null;
        return .{ .big = big };
    }

    pub fn toPyObject(value: Int) ?*c.PyObject {
        return switch (value) {
            .small => |small| Long.toPyObject(small),
            .big => |big| big.toPyObject(),
        };
    }

    pub fn toObject(value: Int) ?Object {
        const obj = value.toPyObject() orelse return null;
        return .owned(obj);
    }
};

/// Result of parsing a Python int into a 64-bit signed/unsigned value.
pub const Long = union(enum) {
    signed: i64,
    unsigned: u64,

    pub fn fromObject(obj: Object) ?Long {
        if (!obj.isLong()) {
            raise(.TypeError, "expected int");
            return null;
        }
        var overflow: c_int = 0;
        const signed_value = c.PyLong_AsLongLongAndOverflow(obj.ptr, &overflow);
        if (c.PyErr_Occurred() != null) return null;
        if (overflow == 0) {
            return .{ .signed = @intCast(signed_value) };
        }
        if (overflow > 0) {
            const unsigned_value = c.PyLong_AsUnsignedLongLong(obj.ptr);
            if (c.PyErr_Occurred() != null) return null;
            return .{ .unsigned = @intCast(unsigned_value) };
        }
        raise(.OverflowError, "integer out of range");
        return null;
    }

    pub fn unsignedMask(obj: Object) ?u64 {
        if (!obj.isLong()) {
            raise(.TypeError, "expected int");
            return null;
        }
        const value = c.PyLong_AsUnsignedLongLongMask(obj.ptr);
        if (c.PyErr_Occurred() != null) return null;
        return @intCast(value);
    }

    pub fn toPyObject(value: Long) ?*c.PyObject {
        return switch (value) {
            .signed => |signed_value| c.PyLong_FromLongLong(@intCast(signed_value)),
            .unsigned => |unsigned_value| c.PyLong_FromUnsignedLongLong(@intCast(unsigned_value)),
        };
    }

    pub fn toObject(value: Long) ?Object {
        const obj = value.toPyObject() orelse return null;
        return .owned(obj);
    }

    pub fn fromString(text: [:0]const u8) ?Object {
        const value = c.PyLong_FromString(@ptrCast(text.ptr), null, 10) orelse return null;
        return .owned(value);
    }
};

/// Wrapper for Python list objects.
pub const List = struct {
    obj: Object,

    /// Borrow a list without changing refcount.
    pub fn borrowed(ptr: *c.PyObject) List {
        return .{ .obj = .borrowed(ptr) };
    }

    pub fn fromObject(obj: Object) ?List {
        if (!obj.isList()) {
            raise(.TypeError, "expected list");
            return null;
        }
        return .{ .obj = .borrowed(obj.ptr) };
    }

    pub fn toPyObject(self: List) ?*c.PyObject {
        return self.obj.toPyObject();
    }

    pub fn toObject(self: List) ?Object {
        const obj = self.toPyObject() orelse return null;
        return .owned(obj);
    }

    /// Own a list reference.
    pub fn owned(ptr: *c.PyObject) List {
        return .{ .obj = .owned(ptr) };
    }

    /// Create a new list with the given size.
    pub fn init(size: usize) ?List {
        const list_obj = c.PyList_New(@intCast(size)) orelse return null;
        return .owned(list_obj);
    }

    /// Create a new list from a Zig slice.
    pub fn fromSlice(comptime T: type, values: []const T) ?List {
        var list: List = .init(values.len) orelse return null;
        for (values, 0..) |v, i| {
            if (!list.set(T, i, v)) {
                list.deinit();
                return null;
            }
        }
        return list;
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
        return .borrowed(item);
    }

    /// Set the item at the given index.
    pub fn set(self: List, comptime T: type, index: usize, value: T) bool {
        const value_obj = toPy(T, value) orelse return false;
        if (c.PyList_SetItem(self.obj.ptr, @intCast(index), value_obj) != 0) {
            c.Py_DecRef(value_obj);
            return false;
        }
        return true;
    }

    /// Append an item to the list.
    pub fn append(self: List, comptime T: type, value: T) bool {
        const value_obj = toPy(T, value) orelse return false;
        defer c.Py_DecRef(value_obj);
        return c.PyList_Append(self.obj.ptr, value_obj) == 0;
    }

    /// Convert this list into an owned Zig slice.
    pub fn toSlice(self: List, comptime T: type, gpa: Allocator) ?[]T {
        const size = self.len() orelse return null;
        const buffer = gpa.alloc(T, size) catch {
            raise(.MemoryError, "out of memory");
            return null;
        };
        for (0..size) |i| {
            const item = self.get(i) orelse {
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
};

/// Wrapper for Python dict objects.
pub const Dict = struct {
    obj: Object,

    /// Borrow a dict without changing refcount.
    pub fn borrowed(ptr: *c.PyObject) Dict {
        return .{ .obj = .borrowed(ptr) };
    }

    pub fn fromObject(obj: Object) ?Dict {
        if (!obj.isDict()) {
            raise(.TypeError, "expected dict");
            return null;
        }
        return .{ .obj = .borrowed(obj.ptr) };
    }

    pub fn toPyObject(self: Dict) ?*c.PyObject {
        return self.obj.toPyObject();
    }

    pub fn toObject(self: Dict) ?Object {
        const obj = self.toPyObject() orelse return null;
        return .owned(obj);
    }

    /// Own a dict reference.
    pub fn owned(ptr: *c.PyObject) Dict {
        return .{ .obj = .owned(ptr) };
    }

    /// Create a new dict.
    pub fn init() ?Dict {
        const dict_obj = c.PyDict_New() orelse return null;
        return .owned(dict_obj);
    }

    /// Create a dict from key/value entries.
    pub fn fromEntries(
        comptime K: type,
        comptime V: type,
        entries: []const struct { key: K, value: V },
    ) ?Dict {
        var dict: Dict = .init() orelse return null;
        for (entries) |entry| {
            if (!dict.setItem(K, entry.key, V, entry.value)) {
                dict.deinit();
                return null;
            }
        }
        return dict;
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
    pub fn getItem(self: Dict, comptime K: type, key: K) ?Object {
        const key_obj = toPy(K, key) orelse return null;
        defer c.Py_DecRef(key_obj);
        const item = c.PyDict_GetItemWithError(self.obj.ptr, key_obj);
        if (item == null) {
            return null;
        }
        return .borrowed(item);
    }

    /// Set a key to a value.
    pub fn setItem(self: Dict, comptime K: type, key: K, comptime V: type, value: V) bool {
        const key_obj = toPy(K, key) orelse return false;
        defer c.Py_DecRef(key_obj);
        const value_obj = toPy(V, value) orelse return false;
        defer c.Py_DecRef(value_obj);
        return c.PyDict_SetItem(self.obj.ptr, key_obj, value_obj) == 0;
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
    ) ?[]Entry(K, V) {
        const size = self.len() orelse return null;
        const buffer = gpa.alloc(Entry(K, V), size) catch {
            raise(.MemoryError, "out of memory");
            return null;
        };
        var it = self.iter();
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

    pub fn fromObject(obj: Object) ?@This() {
        if (!obj.isDict()) {
            raise(.TypeError, "expected dict");
            return null;
        }
        return .{ .dict = obj.ptr };
    }

    pub fn fromPtr(ptr: *c.PyObject) ?@This() {
        return .fromObject(.borrowed(ptr));
    }

    /// Return the next borrowed entry, or null when complete.
    pub fn next(self: *@This()) ?Entry {
        var key: ?*c.PyObject = null;
        var value: ?*c.PyObject = null;
        if (c.PyDict_Next(self.dict, &self.pos, &key, &value) == 0) return null;
        return .{
            .key = .borrowed(key orelse return null),
            .value = .borrowed(value orelse return null),
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

    pub fn fromObject(obj: Object) ?Tuple {
        if (!obj.isTuple()) {
            raise(.TypeError, "expected tuple");
            return null;
        }
        return .{ .obj = .borrowed(obj.ptr) };
    }

    pub fn toPyObject(self: Tuple) ?*c.PyObject {
        return self.obj.toPyObject();
    }

    pub fn toObject(self: Tuple) ?Object {
        const obj = self.toPyObject() orelse return null;
        return .owned(obj);
    }

    /// Own a tuple reference.
    pub fn owned(ptr: *c.PyObject) Tuple {
        return .{ .obj = .owned(ptr) };
    }

    /// Create a new tuple with the given size.
    pub fn init(size: usize) ?Tuple {
        const tuple_obj = c.PyTuple_New(@intCast(size)) orelse return null;
        return .owned(tuple_obj);
    }

    /// Create a new tuple from a Zig slice.
    pub fn fromSlice(comptime T: type, values: []const T) ?Tuple {
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
        return .owned(tuple_obj);
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
        return .borrowed(item);
    }

    /// Set the item at the given index.
    pub fn set(self: Tuple, comptime T: type, index: usize, value: T) bool {
        const value_obj = toPy(T, value) orelse return false;
        if (c.PyTuple_SetItem(self.obj.ptr, @intCast(index), value_obj) != 0) {
            c.Py_DecRef(value_obj);
            return false;
        }
        return true;
    }

    /// Convert this tuple into an owned Zig slice.
    pub fn toSlice(self: Tuple, comptime T: type, gpa: Allocator) ?[]T {
        const size = self.len() orelse return null;
        const buffer = gpa.alloc(T, size) catch {
            raise(.MemoryError, "out of memory");
            return null;
        };
        for (0..size) |i| {
            const item = self.get(i) orelse {
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
pub fn importModule(name: [:0]const u8) ?Object {
    const obj = c.PyImport_ImportModule(@ptrCast(name.ptr));
    if (obj == null) return null;
    return .owned(obj);
}

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

    return switch (T) {
        // Wrapper types
        Object => Object.borrowed(ptr),
        Bytes => Bytes.fromObject(.borrowed(ptr)),
        BigInt => BigInt.fromObject(.borrowed(ptr)),
        Long => Long.fromObject(.borrowed(ptr)),
        Int => Int.fromObject(.borrowed(ptr)),
        Buffer => Buffer.fromObject(.borrowed(ptr)),
        List => List.fromObject(.borrowed(ptr)),
        Tuple => Tuple.fromObject(.borrowed(ptr)),
        Dict => Dict.fromObject(.borrowed(ptr)),
        // String slices
        []const u8 => return Object.borrowed(ptr).unicodeSlice(),
        [:0]const u8 => {
            const slice = Object.borrowed(ptr).unicodeSlice() orelse return null;
            return slice[0..slice.len :0];
        },
        // Boolean
        bool => return Object.borrowed(ptr).isTrue(),
        // Numeric types fall through to typeInfo-based handling
        else => switch (@typeInfo(T)) {
            .int => |info| switch (info.signedness) {
                .signed => {
                    const value = c.PyLong_AsLongLong(ptr);
                    if (c.PyErr_Occurred() != null) return null;
                    return math.cast(T, value) orelse {
                        raise(.OverflowError, "integer out of range");
                        return null;
                    };
                },
                .unsigned => {
                    const value = c.PyLong_AsUnsignedLongLong(ptr);
                    if (c.PyErr_Occurred() != null) return null;
                    return math.cast(T, value) orelse {
                        raise(.OverflowError, "integer out of range");
                        return null;
                    };
                },
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
    };
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

    return switch (T) {
        // Raw PyObject pointers pass through
        ?*c.PyObject, *c.PyObject => value,
        // Wrapper types - transfer or share ownership appropriately
        Object => value.toPyObject(),
        Bytes => value.toPyObject(),
        BigInt => value.toPyObject(),
        Long => value.toPyObject(),
        Int => value.toPyObject(),
        List => value.toPyObject(),
        Tuple => value.toPyObject(),
        Dict => value.toPyObject(),
        // String slices
        []const u8, [:0]const u8 => c.PyUnicode_FromStringAndSize(value.ptr, @intCast(value.len)),
        // Boolean
        bool => c.PyBool_FromLong(@intFromBool(value)),
        // Numeric types fall through to typeInfo-based handling
        else => switch (@typeInfo(T)) {
            .int => |info| switch (info.signedness) {
                .signed => c.PyLong_FromLongLong(@intCast(value)),
                .unsigned => c.PyLong_FromUnsignedLongLong(@intCast(value)),
            },
            .float => return c.PyFloat_FromDouble(@floatCast(value)),
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
