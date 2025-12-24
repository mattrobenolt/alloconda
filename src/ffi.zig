const std = @import("std");
const mem = std.mem;
const heap = std.heap;
const fmt = std.fmt;
const ArenaAllocator = heap.ArenaAllocator;
/// Default allocator backed by CPython's memory allocator.
pub const allocator = heap.c_allocator;

/// Python C API bindings via cImport.
pub const c = @cImport({
    @cDefine("PY_SSIZE_T_CLEAN", {});
    @cInclude("Python.h");
});

/// Type aliases for common Python C types.
pub const PyObject = c.PyObject;
pub const Py_ssize_t = c.Py_ssize_t;

/// PyModuleDef_HEAD_INIT - initializer for PyModuleDef.m_base.
pub const PyModuleDef_HEAD_INIT = mem.zeroes(c.PyModuleDef_Base);

/// Convenience arena allocator backed by the CPython allocator.
pub fn arenaAllocator() ArenaAllocator {
    return .init(allocator);
}

/// Get a borrowed reference to Python None.
pub fn pyNone() *c.PyObject {
    if (comptime @hasDecl(c, "Py_GetConstantBorrowed") and @hasDecl(c, "Py_CONSTANT_NONE")) {
        return c.Py_GetConstantBorrowed(c.Py_CONSTANT_NONE);
    }
    if (comptime @hasDecl(c, "_Py_NoneStruct")) {
        return &c._Py_NoneStruct;
    }
    @compileError("Python headers missing Py_None");
}

/// Convert a comptime slice to a null-terminated string.
pub fn cstr(comptime s: []const u8) [:0]const u8 {
    return fmt.comptimePrint("{s}\x00", .{s});
}

/// Convert an optional sentinel-terminated slice to a C pointer.
pub fn cPtr(comptime value: ?[:0]const u8) [*c]const u8 {
    return if (value) |s| @ptrCast(s.ptr) else null;
}
