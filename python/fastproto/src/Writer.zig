const std = @import("std");

const py = @import("alloconda");
const wire = @import("fastproto").wire;

const Buffer = std.ArrayList(u8);

pub const Writer = py.class("Writer", "Builds a protobuf-encoded message.", .{
    .__init__ = py.method(
        writerInit,
        .{ .doc = "Initialize a writer.", .args = &.{ "parent", "field_num" } },
    ),
    .__enter__ = py.method(writerEnter, .{ .doc = "Enter context." }),
    .__exit__ = py.method(writerExit, .{ .doc = "Exit context." }),
    .int32 = py.method(
        writeField(.i32),
        .{ .doc = "Write an int32 field.", .args = &.{ "field_number", "value" } },
    ),
    .int64 = py.method(
        writeField(.i64),
        .{ .doc = "Write an int64 field.", .args = &.{ "field_number", "value" } },
    ),
    .uint32 = py.method(
        writeField(.u32),
        .{ .doc = "Write a uint32 field.", .args = &.{ "field_number", "value" } },
    ),
    .uint64 = py.method(
        writeField(.u64),
        .{ .doc = "Write a uint64 field.", .args = &.{ "field_number", "value" } },
    ),
    .sint32 = py.method(
        writeField(.sint32),
        .{ .doc = "Write a sint32 field (ZigZag encoded).", .args = &.{ "field_number", "value" } },
    ),
    .sint64 = py.method(
        writeField(.sint64),
        .{ .doc = "Write a sint64 field (ZigZag encoded).", .args = &.{ "field_number", "value" } },
    ),
    .bool = py.method(
        writeField(.bool),
        .{ .doc = "Write a bool field.", .args = &.{ "field_number", "value" } },
    ),
    .@"enum" = py.method(
        writeField(.i32),
        .{ .doc = "Write an enum field (same as int32).", .args = &.{ "field_number", "value" } },
    ),
    .fixed64 = py.method(
        writeField(.fixed64),
        .{ .doc = "Write a fixed64 field.", .args = &.{ "field_number", "value" } },
    ),
    .sfixed64 = py.method(
        writeField(.sfixed64),
        .{ .doc = "Write an sfixed64 field.", .args = &.{ "field_number", "value" } },
    ),
    .double = py.method(
        writeField(.double),
        .{ .doc = "Write a double field.", .args = &.{ "field_number", "value" } },
    ),
    .fixed32 = py.method(
        writeField(.fixed32),
        .{ .doc = "Write a fixed32 field.", .args = &.{ "field_number", "value" } },
    ),
    .sfixed32 = py.method(
        writeField(.sfixed32),
        .{ .doc = "Write an sfixed32 field.", .args = &.{ "field_number", "value" } },
    ),
    .float = py.method(
        writeField(.float),
        .{ .doc = "Write a float field.", .args = &.{ "field_number", "value" } },
    ),
    .string = py.method(writerString, .{ .doc = "Write a string field.", .args = &.{ "field_number", "value" } }),
    .bytes = py.method(writerBytes, .{ .doc = "Write a bytes field.", .args = &.{ "field_number", "value" } }),
    .message = py.method(writerMessage, .{ .doc = "Start a nested message.", .args = &.{"field_number"} }),
    .end = py.method(writerEnd, .{ .doc = "Explicitly end a nested message." }),
    .packed_int32s = py.method(
        writePackedField(.i32),
        .{ .doc = "Write packed repeated int32.", .args = &.{ "field_number", "values" } },
    ),
    .packed_int64s = py.method(
        writePackedField(.i64),
        .{ .doc = "Write packed repeated int64.", .args = &.{ "field_number", "values" } },
    ),
    .packed_uint32s = py.method(
        writePackedField(.u32),
        .{ .doc = "Write packed repeated uint32.", .args = &.{ "field_number", "values" } },
    ),
    .packed_uint64s = py.method(
        writePackedField(.u64),
        .{ .doc = "Write packed repeated uint64.", .args = &.{ "field_number", "values" } },
    ),
    .packed_sint32s = py.method(
        writePackedField(.sint32),
        .{ .doc = "Write packed repeated sint32.", .args = &.{ "field_number", "values" } },
    ),
    .packed_sint64s = py.method(
        writePackedField(.sint64),
        .{ .doc = "Write packed repeated sint64.", .args = &.{ "field_number", "values" } },
    ),
    .packed_bools = py.method(
        writePackedField(.bool),
        .{ .doc = "Write packed repeated bool.", .args = &.{ "field_number", "values" } },
    ),
    .packed_fixed32s = py.method(
        writePackedField(.fixed32),
        .{ .doc = "Write packed repeated fixed32.", .args = &.{ "field_number", "values" } },
    ),
    .packed_sfixed32s = py.method(
        writePackedField(.sfixed32),
        .{ .doc = "Write packed repeated sfixed32.", .args = &.{ "field_number", "values" } },
    ),
    .packed_floats = py.method(
        writePackedField(.float),
        .{ .doc = "Write packed repeated float.", .args = &.{ "field_number", "values" } },
    ),
    .packed_fixed64s = py.method(
        writePackedField(.fixed64),
        .{ .doc = "Write packed repeated fixed64.", .args = &.{ "field_number", "values" } },
    ),
    .packed_sfixed64s = py.method(
        writePackedField(.sfixed64),
        .{ .doc = "Write packed repeated sfixed64.", .args = &.{ "field_number", "values" } },
    ),
    .packed_doubles = py.method(
        writePackedField(.double),
        .{ .doc = "Write packed repeated double.", .args = &.{ "field_number", "values" } },
    ),
    .finish = py.method(writerFinish, .{ .doc = "Finish building and return the encoded message." }),
    .clear = py.method(writerClear, .{ .doc = "Clear the buffer to reuse the writer." }),
    .__del__ = py.method(deinit, .{ .doc = "Release buffer resources." }),
}).withPayload(State);

const State = struct {
    buffer: Buffer = .empty,
    parent: ?py.Object = null,
    field_num: i64 = 0,

    const init: @This() = .{};

    fn deinit(self: *@This()) void {
        self.buffer.deinit(py.allocator);
        if (self.parent) |obj| {
            obj.deinit();
            self.parent = null;
        }
        self.* = undefined;
    }
};

fn appendVarint(comptime T: type, buffer: *Buffer, value: T) !void {
    var buf: [wire.max_varint_len]u8 = undefined;
    const data = wire.encodeVarint(T, value, &buf) catch unreachable;
    try buffer.appendSlice(py.allocator, data);
}

fn appendVarintFromLong(buffer: *Buffer, parsed: py.Long) !void {
    try switch (parsed) {
        .signed => |v| appendVarint(i64, buffer, v),
        .unsigned => |v| appendVarint(u64, buffer, v),
    };
}

fn writeTag(buffer: *Buffer, field_number: i64, wire_type: wire.WireType) !void {
    if (field_number < 1) return py.raise(.ValueError, "field number must be >= 1");
    if (field_number > 0x1FFFFFFF) return py.raise(.ValueError, "field number too large");
    const tag = wire.Tag.must(@intCast(field_number), wire_type);
    try appendVarint(u64, buffer, tag.encode());
}

fn TypeForScalar(comptime scalar: wire.Scalar) type {
    return switch (scalar) {
        .i32, .i64, .u32, .u64, .fixed32, .fixed64 => py.Object,
        .sint32, .sint64, .sfixed64 => i64,
        .sfixed32 => i32,
        .float => f32,
        .double => f64,
        .bool => bool,
    };
}

fn writeField(comptime scalar: wire.Scalar) fn (py.Object, i64, TypeForScalar(scalar)) anyerror!void {
    return struct {
        fn write(self: py.Object, field_number: i64, value: TypeForScalar(scalar)) !void {
            const state = try Writer.payloadFrom(self);
            try writeTag(&state.buffer, field_number, scalar.wireType());
            switch (scalar) {
                .i32, .i64 => {
                    const parsed = try py.Long.fromObject(value);
                    try appendVarintFromLong(&state.buffer, parsed);
                },
                .u32 => {
                    const masked = try py.Long.unsignedMask(value);
                    try appendVarint(u64, &state.buffer, masked & 0xFFFFFFFF);
                },
                .u64 => {
                    const masked = try py.Long.unsignedMask(value);
                    try appendVarint(u64, &state.buffer, masked);
                },
                .sint32 => {
                    const encoded = wire.zigzagEncode(i64, value) & 0xFFFFFFFF;
                    try appendVarint(u64, &state.buffer, encoded);
                },
                .sint64 => {
                    const encoded = wire.zigzagEncode(i64, value);
                    try appendVarint(u64, &state.buffer, encoded);
                },
                .bool => {
                    try appendVarint(u64, &state.buffer, if (value) 1 else 0);
                },
                .fixed64 => {
                    const masked = try py.Long.unsignedMask(value);
                    var buf: [8]u8 = undefined;
                    wire.writeInt(u64, &buf, masked);
                    try state.buffer.appendSlice(py.allocator, &buf);
                },
                .sfixed64 => {
                    var buf: [8]u8 = undefined;
                    wire.writeInt(i64, &buf, value);
                    try state.buffer.appendSlice(py.allocator, &buf);
                },
                .double => {
                    var buf: [8]u8 = undefined;
                    wire.writeInt(u64, &buf, @bitCast(value));
                    try state.buffer.appendSlice(py.allocator, &buf);
                },
                .fixed32 => {
                    const masked = try py.Long.unsignedMask(value);
                    var buf: [4]u8 = undefined;
                    wire.writeInt(u32, &buf, @truncate(masked));
                    try state.buffer.appendSlice(py.allocator, &buf);
                },
                .sfixed32 => {
                    var buf: [4]u8 = undefined;
                    wire.writeInt(i32, &buf, value);
                    try state.buffer.appendSlice(py.allocator, &buf);
                },
                .float => {
                    var buf: [4]u8 = undefined;
                    wire.writeInt(u32, &buf, @bitCast(value));
                    try state.buffer.appendSlice(py.allocator, &buf);
                },
            }
        }
    }.write;
}

fn writePackedField(comptime scalar: wire.Scalar) fn (py.Object, i64, py.List) anyerror!void {
    return struct {
        fn write(self: py.Object, field_number: i64, values: py.List) !void {
            const count = try values.len();
            if (count == 0) return;
            const packed_bytes = try encodePacked(values, scalar);
            defer packed_bytes.deinit();
            const slice = try packed_bytes.slice();
            const state = try Writer.payloadFrom(self);
            try writeTag(&state.buffer, field_number, .len);
            try appendVarint(u64, &state.buffer, slice.len);
            try state.buffer.appendSlice(py.allocator, slice);
        }
    }.write;
}

fn encodePacked(values: py.List, comptime scalar: wire.Scalar) !py.Bytes {
    return switch (comptime scalar.wireType()) {
        .varint => encodePackedVarints(values, scalar),
        .fixed32, .fixed64 => encodePackedFixed(values, scalar),
        else => @compileError("encodePacked expects a packed scalar"),
    };
}

fn encodePackedVarints(values: py.List, comptime scalar: wire.Scalar) !py.Bytes {
    const count = try values.len();
    var out: Buffer = .empty;
    defer out.deinit(py.allocator);
    if (count > 0) try out.ensureTotalCapacity(py.allocator, count);

    var buf: [wire.max_varint_len]u8 = undefined;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const item = try values.get(i);
        const data = switch (scalar) {
            .i32, .i64 => blk: {
                const parsed = try py.Long.fromObject(item);
                break :blk switch (parsed) {
                    .signed => |v| wire.encodeVarint(i64, v, &buf) catch unreachable,
                    .unsigned => |v| wire.encodeVarint(u64, v, &buf) catch unreachable,
                };
            },
            .u32 => blk: {
                const masked = try py.Long.unsignedMask(item);
                const value: u64 = masked & 0xFFFF_FFFF;
                break :blk wire.encodeVarint(u64, value, &buf) catch unreachable;
            },
            .u64 => blk: {
                const masked = try py.Long.unsignedMask(item);
                break :blk wire.encodeVarint(u64, masked, &buf) catch unreachable;
            },
            .sint32 => blk: {
                const value = try item.as(i64);
                const encoded = wire.zigzagEncode(i64, value) & 0xFFFF_FFFF;
                break :blk wire.encodeVarint(u64, encoded, &buf) catch unreachable;
            },
            .sint64 => blk: {
                const value = try item.as(i64);
                const encoded = wire.zigzagEncode(i64, value);
                break :blk wire.encodeVarint(u64, encoded, &buf) catch unreachable;
            },
            .bool => blk: {
                const value = try item.as(bool);
                const encoded: u64 = if (value) 1 else 0;
                break :blk wire.encodeVarint(u64, encoded, &buf) catch unreachable;
            },
            else => @compileError("encodePackedVarints expects a varint scalar"),
        };
        try out.appendSlice(py.allocator, data);
    }

    return .fromSlice(out.items);
}

fn encodePackedFixed(values: py.List, comptime scalar: wire.Scalar) !py.Bytes {
    const count = try values.len();
    const chunk: usize = comptime scalar.size();
    var out: Buffer = .empty;
    defer out.deinit(py.allocator);
    try out.resize(py.allocator, count * chunk);
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const item = try values.get(i);
        const start = i * chunk;
        const raw_ptr: *[chunk]u8 = @ptrCast(out.items[start .. start + chunk].ptr);
        switch (scalar) {
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
            else => @compileError("encodePackedFixed expects a fixed scalar"),
        }
    }
    return .fromSlice(out.items);
}

fn writerInit(self: py.Object, parent: ?py.Object, field_num: ?i64) !void {
    const state = try Writer.payloadFrom(self);
    state.* = .init;
    if (parent) |parent_obj| {
        state.parent = parent_obj.incref();
        state.field_num = field_num orelse 0;
    }
}

fn writerEnter(self: py.Object) !py.Object {
    return self.incref();
}

fn writerExit(self: py.Object, exc_type: ?py.Object, _: ?py.Object, _: ?py.Object) !bool {
    if (exc_type == null) try writerEnd(self);
    return false;
}

fn writerString(self: py.Object, field_number: i64, value: []const u8) !void {
    const state = try Writer.payloadFrom(self);
    try writeTag(&state.buffer, field_number, .len);
    try appendVarint(u64, &state.buffer, @intCast(value.len));
    try state.buffer.appendSlice(py.allocator, value);
}

fn writerBytes(self: py.Object, field_number: i64, value: py.Buffer) !void {
    const state = try Writer.payloadFrom(self);
    var buffer = value;
    defer buffer.release();
    const slice = buffer.slice();
    try writeTag(&state.buffer, field_number, .len);
    try appendVarint(u64, &state.buffer, slice.len);
    try state.buffer.appendSlice(py.allocator, slice);
}

fn writerMessage(self: py.Object, field_number: i64) !py.Object {
    var child = try Writer.new();
    errdefer child.deinit();
    const state = try Writer.payloadFrom(child);
    state.* = .{
        .buffer = .empty,
        .parent = self.incref(),
        .field_num = field_number,
    };
    return child;
}

fn writerEnd(self: py.Object) !void {
    const state = try Writer.payloadFrom(self);
    const parent_state = try Writer.payloadFrom(state.parent orelse return);
    try writeTag(&parent_state.buffer, state.field_num, .len);
    try appendVarint(u64, &parent_state.buffer, state.buffer.items.len);
    try parent_state.buffer.appendSlice(py.allocator, state.buffer.items);
}

fn writerFinish(self: py.Object) !py.Bytes {
    const state = try Writer.payloadFrom(self);
    return .fromSlice(state.buffer.items);
}

fn writerClear(self: py.Object) !void {
    const state = try Writer.payloadFrom(self);
    state.buffer.items.len = 0;
}

fn deinit(self: py.Object) void {
    const state = Writer.payloadFrom(self) catch return;
    state.deinit();
}
