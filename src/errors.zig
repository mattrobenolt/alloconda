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
    StopIteration,
};

pub const PyError = error{PythonError};

/// Raise a Python exception of a given kind.
pub inline fn raise(comptime kind: Exception, msg: [:0]const u8) PyError {
    setError(kind, msg);
    return error.PythonError;
}

/// Set a Python exception of a given kind without returning an error.
pub inline fn setError(comptime kind: Exception, msg: [:0]const u8) void {
    _ = c.PyErr_SetString(exceptionPtr(kind), msg);
}

/// Return true if a Python exception is already set.
pub inline fn errorOccurred() bool {
    return c.PyErr_Occurred() != null;
}

pub inline fn reraise() !void {
    if (errorOccurred()) return error.PythonError;
}

/// Mapping entry for raiseError.
pub const ErrorMap = struct {
    err: anyerror,
    kind: Exception,
    msg: ?[:0]const u8 = null,
};

/// Raise a mapped Python exception for a Zig error.
pub fn raiseError(err: anyerror, comptime mapping: []const ErrorMap) PyError {
    inline for (mapping) |entry| {
        if (err == entry.err) {
            if (entry.msg) |msg| {
                setError(entry.kind, msg);
            } else {
                setPythonErrorKind(entry.kind, err);
            }
            return error.PythonError;
        }
    }
    setPythonError(err);
    return error.PythonError;
}

/// Set a Python RuntimeError from a Zig error if no exception is pending.
pub fn setPythonError(err: anyerror) void {
    if (errorOccurred()) return;
    setPythonErrorKind(.RuntimeError, err);
}

/// Set a Python exception of a specific kind from a Zig error.
pub fn setPythonErrorKind(comptime kind: Exception, err: anyerror) void {
    var buf: [128]u8 = undefined;
    const fallback = "alloconda error";
    const msg = fmt.bufPrintZ(&buf, "{s}", .{@errorName(err)}) catch fallback;
    setError(kind, msg);
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
        .StopIteration => c.PyExc_StopIteration,
    };
}
