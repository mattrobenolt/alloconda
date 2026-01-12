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
    OSError,
    PermissionError,
};

pub const PyError = error{ PythonError, OutOfMemory };

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

/// Set a Python exception from a Zig error if no exception is pending.
/// Common Zig errors are automatically mapped to appropriate Python exceptions.
pub fn setPythonError(err: anyerror) void {
    if (errorOccurred()) return;
    switch (err) {
        error.OutOfMemory => setError(.MemoryError, "out of memory"),
        error.InvalidCharacter, error.InvalidValue => setPythonErrorKind(.ValueError, err),
        error.Overflow => setPythonErrorKind(.OverflowError, err),
        error.DivisionByZero => setPythonErrorKind(.ZeroDivisionError, err),
        error.EndOfStream, error.FileNotFound => setPythonErrorKind(.OSError, err),
        error.AccessDenied => setPythonErrorKind(.PermissionError, err),
        else => setPythonErrorKind(.RuntimeError, err),
    }
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
        .OSError => c.PyExc_OSError,
        .PermissionError => c.PyExc_PermissionError,
    };
}
