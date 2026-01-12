const std = @import("std");
const Allocator = std.mem.Allocator;
const Zoir = std.zig.Zoir;
const Ast = std.zig.Ast;
const ZonGen = std.zig.ZonGen;
const Writer = std.Io.Writer;
const math = std.math;

const py = @import("alloconda");
const PyObject = py.PyObject;

const ZonDocument = py.class("ZonDocument", "Small helper for stored ZON text/value.", .{
    .set_text = py.method(docSetText, .{ .args = &.{"text"} }),
    .get_text = py.method(docGetText, .{}),
    .loads = py.method(docLoads, .{}),
    .set_value = py.method(docSetValue, .{ .args = &.{"value"} }),
    .dumps = py.method(docDumps, .{}),
});

pub const MODULE = py.module("ZON codec implemented in Zig.", .{
    .loads = py.function(loads, .{
        .doc = "Parse ZON text into Python objects.",
        .args = &.{"data"},
    }),
    .load = py.function(load, .{
        .doc = "Parse ZON from a file-like object.",
        .args = &.{"fp"},
    }),
    .dumps = py.function(dumps, .{
        .doc = "Serialize a Python value to ZON text.",
        .args = &.{"value"},
    }),
    .dump = py.function(dump, .{
        .doc = "Serialize a Python value to a file-like object.",
        .args = &.{ "value", "fp" },
    }),
    .to_python = py.function(to_python, .{
        .doc = "Alias for loads().",
        .args = &.{"data"},
    }),
    .from_python = py.function(from_python, .{
        .doc = "Alias for dumps().",
        .args = &.{"value"},
    }),
}).withTypes(.{ .ZonDocument = ZonDocument });

fn loads(input: py.Object) !py.Object {
    var arena = py.arenaAllocator();
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = try coerceSource(allocator, input);
    return parseZon(allocator, source);
}

fn to_python(input: py.Object) !py.Object {
    return loads(input);
}

fn load(fp: py.Object) !py.Object {
    const data = try fp.callMethod("read", .{});
    defer data.deinit();
    return loads(data);
}

fn dumps(value: py.Object) !py.Object {
    var arena = py.arenaAllocator();
    defer arena.deinit();
    const allocator = arena.allocator();
    const text = try renderZon(allocator, value.ptr);
    return .from(text);
}

fn from_python(value: py.Object) !py.Object {
    return dumps(value);
}

fn dump(value: py.Object, fp: py.Object) !void {
    var arena = py.arenaAllocator();
    defer arena.deinit();
    const allocator = arena.allocator();
    const text = try renderZon(allocator, value.ptr);
    const result = try fp.callMethod("write", .{text});
    result.deinit();
}

fn docSetText(self: py.Object, text: py.Object) !void {
    if (!text.isUnicode() and !text.isBytes()) {
        return py.raise(.TypeError, "text must be str or bytes");
    }
    try self.setAttr("text", text);
}

fn docGetText(self: py.Object) !py.Object {
    return self.getAttr("text");
}

fn docLoads(self: py.Object) !py.Object {
    const text = try self.getAttr("text");
    defer text.deinit();
    return loads(text);
}

fn docSetValue(self: py.Object, value: py.Object) !void {
    try self.setAttr("value", value);
}

fn docDumps(self: py.Object) !py.Object {
    const value = try self.getAttr("value");
    defer value.deinit();
    return dumps(value);
}

fn parseZon(gpa: Allocator, source: [:0]const u8) !py.Object {
    var diag: std.zon.parse.Diagnostics = .{};
    defer diag.deinit(gpa);

    const ast: Ast = try .parse(gpa, source, .zon);
    const zoir = try ZonGen.generate(gpa, ast, .{ .parse_str_lits = true });
    diag.ast = ast;
    diag.zoir = zoir;

    if (zoir.hasCompileErrors()) {
        return raiseParseError(gpa, &diag);
    }

    return zoirToPy(gpa, zoir, .root);
}

fn coerceSource(gpa: Allocator, input: py.Object) ![:0]const u8 {
    if (input.isUnicode()) {
        const text = try input.unicodeSlice();
        return copyWithSentinel(gpa, text);
    }
    if (input.isBytes()) {
        const text = try input.bytesSlice();
        return copyWithSentinel(gpa, text);
    }
    return py.raise(.TypeError, "expected str or bytes");
}

fn copyWithSentinel(gpa: Allocator, data: []const u8) ![:0]const u8 {
    const buf = try gpa.alloc(u8, data.len + 1);
    @memcpy(buf[0..data.len], data);
    buf[data.len] = 0;
    return buf[0..data.len :0];
}

fn raiseParseError(gpa: Allocator, diag: *const std.zon.parse.Diagnostics) py.PyError {
    var output: Writer.Allocating = .init(gpa);
    defer output.deinit();

    diag.format(&output.writer) catch {
        return py.raise(.ValueError, "ZON parse error");
    };

    const msg = output.toOwnedSliceSentinel(0) catch {
        return py.raise(.ValueError, "ZON parse error");
    };

    return py.raise(.ValueError, msg);
}

fn renderZon(gpa: Allocator, obj: *PyObject) ![]const u8 {
    var output: Writer.Allocating = .init(gpa);
    defer output.deinit();
    try writeZonValue(&output.writer, obj);
    return output.toOwnedSlice();
}

fn zoirToPy(gpa: Allocator, zoir: Zoir, node: Zoir.Node.Index) anyerror!py.Object {
    return switch (node.get(zoir)) {
        .true => try .from(true),
        .false => try .from(false),
        .null => py.none(),
        .pos_inf => try .from(math.inf(f64)),
        .neg_inf => try .from(-math.inf(f64)),
        .nan => try .from(math.nan(f64)),
        .int_literal => |lit| intLiteralToPy(gpa, lit),
        .float_literal => |value| try .from(@as(f64, @floatCast(value))),
        .char_literal => |value| charLiteralToPy(value),
        .enum_literal => |value| try .from(value.get(zoir)),
        .string_literal => |value| try .from(value),
        .empty_literal => {
            const dict: py.Dict = try .init();
            return dict.obj;
        },
        .array_literal => |range| arrayToPy(gpa, zoir, range),
        .struct_literal => |fields| structToPy(gpa, zoir, fields),
    };
}

fn intLiteralToPy(gpa: Allocator, lit: anytype) anyerror!py.Object {
    switch (lit) {
        .small => |value| return .from(@as(i64, @intCast(value))),
        .big => |value| {
            const text = try value.toStringAlloc(gpa, 10, .lower);
            const ztext = try copyWithSentinel(gpa, text);
            return py.Long.fromString(ztext);
        },
    }
}

fn charLiteralToPy(value: u21) anyerror!py.Object {
    var buf: [4]u8 = undefined;
    const len = std.unicode.utf8Encode(value, &buf) catch {
        return py.raise(.ValueError, "invalid char literal");
    };
    return .from(@as([]const u8, buf[0..len]));
}

fn arrayToPy(gpa: Allocator, zoir: Zoir, range: Zoir.Node.Index.Range) anyerror!py.Object {
    var list: py.List = try .init(@intCast(range.len));
    errdefer list.deinit();
    var i: u32 = 0;
    while (i < range.len) : (i += 1) {
        const item = try zoirToPy(gpa, zoir, range.at(i));
        try list.set(@intCast(i), item);
    }
    return list.obj;
}

fn structToPy(gpa: Allocator, zoir: Zoir, fields: anytype) anyerror!py.Object {
    var dict: py.Dict = try .init();
    errdefer dict.deinit();
    var i: usize = 0;
    while (i < fields.names.len) : (i += 1) {
        const name = fields.names[i].get(zoir);
        const value = try zoirToPy(gpa, zoir, fields.vals.at(@intCast(i)));
        try dict.setItem(name, value);
    }
    return dict.obj;
}

fn writeZonValue(writer: *Writer, obj: *PyObject) anyerror!void {
    const obj_ref: py.Object = .borrowed(obj);
    if (obj_ref.isNone()) {
        try writer.writeAll("null");
        return;
    }
    if (obj_ref.isBool()) {
        const value = try obj_ref.isTrue();
        try writer.writeAll(if (value) "true" else "false");
        return;
    }
    if (obj_ref.isLong()) {
        const text_obj = try obj_ref.str();
        defer text_obj.deinit();
        const text = try text_obj.unicodeSlice();
        try writer.writeAll(text);
        return;
    }
    if (obj_ref.isFloat()) {
        const value = try obj_ref.as(f64);
        if (math.isNan(value)) {
            try writer.writeAll("nan");
        } else if (math.isInf(value)) {
            try writer.writeAll(if (value > 0) "inf" else "-inf");
        } else {
            try writer.print("{d}", .{value});
        }
        return;
    }
    if (obj_ref.isUnicode()) {
        const text = try obj_ref.unicodeSlice();
        try writer.print("\"{f}\"", .{std.zig.fmtString(text)});
        return;
    }
    if (obj_ref.isBytes()) {
        const text = try obj_ref.bytesSlice();
        try writer.print("\"{f}\"", .{std.zig.fmtString(text)});
        return;
    }
    if (obj_ref.isList()) {
        const list: py.List = .borrowed(obj_ref.ptr);
        const size = try list.len();
        try writeZonSequence(writer, .{ .list = list }, size);
        return;
    }
    if (obj_ref.isTuple()) {
        const tuple: py.Tuple = .borrowed(obj_ref.ptr);
        const size = try tuple.len();
        try writeZonSequence(writer, .{ .tuple = tuple }, size);
        return;
    }
    if (obj_ref.isDict()) {
        try writeZonDict(writer, obj_ref.ptr);
        return;
    }

    return py.raise(.TypeError, "unsupported type for ZON serialization");
}

const ListOrTuple = union(enum) {
    list: py.List,
    tuple: py.Tuple,

    fn get(self: @This(), index: usize) anyerror!py.Object {
        return switch (self) {
            .list => |list| try list.get(index),
            .tuple => |tuple| try tuple.get(index),
        };
    }
};

fn writeZonSequence(writer: *Writer, seq: ListOrTuple, size: usize) anyerror!void {
    try writer.writeAll(".{");
    if (size == 0) {
        try writer.writeAll("}");
        return;
    }
    try writer.writeAll(" ");
    var i: usize = 0;
    while (i < size) : (i += 1) {
        if (i != 0) {
            try writer.writeAll(", ");
        }
        const item = try seq.get(i);
        try writeZonValue(writer, item.ptr);
    }
    try writer.writeAll(" }");
}

fn writeZonDict(writer: *Writer, obj: *PyObject) anyerror!void {
    try writer.writeAll(".{");
    var first = true;
    var iter: py.DictIter = try .fromPtr(obj);
    while (iter.next()) |entry| {
        if (first) {
            try writer.writeAll(" ");
            first = false;
        } else {
            try writer.writeAll(", ");
        }
        try writeZonKey(writer, entry.key.ptr);
        try writer.writeAll(" = ");
        try writeZonValue(writer, entry.value.ptr);
    }
    if (!first) {
        try writer.writeAll(" ");
    }
    try writer.writeAll("}");
}

fn writeZonKey(writer: *Writer, key: *PyObject) anyerror!void {
    const text = try stringLikeSlice(key);
    try writer.writeAll(".");
    try writer.print("{f}", .{std.zig.fmtId(text)});
}

fn stringLikeSlice(obj: *PyObject) anyerror![]const u8 {
    const obj_ref: py.Object = .borrowed(obj);
    if (obj_ref.isUnicode()) return obj_ref.unicodeSlice();
    if (obj_ref.isBytes()) return obj_ref.bytesSlice();
    return py.raise(.TypeError, "dict keys must be str or bytes");
}
