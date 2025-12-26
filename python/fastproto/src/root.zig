//! Python bindings for fastproto.
//!
//! Exposes the Zig protobuf implementation to Python.

const std = @import("std");
const mem = std.mem;

const fastproto = @import("fastproto");
const wire = fastproto.wire;
const py = @import("alloconda");

pub const MODULE = py.module("_native", "Fast protobuf wire format encoding/decoding.", .{
    .encode_varint = py.method(encodeVarint, .{
        .doc = "Encode a signed integer as a varint, returns bytes.",
    }),
    .encode_varint_unsigned = py.method(encodeVarintUnsigned, .{
        .doc = "Encode an unsigned integer as a varint, returns bytes.",
    }),
    .decode_varint = py.method(decodeVarint, .{
        .doc = "Decode a varint from bytes at offset, returns (value, new_offset).",
    }),
    .make_tag = py.method(makeTag, .{
        .doc = "Create a tag from field number and wire type.",
    }),
    .parse_tag = py.method(parseTag, .{
        .doc = "Parse a tag into (field_number, wire_type).",
    }),
    .zigzag_encode = py.method(zigzagEncode, .{
        .doc = "Encode a signed integer using zigzag encoding.",
    }),
    .zigzag_decode = py.method(zigzagDecode, .{
        .doc = "Decode a zigzag-encoded integer.",
    }),
    .encode_fixed32 = py.method(encodeFixed32, .{
        .doc = "Encode a fixed32 value as 4 little-endian bytes.",
    }),
    .encode_sfixed32 = py.method(encodeSfixed32, .{
        .doc = "Encode an sfixed32 value as 4 little-endian bytes.",
    }),
    .encode_fixed64 = py.method(encodeFixed64, .{
        .doc = "Encode a fixed64 value as 8 little-endian bytes.",
    }),
    .encode_sfixed64 = py.method(encodeSfixed64, .{
        .doc = "Encode an sfixed64 value as 8 little-endian bytes.",
    }),
    .encode_float = py.method(encodeFloat, .{
        .doc = "Encode a float value as 4 little-endian bytes.",
    }),
    .encode_double = py.method(encodeDouble, .{
        .doc = "Encode a double value as 8 little-endian bytes.",
    }),
    .decode_fixed32 = py.method(decodeFixed32, .{
        .doc = "Decode a fixed32 from bytes at offset, returns (value, new_offset).",
    }),
    .decode_fixed64 = py.method(decodeFixed64, .{
        .doc = "Decode a fixed64 from bytes at offset, returns (value, new_offset).",
    }),
    .float_from_bits = py.method(floatFromBits, .{
        .doc = "Interpret u32 bits as float.",
    }),
    .double_from_bits = py.method(doubleFromBits, .{
        .doc = "Interpret u64 bits as double.",
    }),
});

fn encodeVarint(value: i64) ?py.Bytes {
    var buf: [wire.max_varint_len]u8 = undefined;
    const len = wire.encodeVarint(i64, value, &buf) catch return null;
    return .fromSlice(buf[0..len]);
}

fn encodeVarintUnsigned(value: u64) ?py.Bytes {
    var buf: [wire.max_varint_len]u8 = undefined;
    const len = wire.encodeVarint(u64, value, &buf) catch return null;
    return .fromSlice(buf[0..len]);
}

fn decodeVarint(data: py.Bytes, offset: usize) ?py.Tuple {
    const slice = data.slice() orelse return null;
    if (offset >= slice.len) {
        py.raise(.ValueError, "offset beyond data length");
        return null;
    }
    const value, const bytes_read = wire.decodeVarint(u64, slice[offset..]) catch |err| {
        switch (err) {
            wire.Error.Truncated => py.raise(.ValueError, "truncated varint"),
            wire.Error.VarintTooLong => py.raise(.ValueError, "varint too long"),
            else => py.raise(.ValueError, "decode error"),
        }
        return null;
    };
    return tuple2(value, offset + bytes_read);
}

fn tuple2(first: anytype, second: anytype) ?py.Tuple {
    var result = py.Tuple.init(2) orelse return null;
    if (!result.set(0, first)) {
        result.deinit();
        return null;
    }
    if (!result.set(1, second)) {
        result.deinit();
        return null;
    }
    return result;
}

fn encodeFixed32(value: u32) ?py.Bytes {
    var buf: [4]u8 = undefined;
    mem.writeInt(u32, buf[0..], value, .little);
    return .fromSlice(buf[0..]);
}

fn encodeSfixed32(value: i32) ?py.Bytes {
    var buf: [4]u8 = undefined;
    mem.writeInt(i32, buf[0..], value, .little);
    return .fromSlice(buf[0..]);
}

fn encodeFixed64(value: u64) ?py.Bytes {
    var buf: [8]u8 = undefined;
    mem.writeInt(u64, buf[0..], value, .little);
    return .fromSlice(buf[0..]);
}

fn encodeSfixed64(value: i64) ?py.Bytes {
    var buf: [8]u8 = undefined;
    mem.writeInt(i64, buf[0..], value, .little);
    return .fromSlice(buf[0..]);
}

fn encodeFloat(value: f32) ?py.Bytes {
    var buf: [4]u8 = undefined;
    mem.writeInt(u32, buf[0..], @bitCast(value), .little);
    return .fromSlice(buf[0..]);
}

fn encodeDouble(value: f64) ?py.Bytes {
    var buf: [8]u8 = undefined;
    mem.writeInt(u64, buf[0..], @bitCast(value), .little);
    return .fromSlice(buf[0..]);
}

fn decodeFixed32(data: py.Bytes, offset: usize) ?py.Tuple {
    const slice = data.slice() orelse return null;
    if (offset >= slice.len) {
        py.raise(.ValueError, "offset beyond data length");
        return null;
    }
    if (slice.len - offset < 4) {
        py.raise(.ValueError, "truncated fixed32");
        return null;
    }
    const raw = slice[offset .. offset + 4];
    const raw_ptr: *const [4]u8 = @ptrCast(raw.ptr);
    const value = mem.readInt(u32, raw_ptr, .little);
    return tuple2(value, offset + 4);
}

fn decodeFixed64(data: py.Bytes, offset: usize) ?py.Tuple {
    const slice = data.slice() orelse return null;
    if (offset >= slice.len) {
        py.raise(.ValueError, "offset beyond data length");
        return null;
    }
    if (slice.len - offset < 8) {
        py.raise(.ValueError, "truncated fixed64");
        return null;
    }
    const raw = slice[offset .. offset + 8];
    const raw_ptr: *const [8]u8 = @ptrCast(raw.ptr);
    const value = mem.readInt(u64, raw_ptr, .little);
    return tuple2(value, offset + 8);
}

fn makeTag(field_number: u32, wire_type_int: u8) ?u32 {
    if (field_number < 1) {
        py.raise(.ValueError, "field number must be >= 1");
        return null;
    }
    if (field_number > 0x1FFFFFFF) {
        py.raise(.ValueError, "field number too large");
        return null;
    }
    if (wire_type_int > 5 or wire_type_int == 3 or wire_type_int == 4) {
        py.raise(.ValueError, "invalid wire type");
        return null;
    }
    return (field_number << 3) | @as(u32, wire_type_int);
}

fn parseTag(tag: u64) ?py.Tuple {
    const parsed = wire.Tag.parse(tag) catch |err| {
        switch (err) {
            wire.Error.InvalidWireType => py.raise(.ValueError, "invalid wire type"),
            wire.Error.InvalidFieldNumber => py.raise(.ValueError, "invalid field number"),
            else => py.raise(.ValueError, "invalid tag"),
        }
        return null;
    };
    return tuple2(parsed.field_number, @intFromEnum(parsed.wire_type));
}

fn zigzagEncode(value: i64) u64 {
    return wire.zigzagEncode(i64, value);
}

fn zigzagDecode(value: u64) i64 {
    return wire.zigzagDecode(u64, value);
}

fn floatFromBits(value: u32) f32 {
    return @bitCast(value);
}

fn doubleFromBits(value: u64) f64 {
    return @bitCast(value);
}
