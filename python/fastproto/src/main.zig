const std = @import("std");
const Io = std.Io;
const print = std.debug.print;
const heap = std.heap;
const Allocator = std.mem.Allocator;
const ArenaAllocator = heap.ArenaAllocator;
const builtin = @import("builtin");

const fastproto = @import("fastproto");

var debug_allocator: heap.DebugAllocator(.{}) = .init;

pub fn main() !void {
    const gpa, const is_debug = gpa: {
        break :gpa switch (builtin.mode) {
            .Debug, .ReleaseSafe => .{ debug_allocator.allocator(), true },
            .ReleaseFast, .ReleaseSmall => .{ heap.smp_allocator, false },
        };
    };
    defer if (is_debug) {
        _ = debug_allocator.deinit();
    };

    try simpleMessage(gpa);
    print("\n", .{});
    try nestedMessage(gpa);
    print("\n", .{});
    try packedRepeated(gpa);
    print("\n", .{});
    try knownLengthPacked(gpa);
}

/// Demonstrates basic message encoding/decoding.
fn simpleMessage(gpa: Allocator) !void {
    var arena: ArenaAllocator = .init(gpa);
    const allocator = arena.allocator();
    defer arena.deinit();

    print("=== Simple Message ===\n", .{});

    var io_writer: Io.Writer.Allocating = .init(allocator);
    defer io_writer.deinit();

    var writer: fastproto.Writer = .init(&io_writer.writer);

    try writer.writeTag(try .init(1, .len));
    try writer.writeLen("hello");
    try writer.writeTag(try .init(2, .varint));
    try writer.writeScalar(.i64, 42);
    try writer.writeTag(try .init(3, .varint));
    try writer.writeScalar(.bool, true);
    try writer.writeTag(try .init(4, .fixed64));
    try writer.writeScalar(.double, 3.14159);

    const data = io_writer.writer.buffered();
    print("Encoded {d} bytes\n", .{data.len});

    var io_reader: Io.Reader = .fixed(data);
    var reader: fastproto.Reader = .init(&io_reader);

    while (try reader.next()) |field| {
        switch (field.fieldNumber()) {
            1 => {
                var buf: [256]u8 = undefined;
                const s = try field.expect(.len).string(&buf);
                print("  field 1 (string): \"{s}\"\n", .{s});
            },
            2 => print("  field 2 (int64): {d}\n", .{field.expect(.varint).as(.i64)}),
            3 => print("  field 3 (bool): {}\n", .{field.expect(.varint).as(.bool)}),
            4 => print("  field 4 (double): {d:.5}\n", .{field.expect(.fixed64).as(.double)}),
            else => print("  unknown field: {d}\n", .{field.fieldNumber()}),
        }
    }
}

/// Demonstrates nested message encoding/decoding.
fn nestedMessage(gpa: Allocator) !void {
    var arena: ArenaAllocator = .init(gpa);
    const allocator = arena.allocator();
    defer arena.deinit();

    print("=== Nested Message ===\n", .{});

    // First, encode the inner message
    var inner_writer: Io.Writer.Allocating = .init(allocator);
    defer inner_writer.deinit();

    var inner: fastproto.Writer = .init(&inner_writer.writer);
    try inner.writeTag(try .init(1, .len));
    try inner.writeLen("nested content");
    try inner.writeTag(try .init(2, .varint));
    try inner.writeScalar(.u32, 999);

    const inner_data = inner_writer.writer.buffered();

    // Now encode the outer message with the inner message embedded
    var outer_writer: Io.Writer.Allocating = .init(allocator);
    defer outer_writer.deinit();

    var outer: fastproto.Writer = .init(&outer_writer.writer);
    try outer.writeTag(try .init(1, .len));
    try outer.writeLen("outer");
    try outer.writeTag(try .init(2, .len));
    try outer.writeLen(inner_data); // nested message
    try outer.writeTag(try .init(3, .varint));
    try outer.writeScalar(.i32, -123);

    const data = outer_writer.writer.buffered();
    print("Encoded {d} bytes (outer), {d} bytes (inner)\n", .{ data.len, inner_data.len });

    // Read it back
    var io_reader: Io.Reader = .fixed(data);
    var reader: fastproto.Reader = .init(&io_reader);

    while (try reader.next()) |field| {
        switch (field.fieldNumber()) {
            1 => {
                var buf: [256]u8 = undefined;
                const s = try field.expect(.len).string(&buf);
                print("  field 1 (string): \"{s}\"\n", .{s});
            },
            2 => {
                print("  field 2 (nested message):\n", .{});
                var nested = field.expect(.len).message();

                while (try nested.next()) |nf| {
                    switch (nf.fieldNumber()) {
                        1 => {
                            var buf: [256]u8 = undefined;
                            const s = try nf.expect(.len).string(&buf);
                            print("    field 1 (string): \"{s}\"\n", .{s});
                        },
                        2 => print("    field 2 (uint32): {d}\n", .{nf.expect(.varint).as(.u32)}),
                        else => print("    unknown field: {d}\n", .{nf.fieldNumber()}),
                    }
                }
            },
            3 => print("  field 3 (int32): {d}\n", .{field.expect(.varint).as(.i32)}),
            else => print("  unknown field: {d}\n", .{field.fieldNumber()}),
        }
    }
}

/// Demonstrates packed repeated field encoding/decoding.
fn packedRepeated(gpa: Allocator) !void {
    var arena: ArenaAllocator = .init(gpa);
    const allocator = arena.allocator();
    defer arena.deinit();

    print("=== Packed Repeated ===\n", .{});

    var io_writer: Io.Writer.Allocating = .init(allocator);
    defer io_writer.deinit();

    var writer: fastproto.Writer = .init(&io_writer.writer);

    // Reusable inner writer for packed fields
    var inner_buf: [64]u8 = undefined;
    var inner_io: Io.Writer = .fixed(&inner_buf);
    var inner: fastproto.Writer = .init(&inner_io);

    // Packed int64s
    for ([_]i64{ 1, 2, 3, 4, 5 }) |v| try inner.writeScalar(.i64, v);
    try writer.writeTag(try .init(1, .len));
    try writer.writeLen(inner_io.buffered());

    // Reset and reuse for packed doubles
    inner_io = .fixed(&inner_buf);
    for ([_]f64{ 1.1, 2.2, 3.3 }) |v| try inner.writeScalar(.double, v);
    try writer.writeTag(try .init(2, .len));
    try writer.writeLen(inner_io.buffered());

    // Reset and reuse for packed sint32s
    inner_io = .fixed(&inner_buf);
    for ([_]i32{ -1, -2, -3, 100, 200 }) |v| try inner.writeScalar(.sint32, v);
    try writer.writeTag(try .init(3, .len));
    try writer.writeLen(inner_io.buffered());

    const data = io_writer.writer.buffered();
    print("Encoded {d} bytes\n", .{data.len});

    var io_reader: Io.Reader = .fixed(data);
    var reader: fastproto.Reader = .init(&io_reader);

    while (try reader.next()) |field| {
        switch (field.fieldNumber()) {
            1 => {
                print("  field 1 (packed int64s): ", .{});
                var buf: [64]u8 = undefined;
                var iter = try field.expect(.len).repeated(i64, .varint, &buf);
                var first = true;
                while (try iter.next()) |val| {
                    if (!first) print(", ", .{});
                    print("{d}", .{val});
                    first = false;
                }
                print("\n", .{});
            },
            2 => {
                print("  field 2 (packed doubles): ", .{});
                var buf: [64]u8 = undefined;
                var iter = try field.expect(.len).repeated(f64, .fixed, &buf);
                var first = true;
                while (try iter.next()) |val| {
                    if (!first) print(", ", .{});
                    print("{d:.1}", .{val});
                    first = false;
                }
                print("\n", .{});
            },
            3 => {
                print("  field 3 (packed sint32s): ", .{});
                var buf: [64]u8 = undefined;
                var iter = try field.expect(.len).repeated(i32, .sint, &buf);
                var first = true;
                while (try iter.next()) |val| {
                    if (!first) print(", ", .{});
                    print("{d}", .{val});
                    first = false;
                }
                print("\n", .{});
            },
            else => print("  unknown field: {d}\n", .{field.fieldNumber()}),
        }
    }
}

/// Demonstrates packed fields with known length (no inner buffer needed).
fn knownLengthPacked(gpa: Allocator) !void {
    var arena: ArenaAllocator = .init(gpa);
    const allocator = arena.allocator();
    defer arena.deinit();

    print("=== Known-Length Packed (no inner buffer) ===\n", .{});

    var io_writer: Io.Writer.Allocating = .init(allocator);
    defer io_writer.deinit();

    var writer: fastproto.Writer = .init(&io_writer.writer);

    // For fixed-size types, we know the length upfront: count * @sizeOf(T)
    // No inner buffer needed - write length then values directly
    const doubles = [_]f64{ 1.1, 2.2, 3.3, 4.4 };
    const packed_len = doubles.len * @sizeOf(f64); // 4 * 8 = 32 bytes

    try writer.writeTag(try .init(1, .len));
    try writer.writeVarint(usize, packed_len);
    for (doubles) |v| try writer.writeScalar(.double, v);

    // Same for fixed32
    const fixed32s = [_]u32{ 100, 200, 300 };
    const fixed32_len = fixed32s.len * @sizeOf(u32); // 3 * 4 = 12 bytes

    try writer.writeTag(try .init(2, .len));
    try writer.writeVarint(usize, fixed32_len);
    for (fixed32s) |v| try writer.writeScalar(.fixed32, v);

    const data = io_writer.writer.buffered();
    print("Encoded {d} bytes\n", .{data.len});

    // Read it back
    var io_reader: Io.Reader = .fixed(data);
    var reader: fastproto.Reader = .init(&io_reader);

    while (try reader.next()) |field| {
        switch (field.fieldNumber()) {
            1 => {
                print("  field 1 (packed doubles): ", .{});
                var buf: [64]u8 = undefined;
                var iter = try field.expect(.len).repeated(f64, .fixed, &buf);
                var first = true;
                while (try iter.next()) |val| {
                    if (!first) print(", ", .{});
                    print("{d:.1}", .{val});
                    first = false;
                }
                print("\n", .{});
            },
            2 => {
                print("  field 2 (packed fixed32s): ", .{});
                var buf: [64]u8 = undefined;
                var iter = try field.expect(.len).repeated(u32, .fixed, &buf);
                var first = true;
                while (try iter.next()) |val| {
                    if (!first) print(", ", .{});
                    print("{d}", .{val});
                    first = false;
                }
                print("\n", .{});
            },
            else => print("  unknown field: {d}\n", .{field.fieldNumber()}),
        }
    }
}

test "simple roundtrip" {
    var write_buf: [256]u8 = undefined;
    var io_writer: Io.Writer = .fixed(&write_buf);
    var writer: fastproto.Writer = .init(&io_writer);

    try writer.writeTag(try .init(1, .varint));
    try writer.writeScalar(.u32, 150);

    const data = io_writer.buffered();

    var io_reader: Io.Reader = .fixed(data);
    var reader: fastproto.Reader = .init(&io_reader);
    const field = (try reader.next()).?;

    try std.testing.expectEqual(@as(u32, 1), field.fieldNumber());
    try std.testing.expectEqual(@as(u32, 150), field.expect(.varint).as(.u32));
}
