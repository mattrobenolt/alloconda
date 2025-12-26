const std = @import("std");
const Allocator = std.mem.Allocator;
const Zoir = std.zig.Zoir;
const Ast = std.zig.Ast;
const ZonGen = std.zig.ZonGen;
const Writer = std.Io.Writer;
const math = std.math;

const py = @import("alloconda");
const PyObject = py.PyObject;

const CallError = error{ PythonError, OutOfMemory, WriteFailed };

const ZonDocument = py.class("ZonDocument", "Small helper for stored ZON text/value.", .{
    .set_text = py.method(docSetText, .{
        .self = true,
        .args = &.{"text"},
    }),
    .get_text = py.method(docGetText, .{
        .self = true,
    }),
    .loads = py.method(docLoads, .{
        .self = true,
    }),
    .set_value = py.method(docSetValue, .{
        .self = true,
        .args = &.{"value"},
    }),
    .dumps = py.method(docDumps, .{
        .self = true,
    }),
});

pub const MODULE = py.module("_zigzon", "ZON codec implemented in Zig.", .{
    .loads = py.method(loads, .{
        .doc = "Parse ZON text into Python objects.",
        .args = &.{"data"},
    }),
    .load = py.method(load, .{
        .doc = "Parse ZON from a file-like object.",
        .args = &.{"fp"},
    }),
    .dumps = py.method(dumps, .{
        .doc = "Serialize a Python value to ZON text.",
        .args = &.{"value"},
    }),
    .dump = py.method(dump, .{
        .doc = "Serialize a Python value to a file-like object.",
        .args = &.{ "value", "fp" },
    }),
    .to_python = py.method(to_python, .{
        .doc = "Alias for loads().",
        .args = &.{"data"},
    }),
    .from_python = py.method(from_python, .{
        .doc = "Alias for dumps().",
        .args = &.{"value"},
    }),
}).withTypes(.{ .ZonDocument = ZonDocument });

fn loads(input: py.Object) CallError!py.Object {
    var arena = py.arenaAllocator();
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = try coerceSource(allocator, input);
    return parseZon(allocator, source);
}

fn to_python(input: py.Object) CallError!py.Object {
    return loads(input);
}

fn load(fp: py.Object) CallError!py.Object {
    const data = fp.callMethod0("read") orelse return error.PythonError;
    defer data.deinit();
    return loads(data);
}

fn dumps(value: py.Object) CallError!py.Object {
    var arena = py.arenaAllocator();
    defer arena.deinit();
    const allocator = arena.allocator();
    const text = try renderZon(allocator, value.ptr);
    return py.Object.from([]const u8, text) orelse error.PythonError;
}

fn from_python(value: py.Object) CallError!py.Object {
    return dumps(value);
}

fn dump(value: py.Object, fp: py.Object) CallError!void {
    var arena = py.arenaAllocator();
    defer arena.deinit();
    const allocator = arena.allocator();
    const text = try renderZon(allocator, value.ptr);
    const result = fp.callMethod1("write", []const u8, text) orelse return error.PythonError;
    result.deinit();
}

fn docSetText(self: py.Object, text: py.Object) CallError!void {
    if (!text.isUnicode() and !text.isBytes()) {
        py.raise(.TypeError, "text must be str or bytes");
        return error.PythonError;
    }
    if (!self.setAttr("text", py.Object, text)) {
        return error.PythonError;
    }
}

fn docGetText(self: py.Object) CallError!py.Object {
    return self.getAttr("text") orelse error.PythonError;
}

fn docLoads(self: py.Object) CallError!py.Object {
    const text = self.getAttr("text") orelse return error.PythonError;
    defer text.deinit();
    return loads(text);
}

fn docSetValue(self: py.Object, value: py.Object) CallError!void {
    if (!self.setAttr("value", py.Object, value)) {
        return error.PythonError;
    }
}

fn docDumps(self: py.Object) CallError!py.Object {
    const value = self.getAttr("value") orelse return error.PythonError;
    defer value.deinit();
    return dumps(value);
}

fn parseZon(gpa: Allocator, source: [:0]const u8) CallError!py.Object {
    var diag: std.zon.parse.Diagnostics = .{};
    defer diag.deinit(gpa);

    const ast = try Ast.parse(gpa, source, .zon);
    const zoir = try ZonGen.generate(gpa, ast, .{ .parse_str_lits = true });
    diag.ast = ast;
    diag.zoir = zoir;

    if (zoir.hasCompileErrors()) {
        raiseParseError(gpa, &diag);
        return error.PythonError;
    }

    return zoirToPy(gpa, zoir, .root);
}

fn coerceSource(gpa: Allocator, input: py.Object) CallError![:0]const u8 {
    if (input.isUnicode()) {
        const text = input.unicodeSlice() orelse return error.PythonError;
        return copyWithSentinel(gpa, text);
    }
    if (input.isBytes()) {
        const text = input.bytesSlice() orelse return error.PythonError;
        return copyWithSentinel(gpa, text);
    }
    py.raise(.TypeError, "expected str or bytes");
    return error.PythonError;
}

fn copyWithSentinel(gpa: Allocator, data: []const u8) CallError![:0]const u8 {
    const buf = try gpa.alloc(u8, data.len + 1);
    @memcpy(buf[0..data.len], data);
    buf[data.len] = 0;
    return buf[0..data.len :0];
}

fn raiseParseError(gpa: Allocator, diag: *const std.zon.parse.Diagnostics) void {
    var output: Writer.Allocating = .init(gpa);
    defer output.deinit();

    diag.format(&output.writer) catch {
        py.raise(.ValueError, "ZON parse error");
        return;
    };

    const msg = output.toOwnedSliceSentinel(0) catch {
        py.raise(.ValueError, "ZON parse error");
        return;
    };
    py.raise(.ValueError, msg);
}

fn renderZon(gpa: Allocator, obj: *PyObject) CallError![]const u8 {
    var output: Writer.Allocating = .init(gpa);
    defer output.deinit();
    try writeZonValue(&output.writer, obj);
    return output.toOwnedSlice();
}

fn zoirToPy(gpa: Allocator, zoir: Zoir, node: Zoir.Node.Index) CallError!py.Object {
    return switch (node.get(zoir)) {
        .true => py.Object.from(bool, true) orelse error.PythonError,
        .false => py.Object.from(bool, false) orelse error.PythonError,
        .null => py.none(),
        .pos_inf => py.Object.from(f64, math.inf(f64)) orelse error.PythonError,
        .neg_inf => py.Object.from(f64, -math.inf(f64)) orelse error.PythonError,
        .nan => return py.Object.from(f64, math.nan(f64)) orelse error.PythonError,
        .int_literal => |lit| intLiteralToPy(gpa, lit),
        .float_literal => |value| py.Object.from(f64, @as(f64, @floatCast(value))) orelse error.PythonError,
        .char_literal => |value| charLiteralToPy(value),
        .enum_literal => |value| py.Object.from(@TypeOf(value.get(zoir)), value.get(zoir)) orelse error.PythonError,
        .string_literal => |value| py.Object.from([]const u8, value) orelse error.PythonError,
        .empty_literal => {
            const dict = py.Dict.init() orelse return error.PythonError;
            return dict.obj;
        },
        .array_literal => |range| arrayToPy(gpa, zoir, range),
        .struct_literal => |fields| structToPy(gpa, zoir, fields),
    };
}

fn intLiteralToPy(gpa: Allocator, lit: anytype) CallError!py.Object {
    switch (lit) {
        .small => |value| return py.Object.from(i64, @as(i64, value)) orelse error.PythonError,
        .big => |value| {
            const text = try value.toStringAlloc(gpa, 10, .lower);
            const ztext = try copyWithSentinel(gpa, text);
            return py.Long.fromString(ztext) orelse error.PythonError;
        },
    }
}

fn charLiteralToPy(value: u21) CallError!py.Object {
    var buf: [4]u8 = undefined;
    const len = std.unicode.utf8Encode(value, &buf) catch {
        py.raise(.ValueError, "invalid char literal");
        return error.PythonError;
    };
    return py.Object.from([]const u8, @as([]const u8, buf[0..len])) orelse error.PythonError;
}

fn arrayToPy(gpa: Allocator, zoir: Zoir, range: Zoir.Node.Index.Range) CallError!py.Object {
    var list = py.List.init(@intCast(range.len)) orelse return error.PythonError;
    var i: u32 = 0;
    while (i < range.len) : (i += 1) {
        const item = try zoirToPy(gpa, zoir, range.at(i));
        if (!list.set(py.Object, @intCast(i), item)) {
            list.deinit();
            return error.PythonError;
        }
    }
    return list.obj;
}

fn structToPy(gpa: Allocator, zoir: Zoir, fields: anytype) CallError!py.Object {
    var dict = py.Dict.init() orelse return error.PythonError;
    var i: usize = 0;
    while (i < fields.names.len) : (i += 1) {
        const name = fields.names[i].get(zoir);
        const value = try zoirToPy(gpa, zoir, fields.vals.at(@intCast(i)));
        if (!dict.setItem([]const u8, name, py.Object, value)) {
            dict.deinit();
            return error.PythonError;
        }
    }
    return dict.obj;
}

fn writeZonValue(writer: *Writer, obj: *PyObject) CallError!void {
    const obj_ref = py.Object.borrowed(obj);
    if (obj_ref.isNone()) {
        try writer.writeAll("null");
        return;
    }
    if (obj_ref.isBool()) {
        const value = obj_ref.isTrue() orelse return error.PythonError;
        try writer.writeAll(if (value) "true" else "false");
        return;
    }
    if (obj_ref.isLong()) {
        const text_obj = obj_ref.str() orelse return error.PythonError;
        defer text_obj.deinit();
        const text = text_obj.unicodeSlice() orelse return error.PythonError;
        try writer.writeAll(text);
        return;
    }
    if (obj_ref.isFloat()) {
        const value = obj_ref.as(f64) orelse return error.PythonError;
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
        const text = obj_ref.unicodeSlice() orelse return error.PythonError;
        try writer.print("\"{f}\"", .{std.zig.fmtString(text)});
        return;
    }
    if (obj_ref.isBytes()) {
        const text = obj_ref.bytesSlice() orelse return error.PythonError;
        try writer.print("\"{f}\"", .{std.zig.fmtString(text)});
        return;
    }
    if (obj_ref.isList()) {
        const list = py.List.borrowed(obj_ref.ptr);
        const size = list.len() orelse return error.PythonError;
        try writeZonSequence(writer, .{ .list = list }, size);
        return;
    }
    if (obj_ref.isTuple()) {
        const tuple = py.Tuple.borrowed(obj_ref.ptr);
        const size = tuple.len() orelse return error.PythonError;
        try writeZonSequence(writer, .{ .tuple = tuple }, size);
        return;
    }
    if (obj_ref.isDict()) {
        try writeZonDict(writer, obj_ref.ptr);
        return;
    }

    py.raise(.TypeError, "unsupported type for ZON serialization");
    return error.PythonError;
}

const ListOrTuple = union(enum) {
    list: py.List,
    tuple: py.Tuple,

    fn get(self: @This(), index: usize) ?py.Object {
        return switch (self) {
            inline else => |t| t.get(index),
        };
    }
};

fn writeZonSequence(writer: *Writer, seq: ListOrTuple, size: usize) CallError!void {
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
        const item = seq.get(i) orelse return error.PythonError;
        try writeZonValue(writer, item.ptr);
    }
    try writer.writeAll(" }");
}

fn writeZonDict(writer: *Writer, obj: *PyObject) CallError!void {
    try writer.writeAll(".{");
    var first = true;
    var iter = py.DictIter.fromPtr(obj) orelse return error.PythonError;
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

fn writeZonKey(writer: *Writer, key: *PyObject) CallError!void {
    const text = try stringLikeSlice(key);
    try writer.writeAll(".");
    try writer.print("{f}", .{std.zig.fmtId(text)});
}

fn stringLikeSlice(obj: *PyObject) CallError![]const u8 {
    const obj_ref = py.Object.borrowed(obj);
    if (obj_ref.isUnicode()) return obj_ref.unicodeSlice() orelse error.PythonError;
    if (obj_ref.isBytes()) return obj_ref.bytesSlice() orelse error.PythonError;
    py.raise(.TypeError, "dict keys must be str or bytes");
    return error.PythonError;
}
