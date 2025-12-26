//! Protobuf message reader.
//!
//! Provides the Reader struct for parsing protobuf-encoded messages.

const std = @import("std");
const Io = std.Io;
const mem = std.mem;
const meta = std.meta;
const testing = std.testing;
const unicode = std.unicode;
const Allocator = mem.Allocator;

const wire = @import("wire.zig");
const Error = wire.Error;
const Tag = wire.Tag;
const Scalar = wire.Scalar;
const Encoding = wire.Encoding;
const decodeVarint = wire.decodeVarint;
const zigzagDecode = wire.zigzagDecode;
const readVarintFromIo = wire.readVarintFromIo;

/// A protobuf field, tagged by wire type.
pub const Field = union(enum) {
    varint: Varint,
    fixed64: Fixed64,
    len: Len,
    fixed32: Fixed32,

    const Kind = meta.Tag(@This());

    fn Payload(comptime kind: Kind) type {
        return meta.TagPayload(@This(), kind);
    }

    /// Get the field number regardless of wire type.
    pub fn fieldNumber(self: @This()) u32 {
        return switch (self) {
            inline else => |f| f.field_number,
        };
    }

    /// Get the payload as a specific scalar type.
    pub fn as(self: @This(), comptime scalar: Scalar) Scalar.Type(scalar) {
        return switch (self) {
            inline else => |f| f.as(scalar),
        };
    }

    /// Assert the wire type and return the payload.
    pub fn expect(self: @This(), comptime kind: Kind) Payload(kind) {
        return @field(self, @tagName(kind));
    }

    /// Varint field payload.
    pub const Varint = struct {
        field_number: u32,
        value: u64,

        /// Interpret as a specific scalar type.
        pub fn as(self: @This(), comptime scalar: Scalar) Scalar.Type(scalar) {
            return switch (scalar) {
                .i32 => @bitCast(@as(u32, @truncate(self.value))),
                .i64 => @bitCast(self.value),
                .u32 => @truncate(self.value),
                .u64 => self.value,
                .sint32 => zigzagDecode(u32, @truncate(self.value)),
                .sint64 => zigzagDecode(u64, self.value),
                .bool => self.value != 0,
                else => @compileError("Varint cannot be read as " ++ @tagName(scalar)),
            };
        }
    };

    /// Fixed64 field payload.
    pub const Fixed64 = struct {
        field_number: u32,
        value: u64,

        /// Interpret as a specific scalar type.
        pub fn as(self: @This(), comptime scalar: Scalar) Scalar.Type(scalar) {
            return switch (scalar) {
                .fixed64 => self.value,
                .sfixed64 => @bitCast(self.value),
                .double => @bitCast(self.value),
                else => @compileError("Fixed64 cannot be read as " ++ @tagName(scalar)),
            };
        }
    };

    /// Fixed32 field payload.
    pub const Fixed32 = struct {
        field_number: u32,
        value: u32,

        /// Interpret as a specific scalar type.
        pub fn as(self: @This(), comptime scalar: Scalar) Scalar.Type(scalar) {
            return switch (scalar) {
                .fixed32 => self.value,
                .sfixed32 => @bitCast(self.value),
                .float => @bitCast(self.value),
                else => @compileError("Fixed32 cannot be read as " ++ @tagName(scalar)),
            };
        }
    };

    /// Length-delimited field payload.
    pub const Len = struct {
        field_number: u32,
        length: usize,
        io: *Io.Reader,
        parent: ?*Reader = null,

        /// Read as UTF-8 string into the provided buffer.
        pub fn string(self: @This(), buf: []u8) ![]const u8 {
            const data = try self.bytes(buf);
            if (!unicode.utf8ValidateSlice(data)) return Error.InvalidUtf8;
            return data;
        }

        /// Read as UTF-8 string with allocation.
        pub fn stringAlloc(self: @This(), gpa: Allocator) ![]u8 {
            const data = try self.bytesAlloc(gpa);
            if (!unicode.utf8ValidateSlice(data)) {
                gpa.free(data);
                return Error.InvalidUtf8;
            }
            return data;
        }

        /// Read raw bytes into the provided buffer.
        pub fn bytes(self: @This(), buf: []u8) ![]u8 {
            if (buf.len < self.length) return Error.BufferTooSmall;
            const dest = buf[0..self.length];
            self.io.readSliceAll(dest) catch |err| switch (err) {
                error.EndOfStream => return Error.Truncated,
                error.ReadFailed => return Error.ReadFailed,
            };
            if (self.parent) |p| {
                if (p.remaining) |*rem| {
                    rem.* -= self.length;
                }
            }
            return dest;
        }

        /// Read raw bytes with allocation.
        pub fn bytesAlloc(self: @This(), gpa: Allocator) ![]u8 {
            const buf = try gpa.alloc(u8, self.length);
            errdefer gpa.free(buf);
            self.io.readSliceAll(buf) catch |err| switch (err) {
                error.EndOfStream => return Error.Truncated,
                error.ReadFailed => return Error.ReadFailed,
            };
            if (self.parent) |p| {
                if (p.remaining) |*rem| {
                    rem.* -= self.length;
                }
            }
            return buf;
        }

        /// Read as embedded message (streaming, no copy).
        /// Returns a Reader that reads directly from the parent stream.
        /// Decrements parent's remaining since the bytes will be consumed by the nested reader.
        pub fn message(self: @This()) Reader {
            if (self.parent) |p| {
                if (p.remaining) |*rem| {
                    rem.* -= self.length;
                }
            }
            return .{ .io = self.io, .remaining = self.length, .parent = self.parent };
        }

        /// Skip this field without reading the data.
        pub fn skip(self: @This()) !void {
            self.io.discardAll(self.length) catch |err| switch (err) {
                error.EndOfStream => return Error.Truncated,
                error.ReadFailed => return Error.ReadFailed,
            };
            if (self.parent) |p| {
                if (p.remaining) |*rem| {
                    rem.* -= self.length;
                }
            }
        }

        /// Iterator for packed repeated fields.
        pub fn PackedIterator(comptime T: type, comptime encoding: Encoding) type {
            return struct {
                data: []const u8,
                pos: usize,

                pub fn next(self: *@This()) !?T {
                    switch (encoding) {
                        .varint => {
                            if (self.pos >= self.data.len) return null;
                            const value, const bytes_read = try decodeVarint(u64, self.data[self.pos..]);
                            self.pos += bytes_read;
                            return switch (T) {
                                i32 => @bitCast(@as(u32, @truncate(value))),
                                i64 => @bitCast(value),
                                u32 => @truncate(value),
                                u64 => value,
                                bool => value != 0,
                                else => @compileError("varint encoding does not support " ++ @typeName(T)),
                            };
                        },
                        .sint => {
                            if (self.pos >= self.data.len) return null;
                            const value, const bytes_read = try decodeVarint(u64, self.data[self.pos..]);
                            self.pos += bytes_read;
                            return switch (T) {
                                i32 => zigzagDecode(u32, @truncate(value)),
                                i64 => zigzagDecode(u64, value),
                                else => @compileError("sint encoding only supports i32 and i64"),
                            };
                        },
                        .fixed => {
                            const size = @sizeOf(T);
                            if (self.pos + size > self.data.len) {
                                if (self.pos >= self.data.len) return null;
                                return Error.Truncated;
                            }
                            const raw = self.data[self.pos..][0..size];
                            self.pos += size;
                            return @bitCast(raw.*);
                        },
                    }
                }
            };
        }

        /// Result of repeatedAlloc - holds iterator and allocated data.
        pub fn PackedRepeated(comptime T: type, comptime encoding: Encoding) type {
            return struct {
                iter: PackedIterator(T, encoding),
                data: []u8,

                pub fn deinit(self: *@This(), gpa: Allocator) void {
                    gpa.free(self.data);
                    self.* = undefined;
                }
            };
        }

        /// Read packed repeated field into buffer, returns iterator.
        pub fn repeated(
            self: @This(),
            comptime T: type,
            comptime encoding: Encoding,
            buf: []u8,
        ) !PackedIterator(T, encoding) {
            const data = try self.bytes(buf);
            return .{ .data = data, .pos = 0 };
        }

        /// Read packed repeated field with allocation, returns iterator.
        /// Call deinit() on the result to free the allocated buffer.
        pub fn repeatedAlloc(
            self: @This(),
            comptime T: type,
            comptime encoding: Encoding,
            gpa: Allocator,
        ) !PackedRepeated(T, encoding) {
            const data = try self.bytesAlloc(gpa);
            return .{
                .iter = .{ .data = data, .pos = 0 },
                .data = data,
            };
        }
    };
};

/// Reads fields from a protobuf-encoded message.
/// When remaining is set, acts as a bounded reader for nested messages.
pub const Reader = struct {
    io: *Io.Reader,
    remaining: ?usize = null,
    parent: ?*Reader = null,

    pub fn init(reader: *Io.Reader) @This() {
        return .{ .io = reader };
    }

    /// Decrement remaining bytes (for bounded readers).
    fn advance(self: *@This(), n: usize) void {
        if (self.remaining) |*rem| rem.* -= n;
    }

    /// Read the next field, or return null if at end of message.
    pub fn next(self: *@This()) !?Field {
        // If bounded and exhausted, return null
        if (self.remaining) |rem| {
            if (rem == 0) return null;
        }

        // Try to read tag - EOF means end of message (unbounded) or error (bounded)
        const tag, const tag_len = readVarintFromIo(self.io, u64) catch |err| switch (err) {
            Error.Truncated => return if (self.remaining == null) null else err,
            else => |e| return e,
        };

        self.advance(tag_len);

        const parsed: Tag = try .parse(tag);

        return switch (parsed.wire_type) {
            .varint => {
                const value, const value_len = try readVarintFromIo(self.io, u64);
                self.advance(value_len);
                return .{ .varint = .{
                    .field_number = parsed.field_number,
                    .value = value,
                } };
            },
            .fixed64 => {
                const value = self.io.takeInt(u64, .little) catch |err| switch (err) {
                    error.EndOfStream => return Error.Truncated,
                    error.ReadFailed => return Error.ReadFailed,
                };
                self.advance(8);
                return .{ .fixed64 = .{
                    .field_number = parsed.field_number,
                    .value = value,
                } };
            },
            .len => {
                const len, const len_len = try readVarintFromIo(self.io, u64);
                self.advance(len_len);
                const length: usize = @intCast(len);
                return .{ .len = .{
                    .field_number = parsed.field_number,
                    .length = length,
                    .io = self.io,
                    .parent = self,
                } };
            },
            .fixed32 => {
                const value = self.io.takeInt(u32, .little) catch |err| switch (err) {
                    error.EndOfStream => return Error.Truncated,
                    error.ReadFailed => return Error.ReadFailed,
                };
                self.advance(4);
                return .{ .fixed32 = .{
                    .field_number = parsed.field_number,
                    .value = value,
                } };
            },
        };
    }
};

test Reader {
    // Basic varint
    {
        const data = [_]u8{
            0x08, // tag(1, VARINT)
            0x96, 0x01, // 150
        };

        var io_reader: Io.Reader = .fixed(&data);
        var r: Reader = .init(&io_reader);

        const field = (try r.next()).?;
        try testing.expectEqual(@as(u32, 1), field.fieldNumber());
        try testing.expectEqual(@as(u32, 150), field.expect(.varint).as(.u32));

        try testing.expect((try r.next()) == null);
    }

    // String field
    {
        const data = [_]u8{
            0x12, // tag(2, LEN)
            0x07, // length 7
            't',
            'e',
            's',
            't',
            'i',
            'n',
            'g',
        };

        var io_reader: Io.Reader = .fixed(&data);
        var r: Reader = .init(&io_reader);

        const field = (try r.next()).?;
        try testing.expectEqual(@as(u32, 2), field.fieldNumber());

        var buf: [32]u8 = undefined;
        const s = try field.expect(.len).string(&buf);
        try testing.expectEqualStrings("testing", s);
    }

    // Nested message
    {
        const data = [_]u8{
            0x08, 0x2a, // field 1: uint32 42
            0x12, 0x0a, // field 2: len 10
            0x0a, 0x06, 'n', 'e', 's', 't', 'e', 'd', // nested field 1: string "nested"
            0x10, 0x64, // nested field 2: uint32 100
        };

        var io_reader: Io.Reader = .fixed(&data);
        var r: Reader = .init(&io_reader);

        // Field 1: uint32
        {
            const field = (try r.next()).?;
            try testing.expectEqual(@as(u32, 1), field.fieldNumber());
            try testing.expectEqual(@as(u32, 42), field.expect(.varint).as(.u32));
        }

        // Field 2: nested message
        {
            const field = (try r.next()).?;
            try testing.expectEqual(@as(u32, 2), field.fieldNumber());

            var nested = field.expect(.len).message();

            // Nested field 1: string
            {
                const nf = (try nested.next()).?;
                var str_buf: [32]u8 = undefined;
                try testing.expectEqualStrings("nested", try nf.expect(.len).string(&str_buf));
            }

            // Nested field 2: uint32
            {
                const nf = (try nested.next()).?;
                try testing.expectEqual(@as(u32, 100), nf.expect(.varint).as(.u32));
            }

            try testing.expect((try nested.next()) == null);
        }

        try testing.expect((try r.next()) == null);
    }

    // Python-encoded bytes compatibility
    {
        const data = [_]u8{
            0x0a, 0x05, 'h',  'e',  'l', 'l', 'o',
            0x10, 0x2a, 0x18, 0x01,
        };

        var io_reader: Io.Reader = .fixed(&data);
        var r: Reader = .init(&io_reader);

        {
            const field = (try r.next()).?;
            var buf: [32]u8 = undefined;
            try testing.expectEqualStrings("hello", try field.expect(.len).string(&buf));
        }

        {
            const field = (try r.next()).?;
            try testing.expectEqual(@as(i64, 42), field.expect(.varint).as(.i64));
        }

        {
            const field = (try r.next()).?;
            try testing.expectEqual(true, field.expect(.varint).as(.bool));
        }

        try testing.expect((try r.next()) == null);
    }
}

test "bounded reader" {
    // Empty nested message
    {
        const data = [_]u8{
            0x0a, 0x00, // field 1: len 0 (empty message)
            0x10, 0x2a, // field 2: varint 42
        };

        var io_reader: Io.Reader = .fixed(&data);
        var r: Reader = .init(&io_reader);

        // Field 1: empty nested message
        {
            const field = (try r.next()).?;
            try testing.expectEqual(@as(u32, 1), field.fieldNumber());
            var nested = field.expect(.len).message();
            try testing.expectEqual(@as(usize, 0), nested.remaining.?);
            try testing.expect((try nested.next()) == null);
        }

        // Field 2: varint after empty message
        {
            const field = (try r.next()).?;
            try testing.expectEqual(@as(u32, 42), field.expect(.varint).as(.u32));
        }

        try testing.expect((try r.next()) == null);
    }

    // All wire types within nested message
    {
        const data = [_]u8{
            0x0a, 0x18, // field 1: len 24 (nested message)
            // nested contents:
            0x08, 0x96, 0x01, // field 1: varint 150
            0x15, 0x00, 0x00, 0x80, 0x3f, // field 2: fixed32 (float 1.0)
            0x19, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xf0, 0x3f, // field 3: fixed64 (double 1.0)
            0x22, 0x05, 'h', 'e', 'l', 'l', 'o', // field 4: string "hello"
        };

        var io_reader: Io.Reader = .fixed(&data);
        var r: Reader = .init(&io_reader);

        const field = (try r.next()).?;
        try testing.expectEqual(@as(u32, 1), field.fieldNumber());
        var nested = field.expect(.len).message();
        try testing.expectEqual(@as(usize, 24), nested.remaining.?);

        // Nested field 1: varint
        {
            const nf = (try nested.next()).?;
            try testing.expectEqual(@as(u32, 1), nf.fieldNumber());
            try testing.expectEqual(@as(u32, 150), nf.expect(.varint).as(.u32));
        }

        // Nested field 2: fixed32
        {
            const nf = (try nested.next()).?;
            try testing.expectEqual(@as(u32, 2), nf.fieldNumber());
            try testing.expectEqual(@as(f32, 1.0), nf.expect(.fixed32).as(.float));
        }

        // Nested field 3: fixed64
        {
            const nf = (try nested.next()).?;
            try testing.expectEqual(@as(u32, 3), nf.fieldNumber());
            try testing.expectEqual(@as(f64, 1.0), nf.expect(.fixed64).as(.double));
        }

        // Nested field 4: string
        {
            const nf = (try nested.next()).?;
            try testing.expectEqual(@as(u32, 4), nf.fieldNumber());
            var buf: [32]u8 = undefined;
            try testing.expectEqualStrings("hello", try nf.expect(.len).string(&buf));
        }

        try testing.expectEqual(@as(usize, 0), nested.remaining.?);
        try testing.expect((try nested.next()) == null);
        try testing.expect((try r.next()) == null);
    }

    // Skip within nested message decrements remaining
    {
        const data = [_]u8{
            0x0a, 0x0b, // field 1: len 11 (nested message)
            // nested contents:
            0x0a, 0x05, 'h', 'e', 'l', 'l', 'o', // field 1: string "hello" (7 bytes)
            0x10, 0x2a, // field 2: varint 42 (2 bytes)
            0x18, 0x01, // field 3: varint 1 (2 bytes)
        };

        var io_reader: Io.Reader = .fixed(&data);
        var r: Reader = .init(&io_reader);

        const field = (try r.next()).?;
        var nested = field.expect(.len).message();
        try testing.expectEqual(@as(usize, 11), nested.remaining.?);

        // Skip field 1
        {
            const nf = (try nested.next()).?;
            try testing.expectEqual(@as(u32, 1), nf.fieldNumber());
            try nf.expect(.len).skip();
        }

        // Remaining should be decremented by skipped content
        // Started with 11, consumed tag (1) + len (1), then skipped 5 = 4 remaining
        try testing.expectEqual(@as(usize, 4), nested.remaining.?);

        // Read remaining fields
        {
            const nf = (try nested.next()).?;
            try testing.expectEqual(@as(u32, 42), nf.expect(.varint).as(.u32));
        }
        {
            const nf = (try nested.next()).?;
            try testing.expectEqual(true, nf.expect(.varint).as(.bool));
        }

        try testing.expectEqual(@as(usize, 0), nested.remaining.?);
        try testing.expect((try nested.next()) == null);
    }

    // Multiple levels of nesting
    {
        const data = [_]u8{
            0x0a, 0x0a, // field 1: len 10 (outer nested)
            // outer nested (10 bytes):
            0x08, 0x01, // field 1: varint 1 (2 bytes)
            0x12, 0x06, // field 2: len 6 (inner nested)
            // inner nested (6 bytes):
            0x08, 0x02, // field 1: varint 2 (2 bytes)
            0x12, 0x02, 'h', 'i', // field 2: string "hi" (4 bytes)
        };

        var io_reader: Io.Reader = .fixed(&data);
        var r: Reader = .init(&io_reader);

        const field = (try r.next()).?;
        var outer = field.expect(.len).message();

        // Outer field 1
        {
            const of = (try outer.next()).?;
            try testing.expectEqual(@as(u32, 1), of.expect(.varint).as(.u32));
        }

        // Outer field 2: inner nested
        {
            const of = (try outer.next()).?;
            var inner = of.expect(.len).message();

            // Inner field 1
            {
                const inf = (try inner.next()).?;
                try testing.expectEqual(@as(u32, 2), inf.expect(.varint).as(.u32));
            }

            // Inner field 2
            {
                const inf = (try inner.next()).?;
                var buf: [8]u8 = undefined;
                try testing.expectEqualStrings("hi", try inf.expect(.len).string(&buf));
            }

            try testing.expect((try inner.next()) == null);
        }

        try testing.expect((try outer.next()) == null);
        try testing.expect((try r.next()) == null);
    }

    // Packed repeated within nested message
    {
        const data = [_]u8{
            0x0a, 0x07, // field 1: len 7 (nested message)
            // nested contents:
            0x0a, 0x05, // field 1: packed repeated, len 5
            0x01, 0x02, 0x03, 0x04, 0x05, // values 1,2,3,4,5
        };

        var io_reader: Io.Reader = .fixed(&data);
        var r: Reader = .init(&io_reader);

        const field = (try r.next()).?;
        var nested = field.expect(.len).message();

        const nf = (try nested.next()).?;
        try testing.expectEqual(@as(u32, 1), nf.fieldNumber());

        var buf: [16]u8 = undefined;
        var iter = try nf.expect(.len).repeated(u32, .varint, &buf);

        try testing.expectEqual(@as(u32, 1), (try iter.next()).?);
        try testing.expectEqual(@as(u32, 2), (try iter.next()).?);
        try testing.expectEqual(@as(u32, 3), (try iter.next()).?);
        try testing.expectEqual(@as(u32, 4), (try iter.next()).?);
        try testing.expectEqual(@as(u32, 5), (try iter.next()).?);
        try testing.expect((try iter.next()) == null);

        try testing.expect((try nested.next()) == null);
        try testing.expect((try r.next()) == null);
    }

    // Remaining tracking with multi-byte varints
    {
        const data = [_]u8{
            0x0a, 0x04, // field 1: len 4 (nested message)
            0x08, 0x80, 0x80, 0x01, // field 1: varint 16384 (3-byte encoding)
        };

        var io_reader: Io.Reader = .fixed(&data);
        var r: Reader = .init(&io_reader);

        const field = (try r.next()).?;
        var nested = field.expect(.len).message();
        try testing.expectEqual(@as(usize, 4), nested.remaining.?);

        const nf = (try nested.next()).?;
        try testing.expectEqual(@as(u32, 16384), nf.expect(.varint).as(.u32));

        try testing.expectEqual(@as(usize, 0), nested.remaining.?);
        try testing.expect((try nested.next()) == null);
    }
}
