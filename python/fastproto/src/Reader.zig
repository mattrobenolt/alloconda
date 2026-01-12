const fastproto = @import("fastproto");
const py = @import("alloconda");

const Field = @import("Field.zig");
const wrap = @import("errors.zig").wrap;

const default_buffer_size = 8192;

pub const Reader = py.class("Reader", "Reads fields from a protobuf-encoded message.", .{
    .__init__ = py.method(
        readerInit,
        .{ .doc = "Initialize reader from a binary IO stream.", .args = &.{"stream"} },
    ),
    .__iter__ = py.method(readerIter, .{ .doc = "Return iterator." }),
    .__next__ = py.method(readerNext, .{ .doc = "Return next field." }),
    .next = py.method(readerNextField, .{ .doc = "Read the next field, or None if at end." }),
    .remaining = py.method(readerRemaining, .{ .doc = "Return remaining bytes for bounded readers." }),
    .__del__ = py.method(deinit, .{ .doc = "Release held stream resources." }),
}).withPayload(State);

const State = struct {
    io: ?py.IoReader = null,
    reader: fastproto.Reader = undefined,
    owner: ?py.Object = null,
    buffer: [default_buffer_size]u8 = undefined,

    fn deinit(self: *@This()) void {
        if (self.io) |*io| io.deinit();
        if (self.owner) |obj| obj.deinit();
        self.* = undefined;
    }
};

pub fn newFromReader(reader: fastproto.Reader, owner: py.Object) !py.Object {
    return Reader.newWithPayload(.{
        .reader = reader,
        .owner = owner.incref(),
    });
}

fn readerInit(self: py.Object, stream: py.Object) !void {
    const state = try Reader.payloadFrom(self);
    state.deinit();

    state.io = try .init(stream, &state.buffer);
    state.reader = .init(&state.io.?.interface);
    state.owner = null;
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
    const field = try wrap(state.reader.next());
    if (field) |value| {
        const obj = try Field.init(value, self);
        return obj;
    }
    return null;
}

fn readerRemaining(self: py.Object) !?usize {
    const state = try Reader.payloadFrom(self);
    return state.reader.remaining;
}

fn deinit(self: py.Object) void {
    const state = Reader.payloadFrom(self) catch return;
    state.deinit();
}
