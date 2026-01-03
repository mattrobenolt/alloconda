const py = @import("alloconda");
const wire = @import("fastproto").wire;

const ByteView = @import("ByteView.zig");
const Field = @import("Field.zig");

pub const Reader = py.class("Reader", "Reads fields from a protobuf-encoded message.", .{
    .__init__ = py.method(readerInit, .{ .doc = "Initialize reader from bytes-like data.", .args = &.{"data"} }),
    .__iter__ = py.method(readerIter, .{ .doc = "Return iterator." }),
    .__next__ = py.method(readerNext, .{ .doc = "Return next field." }),
    .next_field = py.method(readerNextField, .{ .doc = "Read the next field, or None if at end." }),
    .skip = py.method(readerSkip, .{ .doc = "Skip the next field, returns True if skipped." }),
    .remaining = py.method(readerRemaining, .{ .doc = "Return the number of bytes remaining." }),
    .__del__ = py.method(deinit, .{ .doc = "Release held buffer." }),
}).withPayload(State);

const State = struct {
    view: ByteView = .empty,
    pos: usize = 0,

    const empty: @This() = .{};

    fn slice(self: *const @This()) ![]const u8 {
        return self.view.slice();
    }

    fn deinit(self: *@This()) void {
        self.view.deinit();
        self.* = undefined;
    }
};

pub fn new(data: py.Object, start: usize, len: usize) !py.Object {
    var reader = try Reader.new();
    errdefer reader.deinit();
    const state = try Reader.payloadFrom(reader);
    state.* = .{
        .view = .init(data, start, len),
        .pos = 0,
    };
    return reader;
}

fn readerInit(self: py.Object, data: py.Object) !void {
    const state = try Reader.payloadFrom(self);
    state.* = .empty;
    const bytes: py.Bytes = try .fromObjectOwned(data);
    state.view.data = bytes.obj;
    state.view.len = try bytes.len();
}

fn readerIter(self: py.Object) !py.Object {
    return self.incref();
}

fn readerNext(self: py.Object) !py.Object {
    if (try readerNextField(self)) |field| return field;
    return py.raise(.StopIteration, "");
}

fn readerNextField(self: py.Object) !?py.Object {
    const state = try Reader.payloadFrom(self);
    if (state.pos >= state.view.len) return null;

    const slice = try state.slice();
    var pos = state.pos;

    const tag_value, const tag_next = try decodeVarintAt(slice, pos);
    pos = tag_next;

    const parsed = wire.Tag.parse(tag_value) catch |err| {
        return py.raise(.ValueError, switch (err) {
            wire.Error.InvalidWireType => "invalid wire type",
            wire.Error.InvalidFieldNumber => "invalid field number",
            else => "invalid tag",
        });
    };

    const field: py.Object = try switch (parsed.wire_type) {
        .fixed32 => blk: {
            const size = 4;
            if (slice.len - pos < size) return py.raise(.ValueError, "truncated fixed32");
            const raw = slice[pos .. pos + size];
            const raw_ptr: *const [size]u8 = @ptrCast(raw.ptr);
            const value = wire.readInt(u32, raw_ptr);
            pos += size;
            break :blk Field.init(parsed.field_number, parsed.wire_type, value, null, 0, 0);
        },
        .fixed64 => blk: {
            const size = 8;
            if (slice.len - pos < size) return py.raise(.ValueError, "truncated fixed64");
            const raw = slice[pos .. pos + size];
            const raw_ptr: *const [size]u8 = @ptrCast(raw.ptr);
            const value = wire.readInt(u64, raw_ptr);
            pos += size;
            break :blk Field.init(parsed.field_number, parsed.wire_type, value, null, 0, 0);
        },
        .varint => blk: {
            const value, const next = try decodeVarintAt(slice, pos);
            pos = next;
            break :blk Field.init(parsed.field_number, parsed.wire_type, value, null, 0, 0);
        },
        .len => blk: {
            const length_value, const next = try decodeVarintAt(slice, pos);
            pos = next;
            const remaining = slice.len - pos;
            if (length_value > remaining) return py.raise(.ValueError, "truncated length-delimited field");
            const length: usize = @intCast(length_value);
            const data_start = state.view.start + pos;
            pos += length;
            break :blk Field.init(
                parsed.field_number,
                parsed.wire_type,
                0,
                state.view.data,
                data_start,
                length,
            );
        },
    };

    state.pos = pos;
    return field;
}

fn readerSkip(self: py.Object) !bool {
    const state = try Reader.payloadFrom(self);
    if (state.pos >= state.view.len) return false;
    const slice = try state.slice();
    var pos = state.pos;

    const tag_value, const tag_next = try decodeVarintAt(slice, pos);
    pos = tag_next;

    const parsed = wire.Tag.parse(tag_value) catch |err| {
        return py.raise(.ValueError, switch (err) {
            wire.Error.InvalidWireType => "invalid wire type",
            wire.Error.InvalidFieldNumber => "invalid field number",
            else => "invalid tag",
        });
    };

    switch (parsed.wire_type) {
        .varint => {
            _, const next = try decodeVarintAt(slice, pos);
            pos = next;
        },
        .len => {
            const value, const next = try decodeVarintAt(slice, pos);
            const remaining = slice.len - pos;
            if (value > remaining) return py.raise(.ValueError, "truncated length-delimited field");
            pos = next + value;
        },
        .fixed32 => {
            const size = 4;
            if (slice.len - pos < size) return py.raise(.ValueError, "truncated fixed32");
            pos += size;
        },
        .fixed64 => {
            const size = 8;
            if (slice.len - pos < size) return py.raise(.ValueError, "truncated fixed64");
            pos += size;
        },
    }

    state.pos = pos;
    return true;
}

fn readerRemaining(self: py.Object) !usize {
    const state = try Reader.payloadFrom(self);
    return state.view.len - state.pos;
}

fn deinit(self: py.Object) void {
    const state = Reader.payloadFrom(self) catch return;
    state.deinit();
}

fn decodeVarintAt(slice: []const u8, pos: usize) !struct { u64, usize } {
    const value, const bytes_read = wire.decodeVarint(u64, slice[pos..]) catch |err| {
        return py.raise(.ValueError, switch (err) {
            wire.Error.Truncated => "truncated varint",
            wire.Error.VarintTooLong => "varint too long",
            else => "decode error",
        });
    };
    return .{ value, pos + bytes_read };
}
