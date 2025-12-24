const std = @import("std");
const fmt = std.fmt;

const c = @import("ffi.zig").c;

/// Built-in Python exception kinds.
pub const Exception = enum {
    TypeError,
    ValueError,
    RuntimeError,
    MemoryError,
    OverflowError,
    ZeroDivisionError,
    AttributeError,
    IndexError,
    KeyError,
};

/// Raise a Python exception of a given kind.
pub fn raise(comptime kind: Exception, msg: [:0]const u8) void {
    _ = c.PyErr_SetString(exceptionPtr(kind), msg);
}

/// Return true if a Python exception is already set.
pub fn errorOccurred() bool {
    return c.PyErr_Occurred() != null;
}

/// Mapping entry for raiseError.
pub const ErrorMap = struct {
    err: anyerror,
    kind: Exception,
    msg: ?[:0]const u8 = null,
};

/// Raise a mapped Python exception for a Zig error.
pub fn raiseError(err: anyerror, comptime mapping: []const ErrorMap) void {
    inline for (mapping) |entry| {
        if (err == entry.err) {
            if (entry.msg) |msg| {
                _ = c.PyErr_SetString(exceptionPtr(entry.kind), msg);
            } else {
                setPythonErrorKind(entry.kind, err);
            }
            return;
        }
    }
    setPythonError(err);
}

/// Set a Python RuntimeError from a Zig error if no exception is pending.
pub fn setPythonError(err: anyerror) void {
    if (c.PyErr_Occurred() != null) {
        return;
    }
    setPythonErrorKind(.RuntimeError, err);
}

/// Set a Python exception of a specific kind from a Zig error.
pub fn setPythonErrorKind(comptime kind: Exception, err: anyerror) void {
    var buf: [128]u8 = undefined;
    const fallback: [:0]const u8 = "alloconda error";
    const msg = fmt.bufPrintZ(&buf, "{s}", .{@errorName(err)}) catch fallback;
    _ = c.PyErr_SetString(exceptionPtr(kind), msg);
}

/// Get the C pointer for a Python exception type.
pub fn exceptionPtr(comptime kind: Exception) *c.PyObject {
    return switch (kind) {
        .TypeError => c.PyExc_TypeError,
        .ValueError => c.PyExc_ValueError,
        .RuntimeError => c.PyExc_RuntimeError,
        .MemoryError => c.PyExc_MemoryError,
        .OverflowError => c.PyExc_OverflowError,
        .ZeroDivisionError => c.PyExc_ZeroDivisionError,
        .AttributeError => c.PyExc_AttributeError,
        .IndexError => c.PyExc_IndexError,
        .KeyError => c.PyExc_KeyError,
    };
}
