const std = @import("std");
const fmt = std.fmt;
const math = std.math;
const mem = std.mem;
const Allocator = mem.Allocator;
const Io = std.Io;
const big_int = math.big.int;

const errors = @import("errors.zig");
const raise = errors.raise;
const PyError = errors.PyError;
const ffi = @import("ffi.zig");
const c = ffi.c;
const PyErr = ffi.PyErr;
const PyObject = ffi.PyObject;
const PyImport = ffi.PyImport;
const PyList = ffi.PyList;
const PyTuple = ffi.PyTuple;
const PyDict = ffi.PyDict;
const PyType = ffi.PyType;
const PyBytes = ffi.PyBytes;
const PyUnicode = ffi.PyUnicode;
const PyBuffer = ffi.PyBuffer;
const PyMemoryView = ffi.PyMemoryView;
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
        if (self.owns_ref) PyObject.decRef(self.ptr);
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

    /// Return an owned reference (increments if this is borrowed).
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

    /// Create a new instance of a type object via PyType_GenericNew.
    pub fn newInstance(self: Object, args: ?Object, kwargs: ?Object) PyError!Object {
        const type_obj: *c.PyTypeObject = @ptrCast(@alignCast(self.ptr));
        const args_ptr: ?*c.PyObject = if (args) |obj| obj.ptr else null;
        const kwargs_ptr: ?*c.PyObject = if (kwargs) |obj| obj.ptr else null;
        return .owned(try PyType.genericNew(type_obj, args_ptr, kwargs_ptr));
    }

    /// Get an attribute by name.
    pub fn getAttr(self: Object, name: [:0]const u8) PyError!Object {
        return .owned(try PyObject.getAttrString(self.ptr, name));
    }

    /// Get an attribute by name, clearing the PyErr on AttributeError.
    pub fn getAttrOrNull(self: Object, name: [:0]const u8) PyError!?Object {
        return self.getAttr(name) catch |err| {
            if (PyErr.exceptionMatches(.AttributeError)) {
                PyErr.clear();
                return null;
            }
            return err;
        };
    }

    /// Set an attribute by name.
    pub fn setAttr(self: Object, name: [:0]const u8, comptime T: type, value: T) PyError!void {
        const value_obj = try toPy(T, value);
        defer PyObject.decRef(value_obj);
        try PyObject.setAttrString(self.ptr, name, value_obj);
    }

    /// Use Python's generic attribute lookup on a raw attribute name object.
    pub fn genericGetAttr(self: Object, name: Object) PyError!Object {
        return .owned(try PyObject.genericGetAttr(self.ptr, name.ptr));
    }

    /// Use Python's generic setattr on a raw attribute name object.
    pub fn genericSetAttr(self: Object, name: Object, value: ?Object) PyError!void {
        const value_ptr: ?*c.PyObject = if (value) |obj| obj.ptr else null;
        try PyObject.genericSetAttr(self.ptr, name.ptr, value_ptr);
    }

    /// Use Python's generic delattr on a raw attribute name object.
    pub fn genericDelAttr(self: Object, name: Object) PyError!void {
        try self.genericSetAttr(name, null);
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

    /// Create a new bytes object by copying slice data.
    pub fn fromSlice(data: []const u8) PyError!Bytes {
        return .owned(try PyBytes.fromSlice(data));
    }

    /// Borrow a bytes object without changing refcount.
    pub fn fromObject(obj: Object) PyError!Bytes {
        if (!obj.isBytes()) return raise(.TypeError, "expected bytes");
        return .{ .obj = .borrowed(obj.ptr) };
    }

    /// Ensure an owned bytes object, copying from a buffer-capable object if needed.
    pub fn fromObjectOwned(obj: Object) PyError!Bytes {
        if (obj.isBytes()) return .{ .obj = obj.incref() };

        var buffer: Buffer = try .fromObject(obj);
        defer buffer.release();
        return .owned(try PyBytes.fromSlice(buffer.slice()));
    }

    pub fn toPyObject(self: Bytes) PyError!*c.PyObject {
        return self.obj.toPyObject();
    }

    /// Return an owned Object (increments if needed).
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

    /// Borrow the underlying bytes as a slice (valid while the bytes object lives).
    pub fn slice(self: Bytes) PyError![]const u8 {
        return PyBytes.slice(self.obj.ptr);
    }
};

/// Wrapper for bytes-like objects (bytes or buffer) without copying.
pub const BytesView = struct {
    len_value: usize,
    storage: Storage,

    const Storage = union(enum) {
        bytes: Object,
        buffer: Buffer,
    };

    /// Create a bytes view from bytes or a buffer-capable object.
    pub fn fromObject(obj: Object) PyError!BytesView {
        if (obj.isBytes()) {
            const owned = obj.incref();
            const len_value = try PyBytes.size(owned.ptr);
            return .{ .len_value = len_value, .storage = .{ .bytes = owned } };
        }

        var buffer = try Buffer.fromObject(obj);
        const len_value = buffer.len();
        return .{ .len_value = len_value, .storage = .{ .buffer = buffer } };
    }

    /// Return true if this view wraps a bytes object.
    pub fn isBytes(self: *const BytesView) bool {
        return self.storage == .bytes;
    }

    /// Return true if this view wraps a buffer.
    pub fn isBuffer(self: *const BytesView) bool {
        return self.storage == .buffer;
    }

    /// Return the byte length.
    pub fn len(self: *const BytesView) usize {
        return self.len_value;
    }

    /// Borrow the underlying bytes as a slice (valid while the view lives).
    pub fn slice(self: *const BytesView) PyError![]const u8 {
        switch (self.storage) {
            .bytes => |obj| return PyBytes.slice(obj.ptr),
            .buffer => |buf| return buf.slice(),
        }
    }

    /// Clone this view, retaining ownership of the underlying storage.
    pub fn clone(self: *const BytesView) PyError!BytesView {
        switch (self.storage) {
            .bytes => |obj| return .{
                .len_value = self.len_value,
                .storage = .{ .bytes = obj.incref() },
            },
            .buffer => |buf| {
                var cloned = try buf.clone();
                return .{
                    .len_value = cloned.len(),
                    .storage = .{ .buffer = cloned },
                };
            },
        }
    }

    /// Release owned references.
    pub fn deinit(self: *BytesView) void {
        switch (self.storage) {
            .bytes => |obj| obj.deinit(),
            .buffer => |*buf| buf.release(),
        }
        self.* = undefined;
    }
};

/// Wrapper for Python binary reader objects via std.Io.Reader.
pub const IoReader = struct {
    obj: Object,
    interface: Io.Reader,

    /// Owned buffer with the number of bytes read.
    pub const Slice = struct {
        buf: []u8,
        len: usize,

        /// Free the owned buffer.
        pub fn deinit(self: *@This(), allocator: Allocator) void {
            allocator.free(self.buf);
            self.* = undefined;
        }

        /// Return the valid data slice.
        pub fn slice(self: *const @This()) []const u8 {
            return self.buf[0..self.len];
        }
    };

    /// Create a new IO reader from a Python object with readinto().
    pub fn init(obj: Object, buffer: []u8) PyError!IoReader {
        return .{
            .obj = obj.incref(),
            .interface = initInterface(buffer),
        };
    }

    /// Create an unbuffered IO reader (no internal buffer).
    pub fn initUnbuffered(obj: Object) PyError!IoReader {
        return init(obj, &.{});
    }

    pub fn initInterface(buffer: []u8) Io.Reader {
        return .{
            .vtable = &.{ .stream = IoReader.stream },
            .buffer = buffer,
            .seek = 0,
            .end = 0,
        };
    }

    /// Release the held reference.
    pub fn deinit(self: *IoReader) void {
        self.obj.deinit();
        self.* = undefined;
    }

    /// Read up to buffer.len bytes into buffer.
    pub fn readAll(self: *IoReader, buffer: []u8) PyError![]const u8 {
        const n = self.interface.readSliceShort(buffer) catch |err| switch (err) {
            error.ReadFailed => {
                try errors.reraise();
                return raise(.RuntimeError, "read failed");
            },
        };
        return buffer[0..n];
    }

    /// Allocate a buffer of len and read up to len bytes into it.
    /// Caller owns the returned buffer and must free it with allocator.free.
    pub fn readAllAlloc(self: *IoReader, allocator: Allocator, len: usize) PyError!Slice {
        const buf = try allocator.alloc(u8, len);
        errdefer allocator.free(buf);
        const data = try self.readAll(buf);
        return .{ .buf = buf, .len = data.len };
    }

    /// Append all remaining bytes into list until EOF.
    pub fn appendRemainingUnlimited(
        self: *IoReader,
        allocator: Allocator,
        list: *std.ArrayList(u8),
    ) PyError!void {
        self.interface.appendRemainingUnlimited(allocator, list) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.ReadFailed => {
                try errors.reraise();
                return raise(.RuntimeError, "read failed");
            },
        };
    }

    fn stream(r: *Io.Reader, w: *Io.Writer, limit: Io.Limit) Io.Reader.StreamError!usize {
        const self: *IoReader = @alignCast(@fieldParentPtr("interface", r));
        const dest = limit.slice(try w.writableSliceGreedy(1));
        if (dest.len == 0) return 0;

        const memview = PyMemoryView.fromMemory(dest.ptr, dest.len, c.PyBUF_WRITE) catch return error.ReadFailed;

        const result = self.obj.callMethod1("readinto", *c.PyObject, memview) catch return error.ReadFailed;
        defer result.deinit();

        const n_signed = result.as(i64) catch return error.ReadFailed;
        if (n_signed < 0) return error.ReadFailed;
        const n: usize = @intCast(n_signed);
        if (n == 0) return error.EndOfStream;
        if (n > dest.len) return error.ReadFailed;
        w.advance(n);
        return n;
    }
};

/// Wrapper for Python binary writer objects via std.Io.Writer.
pub const IoWriter = struct {
    obj: Object,
    interface: Io.Writer,

    /// Create a new IO writer from a Python object with write().
    pub fn init(obj: Object, buffer: []u8) PyError!IoWriter {
        return .{
            .obj = obj.incref(),
            .interface = initInterface(buffer),
        };
    }

    /// Create an unbuffered IO writer (no internal buffer).
    pub fn initUnbuffered(obj: Object) PyError!IoWriter {
        return init(obj, &.{});
    }

    pub fn initInterface(buffer: []u8) Io.Writer {
        return .{
            .vtable = &.{ .drain = IoWriter.drain },
            .buffer = buffer,
            .end = 0,
        };
    }

    /// Write all bytes to the underlying stream.
    pub fn writeAll(self: *@This(), bytes: []const u8) PyError!void {
        const writer = &self.interface;
        writer.writeAll(bytes) catch |err| switch (err) {
            error.WriteFailed => {
                try errors.reraise();
                return raise(.RuntimeError, "write failed");
            },
        };
    }

    /// Flush buffered data to the underlying stream.
    pub fn flush(self: *@This()) PyError!void {
        const writer = &self.interface;
        writer.flush() catch |err| switch (err) {
            error.WriteFailed => {
                try errors.reraise();
                return raise(.RuntimeError, "flush failed");
            },
        };
    }

    /// Release the held reference.
    pub fn deinit(self: *IoWriter) void {
        self.obj.deinit();
        self.* = undefined;
    }

    fn drain(w: *Io.Writer, data: []const []const u8, splat: usize) Io.Writer.Error!usize {
        const self: *IoWriter = @alignCast(@fieldParentPtr("interface", w));
        if (w.end != 0) {
            const buffered = w.buffered();
            const n = try self.writeSlice(buffered);
            _ = w.consume(n);
            if (n < buffered.len) return 0;
        }

        if (data.len == 0) return 0;
        var written: usize = 0;
        for (data[0 .. data.len - 1]) |slice| {
            if (slice.len == 0) continue;
            const n = try self.writeSlice(slice);
            written += n;
            if (n < slice.len) return written;
        }

        const pattern = data[data.len - 1];
        if (pattern.len == 0 or splat == 0) return written;
        var i: usize = 0;
        while (i < splat) : (i += 1) {
            const n = try self.writeSlice(pattern);
            written += n;
            if (n < pattern.len) return written;
        }
        return written;
    }

    fn writeSlice(self: *IoWriter, bytes: []const u8) Io.Writer.Error!usize {
        if (bytes.len == 0) return 0;
        const ptr: [*]u8 = @ptrCast(@constCast(bytes.ptr));
        const memview = PyMemoryView.fromMemory(ptr, bytes.len, c.PyBUF_READ) catch return error.WriteFailed;

        const result = self.obj.callMethod1("write", *c.PyObject, memview) catch return error.WriteFailed;
        defer result.deinit();

        const n_signed = result.as(i64) catch return error.WriteFailed;
        if (n_signed < 0) return error.WriteFailed;
        const n: usize = @intCast(n_signed);
        if (n > bytes.len) return error.WriteFailed;
        return n;
    }
};

/// Wrapper for Python buffer protocol.
pub const Buffer = struct {
    view: c.Py_buffer,

    /// Request a buffer view (read-only); release when done.
    pub fn init(obj: Object) PyError!Buffer {
        const view = try PyBuffer.get(obj.ptr, c.PyBUF_SIMPLE);
        return .{ .view = view };
    }

    /// Request a buffer view from a buffer-capable object; release when done.
    pub fn fromObject(obj: Object) PyError!Buffer {
        if (!checkBuffer(obj.ptr)) return raise(.TypeError, "expected buffer");
        return init(obj);
    }

    /// Release the buffer view.
    pub fn release(self: *Buffer) void {
        PyBuffer.release(&self.view);
    }

    /// Clone this buffer view by requesting a new view from the exporter.
    pub fn clone(self: *const Buffer) PyError!Buffer {
        const obj = self.view.obj orelse return raise(.RuntimeError, "buffer missing owner");
        return init(.borrowed(obj));
    }

    /// Return the byte length.
    pub fn len(self: *const Buffer) usize {
        return @intCast(self.view.len);
    }

    /// Borrow the underlying bytes as a slice (valid until released).
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
        const gpa = ffi.allocator;
        if (!obj.isLong()) return raise(.TypeError, "expected int");

        const text_obj = try PyObject.str(obj.ptr);
        defer PyObject.decRef(text_obj);
        const text = try PyUnicode.slice(text_obj);
        var managed: big_int.Managed = try .init(gpa);

        errdefer managed.deinit();
        managed.setString(10, text) catch |err| {
            return switch (err) {
                error.OutOfMemory => error.OutOfMemory,
                error.InvalidCharacter, error.InvalidBase => raise(.ValueError, "invalid integer string"),
            };
        };
        return .{ .value = managed };
    }

    pub fn toPyObject(self: BigInt) PyError!*c.PyObject {
        const gpa = ffi.allocator;
        const text = try self.value.toConst().toStringAlloc(gpa, 10, .lower);
        defer gpa.free(text);
        const buf = try gpa.alloc(u8, text.len + 1);
        defer gpa.free(buf);
        @memcpy(buf[0..text.len], text);
        buf[text.len] = 0;
        const text_z: [:0]const u8 = buf[0..text.len :0];
        return PyLong.fromString(text_z);
    }

    /// Return an owned Object (increments if needed).
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
                PyErr.clear();
                return .{ .big = try .fromObject(obj) };
            };
            return .{ .small = .{ .unsigned = unsigned_value } };
        }
        return .{ .big = try .fromObject(obj) };
    }

    pub fn toPyObject(value: Int) PyError!*c.PyObject {
        return switch (value) {
            .small => |small| Long.toPyObject(small),
            .big => |big| big.toPyObject(),
        };
    }

    /// Return an owned Object (increments if needed).
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

    /// Return an owned Object (increments if needed).
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

    /// Borrow a list without changing refcount.
    pub fn fromObject(obj: Object) PyError!List {
        if (!obj.isList()) return raise(.TypeError, "expected list");
        return .{ .obj = .borrowed(obj.ptr) };
    }

    pub fn toPyObject(self: List) PyError!*c.PyObject {
        return self.obj.toPyObject();
    }

    /// Return an owned Object (increments if needed).
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

    /// Create a new list by converting each element; the list owns the references.
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

    /// Set the item at the given index; transfers ownership of the new reference.
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

    /// Convert this list into an owned Zig slice; caller must free the buffer.
    pub fn toSlice(self: List, comptime T: type, allocator: Allocator) PyError![]T {
        const size = try self.len();
        const buffer = try allocator.alloc(T, size);
        errdefer allocator.free(buffer);
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

    /// Borrow a dict without changing refcount.
    pub fn fromObject(obj: Object) PyError!Dict {
        if (!obj.isDict()) return raise(.TypeError, "expected dict");
        return .{ .obj = .borrowed(obj.ptr) };
    }

    pub fn toPyObject(self: Dict) PyError!*c.PyObject {
        return self.obj.toPyObject();
    }

    /// Return an owned Object (increments if needed).
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

    /// Convert this dict into an owned slice of key/value pairs; caller must free the buffer.
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

    /// Borrow a dict without changing refcount.
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

    /// Borrow a tuple without changing refcount.
    pub fn fromObject(obj: Object) PyError!Tuple {
        if (!obj.isTuple()) return raise(.TypeError, "expected tuple");
        return .{ .obj = .borrowed(obj.ptr) };
    }

    pub fn toPyObject(self: Tuple) PyError!*c.PyObject {
        return self.obj.toPyObject();
    }

    /// Return an owned Object (increments if needed).
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

    /// Create a new tuple by converting each element; the tuple owns the references.
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

    /// Set the item at the given index; transfers ownership of the new reference.
    pub fn set(self: Tuple, comptime T: type, index: usize, value: T) PyError!void {
        const value_obj = try toPy(T, value);
        errdefer PyObject.decRef(value_obj);
        try PyTuple.setItem(self.obj.ptr, index, value_obj);
    }

    /// Convert this tuple into an owned Zig slice; caller must free the buffer.
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
        BytesView => try BytesView.fromObject(.borrowed(ptr)),
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
