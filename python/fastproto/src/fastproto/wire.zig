//! Protobuf wire format primitives.
//!
//! Low-level encoding/decoding for varints, zigzag, and tags.
//! Based on: https://protobuf.dev/programming-guides/encoding/

const std = @import("std");
const Io = std.Io;
const meta = std.meta;
const testing = std.testing;

/// Protobuf wire types.
pub const WireType = enum(u3) {
    varint = 0, // int32, int64, uint32, uint64, sint32, sint64, bool, enum
    fixed64 = 1, // fixed64, sfixed64, double
    len = 2, // string, bytes, embedded messages, packed repeated fields
    // 3 and 4 are deprecated (start/end group)
    fixed32 = 5, // fixed32, sfixed32, float
};

/// Errors that can occur during protobuf operations.
pub const Error = error{
    /// Varint encoding exceeds maximum allowed bytes
    VarintTooLong,
    /// Unexpected end of data
    Truncated,
    /// Invalid wire type in tag
    InvalidWireType,
    /// Field number must be >= 1
    InvalidFieldNumber,
    /// Field number too large (max 2^29-1)
    FieldNumberTooLarge,
    /// Wire type doesn't match expected type for operation
    WireTypeMismatch,
    /// Buffer too small for operation
    BufferTooSmall,
    /// Invalid UTF-8 in string field
    InvalidUtf8,
    /// Underlying I/O read failed
    ReadFailed,
};

/// Returns the unsigned integer type with the same bit width as T.
pub fn Unsigned(comptime T: type) type {
    return meta.Int(.unsigned, @typeInfo(T).int.bits);
}

/// Returns the signed integer type with the same bit width as T.
pub fn Signed(comptime T: type) type {
    return meta.Int(.signed, @typeInfo(T).int.bits);
}

/// Maximum bytes a varint can occupy (64-bit value).
pub const max_varint_len: usize = 10;

/// Encode an integer as a varint into a buffer.
/// Returns the number of bytes written.
pub fn encodeVarint(comptime T: type, value: T, buf: []u8) !usize {
    var v: Unsigned(T) = @bitCast(value);

    var i: usize = 0;
    while (v > 0x7F) : (i += 1) {
        if (i >= buf.len) return Error.BufferTooSmall;
        buf[i] = @as(u8, @truncate(v)) | 0x80;
        v >>= 7;
    }

    if (i >= buf.len) return Error.BufferTooSmall;
    buf[i] = @truncate(v);
    return i + 1;
}

test encodeVarint {
    // Roundtrip u64
    for ([_]u64{
        0,
        1,
        127,
        128,
        255,
        256,
        16383,
        16384,
        0x7FFFFFFF,
        0xFFFFFFFF,
        0x7FFFFFFFFFFFFFFF,
        0xFFFFFFFFFFFFFFFF,
    }) |value| {
        var buf: [max_varint_len]u8 = undefined;
        const len = try encodeVarint(u64, value, &buf);
        const decoded, const bytes_read = try decodeVarint(u64, buf[0..len]);
        try testing.expectEqual(value, decoded);
        try testing.expectEqual(len, bytes_read);
    }

    // Roundtrip i64
    for ([_]i64{
        0,
        1,
        -1,
        127,
        -128,
        255,
        -256,
        0x7FFFFFFFFFFFFFFF,
        -0x8000000000000000,
    }) |value| {
        var buf: [max_varint_len]u8 = undefined;
        const len = try encodeVarint(i64, value, &buf);
        const decoded, const bytes_read = try decodeVarint(i64, buf[0..len]);
        try testing.expectEqual(value, decoded);
        try testing.expectEqual(len, bytes_read);
    }
}

/// Decode a varint from a byte slice into the specified integer type.
/// Returns the decoded value and number of bytes consumed.
pub fn decodeVarint(comptime T: type, data: []const u8) !struct { T, usize } {
    var result: u64 = 0;
    var shift: u6 = 0;

    for (data, 0..) |byte, i| {
        if (i >= max_varint_len) return Error.VarintTooLong;

        const value_bits: u64 = byte & 0x7F;
        result |= value_bits << shift;

        if (byte & 0x80 == 0) {
            const truncated: Unsigned(T) = @truncate(result);
            return .{ @bitCast(truncated), i + 1 };
        }

        shift +|= 7;
    }

    return Error.Truncated;
}

/// Read a varint from an Io.Reader.
/// Returns the decoded value and number of bytes consumed.
pub fn readVarintFromIo(io: *Io.Reader, comptime T: type) !struct { T, usize } {
    var result: u64 = 0;
    var shift: u6 = 0;
    var bytes_read: usize = 0;

    while (bytes_read < max_varint_len) {
        const byte = io.takeByte() catch |err| switch (err) {
            error.EndOfStream => return Error.Truncated,
            error.ReadFailed => return Error.ReadFailed,
        };
        bytes_read += 1;

        const value_bits: u64 = byte & 0x7F;
        result |= value_bits << shift;

        if (byte & 0x80 == 0) {
            const truncated: Unsigned(T) = @truncate(result);
            return .{ @bitCast(truncated), bytes_read };
        }

        shift +|= 7;
    }

    return Error.VarintTooLong;
}

/// Encode a signed integer using ZigZag encoding.
/// Maps signed integers to unsigned so small absolute values have small encodings.
pub fn zigzagEncode(comptime T: type, value: T) Unsigned(T) {
    const U = Unsigned(T);
    const bits = @typeInfo(T).int.bits;
    const v: U = @bitCast(value);
    const sign: U = @bitCast(value >> (bits - 1));
    return (v << 1) ^ sign;
}

test zigzagEncode {
    // From protobuf spec: 0 -> 0, -1 -> 1, 1 -> 2, -2 -> 3, 2 -> 4
    try testing.expectEqual(@as(u64, 0), zigzagEncode(i64, 0));
    try testing.expectEqual(@as(u64, 1), zigzagEncode(i64, -1));
    try testing.expectEqual(@as(u64, 2), zigzagEncode(i64, 1));
    try testing.expectEqual(@as(u64, 3), zigzagEncode(i64, -2));
    try testing.expectEqual(@as(u64, 4), zigzagEncode(i64, 2));

    // Roundtrip
    for ([_]i64{ 0, -1, 1, -2, 2, -64, 63, -128, 127, -2147483648, 2147483647 }) |value| {
        const encoded = zigzagEncode(i64, value);
        const decoded = zigzagDecode(u64, encoded);
        try testing.expectEqual(value, decoded);
    }
}

/// Decode a ZigZag-encoded unsigned integer back to signed.
pub fn zigzagDecode(comptime T: type, value: T) Signed(T) {
    const shifted = value >> 1;
    const sign_bit = value & 1;
    const mask: T = 0 -% sign_bit;
    return @bitCast(shifted ^ mask);
}

pub const Tag = struct {
    field_number: u32,
    wire_type: WireType,

    /// Create a tag from field number and wire type.
    /// Returns error if field_number is invalid (must be 1 to 2^29-1).
    pub fn init(field_number: u32, wire_type: WireType) !Tag {
        if (field_number < 1) return Error.InvalidFieldNumber;
        if (field_number > 0x1FFFFFFF) return Error.FieldNumberTooLarge;
        return .{ .field_number = field_number, .wire_type = wire_type };
    }

    pub fn must(field_number: u32, wire_type: WireType) Tag {
        return init(field_number, wire_type) catch unreachable;
    }

    /// Parse a tag from its raw encoded form.
    pub fn parse(raw: u64) !Tag {
        const wire_type = meta.intToEnum(WireType, @as(u3, @truncate(raw))) catch
            return Error.InvalidWireType;
        const field_number: u32 = @truncate(raw >> 3);
        if (field_number < 1) return Error.InvalidFieldNumber;
        return .{ .field_number = field_number, .wire_type = wire_type };
    }

    /// Encode the tag to its raw form.
    pub fn encode(self: @This()) u32 {
        return (self.field_number << 3) | @intFromEnum(self.wire_type);
    }

    test init {
        // Valid tags
        const tag: Tag = try .init(1, .varint);
        try testing.expectEqual(@as(u32, 1), tag.field_number);
        try testing.expectEqual(WireType.varint, tag.wire_type);

        // Edge cases
        const max_tag: Tag = try .init(0x1FFFFFFF, .len);
        try testing.expectEqual(@as(u32, 0x1FFFFFFF), max_tag.field_number);

        // Invalid field numbers
        try testing.expectError(Error.InvalidFieldNumber, Tag.init(0, .varint));
        try testing.expectError(Error.FieldNumberTooLarge, Tag.init(0x20000000, .varint));
    }

    test encode {
        for ([_]WireType{ .varint, .fixed64, .len, .fixed32 }) |wire_type| {
            for ([_]u32{ 1, 2, 15, 16, 2047, 2048, 0x1FFFFFFF }) |field_number| {
                const tag: Tag = try .init(field_number, wire_type);
                const parsed: Tag = try .parse(tag.encode());
                try testing.expectEqual(field_number, parsed.field_number);
                try testing.expectEqual(wire_type, parsed.wire_type);
            }
        }
    }
};

/// Protobuf scalar types for type-safe field access.
pub const Scalar = enum {
    // Varint types
    i32,
    i64,
    u32,
    u64,
    sint32,
    sint64,
    bool,
    // Fixed64 types
    fixed64,
    sfixed64,
    double,
    // Fixed32 types
    fixed32,
    sfixed32,
    float,

    /// Get the Zig type corresponding to this scalar.
    pub fn Type(comptime self: Scalar) type {
        return switch (self) {
            .i32, .sint32, .sfixed32 => i32,
            .i64, .sint64, .sfixed64 => i64,
            .u32, .fixed32 => u32,
            .u64, .fixed64 => u64,
            .bool => bool,
            .double => f64,
            .float => f32,
        };
    }

    /// Get the wire type for this scalar.
    pub fn wireType(comptime self: Scalar) WireType {
        return switch (self) {
            .i32, .i64, .u32, .u64, .sint32, .sint64, .bool => .varint,
            .fixed64, .sfixed64, .double => .fixed64,
            .fixed32, .sfixed32, .float => .fixed32,
        };
    }
};

/// Encoding type for packed repeated fields.
pub const Encoding = enum {
    varint,
    sint,
    fixed,

    /// Get the Zig element type for this encoding and target type.
    pub fn Type(comptime self: Encoding, comptime T: type) type {
        _ = self;
        return T;
    }
};
