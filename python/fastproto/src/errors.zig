//! Shared error handling for fastproto Python bindings.

const fastproto = @import("fastproto");
const Error = fastproto.wire.Error;
const py = @import("alloconda");

/// Wrapper for wire errors - use with try.
const WireErrors = py.makeErrorWrapper(&[_]py.ErrorMap{
    .{ .err = Error.Truncated, .kind = .ValueError, .msg = "truncated field" },
    .{ .err = Error.VarintTooLong, .kind = .ValueError, .msg = "varint too long" },
    .{ .err = Error.InvalidWireType, .kind = .ValueError, .msg = "invalid wire type" },
    .{ .err = Error.InvalidFieldNumber, .kind = .ValueError, .msg = "invalid field number" },
    .{ .err = Error.FieldNumberTooLarge, .kind = .ValueError, .msg = "field number too large" },
    .{ .err = Error.WireTypeMismatch, .kind = .ValueError, .msg = "wire type mismatch" },
    .{ .err = Error.BufferTooSmall, .kind = .ValueError, .msg = "buffer too small" },
    .{ .err = Error.InvalidUtf8, .kind = .ValueError, .msg = "invalid utf-8" },
    .{ .err = Error.ReadFailed, .kind = .RuntimeError, .msg = "read failed" },
    .{ .err = error.WriteFailed, .kind = .RuntimeError, .msg = "write failed" },
});

/// Wrap a wire-error-returning call for Python bindings.
/// Converts wire.Error to py.PyError, enabling ergonomic use of `try`.
///
/// Example:
///     const field = try wrap(reader.next());
///     const data = try wrap(len_field.bytesAlloc(allocator));
pub const wrap = WireErrors.wrap;
