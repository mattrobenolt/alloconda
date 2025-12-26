//! Python bindings for fastproto.
//!
//! Exposes the Zig protobuf implementation to Python.

const std = @import("std");
const intToEnum = std.meta.intToEnum;

const fastproto = @import("fastproto");
const wire = fastproto.wire;
const py = @import("alloconda");

const Buffer = std.ArrayList(u8);

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
    .encode_packed_int32s = py.method(encodePackedInt32s, .{
        .doc = "Encode packed int32 values.",
    }),
    .encode_packed_int64s = py.method(encodePackedInt64s, .{
        .doc = "Encode packed int64 values.",
    }),
    .encode_packed_uint32s = py.method(encodePackedUint32s, .{
        .doc = "Encode packed uint32 values.",
    }),
    .encode_packed_uint64s = py.method(encodePackedUint64s, .{
        .doc = "Encode packed uint64 values.",
    }),
    .encode_packed_sint32s = py.method(encodePackedSint32s, .{
        .doc = "Encode packed sint32 values.",
    }),
    .encode_packed_sint64s = py.method(encodePackedSint64s, .{
        .doc = "Encode packed sint64 values.",
    }),
    .encode_packed_bools = py.method(encodePackedBools, .{
        .doc = "Encode packed bool values.",
    }),
    .encode_packed_fixed32s = py.method(encodePackedFixed32s, .{
        .doc = "Encode packed fixed32 values.",
    }),
    .encode_packed_sfixed32s = py.method(encodePackedSfixed32s, .{
        .doc = "Encode packed sfixed32 values.",
    }),
    .encode_packed_floats = py.method(encodePackedFloats, .{
        .doc = "Encode packed float values.",
    }),
    .encode_packed_fixed64s = py.method(encodePackedFixed64s, .{
        .doc = "Encode packed fixed64 values.",
    }),
    .encode_packed_sfixed64s = py.method(encodePackedSfixed64s, .{
        .doc = "Encode packed sfixed64 values.",
    }),
    .encode_packed_doubles = py.method(encodePackedDoubles, .{
        .doc = "Encode packed double values.",
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
    .skip_field = py.method(skipField, .{
        .doc = "Skip a field at offset, returns new offset or None at end.",
    }),
});

fn encodeVarint(value: py.Object) !py.Bytes {
    const parsed: py.Long = try .fromObject(value);
    var buf: [wire.max_varint_len]u8 = undefined;
    const len = try switch (parsed) {
        .signed => |v| wire.encodeVarint(i64, v, &buf),
        .unsigned => |v| wire.encodeVarint(u64, v, &buf),
    };
    return .fromSlice(buf[0..len]);
}

fn encodeVarintUnsigned(value: u64) !py.Bytes {
    var buf: [wire.max_varint_len]u8 = undefined;
    const len = try wire.encodeVarint(u64, value, &buf);
    return .fromSlice(buf[0..len]);
}

fn decodeVarint(data: py.Buffer, offset: usize) !py.Tuple {
    var buffer = data;
    defer buffer.release();
    const slice = buffer.slice();
    if (offset >= slice.len) {
        return py.raise(.ValueError, "offset beyond data length");
    }
    const value, const bytes_read = wire.decodeVarint(u64, slice[offset..]) catch |err| {
        return py.raise(.ValueError, switch (err) {
            wire.Error.Truncated => "truncated varint",
            wire.Error.VarintTooLong => "varint too long",
            else => "decode error",
        });
    };
    return tuple2(u64, value, usize, offset + bytes_read);
}

fn tuple2(comptime T0: type, first: T0, comptime T1: type, second: T1) !py.Tuple {
    var result: py.Tuple = try .init(2);
    errdefer result.deinit();
    try result.set(T0, 0, first);
    try result.set(T1, 1, second);
    return result;
}

fn encodeFixed32(value: py.Object) !py.Bytes {
    const masked = try py.Long.unsignedMask(value);
    const cast_value: u32 = @truncate(masked);
    var buf: [4]u8 = undefined;
    wire.writeInt(u32, &buf, cast_value);
    return .fromSlice(&buf);
}

fn encodeSfixed32(value: i32) !py.Bytes {
    var buf: [4]u8 = undefined;
    wire.writeInt(i32, &buf, value);
    return .fromSlice(&buf);
}

fn encodeFixed64(value: py.Object) !py.Bytes {
    const masked = try py.Long.unsignedMask(value);
    var buf: [8]u8 = undefined;
    wire.writeInt(u64, &buf, masked);
    return .fromSlice(&buf);
}

fn encodeSfixed64(value: i64) !py.Bytes {
    var buf: [8]u8 = undefined;
    wire.writeInt(i64, &buf, value);
    return .fromSlice(&buf);
}

fn encodeFloat(value: f32) !py.Bytes {
    var buf: [4]u8 = undefined;
    wire.writeInt(u32, &buf, @bitCast(value));
    return .fromSlice(&buf);
}

fn encodeDouble(value: f64) !py.Bytes {
    var buf: [8]u8 = undefined;
    wire.writeInt(u64, &buf, @bitCast(value));
    return .fromSlice(&buf);
}

fn encodePackedVarints(values: py.List, comptime kind: VarintKind) !py.Bytes {
    const count = try values.len();
    var out: Buffer = .empty;
    defer out.deinit(py.allocator);
    if (count > 0) try out.ensureTotalCapacity(py.allocator, count);

    var buf: [wire.max_varint_len]u8 = undefined;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const item = try values.get(i);
        const len = try switch (kind) {
            .int32, .int64 => blk: {
                const parsed = try py.Long.fromObject(item);
                break :blk switch (parsed) {
                    .signed => |v| wire.encodeVarint(i64, v, &buf),
                    .unsigned => |v| wire.encodeVarint(u64, v, &buf),
                };
            },
            .uint32 => blk: {
                const masked = try py.Long.unsignedMask(item);
                const value: u64 = masked & 0xFFFF_FFFF;
                break :blk wire.encodeVarint(u64, value, &buf);
            },
            .uint64 => blk: {
                const masked = try py.Long.unsignedMask(item);
                break :blk wire.encodeVarint(u64, masked, &buf);
            },
            .sint32 => blk: {
                const value = try item.as(i64);
                const encoded = wire.zigzagEncode(i64, value) & 0xFFFF_FFFF;
                break :blk wire.encodeVarint(u64, encoded, &buf);
            },
            .sint64 => blk: {
                const value = try item.as(i64);
                const encoded = wire.zigzagEncode(i64, value);
                break :blk wire.encodeVarint(u64, encoded, &buf);
            },
            .bool => blk: {
                const value = try item.as(bool);
                const encoded: u64 = if (value) 1 else 0;
                break :blk wire.encodeVarint(u64, encoded, &buf);
            },
        };
        try out.appendSlice(py.allocator, buf[0..len]);
    }

    return .fromSlice(out.items);
}

fn encodePackedInt32s(values: py.List) !py.Bytes {
    return encodePackedVarints(values, .int32);
}

fn encodePackedInt64s(values: py.List) !py.Bytes {
    return encodePackedVarints(values, .int64);
}

fn encodePackedUint32s(values: py.List) !py.Bytes {
    return encodePackedVarints(values, .uint32);
}

fn encodePackedUint64s(values: py.List) !py.Bytes {
    return encodePackedVarints(values, .uint64);
}

fn encodePackedSint32s(values: py.List) !py.Bytes {
    return encodePackedVarints(values, .sint32);
}

fn encodePackedSint64s(values: py.List) !py.Bytes {
    return encodePackedVarints(values, .sint64);
}

fn encodePackedBools(values: py.List) !py.Bytes {
    return encodePackedVarints(values, .bool);
}

fn decodeFixed32(data: py.Buffer, offset: usize) !py.Tuple {
    var buffer = data;
    defer buffer.release();
    const slice = buffer.slice();
    if (offset >= slice.len) {
        return py.raise(.ValueError, "offset beyond data length");
    }
    if (slice.len - offset < 4) {
        return py.raise(.ValueError, "truncated fixed32");
    }
    const raw = slice[offset .. offset + 4];
    const raw_ptr: *const [4]u8 = @ptrCast(raw.ptr);
    const value = wire.readInt(u32, raw_ptr);
    return tuple2(u32, value, usize, offset + 4);
}

fn decodeFixed64(data: py.Buffer, offset: usize) !py.Tuple {
    var buffer = data;
    defer buffer.release();
    const slice = buffer.slice();
    if (offset >= slice.len) {
        return py.raise(.ValueError, "offset beyond data length");
    }
    if (slice.len - offset < 8) {
        return py.raise(.ValueError, "truncated fixed64");
    }
    const raw = slice[offset .. offset + 8];
    const raw_ptr: *const [8]u8 = @ptrCast(raw.ptr);
    const value = wire.readInt(u64, raw_ptr);
    return tuple2(u64, value, usize, offset + 8);
}

const EncodeFixed32Kind = enum {
    fixed32,
    sfixed32,
    float,
};

fn encodePackedFixed32(values: py.List, comptime kind: EncodeFixed32Kind) !py.Bytes {
    const count = try values.len();
    var out: Buffer = .empty;
    defer out.deinit(py.allocator);
    try out.resize(py.allocator, count * 4);
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const item = try values.get(i);
        const start = i * 4;
        const raw_ptr: *[4]u8 = @ptrCast(out.items[start .. start + 4].ptr);
        switch (kind) {
            .fixed32 => {
                const masked = try py.Long.unsignedMask(item);
                const value: u32 = @truncate(masked);
                wire.writeInt(u32, raw_ptr, value);
            },
            .sfixed32 => {
                const value = try item.as(i32);
                wire.writeInt(i32, raw_ptr, value);
            },
            .float => {
                const value = try item.as(f32);
                wire.writeInt(u32, raw_ptr, @bitCast(value));
            },
        }
    }
    return .fromSlice(out.items);
}

fn encodePackedFixed32s(values: py.List) !py.Bytes {
    return encodePackedFixed32(values, .fixed32);
}

fn encodePackedSfixed32s(values: py.List) !py.Bytes {
    return encodePackedFixed32(values, .sfixed32);
}

fn encodePackedFloats(values: py.List) !py.Bytes {
    return encodePackedFixed32(values, .float);
}

const EncodeFixed64Kind = enum {
    fixed64,
    sfixed64,
    double,
};

fn encodePackedFixed64(values: py.List, comptime kind: EncodeFixed64Kind) !py.Bytes {
    const count = try values.len();
    var out: Buffer = .empty;
    defer out.deinit(py.allocator);
    try out.resize(py.allocator, count * 8);
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const item = try values.get(i);
        const start = i * 8;
        const raw_ptr: *[8]u8 = @ptrCast(out.items[start .. start + 8].ptr);
        switch (kind) {
            .fixed64 => {
                const masked = try py.Long.unsignedMask(item);
                wire.writeInt(u64, raw_ptr, masked);
            },
            .sfixed64 => {
                const value = try item.as(i64);
                wire.writeInt(i64, raw_ptr, value);
            },
            .double => {
                const value = try item.as(f64);
                wire.writeInt(u64, raw_ptr, @bitCast(value));
            },
        }
    }
    return .fromSlice(out.items);
}

fn encodePackedFixed64s(values: py.List) !py.Bytes {
    return encodePackedFixed64(values, .fixed64);
}

fn encodePackedSfixed64s(values: py.List) !py.Bytes {
    return encodePackedFixed64(values, .sfixed64);
}

fn encodePackedDoubles(values: py.List) !py.Bytes {
    return encodePackedFixed64(values, .double);
}

fn skipField(data: py.Buffer, offset: usize) !?usize {
    var buffer = data;
    defer buffer.release();
    const slice = buffer.slice();
    if (offset >= slice.len) return null;

    const tag, const tag_len = wire.decodeVarint(u64, slice[offset..]) catch |err| {
        return py.raise(.ValueError, switch (err) {
            wire.Error.Truncated => "truncated varint",
            wire.Error.VarintTooLong => "varint too long",
            else => "decode error",
        });
    };
    const parsed = wire.Tag.parse(tag) catch |err| {
        return py.raise(.ValueError, switch (err) {
            wire.Error.InvalidWireType => "invalid wire type",
            wire.Error.InvalidFieldNumber => "invalid field number",
            else => "invalid tag",
        });
    };

    var pos = offset + tag_len;
    switch (parsed.wire_type) {
        .varint => {
            _, const bytes_read = wire.decodeVarint(u64, slice[pos..]) catch |err| {
                return py.raise(.ValueError, switch (err) {
                    wire.Error.Truncated => "truncated varint",
                    wire.Error.VarintTooLong => "varint too long",
                    else => "decode error",
                });
            };
            pos += bytes_read;
        },
        .fixed64 => {
            if (slice.len - pos < 8) {
                return py.raise(.ValueError, "truncated fixed64");
            }
            pos += 8;
        },
        .len => {
            const length, const length_len = wire.decodeVarint(u64, slice[pos..]) catch |err| {
                return py.raise(.ValueError, switch (err) {
                    wire.Error.Truncated => "truncated varint",
                    wire.Error.VarintTooLong => "varint too long",
                    else => "decode error",
                });
            };
            pos += length_len;
            if (slice.len - pos < length) {
                return py.raise(.ValueError, "truncated length-delimited field");
            }
            pos += length;
        },
        .fixed32 => {
            if (slice.len - pos < 4) {
                return py.raise(.ValueError, "truncated fixed32");
            }
            pos += 4;
        },
    }

    return pos;
}

fn makeTag(field_number: u32, wire_type_int: u8) !u32 {
    const wire_type = intToEnum(wire.WireType, wire_type_int) catch {
        return py.raise(.ValueError, "invalid wire type");
    };
    const tag = wire.Tag.init(field_number, wire_type) catch |err| {
        return py.raise(.ValueError, switch (err) {
            fastproto.Error.InvalidFieldNumber => "field number must be >= 1",
            fastproto.Error.FieldNumberTooLarge => "field number too large",
            else => "invalid tag",
        });
    };
    return tag.encode();
}

fn parseTag(tag: u64) !py.Tuple {
    const parsed = wire.Tag.parse(tag) catch |err| {
        return py.raise(.ValueError, switch (err) {
            wire.Error.InvalidWireType => "invalid wire type",
            wire.Error.InvalidFieldNumber => "invalid field number",
            else => "invalid tag",
        });
    };
    return tuple2(u32, parsed.field_number, u3, @intFromEnum(parsed.wire_type));
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

fn decodePackedVarints(data: py.Buffer, comptime kind: VarintKind) !py.List {
    var buffer = data;
    defer buffer.release();
    const slice = buffer.slice();
    var list: py.List = try .init(0);
    errdefer list.deinit();
    var offset: usize = 0;
    while (offset < slice.len) {
        const value, const bytes_read = wire.decodeVarint(u64, slice[offset..]) catch |err| {
            return py.raise(.ValueError, switch (err) {
                wire.Error.Truncated => "truncated varint",
                wire.Error.VarintTooLong => "varint too long",
                else => "decode error",
            });
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
        try list.append(@TypeOf(out), out);
    }
    return list;
}

fn decodePackedInt32s(data: py.Buffer) !py.List {
    return decodePackedVarints(data, .int32);
}

fn decodePackedInt64s(data: py.Buffer) !py.List {
    return decodePackedVarints(data, .int64);
}

fn decodePackedUint32s(data: py.Buffer) !py.List {
    return decodePackedVarints(data, .uint32);
}

fn decodePackedUint64s(data: py.Buffer) !py.List {
    return decodePackedVarints(data, .uint64);
}

fn decodePackedSint32s(data: py.Buffer) !py.List {
    return decodePackedVarints(data, .sint32);
}

fn decodePackedSint64s(data: py.Buffer) !py.List {
    return decodePackedVarints(data, .sint64);
}

fn decodePackedBools(data: py.Buffer) !py.List {
    return decodePackedVarints(data, .bool);
}

const Fixed32Kind = enum {
    fixed32,
    sfixed32,
    float,
};

fn decodePackedFixed32(data: py.Buffer, comptime kind: Fixed32Kind) !py.List {
    var buffer = data;
    defer buffer.release();
    const slice = buffer.slice();
    if (slice.len % 4 != 0) return py.raise(.ValueError, switch (kind) {
        .fixed32 => "packed fixed32 data length not a multiple of 4",
        .sfixed32 => "packed sfixed32 data length not a multiple of 4",
        .float => "packed float data length not a multiple of 4",
    });
    const count = slice.len / 4;
    var list: py.List = try .init(count);
    errdefer list.deinit();
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const start = i * 4;
        const raw = slice[start .. start + 4];
        const raw_ptr: *const [4]u8 = @ptrCast(raw.ptr);
        const value = wire.readInt(u32, raw_ptr);
        const out = switch (kind) {
            .fixed32 => value,
            .sfixed32 => fixed32ToSfixed32(value),
            .float => @as(f32, @bitCast(value)),
        };
        try list.set(@TypeOf(out), i, out);
    }
    return list;
}

fn decodePackedFixed32s(data: py.Buffer) !py.List {
    return decodePackedFixed32(data, .fixed32);
}

fn decodePackedSfixed32s(data: py.Buffer) !py.List {
    return decodePackedFixed32(data, .sfixed32);
}

fn decodePackedFloats(data: py.Buffer) !py.List {
    return decodePackedFixed32(data, .float);
}

const Fixed64Kind = enum {
    fixed64,
    sfixed64,
    double,
};

fn decodePackedFixed64(data: py.Buffer, comptime kind: Fixed64Kind) !py.List {
    var buffer = data;
    defer buffer.release();
    const slice = buffer.slice();
    if (slice.len % 8 != 0) return py.raise(.ValueError, switch (kind) {
        .fixed64 => "packed fixed64 data length not a multiple of 8",
        .sfixed64 => "packed sfixed64 data length not a multiple of 8",
        .double => "packed double data length not a multiple of 8",
    });
    const count = slice.len / 8;
    var list: py.List = try .init(count);
    errdefer list.deinit();
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const start = i * 8;
        const raw = slice[start .. start + 8];
        const raw_ptr: *const [8]u8 = @ptrCast(raw.ptr);
        const value = wire.readInt(u64, raw_ptr);
        const out = switch (kind) {
            .fixed64 => value,
            .sfixed64 => fixed64ToSfixed64(value),
            .double => @as(f64, @bitCast(value)),
        };
        try list.set(@TypeOf(out), i, out);
    }
    return list;
}

fn decodePackedFixed64s(data: py.Buffer) !py.List {
    return decodePackedFixed64(data, .fixed64);
}

fn decodePackedSfixed64s(data: py.Buffer) !py.List {
    return decodePackedFixed64(data, .sfixed64);
}

fn decodePackedDoubles(data: py.Buffer) !py.List {
    return decodePackedFixed64(data, .double);
}
