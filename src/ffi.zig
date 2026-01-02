//! Zig ergonomics for the low-level Python C API bindings.
const std = @import("std");
const mem = std.mem;
const heap = std.heap;
const fmt = std.fmt;
const ArenaAllocator = heap.ArenaAllocator;
/// Default allocator backed by CPython's memory allocator.
pub const allocator = heap.c_allocator;

const errors = @import("errors.zig");

/// Python C API bindings via cImport.
pub const c = @cImport({
    @cDefine("PY_SSIZE_T_CLEAN", {});
    @cInclude("Python.h");
});

/// PyModuleDef_HEAD_INIT - initializer for PyModuleDef.m_base.
pub const PyModuleDef_HEAD_INIT = mem.zeroes(c.PyModuleDef_Base);

/// Base object storage layout for types with __dict__ on Python <3.12.
pub const DefaultTypeStorage = extern struct {
    head: c.PyObject,
    dict: ?*c.PyObject,
};

pub const DefaultDictOffset: c.Py_ssize_t = @offsetOf(DefaultTypeStorage, "dict");

/// Convenience arena allocator backed by the CPython allocator.
pub inline fn arenaAllocator() ArenaAllocator {
    return .init(allocator);
}

/// Get a borrowed reference to Python None.
pub inline fn pyNone() *c.PyObject {
    if (comptime @hasDecl(c, "Py_GetConstantBorrowed") and @hasDecl(c, "Py_CONSTANT_NONE")) {
        return c.Py_GetConstantBorrowed(c.Py_CONSTANT_NONE);
    }
    if (comptime @hasDecl(c, "_Py_NoneStruct")) {
        return &c._Py_NoneStruct;
    }
    @compileError("Python headers missing Py_None");
}

/// Return an owned reference to Python None.
pub inline fn pyNoneOwned() *c.PyObject {
    const obj = pyNone();
    PyObject.incRef(obj);
    return obj;
}

/// Get a borrowed reference to Python NotImplemented.
pub inline fn pyNotImplemented() *c.PyObject {
    if (comptime @hasDecl(c, "Py_GetConstantBorrowed") and @hasDecl(c, "Py_CONSTANT_NOT_IMPLEMENTED")) {
        return c.Py_GetConstantBorrowed(c.Py_CONSTANT_NOT_IMPLEMENTED);
    }
    if (comptime @hasDecl(c, "_Py_NotImplementedStruct")) {
        return &c._Py_NotImplementedStruct;
    }
    @compileError("Python headers missing Py_NotImplemented");
}

/// Return an owned reference to Python NotImplemented.
pub inline fn pyNotImplementedOwned() *c.PyObject {
    const obj = pyNotImplemented();
    PyObject.incRef(obj);
    return obj;
}

/// Convert a comptime slice to a null-terminated string.
pub inline fn cstr(comptime s: []const u8) [:0]const u8 {
    return fmt.comptimePrint("{s}\x00", .{s});
}

/// Convert an optional sentinel-terminated slice to a C pointer.
pub inline fn cPtr(comptime value: ?[:0]const u8) [*c]const u8 {
    return if (value) |s| @ptrCast(s.ptr) else null;
}

/// C API analog: PyObject_* helpers.
pub const PyObject = struct {
    pub inline fn incRef(obj: *c.PyObject) void {
        c.Py_IncRef(obj);
    }

    pub inline fn decRef(obj: *c.PyObject) void {
        c.Py_DecRef(obj);
    }

    /// New reference.
    pub inline fn callNoArgs(obj: *c.PyObject) !*c.PyObject {
        if (@hasDecl(c, "PyObject_CallNoArgs")) {
            return objectOrError(c.PyObject_CallNoArgs(obj));
        }
        const tuple = try PyTuple.new(0);
        defer PyObject.decRef(tuple);
        return callObject(obj, tuple);
    }

    /// New reference.
    pub inline fn callObject(obj: *c.PyObject, args: *c.PyObject) !*c.PyObject {
        return objectOrError(c.PyObject_CallObject(obj, args));
    }

    /// New reference.
    pub inline fn getAttrString(obj: *c.PyObject, name: [:0]const u8) !*c.PyObject {
        return objectOrError(c.PyObject_GetAttrString(obj, @ptrCast(name.ptr)));
    }

    pub inline fn setAttrString(obj: *c.PyObject, name: [:0]const u8, value: *c.PyObject) !void {
        return voidOrError(c.PyObject_SetAttrString(obj, @ptrCast(name.ptr), value));
    }

    /// New reference.
    pub inline fn genericGetAttr(obj: *c.PyObject, name: *c.PyObject) !*c.PyObject {
        return objectOrError(c.PyObject_GenericGetAttr(obj, name));
    }

    pub inline fn genericSetAttr(obj: *c.PyObject, name: *c.PyObject, value: ?*c.PyObject) !void {
        return voidOrError(c.PyObject_GenericSetAttr(obj, name, value));
    }

    pub inline fn isTrue(obj: *c.PyObject) !bool {
        const value = c.PyObject_IsTrue(obj);
        if (value < 0) return error.PythonError;
        return value != 0;
    }

    /// New reference.
    pub inline fn str(obj: *c.PyObject) !*c.PyObject {
        return objectOrError(c.PyObject_Str(obj));
    }
};

/// C API analog: PyMem_* helpers.
pub const PyMem = struct {
    /// Allocates memory; caller must free with PyMem.free.
    pub inline fn alloc(size: usize) !*anyopaque {
        return c.PyMem_Malloc(size) orelse {
            _ = c.PyErr_NoMemory();
            return error.PythonError;
        };
    }

    pub inline fn free(ptr: *anyopaque) void {
        c.PyMem_Free(ptr);
    }
};

/// C API analog: PyModule_* helpers.
pub const PyModule = struct {
    /// New reference.
    pub inline fn create(def: *c.PyModuleDef) !*c.PyObject {
        return objectOrError(c.PyModule_Create(def));
    }

    /// Steals a reference to `value` on success.
    pub inline fn addObject(obj: *c.PyObject, name: [:0]const u8, value: *c.PyObject) !void {
        return voidOrError(c.PyModule_AddObject(obj, @ptrCast(name.ptr), value));
    }
};

/// C API analog: PyType_* helpers.
pub const PyType = struct {
    /// New reference.
    pub inline fn fromSpec(spec: *c.PyType_Spec) !*c.PyObject {
        return objectOrError(c.PyType_FromSpec(spec));
    }

    /// New reference.
    pub inline fn genericNew(
        type_obj: ?*c.PyTypeObject,
        args: ?*c.PyObject,
        kwargs: ?*c.PyObject,
    ) !*c.PyObject {
        return objectOrError(c.PyType_GenericNew(type_obj, args, kwargs));
    }

    /// Borrowed type pointer.
    pub inline fn typePtr(obj: *c.PyObject) *c.PyTypeObject {
        return @ptrCast(c.Py_TYPE(obj));
    }

    /// Return true if obj is an instance of type_obj or a subtype.
    pub inline fn isSubtype(obj: *c.PyObject, type_obj: *c.PyTypeObject) bool {
        return c.PyType_IsSubtype(c.Py_TYPE(obj), type_obj) != 0;
    }

    /// Return true if obj is an instance of exactly type_obj.
    pub inline fn isExact(obj: *c.PyObject, type_obj: *c.PyTypeObject) bool {
        return c.Py_TYPE(obj) == type_obj;
    }
};

pub fn managedDictGcEnabled() bool {
    if (!@hasDecl(c, "Py_TPFLAGS_MANAGED_DICT")) return false;
    const has_visit = @hasDecl(c, "PyObject_VisitManagedDict") or @hasDecl(c, "_PyObject_VisitManagedDict");
    const has_clear = @hasDecl(c, "PyObject_ClearManagedDict") or @hasDecl(c, "_PyObject_ClearManagedDict");
    return has_visit and has_clear and @hasDecl(c, "PyObject_GC_Del");
}

pub fn classBaseSize() usize {
    return if (comptime managedDictGcEnabled())
        @sizeOf(c.PyObject)
    else
        @sizeOf(DefaultTypeStorage);
}

/// C API analog: PyObject_VisitManagedDict / PyObject_ClearManagedDict helpers.
pub const PyManagedDict = if (@hasDecl(c, "PyObject_VisitManagedDict"))
    struct {
        pub inline fn visit(obj: *c.PyObject, visitfn: c.visitproc, arg: ?*anyopaque) c_int {
            return c.PyObject_VisitManagedDict(obj, visitfn, arg);
        }

        pub inline fn clear(obj: *c.PyObject) void {
            c.PyObject_ClearManagedDict(obj);
        }
    }
else if (@hasDecl(c, "_PyObject_VisitManagedDict"))
    struct {
        pub inline fn visit(obj: *c.PyObject, visitfn: c.visitproc, arg: ?*anyopaque) c_int {
            return c._PyObject_VisitManagedDict(obj, visitfn, arg);
        }

        pub inline fn clear(obj: *c.PyObject) void {
            c._PyObject_ClearManagedDict(obj);
        }
    }
else
    struct {
        pub inline fn visit(_: *c.PyObject, _: c.visitproc, _: ?*anyopaque) c_int {
            return 0;
        }

        pub inline fn clear(_: *c.PyObject) void {}
    };

/// C API analog: PyObject_GC_* helpers.
pub const PyGC = struct {
    pub const del = c.PyObject_GC_Del;

    pub inline fn untrack(obj: *c.PyObject) void {
        if (comptime @hasDecl(c, "PyObject_GC_UnTrack")) {
            c.PyObject_GC_UnTrack(obj);
        }
    }
};

/// C API analog: PyErr_* helpers.
pub const PyErr = struct {
    pub inline fn clear() void {
        c.PyErr_Clear();
    }

    pub inline fn exceptionMatches(comptime kind: errors.Exception) bool {
        return c.PyErr_ExceptionMatches(errors.exceptionPtr(kind)) != 0;
    }

    pub inline fn writeUnraisable(obj: *c.PyObject) void {
        c.PyErr_WriteUnraisable(obj);
    }
};

/// C API analog: PyImport_* helpers.
pub const PyImport = struct {
    /// New reference.
    pub inline fn importModule(name: [:0]const u8) !*c.PyObject {
        return objectOrError(c.PyImport_ImportModule(@ptrCast(name.ptr)));
    }
};

/// C API analog: PyList_* helpers.
pub const PyList = struct {
    /// New reference.
    pub inline fn new(count: usize) !*c.PyObject {
        return objectOrError(c.PyList_New(@intCast(count)));
    }

    pub inline fn size(obj: *c.PyObject) !usize {
        return ssizeOrError(c.PyList_Size(obj));
    }

    /// Borrowed reference.
    pub inline fn getItem(obj: *c.PyObject, index: usize) !*c.PyObject {
        return objectOrError(c.PyList_GetItem(obj, @intCast(index)));
    }

    /// Steals a reference to `item` on success.
    pub inline fn setItem(obj: *c.PyObject, index: usize, item: *c.PyObject) !void {
        return voidOrError(c.PyList_SetItem(obj, @intCast(index), item));
    }

    /// Adds a new reference to `item` (does not steal).
    pub inline fn append(obj: *c.PyObject, item: *c.PyObject) !void {
        return voidOrError(c.PyList_Append(obj, item));
    }
};

/// C API analog: PyTuple_* helpers.
pub const PyTuple = struct {
    /// New reference.
    pub inline fn new(count: usize) !*c.PyObject {
        return objectOrError(c.PyTuple_New(@intCast(count)));
    }

    pub inline fn size(obj: *c.PyObject) !usize {
        return ssizeOrError(c.PyTuple_Size(obj));
    }

    /// Borrowed reference.
    pub inline fn getItem(obj: *c.PyObject, index: usize) !*c.PyObject {
        return objectOrError(c.PyTuple_GetItem(obj, @intCast(index)));
    }

    /// Steals a reference to `item` on success.
    pub inline fn setItem(obj: *c.PyObject, index: usize, item: *c.PyObject) !void {
        return voidOrError(c.PyTuple_SetItem(obj, @intCast(index), item));
    }
};

/// C API analog: PyDict_* helpers.
pub const PyDict = struct {
    /// New reference.
    pub inline fn new() !*c.PyObject {
        return objectOrError(c.PyDict_New());
    }

    pub inline fn size(obj: *c.PyObject) !usize {
        return ssizeOrError(c.PyDict_Size(obj));
    }

    /// Borrowed reference or null.
    pub inline fn getItemWithError(obj: *c.PyObject, key: *c.PyObject) !?*c.PyObject {
        const item = c.PyDict_GetItemWithError(obj, key);
        if (item == null) {
            try errors.reraise();
            return null;
        }
        return item;
    }

    /// Does not steal references.
    pub inline fn setItem(obj: *c.PyObject, key: *c.PyObject, value: *c.PyObject) !void {
        return voidOrError(c.PyDict_SetItem(obj, key, value));
    }

    /// Borrowed key/value pairs.
    pub inline fn next(
        obj: *c.PyObject,
        pos: *c.Py_ssize_t,
    ) ?struct { key: *c.PyObject, value: *c.PyObject } {
        var key: ?*c.PyObject = null;
        var value: ?*c.PyObject = null;
        if (c.PyDict_Next(obj, pos, &key, &value) == 0) return null;
        return .{ .key = key.?, .value = value.? };
    }
};

/// C API analog: PyBytes_* helpers.
pub const PyBytes = struct {
    /// Create a new bytes object by copying slice data.
    pub inline fn fromSlice(data: []const u8) !*c.PyObject {
        return objectOrError(c.PyBytes_FromStringAndSize(data.ptr, @intCast(data.len)));
    }

    pub inline fn size(obj: *c.PyObject) !usize {
        return ssizeOrError(c.PyBytes_Size(obj));
    }

    /// Borrowed view into the bytes object's storage.
    pub inline fn slice(obj: *c.PyObject) ![]const u8 {
        var byte_len: c.Py_ssize_t = 0;
        var raw: [*c]u8 = null;
        try voidOrError(c.PyBytes_AsStringAndSize(obj, &raw, &byte_len));
        const ptr: [*]const u8 = @ptrCast(raw);
        return ptr[0..@intCast(byte_len)];
    }
};

/// C API analog: PyUnicode_* helpers.
pub const PyUnicode = struct {
    /// Create a new unicode object by copying slice data.
    pub inline fn fromSlice(data: []const u8) !*c.PyObject {
        return objectOrError(c.PyUnicode_FromStringAndSize(data.ptr, @intCast(data.len)));
    }

    /// Borrowed view into the unicode object's UTF-8 cache.
    pub inline fn slice(obj: *c.PyObject) ![]const u8 {
        var len: c.Py_ssize_t = 0;
        const raw = c.PyUnicode_AsUTF8AndSize(obj, &len);
        if (raw == null) return error.PythonError;
        const ptr: [*]const u8 = @ptrCast(raw);
        return ptr[0..@intCast(len)];
    }
};

/// C API analog: PyObject_GetBuffer / PyBuffer_Release helpers.
pub const PyBuffer = struct {
    /// Returns a view that must be released with PyBuffer.release.
    pub inline fn get(obj: *c.PyObject, flags: c_int) !c.Py_buffer {
        var view: c.Py_buffer = undefined;
        try voidOrError(c.PyObject_GetBuffer(obj, &view, flags));
        return view;
    }

    /// Release a view returned by PyBuffer.get.
    pub inline fn release(view: *c.Py_buffer) void {
        c.PyBuffer_Release(view);
    }
};

/// C API analog: PyLong_* helpers.
pub const PyLong = struct {
    pub inline fn asLongLong(obj: *c.PyObject) !i64 {
        const value = c.PyLong_AsLongLong(obj);
        try errors.reraise();
        return value;
    }

    pub inline fn asUnsignedLongLong(obj: *c.PyObject) !u64 {
        const value = c.PyLong_AsUnsignedLongLong(obj);
        try errors.reraise();
        return @intCast(value);
    }

    pub inline fn asLongLongAndOverflow(obj: *c.PyObject) !struct { value: i64, overflow: c_int } {
        var overflow: c_int = 0;
        const value = c.PyLong_AsLongLongAndOverflow(obj, &overflow);
        try errors.reraise();
        return .{ .value = value, .overflow = overflow };
    }

    pub inline fn asUnsignedLongLongMask(obj: *c.PyObject) !u64 {
        const value = c.PyLong_AsUnsignedLongLongMask(obj);
        try errors.reraise();
        return @intCast(value);
    }

    /// New reference.
    pub inline fn fromLongLong(value: i64) !*c.PyObject {
        return objectOrError(c.PyLong_FromLongLong(@intCast(value)));
    }

    /// New reference.
    pub inline fn fromUnsignedLongLong(value: u64) !*c.PyObject {
        return objectOrError(c.PyLong_FromUnsignedLongLong(@intCast(value)));
    }

    /// New reference.
    pub inline fn fromString(text: [:0]const u8) !*c.PyObject {
        return objectOrError(c.PyLong_FromString(@ptrCast(text.ptr), null, 10));
    }
};

/// C API analog: PyFloat_* helpers.
pub const PyFloat = struct {
    pub inline fn asDouble(obj: *c.PyObject) !f64 {
        const value = c.PyFloat_AsDouble(obj);
        try errors.reraise();
        return value;
    }

    /// New reference.
    pub inline fn fromDouble(value: f64) !*c.PyObject {
        return objectOrError(c.PyFloat_FromDouble(value));
    }
};

/// C API analog: PyBool_* helpers.
pub const PyBool = struct {
    /// New reference.
    pub inline fn fromBool(value: bool) !*c.PyObject {
        return objectOrError(c.PyBool_FromLong(@intFromBool(value)));
    }
};

inline fn objectOrError(v: ?*c.PyObject) !*c.PyObject {
    return v orelse error.PythonError;
}

inline fn voidOrError(v: c.Py_ssize_t) !void {
    if (v != 0) return error.PythonError;
}

inline fn ssizeOrError(v: c.Py_ssize_t) !usize {
    if (v < 0) return error.PythonError;
    return @intCast(v);
}
