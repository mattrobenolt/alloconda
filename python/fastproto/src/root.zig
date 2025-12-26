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
    .varint_to_int32 = py.method(varintToInt32, .{
        .doc = "Interpret an unsigned varint as int32.",
    }),
    .varint_to_int64 = py.method(varintToInt64, .{
        .doc = "Interpret an unsigned varint as int64.",
    }),
    .varint_to_uint32 = py.method(varintToUint32, .{
        .doc = "Interpret an unsigned varint as uint32.",
    }),
    .varint_to_uint64 = py.method(varintToUint64, .{
        .doc = "Interpret an unsigned varint as uint64.",
    }),
    .varint_to_sint32 = py.method(varintToSint32, .{
        .doc = "Interpret an unsigned varint as sint32 (zigzag).",
    }),
    .varint_to_sint64 = py.method(varintToSint64, .{
        .doc = "Interpret an unsigned varint as sint64 (zigzag).",
    }),
    .varint_to_bool = py.method(varintToBool, .{
        .doc = "Interpret an unsigned varint as bool.",
    }),
    .fixed32_to_sfixed32 = py.method(fixed32ToSfixed32, .{
        .doc = "Interpret a fixed32 value as sfixed32.",
    }),
    .fixed64_to_sfixed64 = py.method(fixed64ToSfixed64, .{
        .doc = "Interpret a fixed64 value as sfixed64.",
    }),
    .decode_packed_int32s = py.method(decodePackedInt32s, .{
        .doc = "Decode packed varints as int32 list.",
    }),
    .decode_packed_int64s = py.method(decodePackedInt64s, .{
        .doc = "Decode packed varints as int64 list.",
    }),
    .decode_packed_uint32s = py.method(decodePackedUint32s, .{
        .doc = "Decode packed varints as uint32 list.",
    }),
    .decode_packed_uint64s = py.method(decodePackedUint64s, .{
        .doc = "Decode packed varints as uint64 list.",
    }),
    .decode_packed_sint32s = py.method(decodePackedSint32s, .{
        .doc = "Decode packed varints as sint32 list.",
    }),
    .decode_packed_sint64s = py.method(decodePackedSint64s, .{
        .doc = "Decode packed varints as sint64 list.",
    }),
    .decode_packed_bools = py.method(decodePackedBools, .{
        .doc = "Decode packed varints as bool list.",
    }),
    .decode_packed_fixed32s = py.method(decodePackedFixed32s, .{
        .doc = "Decode packed fixed32 values.",
    }),
    .decode_packed_sfixed32s = py.method(decodePackedSfixed32s, .{
        .doc = "Decode packed sfixed32 values.",
    }),
    .decode_packed_floats = py.method(decodePackedFloats, .{
        .doc = "Decode packed float values.",
    }),
    .decode_packed_fixed64s = py.method(decodePackedFixed64s, .{
        .doc = "Decode packed fixed64 values.",
    }),
    .decode_packed_sfixed64s = py.method(decodePackedSfixed64s, .{
        .doc = "Decode packed sfixed64 values.",
    }),
    .decode_packed_doubles = py.method(decodePackedDoubles, .{
        .doc = "Decode packed double values.",
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

fn decodeVarint(data: py.Buffer, offset: usize) ?py.Tuple {
    var buffer = data;
    defer buffer.release();
    const slice = buffer.slice();
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
    mem.writeInt(u32, &buf, value, .little);
    return .fromSlice(&buf);
}

fn encodeSfixed32(value: i32) ?py.Bytes {
    var buf: [4]u8 = undefined;
    mem.writeInt(i32, &buf, value, .little);
    return .fromSlice(&buf);
}

fn encodeFixed64(value: u64) ?py.Bytes {
    var buf: [8]u8 = undefined;
    mem.writeInt(u64, &buf, value, .little);
    return .fromSlice(&buf);
}

fn encodeSfixed64(value: i64) ?py.Bytes {
    var buf: [8]u8 = undefined;
    mem.writeInt(i64, &buf, value, .little);
    return .fromSlice(&buf);
}

fn encodeFloat(value: f32) ?py.Bytes {
    var buf: [4]u8 = undefined;
    mem.writeInt(u32, &buf, @bitCast(value), .little);
    return .fromSlice(&buf);
}

fn encodeDouble(value: f64) ?py.Bytes {
    var buf: [8]u8 = undefined;
    mem.writeInt(u64, &buf, @bitCast(value), .little);
    return .fromSlice(&buf);
}

fn decodeFixed32(data: py.Buffer, offset: usize) ?py.Tuple {
    var buffer = data;
    defer buffer.release();
    const slice = buffer.slice();
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

fn decodeFixed64(data: py.Buffer, offset: usize) ?py.Tuple {
    var buffer = data;
    defer buffer.release();
    const slice = buffer.slice();
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

fn varintToInt32(value: u64) i32 {
    return @bitCast(@as(u32, @truncate(value)));
}

fn varintToInt64(value: u64) i64 {
    return @bitCast(value);
}

fn varintToUint32(value: u64) u32 {
    return @truncate(value);
}

fn varintToUint64(value: u64) u64 {
    return value;
}

fn varintToSint32(value: u64) i32 {
    return wire.zigzagDecode(u32, @truncate(value));
}

fn varintToSint64(value: u64) i64 {
    return wire.zigzagDecode(u64, value);
}

fn varintToBool(value: u64) bool {
    return value != 0;
}

fn fixed32ToSfixed32(value: u32) i32 {
    return @bitCast(value);
}

fn fixed64ToSfixed64(value: u64) i64 {
    return @bitCast(value);
}

const VarintKind = enum {
    int32,
    int64,
    uint32,
    uint64,
    sint32,
    sint64,
    bool,
};

fn decodePackedVarints(data: py.Buffer, comptime kind: VarintKind) ?py.List {
    var buffer = data;
    defer buffer.release();
    const slice = buffer.slice();
    var list = py.List.init(0) orelse return null;
    var offset: usize = 0;
    while (offset < slice.len) {
        const value, const bytes_read = wire.decodeVarint(u64, slice[offset..]) catch |err| {
            list.deinit();
            switch (err) {
                wire.Error.Truncated => py.raise(.ValueError, "truncated varint"),
                wire.Error.VarintTooLong => py.raise(.ValueError, "varint too long"),
                else => py.raise(.ValueError, "decode error"),
            }
            return null;
        };
        offset += bytes_read;
        const out = switch (kind) {
            .int32 => varintToInt32(value),
            .int64 => varintToInt64(value),
            .uint32 => varintToUint32(value),
            .uint64 => varintToUint64(value),
            .sint32 => varintToSint32(value),
            .sint64 => varintToSint64(value),
            .bool => varintToBool(value),
        };
        if (!list.append(out)) {
            list.deinit();
            return null;
        }
    }
    return list;
}

fn decodePackedInt32s(data: py.Buffer) ?py.List {
    return decodePackedVarints(data, .int32);
}

fn decodePackedInt64s(data: py.Buffer) ?py.List {
    return decodePackedVarints(data, .int64);
}

fn decodePackedUint32s(data: py.Buffer) ?py.List {
    return decodePackedVarints(data, .uint32);
}

fn decodePackedUint64s(data: py.Buffer) ?py.List {
    return decodePackedVarints(data, .uint64);
}

fn decodePackedSint32s(data: py.Buffer) ?py.List {
    return decodePackedVarints(data, .sint32);
}

fn decodePackedSint64s(data: py.Buffer) ?py.List {
    return decodePackedVarints(data, .sint64);
}

fn decodePackedBools(data: py.Buffer) ?py.List {
    return decodePackedVarints(data, .bool);
}

const Fixed32Kind = enum {
    fixed32,
    sfixed32,
    float,
};

fn decodePackedFixed32(data: py.Buffer, comptime kind: Fixed32Kind) ?py.List {
    var buffer = data;
    defer buffer.release();
    const slice = buffer.slice();
    if (slice.len % 4 != 0) {
        switch (kind) {
            .fixed32 => py.raise(.ValueError, "packed fixed32 data length not a multiple of 4"),
            .sfixed32 => py.raise(.ValueError, "packed sfixed32 data length not a multiple of 4"),
            .float => py.raise(.ValueError, "packed float data length not a multiple of 4"),
        }
        return null;
    }
    const count = slice.len / 4;
    var list = py.List.init(count) orelse return null;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const start = i * 4;
        const raw = slice[start .. start + 4];
        const raw_ptr: *const [4]u8 = @ptrCast(raw.ptr);
        const value = mem.readInt(u32, raw_ptr, .little);
        const out = switch (kind) {
            .fixed32 => value,
            .sfixed32 => fixed32ToSfixed32(value),
            .float => @as(f32, @bitCast(value)),
        };
        if (!list.set(i, out)) {
            list.deinit();
            return null;
        }
    }
    return list;
}

fn decodePackedFixed32s(data: py.Buffer) ?py.List {
    return decodePackedFixed32(data, .fixed32);
}

fn decodePackedSfixed32s(data: py.Buffer) ?py.List {
    return decodePackedFixed32(data, .sfixed32);
}

fn decodePackedFloats(data: py.Buffer) ?py.List {
    return decodePackedFixed32(data, .float);
}

const Fixed64Kind = enum {
    fixed64,
    sfixed64,
    double,
};

fn decodePackedFixed64(data: py.Buffer, comptime kind: Fixed64Kind) ?py.List {
    var buffer = data;
    defer buffer.release();
    const slice = buffer.slice();
    if (slice.len % 8 != 0) {
        switch (kind) {
            .fixed64 => py.raise(.ValueError, "packed fixed64 data length not a multiple of 8"),
            .sfixed64 => py.raise(.ValueError, "packed sfixed64 data length not a multiple of 8"),
            .double => py.raise(.ValueError, "packed double data length not a multiple of 8"),
        }
        return null;
    }
    const count = slice.len / 8;
    var list = py.List.init(count) orelse return null;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const start = i * 8;
        const raw = slice[start .. start + 8];
        const raw_ptr: *const [8]u8 = @ptrCast(raw.ptr);
        const value = mem.readInt(u64, raw_ptr, .little);
        const out = switch (kind) {
            .fixed64 => value,
            .sfixed64 => fixed64ToSfixed64(value),
            .double => @as(f64, @bitCast(value)),
        };
        if (!list.set(i, out)) {
            list.deinit();
            return null;
        }
    }
    return list;
}

fn decodePackedFixed64s(data: py.Buffer) ?py.List {
    return decodePackedFixed64(data, .fixed64);
}

fn decodePackedSfixed64s(data: py.Buffer) ?py.List {
    return decodePackedFixed64(data, .sfixed64);
}

fn decodePackedDoubles(data: py.Buffer) ?py.List {
    return decodePackedFixed64(data, .double);
}
