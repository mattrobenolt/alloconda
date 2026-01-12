const std = @import("std");
const intToEnum = std.meta.intToEnum;

const fastproto = @import("fastproto");
const wire = fastproto.wire;
const py = @import("alloconda");

const wrap = @import("errors.zig").wrap;
const writeScalarValue = @import("scalar.zig").writeScalarValue;

const default_buffer_size = 8192;

pub const Writer = py.class("Writer", "Writes protobuf wire format to a binary IO stream.", .{
    .__init__ = py.method(
        writerInit,
        .{ .doc = "Initialize a writer for a binary IO stream.", .args = &.{"stream"} },
    ),
    .write_tag = py.method(
        writerWriteTag,
        .{ .doc = "Write a tag (field number + wire type).", .args = &.{ "field_number", "wire_type" } },
    ),
    .write_scalar = py.method(
        writerWriteScalar,
        .{ .doc = "Write a scalar value (no tag).", .args = &.{ "scalar", "value" } },
    ),
    .write_len = py.method(
        writerWriteLen,
        .{ .doc = "Write length-delimited bytes (no tag).", .args = &.{"value"} },
    ),
    .write_varint = py.method(
        writerWriteVarint,
        .{ .doc = "Write a raw varint.", .args = &.{"value"} },
    ),
    .flush = py.method(writerFlush, .{ .doc = "Flush buffered data to the stream." }),
    .__del__ = py.method(deinit, .{ .doc = "Release stream resources." }),
}).withPayload(State);

const State = struct {
    io: ?py.IoWriter = null,
    writer: fastproto.Writer = undefined,
    buffer: [default_buffer_size]u8 = undefined,

    fn deinit(self: *@This()) void {
        if (self.io) |*io| io.deinit();
        self.* = undefined;
    }
};

fn writerInit(self: py.Object, stream: py.Object) !void {
    const state = try Writer.payloadFrom(self);
    state.deinit();

    const io_writer: py.IoWriter = try .init(stream, &state.buffer);
    state.io = io_writer;
    state.writer = .init(&state.io.?.interface);
}

fn writerWriteTag(self: py.Object, field_number: i64, wire_type_raw: i64) !void {
    const state = try Writer.payloadFrom(self);
    const wire_type = parseWireType(wire_type_raw) catch {
        return py.raise(.ValueError, "invalid wire type");
    };
    try writeTag(&state.writer, field_number, wire_type);
}

fn writerWriteScalar(self: py.Object, scalar_raw: i64, value: py.Object) !void {
    const state = try Writer.payloadFrom(self);
    const scalar = parseScalar(scalar_raw) catch {
        return py.raise(.ValueError, "invalid scalar type");
    };
    try writeScalarValue(&state.writer, scalar, value);
}

fn writerWriteLen(self: py.Object, value: py.Buffer) !void {
    const state = try Writer.payloadFrom(self);
    var buffer = value;
    defer buffer.release();
    const slice = buffer.slice();
    try writeLen(&state.writer, slice);
}

fn writerWriteVarint(self: py.Object, value: py.Object) !void {
    const state = try Writer.payloadFrom(self);
    const parsed: py.Long = try .fromObject(value);
    try switch (parsed) {
        .signed => |v| writeVarint(i64, &state.writer, v),
        .unsigned => |v| writeVarint(u64, &state.writer, v),
    };
}

fn writerFlush(self: py.Object) !void {
    const state = try Writer.payloadFrom(self);
    if (state.io) |*io| {
        try io.flush();
        try flushStream(io.obj);
    }
}

fn writeTag(writer: *fastproto.Writer, field_number: i64, wire_type: wire.WireType) !void {
    if (field_number < 1) return py.raise(.ValueError, "field number must be >= 1");
    if (field_number > 0x1FFFFFFF) return py.raise(.ValueError, "field number too large");
    const tag: wire.Tag = .must(@intCast(field_number), wire_type);
    try wrap(writer.writeTag(tag));
}

fn writeLen(writer: *fastproto.Writer, value: []const u8) !void {
    try wrap(writer.writeLen(value));
}

fn writeVarint(comptime T: type, writer: *fastproto.Writer, value: T) !void {
    try wrap(writer.writeVarint(T, value));
}

fn parseScalar(value: i64) !wire.Scalar {
    return intToEnum(wire.Scalar, value);
}

fn parseWireType(value: i64) !wire.WireType {
    return intToEnum(wire.WireType, @as(u3, @intCast(value)));
}

fn flushStream(stream: py.Object) !void {
    const flush_obj = try stream.getAttrOrNull("flush") orelse return;
    defer flush_obj.deinit();
    const result = try flush_obj.call(.{});
    result.deinit();
}

fn deinit(self: py.Object) void {
    const state = Writer.payloadFrom(self) catch return;
    state.deinit();
}
