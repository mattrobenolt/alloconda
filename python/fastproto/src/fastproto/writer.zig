//! Protobuf message writer.
//!
//! Provides the Writer struct for building protobuf-encoded messages.
//!
//! The API consists of four composable primitives:
//! - `writeTag(Tag)` - write a field tag
//! - `writeScalar(Scalar, value)` - write a scalar value (varint/fixed)
//! - `writeLen([]const u8)` - write length-delimited bytes
//! - `writeVarint(T, value)` - write a raw varint (for known-length scenarios)
//!
//! For nested messages and packed repeated fields, either:
//! 1. Create an inner Writer with its own buffer, write into it, then `writeLen()` the result.
//! 2. If length is known upfront, use `writeVarint(len)` then write content directly.

const std = @import("std");
const Io = std.Io;
const mem = std.mem;
const testing = std.testing;

const wire = @import("wire.zig");
const Tag = wire.Tag;
const Scalar = wire.Scalar;
const max_varint_len = wire.max_varint_len;
const encodeVarint = wire.encodeVarint;
const zigzagEncode = wire.zigzagEncode;

/// Builds a protobuf-encoded message by writing to an Io.Writer.
pub const Writer = struct {
    io: *Io.Writer,

    pub fn init(writer: *Io.Writer) @This() {
        return .{ .io = writer };
    }

    /// Write a raw varint. Useful when length is known upfront.
    pub fn writeVarint(self: *@This(), comptime T: type, value: T) !void {
        var buf: [max_varint_len]u8 = undefined;
        const data = encodeVarint(T, value, &buf) catch unreachable;
        try self.io.writeAll(data);
    }

    /// Write a tag (field number + wire type).
    pub fn writeTag(self: *@This(), tag: Tag) !void {
        try self.writeVarint(u32, tag.encode());
    }

    /// Write a scalar value (no tag).
    pub fn writeScalar(self: *@This(), comptime scalar: Scalar, value: Scalar.Type(scalar)) !void {
        try switch (scalar) {
            // Varint types
            .i32 => self.writeVarint(i64, @as(i64, value)),
            .i64 => self.writeVarint(i64, value),
            .u32 => self.writeVarint(u32, value),
            .u64 => self.writeVarint(u64, value),
            .sint32 => self.writeVarint(u32, zigzagEncode(i32, value)),
            .sint64 => self.writeVarint(u64, zigzagEncode(i64, value)),
            .bool => self.writeVarint(u8, @intFromBool(value)),
            // Fixed64 types
            .fixed64 => self.io.writeInt(u64, value, .little),
            .sfixed64 => self.io.writeInt(u64, @bitCast(value), .little),
            .double => self.io.writeInt(u64, @bitCast(value), .little),
            // Fixed32 types
            .fixed32 => self.io.writeInt(u32, value, .little),
            .sfixed32 => self.io.writeInt(u32, @bitCast(value), .little),
            .float => self.io.writeInt(u32, @bitCast(value), .little),
        };
    }

    /// Write length-delimited bytes (no tag).
    pub fn writeLen(self: *@This(), value: []const u8) !void {
        try self.writeVarint(usize, value.len);
        try self.io.writeAll(value);
    }

    test writeScalar {
        var write_buf: [64]u8 = undefined;
        var io_writer: Io.Writer = .fixed(&write_buf);
        var w: Writer = .init(&io_writer);

        // string field (tag + len + data)
        try w.writeTag(try .init(1, .len));
        try w.writeLen("hello");

        // int64 field
        try w.writeTag(try .init(2, .varint));
        try w.writeScalar(.i64, 42);

        // bool field
        try w.writeTag(try .init(3, .varint));
        try w.writeScalar(.bool, true);

        // double field
        try w.writeTag(try .init(4, .fixed64));
        try w.writeScalar(.double, 3.14);

        const expected = [_]u8{
            0x0a, 0x05, 'h', 'e', 'l', 'l', 'o', // field 1: string "hello"
            0x10, 0x2a, // field 2: int64 42
            0x18, 0x01, // field 3: bool true
            0x21, 0x1f, 0x85, 0xeb, 0x51, 0xb8, 0x1e, 0x09, 0x40, // field 4: double 3.14
        };

        try testing.expectEqualSlices(u8, &expected, io_writer.buffered());
    }

    test "packed varint" {
        var write_buf: [64]u8 = undefined;
        var io_writer: Io.Writer = .fixed(&write_buf);
        var w: Writer = .init(&io_writer);

        // Build packed data in inner writer
        var inner_buf: [32]u8 = undefined;
        var inner_io: Io.Writer = .fixed(&inner_buf);
        var inner: Writer = .init(&inner_io);

        try inner.writeScalar(.i64, 1);
        try inner.writeScalar(.i64, 2);
        try inner.writeScalar(.i64, 3);

        // Write to main writer
        try w.writeTag(try .init(1, .len));
        try w.writeLen(inner_io.buffered());

        const written = io_writer.buffered();
        try testing.expectEqual(@as(u8, 0x0a), written[0]); // tag(1, LEN)
        try testing.expectEqual(@as(u8, 0x03), written[1]); // length 3
        try testing.expectEqual(@as(u8, 0x01), written[2]); // 1
        try testing.expectEqual(@as(u8, 0x02), written[3]); // 2
        try testing.expectEqual(@as(u8, 0x03), written[4]); // 3
    }

    test "packed fixed" {
        var write_buf: [64]u8 = undefined;
        var io_writer: Io.Writer = .fixed(&write_buf);
        var w: Writer = .init(&io_writer);

        // Build packed data in inner writer
        var inner_buf: [32]u8 = undefined;
        var inner_io: Io.Writer = .fixed(&inner_buf);
        var inner: Writer = .init(&inner_io);

        try inner.writeScalar(.fixed32, 100);
        try inner.writeScalar(.fixed32, 200);

        // Write to main writer
        try w.writeTag(try .init(1, .len));
        try w.writeLen(inner_io.buffered());

        const written = io_writer.buffered();
        try testing.expectEqual(@as(u8, 0x0a), written[0]); // tag(1, LEN)
        try testing.expectEqual(@as(u8, 0x08), written[1]); // length 8
        try testing.expectEqual(@as(u32, 100), mem.readInt(u32, written[2..6], .little));
        try testing.expectEqual(@as(u32, 200), mem.readInt(u32, written[6..10], .little));
    }

    test "packed sint" {
        var write_buf: [64]u8 = undefined;
        var io_writer: Io.Writer = .fixed(&write_buf);
        var w: Writer = .init(&io_writer);

        // Build packed data in inner writer
        var inner_buf: [32]u8 = undefined;
        var inner_io: Io.Writer = .fixed(&inner_buf);
        var inner: Writer = .init(&inner_io);

        try inner.writeScalar(.sint32, -1);
        try inner.writeScalar(.sint32, 0);
        try inner.writeScalar(.sint32, 1);

        // Write to main writer
        try w.writeTag(try .init(1, .len));
        try w.writeLen(inner_io.buffered());

        const written = io_writer.buffered();
        try testing.expectEqual(@as(u8, 0x0a), written[0]); // tag(1, LEN)
        try testing.expectEqual(@as(u8, 0x03), written[1]); // length 3
        try testing.expectEqual(@as(u8, 0x01), written[2]); // zigzag(-1) = 1
        try testing.expectEqual(@as(u8, 0x00), written[3]); // zigzag(0) = 0
        try testing.expectEqual(@as(u8, 0x02), written[4]); // zigzag(1) = 2
    }

    test writeLen {
        var write_buf: [64]u8 = undefined;
        var io_writer: Io.Writer = .fixed(&write_buf);
        var w: Writer = .init(&io_writer);

        // Build nested message in inner writer
        var nested_buf: [32]u8 = undefined;
        var nested_io: Io.Writer = .fixed(&nested_buf);
        var nested: Writer = .init(&nested_io);

        try nested.writeTag(try .init(1, .varint));
        try nested.writeScalar(.i32, 123);

        // Write to main writer
        try w.writeTag(try .init(1, .len));
        try w.writeLen(nested_io.buffered());

        const written = io_writer.buffered();
        try testing.expectEqual(@as(u8, 0x0a), written[0]); // tag(1, LEN)
        try testing.expectEqual(@as(u8, 0x02), written[1]); // length 2
        try testing.expectEqual(@as(u8, 0x08), written[2]); // nested tag(1, VARINT)
        try testing.expectEqual(@as(u8, 0x7b), written[3]); // 123
    }
};
