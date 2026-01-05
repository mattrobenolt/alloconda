const std = @import("std");
const fmt = std.fmt;

const fastproto = @import("fastproto");
const wire = fastproto.wire;
const py = @import("alloconda");

const Reader = @import("Reader.zig");

pub const Field = py.class("Field", "Represents a single field from a protobuf message.", .{
    .expect = py.method(
        fieldExpect,
        .{ .doc = "Assert the wire type and return this field.", .args = &.{"wire_type"} },
    ),
    .as_scalar = py.method(
        fieldAsScalar,
        .{ .doc = "Read this field as the requested scalar type.", .args = &.{"scalar"} },
    ),
    .bytes = py.method(fieldBytes, .{ .doc = "Read as raw bytes." }),
    .string = py.method(fieldString, .{ .doc = "Read as UTF-8 string." }),
    .message = py.method(fieldMessage, .{ .doc = "Read as embedded message, returning a new Reader." }),
    .skip = py.method(fieldSkip, .{ .doc = "Skip this length-delimited field." }),
    .repeated = py.method(
        fieldRepeated,
        .{ .doc = "Read packed repeated values for this field.", .args = &.{"scalar"} },
    ),
    .__del__ = py.method(deinit, .{ .doc = "Release held field resources." }),
}).withPayload(State);

const State = struct {
    field: fastproto.Field,
    owner: ?py.Object = null,

    fn require(self: *const @This(), expected: wire.WireType) !void {
        const actual = fieldWireType(self.field);
        if (actual == expected) return;
        var buf: [96]u8 = undefined;
        const msg = fmt.bufPrintZ(
            &buf,
            "wire type mismatch: expected {f}, got {f}",
            .{ expected, actual },
        ) catch "wire type mismatch";
        return py.raise(.ValueError, msg);
    }

    fn deinit(self: *@This()) void {
        if (self.owner) |obj| {
            obj.deinit();
            self.owner = null;
        }
        self.* = undefined;
    }
};

pub fn init(field: fastproto.Field, owner: py.Object) !py.Object {
    var obj = try Field.new();
    errdefer obj.deinit();
    const state = try Field.payloadFrom(obj);
    state.* = .{ .field = field, .owner = owner.incref() };

    const number = field.fieldNumber();
    const wire_type = fieldWireType(field);
    try obj.setAttr("number", u32, number);
    try obj.setAttr("wire_type", u8, @intFromEnum(wire_type));
    return obj;
}

fn fieldWireType(field: fastproto.Field) wire.WireType {
    return switch (field) {
        .varint => .varint,
        .fixed64 => .fixed64,
        .len => .len,
        .fixed32 => .fixed32,
    };
}

fn parseWireType(value: i64) !wire.WireType {
    return std.meta.intToEnum(wire.WireType, @as(u3, @intCast(value)));
}

fn parseScalar(value: i64) !wire.Scalar {
    return std.meta.intToEnum(wire.Scalar, value);
}

fn scalarWireType(scalar: wire.Scalar) wire.WireType {
    return switch (scalar) {
        .i32, .i64, .u32, .u64, .sint32, .sint64, .bool => .varint,
        .fixed64, .sfixed64, .double => .fixed64,
        .fixed32, .sfixed32, .float => .fixed32,
    };
}

fn fieldExpect(self: py.Object, wire_type_raw: i64) !py.Object {
    const state = try Field.payloadFrom(self);
    const expected = parseWireType(wire_type_raw) catch {
        return py.raise(.ValueError, "invalid wire type");
    };
    try state.require(expected);
    return self.incref();
}

fn fieldAsScalar(self: py.Object, scalar_raw: i64) !py.Object {
    const state = try Field.payloadFrom(self);
    const scalar = parseScalar(scalar_raw) catch {
        return py.raise(.ValueError, "invalid scalar type");
    };
    return switch (scalar) {
        inline .i32, .i64, .u32, .u64, .sint32, .sint64, .bool => |s| blk: {
            try state.require(.varint);
            const value = switch (state.field) {
                .varint => |f| s.fromVarint(f.value),
                else => unreachable,
            };
            break :blk py.Object.from(@TypeOf(value), value);
        },
        inline .fixed32, .sfixed32, .float => |s| blk: {
            try state.require(.fixed32);
            const value = switch (state.field) {
                .fixed32 => |f| s.fromFixedBits(f.value),
                else => unreachable,
            };
            break :blk py.Object.from(@TypeOf(value), value);
        },
        inline .fixed64, .sfixed64, .double => |s| blk: {
            try state.require(.fixed64);
            const value = switch (state.field) {
                .fixed64 => |f| s.fromFixedBits(f.value),
                else => unreachable,
            };
            break :blk py.Object.from(@TypeOf(value), value);
        },
    };
}

fn fieldLen(state: *const State) !fastproto.reader.Field.Len {
    try state.require(.len);
    return switch (state.field) {
        .len => |len| len,
        else => unreachable,
    };
}

fn fieldString(self: py.Object) !py.Object {
    const state = try Field.payloadFrom(self);
    const len_field = try fieldLen(state);
    const data = len_field.bytesAlloc(py.allocator) catch |err| {
        return raiseWireError(err);
    };
    defer py.allocator.free(data);
    return py.Object.from([]const u8, data) catch |err| switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.PythonError => {
            if (py.ffi.PyErr.exceptionMatches(.MemoryError)) return error.OutOfMemory;
            if (py.ffi.PyErr.exceptionMatches(.ValueError)) {
                return py.raise(.ValueError, "invalid utf-8");
            }
            return err;
        },
    };
}

fn fieldBytes(self: py.Object) !py.Bytes {
    const state = try Field.payloadFrom(self);
    const len_field = try fieldLen(state);
    const data = len_field.bytesAlloc(py.allocator) catch |err| {
        return raiseWireError(err);
    };
    defer py.allocator.free(data);
    return py.Bytes.fromSlice(data);
}

fn fieldMessage(self: py.Object) !py.Object {
    const state = try Field.payloadFrom(self);
    const len_field = try fieldLen(state);
    const owner = state.owner orelse return py.raise(.RuntimeError, "field missing owner");
    const nested = len_field.message();
    return Reader.newFromReader(nested, owner);
}

fn fieldSkip(self: py.Object) !void {
    const state = try Field.payloadFrom(self);
    const len_field = try fieldLen(state);
    len_field.skip() catch |err| {
        return raiseWireError(err);
    };
}

fn fieldRepeated(self: py.Object, scalar_raw: i64) !py.List {
    const state = try Field.payloadFrom(self);
    const scalar = parseScalar(scalar_raw) catch {
        return py.raise(.ValueError, "invalid scalar type");
    };
    const len_field = try fieldLen(state);
    const data = len_field.bytesAlloc(py.allocator) catch |err| {
        return raiseWireError(err);
    };
    defer py.allocator.free(data);
    return switch (scalar) {
        inline else => |s| decodePackedSlice(data, s),
    };
}

fn decodePackedSlice(slice: []const u8, comptime scalar: wire.Scalar) !py.List {
    switch (comptime scalar.wireType()) {
        .varint => {
            var list: py.List = try .init(0);
            errdefer list.deinit();
            var offset: usize = 0;
            while (offset < slice.len) {
                const value, const bytes_read = wire.decodeVarint(u64, slice[offset..]) catch |err| {
                    return raiseWireError(err);
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

fn raiseWireError(err: anyerror) py.PyError {
    return py.raiseError(err, &.{
        .{ .err = wire.Error.Truncated, .kind = .ValueError, .msg = "truncated field" },
        .{ .err = wire.Error.VarintTooLong, .kind = .ValueError, .msg = "varint too long" },
        .{ .err = wire.Error.InvalidWireType, .kind = .ValueError, .msg = "invalid wire type" },
        .{ .err = wire.Error.InvalidFieldNumber, .kind = .ValueError, .msg = "invalid field number" },
        .{ .err = wire.Error.FieldNumberTooLarge, .kind = .ValueError, .msg = "field number too large" },
        .{ .err = wire.Error.WireTypeMismatch, .kind = .ValueError, .msg = "wire type mismatch" },
        .{ .err = wire.Error.BufferTooSmall, .kind = .ValueError, .msg = "buffer too small" },
        .{ .err = wire.Error.InvalidUtf8, .kind = .ValueError, .msg = "invalid utf-8" },
        .{ .err = wire.Error.ReadFailed, .kind = .RuntimeError, .msg = "read failed" },
    });
}

fn deinit(self: py.Object) void {
    const state = Field.payloadFrom(self) catch return;
    state.deinit();
}
