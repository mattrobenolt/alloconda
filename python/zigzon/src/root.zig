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
});

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
    return py.toObject(text) orelse error.PythonError;
}

fn from_python(value: py.Object) CallError!py.Object {
    return dumps(value);
}

fn dump(value: py.Object, fp: py.Object) CallError!void {
    var arena = py.arenaAllocator();
    defer arena.deinit();
    const allocator = arena.allocator();
    const text = try renderZon(allocator, value.ptr);
    const result = fp.callMethod1("write", text) orelse return error.PythonError;
    result.deinit();
}

fn parseZon(allocator: Allocator, source: [:0]const u8) CallError!py.Object {
    var diag: std.zon.parse.Diagnostics = .{};
    defer diag.deinit(allocator);

    const ast = try Ast.parse(allocator, source, .zon);
    const zoir = try ZonGen.generate(allocator, ast, .{ .parse_str_lits = true });
    diag.ast = ast;
    diag.zoir = zoir;

    if (zoir.hasCompileErrors()) {
        raiseParseError(allocator, &diag);
        return error.PythonError;
    }

    return zoirToPy(allocator, zoir, .root);
}

fn coerceSource(gpa: Allocator, input: py.Object) CallError![:0]const u8 {
    if (py.isUnicode(input.ptr)) {
        const text = py.unicodeSlice(input.ptr) orelse return error.PythonError;
        return copyWithSentinel(gpa, text);
    }
    if (py.isBytes(input.ptr)) {
        const text = py.bytesSlice(input.ptr) orelse return error.PythonError;
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
    switch (node.get(zoir)) {
        .true => return py.toObject(true) orelse error.PythonError,
        .false => return py.toObject(false) orelse error.PythonError,
        .null => return py.none(),
        .pos_inf => return py.toObject(math.inf(f64)) orelse error.PythonError,
        .neg_inf => return py.toObject(-math.inf(f64)) orelse error.PythonError,
        .nan => return py.toObject(math.nan(f64)) orelse error.PythonError,
        .int_literal => |lit| return intLiteralToPy(gpa, lit),
        .float_literal => |value| return py.toObject(@as(f64, @floatCast(value))) orelse error.PythonError,
        .char_literal => |value| return charLiteralToPy(value),
        .enum_literal => |value| return py.toObject(value.get(zoir)) orelse error.PythonError,
        .string_literal => |value| return py.toObject(value) orelse error.PythonError,
        .empty_literal => {
            const dict = py.Dict.init() orelse return error.PythonError;
            return dict.obj;
        },
        .array_literal => |range| return arrayToPy(gpa, zoir, range),
        .struct_literal => |fields| return structToPy(gpa, zoir, fields),
    }
}

fn intLiteralToPy(gpa: Allocator, lit: anytype) CallError!py.Object {
    switch (lit) {
        .small => |value| return py.toObject(@as(i64, value)) orelse error.PythonError,
        .big => |value| {
            const text = try value.toStringAlloc(gpa, 10, .lower);
            const ztext = try copyWithSentinel(gpa, text);
            return py.longFromString(ztext) orelse error.PythonError;
        },
    }
}

fn charLiteralToPy(value: u21) CallError!py.Object {
    var buf: [4]u8 = undefined;
    const len = std.unicode.utf8Encode(value, &buf) catch {
        py.raise(.ValueError, "invalid char literal");
        return error.PythonError;
    };
    return py.toObject(@as([]const u8, buf[0..len])) orelse error.PythonError;
}

fn arrayToPy(gpa: Allocator, zoir: Zoir, range: Zoir.Node.Index.Range) CallError!py.Object {
    var list = py.List.init(@intCast(range.len)) orelse return error.PythonError;
    var i: u32 = 0;
    while (i < range.len) : (i += 1) {
        const item = try zoirToPy(gpa, zoir, range.at(i));
        if (!list.set(@intCast(i), item)) {
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
        if (!dict.setItem(name, value)) {
            dict.deinit();
            return error.PythonError;
        }
    }
    return dict.obj;
}

fn writeZonValue(writer: *Writer, obj: *PyObject) CallError!void {
    if (py.isNone(obj)) {
        try writer.writeAll("null");
        return;
    }
    if (py.isBool(obj)) {
        const value = py.objectIsTrue(obj) orelse return error.PythonError;
        try writer.writeAll(if (value) "true" else "false");
        return;
    }
    if (py.isLong(obj)) {
        const text_obj = py.objectStr(obj) orelse return error.PythonError;
        defer text_obj.deinit();
        const text = py.unicodeSlice(text_obj.ptr) orelse return error.PythonError;
        try writer.writeAll(text);
        return;
    }
    if (py.isFloat(obj)) {
        const value = py.floatAsDouble(obj) orelse return error.PythonError;
        if (math.isNan(value)) {
            try writer.writeAll("nan");
        } else if (math.isInf(value)) {
            try writer.writeAll(if (value > 0) "inf" else "-inf");
        } else {
            try writer.print("{d}", .{value});
        }
        return;
    }
    if (py.isUnicode(obj)) {
        const text = py.unicodeSlice(obj) orelse return error.PythonError;
        try writer.print("\"{f}\"", .{std.zig.fmtString(text)});
        return;
    }
    if (py.isBytes(obj)) {
        const text = py.bytesSlice(obj) orelse return error.PythonError;
        try writer.print("\"{f}\"", .{std.zig.fmtString(text)});
        return;
    }
    if (py.isList(obj)) {
        const list = py.List.borrowed(obj);
        const size = list.len() orelse return error.PythonError;
        try writeZonSequence(writer, list, size);
        return;
    }
    if (py.isTuple(obj)) {
        const tuple = py.Tuple.borrowed(obj);
        const size = tuple.len() orelse return error.PythonError;
        try writeZonSequence(writer, tuple, size);
        return;
    }
    if (py.isDict(obj)) {
        try writeZonDict(writer, obj);
        return;
    }

    py.raise(.TypeError, "unsupported type for ZON serialization");
    return error.PythonError;
}

fn writeZonSequence(writer: *Writer, seq: anytype, size: usize) CallError!void {
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
    var iter = py.dictIter(obj);
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
    if (py.isUnicode(obj)) return py.unicodeSlice(obj) orelse error.PythonError;
    if (py.isBytes(obj)) return py.bytesSlice(obj) orelse error.PythonError;
    py.raise(.TypeError, "dict keys must be str or bytes");
    return error.PythonError;
}
