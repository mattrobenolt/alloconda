const std = @import("std");
const fmt = std.fmt;

const py = @import("alloconda");
const wire = @import("fastproto").wire;

const ByteView = @import("ByteView.zig");
const Reader = @import("Reader.zig");

pub const Field = py.class("Field", "Represents a single field from a protobuf message.", .{
    .int32 = py.method(readField(.i32), .{ .doc = "Read as int32 (may be negative via sign extension)." }),
    .int64 = py.method(readField(.i64), .{ .doc = "Read as int64 (may be negative via sign extension)." }),
    .uint32 = py.method(readField(.u32), .{ .doc = "Read as uint32." }),
    .uint64 = py.method(readField(.u64), .{ .doc = "Read as uint64." }),
    .sint32 = py.method(readField(.sint32), .{ .doc = "Read as sint32 (ZigZag encoded)." }),
    .sint64 = py.method(readField(.sint64), .{ .doc = "Read as sint64 (ZigZag encoded)." }),
    .bool = py.method(readField(.bool), .{ .doc = "Read as bool." }),
    .@"enum" = py.method(readField(.i32), .{ .doc = "Read as enum (same as int32)." }),
    .fixed64 = py.method(readField(.fixed64), .{ .doc = "Read as fixed64." }),
    .sfixed64 = py.method(readField(.sfixed64), .{ .doc = "Read as sfixed64." }),
    .double = py.method(readField(.double), .{ .doc = "Read as double." }),
    .fixed32 = py.method(readField(.fixed32), .{ .doc = "Read as fixed32." }),
    .sfixed32 = py.method(readField(.sfixed32), .{ .doc = "Read as sfixed32." }),
    .float = py.method(readField(.float), .{ .doc = "Read as float." }),
    .string = py.method(fieldString, .{ .doc = "Read as UTF-8 string." }),
    .bytes = py.method(fieldBytes, .{ .doc = "Read as raw bytes." }),
    .message_data = py.method(fieldBytes, .{ .doc = "Get raw message data for nested message parsing." }),
    .message = py.method(fieldMessage, .{ .doc = "Read as embedded message, returning a new Reader." }),
    .packed_int32s = py.method(readPackedField(.i32), .{ .doc = "Read as packed repeated int32." }),
    .packed_int64s = py.method(readPackedField(.i64), .{ .doc = "Read as packed repeated int64." }),
    .packed_uint32s = py.method(readPackedField(.u32), .{ .doc = "Read as packed repeated uint32." }),
    .packed_uint64s = py.method(readPackedField(.u64), .{ .doc = "Read as packed repeated uint64." }),
    .packed_sint32s = py.method(readPackedField(.sint32), .{ .doc = "Read as packed repeated sint32." }),
    .packed_sint64s = py.method(readPackedField(.sint64), .{ .doc = "Read as packed repeated sint64." }),
    .packed_bools = py.method(readPackedField(.bool), .{ .doc = "Read as packed repeated bool." }),
    .packed_fixed32s = py.method(readPackedField(.fixed32), .{ .doc = "Read as packed repeated fixed32." }),
    .packed_sfixed32s = py.method(readPackedField(.sfixed32), .{ .doc = "Read as packed repeated sfixed32." }),
    .packed_floats = py.method(readPackedField(.float), .{ .doc = "Read as packed repeated float." }),
    .packed_fixed64s = py.method(readPackedField(.fixed64), .{ .doc = "Read as packed repeated fixed64." }),
    .packed_sfixed64s = py.method(readPackedField(.sfixed64), .{ .doc = "Read as packed repeated sfixed64." }),
    .packed_doubles = py.method(readPackedField(.double), .{ .doc = "Read as packed repeated double." }),
    .__del__ = py.method(deinit, .{ .doc = "Release held field data." }),
}).withPayload(State);

const State = struct {
    number: u32 = 0,
    wire_type: wire.WireType = .varint,
    value: u64 = 0,
    view: ByteView = .empty,

    const empty: @This() = .{};

    fn slice(self: *const @This()) ![]const u8 {
        return self.view.slice();
    }

    fn require(self: *const @This(), expected: wire.WireType) !void {
        if (self.wire_type == expected) return;
        var buf: [96]u8 = undefined;
        const msg = fmt.bufPrintZ(
            &buf,
            "wire type mismatch: expected {f}, got {f}",
            .{ expected, self.wire_type },
        ) catch "wire type mismatch";
        return py.raise(.ValueError, msg);
    }

    fn deinit(self: *@This()) void {
        self.view.deinit();
        self.* = undefined;
    }
};

pub fn init(
    number: u32,
    wire_type: wire.WireType,
    value: u64,
    view: ByteView,
) !py.Object {
    var owned_view = view;
    errdefer owned_view.deinit();
    var field = try Field.new();
    errdefer field.deinit();
    const state = try Field.payloadFrom(field);
    state.* = .{
        .number = number,
        .wire_type = wire_type,
        .value = value,
        .view = owned_view,
    };
    try field.setAttr("number", u32, number);
    try field.setAttr("wire_type", u8, @intFromEnum(wire_type));
    return field;
}

fn fieldString(self: py.Object) ![]const u8 {
    const state = try Field.payloadFrom(self);
    try state.require(.len);
    return state.slice();
}

fn fieldBytes(self: py.Object) !py.Bytes {
    return .fromSlice(try fieldString(self));
}

fn fieldMessage(self: py.Object) !py.Object {
    const state = try Field.payloadFrom(self);
    try state.require(.len);
    const view = try state.view.clone();
    return Reader.newFromView(view);
}

fn deinit(self: py.Object) void {
    const state = Field.payloadFrom(self) catch return;
    state.deinit();
}

fn readField(comptime scalar: wire.Scalar) fn (py.Object) anyerror!wire.Scalar.Type(scalar) {
    return struct {
        fn read(self: py.Object) !wire.Scalar.Type(scalar) {
            const state = try Field.payloadFrom(self);
            try state.require(scalar.wireType());
            return switch (comptime scalar.wireType()) {
                .varint => scalar.fromVarint(state.value),
                .fixed32, .fixed64 => scalar.fromFixedBits(state.value),
                else => @compileError("readField expects a packed scalar"),
            };
        }
    }.read;
}

fn readPackedField(comptime scalar: wire.Scalar) fn (py.Object) anyerror!py.List {
    return struct {
        fn readPacked(self: py.Object) !py.List {
            const state = try Field.payloadFrom(self);
            try state.require(.len);
            return decodePackedSlice(try state.slice(), scalar);
        }
    }.readPacked;
}

fn decodePackedSlice(slice: []const u8, comptime scalar: wire.Scalar) !py.List {
    switch (comptime scalar.wireType()) {
        .varint => {
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
                const out = scalar.fromVarint(value);
                try list.append(@TypeOf(out), out);
            }
            return list;
        },
        .fixed32, .fixed64 => {
            const length_error = comptime switch (scalar) {
                .fixed32 => "packed fixed32 data length not a multiple of 4",
                .sfixed32 => "packed sfixed32 data length not a multiple of 4",
                .float => "packed float data length not a multiple of 4",
                .fixed64 => "packed fixed64 data length not a multiple of 8",
                .sfixed64 => "packed sfixed64 data length not a multiple of 8",
                .double => "packed double data length not a multiple of 8",
                else => @compileError(fmt.comptimePrint(
                    "decodePackedSlice expects a fixed scalar, got: {any}",
                    .{scalar},
                )),
            };
            const T = scalar.Type();
            const chunk: usize = comptime scalar.size();
            if (slice.len % chunk != 0) return py.raise(.ValueError, length_error);

            const count = slice.len / chunk;
            var list: py.List = try .init(count);
            errdefer list.deinit();
            var i: usize = 0;
            while (i < count) : (i += 1) {
                const start = i * chunk;
                const raw = slice[start .. start + chunk];
                const raw_ptr: *const [chunk]u8 = @ptrCast(raw.ptr);
                const value = scalar.readInt(raw_ptr);
                try list.set(T, i, value);
            }
            return list;
        },
        else => @compileError("decodePackedSlice expects a packed scalar"),
    }
}
