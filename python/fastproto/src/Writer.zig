const std = @import("std");
const math = std.math;
const intToEnum = std.meta.intToEnum;

const fastproto = @import("fastproto");
const wire = fastproto.wire;
const py = @import("alloconda");

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

    const io_writer = try py.IoWriter.init(stream, &state.buffer);
    state.io = io_writer;
    state.writer = fastproto.Writer.init(&state.io.?.interface);
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
    const tag = wire.Tag.must(@intCast(field_number), wire_type);
    writer.writeTag(tag) catch |err| return raiseWriteError(err);
}

fn writeLen(writer: *fastproto.Writer, value: []const u8) !void {
    writer.writeLen(value) catch |err| return raiseWriteError(err);
}

fn writeVarint(comptime T: type, writer: *fastproto.Writer, value: T) !void {
    writer.writeVarint(T, value) catch |err| return raiseWriteError(err);
}

fn parseScalar(value: i64) !wire.Scalar {
    return intToEnum(wire.Scalar, value);
}

fn parseWireType(value: i64) !wire.WireType {
    return intToEnum(wire.WireType, @as(u3, @intCast(value)));
}

fn raiseWriteError(err: anyerror) py.PyError {
    if (err == error.WriteFailed) {
        py.reraise() catch {};
        return py.raise(.RuntimeError, "write failed");
    }
    if (err == error.OutOfMemory) return error.OutOfMemory;
    return py.raise(.RuntimeError, "write failed");
}

fn writeScalarValue(writer: *fastproto.Writer, scalar: wire.Scalar, value: py.Object) !void {
    switch (scalar) {
        .i32 => {
            const raw = try value.as(i64);
            const cast = math.cast(i32, raw) orelse return py.raise(.OverflowError, "integer out of range");
            writer.writeScalar(.i32, cast) catch |err| return raiseWriteError(err);
        },
        .i64 => {
            const raw = try value.as(i64);
            writer.writeScalar(.i64, raw) catch |err| return raiseWriteError(err);
        },
        .u32 => {
            const masked = try py.Long.unsignedMask(value);
            const cast: u32 = @truncate(masked);
            writer.writeScalar(.u32, cast) catch |err| return raiseWriteError(err);
        },
        .u64 => {
            const masked = try py.Long.unsignedMask(value);
            writer.writeScalar(.u64, masked) catch |err| return raiseWriteError(err);
        },
        .sint32 => {
            const raw = try value.as(i64);
            const cast = math.cast(i32, raw) orelse return py.raise(.OverflowError, "integer out of range");
            writer.writeScalar(.sint32, cast) catch |err| return raiseWriteError(err);
        },
        .sint64 => {
            const raw = try value.as(i64);
            writer.writeScalar(.sint64, raw) catch |err| return raiseWriteError(err);
        },
        .bool => {
            const raw = try value.as(bool);
            writer.writeScalar(.bool, raw) catch |err| return raiseWriteError(err);
        },
        .fixed64 => {
            const masked = try py.Long.unsignedMask(value);
            writer.writeScalar(.fixed64, masked) catch |err| return raiseWriteError(err);
        },
        .sfixed64 => {
            const raw = try value.as(i64);
            writer.writeScalar(.sfixed64, raw) catch |err| return raiseWriteError(err);
        },
        .double => {
            const raw = try value.as(f64);
            writer.writeScalar(.double, raw) catch |err| return raiseWriteError(err);
        },
        .fixed32 => {
            const masked = try py.Long.unsignedMask(value);
            const cast: u32 = @truncate(masked);
            writer.writeScalar(.fixed32, cast) catch |err| return raiseWriteError(err);
        },
        .sfixed32 => {
            const raw = try value.as(i64);
            const cast = math.cast(i32, raw) orelse return py.raise(.OverflowError, "integer out of range");
            writer.writeScalar(.sfixed32, cast) catch |err| return raiseWriteError(err);
        },
        .float => {
            const raw = try value.as(f32);
            writer.writeScalar(.float, raw) catch |err| return raiseWriteError(err);
        },
    }
}

fn flushStream(stream: py.Object) !void {
    const flush_obj = try stream.getAttrOrNull("flush") orelse return;
    defer flush_obj.deinit();
    const result = try flush_obj.call0();
    result.deinit();
}

fn deinit(self: py.Object) void {
    const state = Writer.payloadFrom(self) catch return;
    state.deinit();
}
