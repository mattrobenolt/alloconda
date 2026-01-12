//! Protobuf encoder for Python dataclasses.
//!
//! Serializes Python dataclass instances to protobuf wire format bytes.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const fastproto = @import("fastproto");
const wire = fastproto.wire;
const Writer = fastproto.Writer;
const py = @import("alloconda");
const Object = py.Object;

const FieldInfo = @import("FieldInfo.zig");
const PyWriter = @import("Writer.zig").Writer;
const wrap = @import("errors.zig").wrap;
const writeScalarValue = @import("scalar.zig").writeScalarValue;

const EncodeError = py.PyError || wire.Error;

pub fn encode(obj: Object) EncodeError!py.Bytes {
    var arena = py.arenaAllocator();
    defer arena.deinit();
    const allocator = arena.allocator();

    var io_writer: Io.Writer.Allocating = .init(allocator);
    defer io_writer.deinit();

    var writer: Writer = .init(&io_writer.writer);

    try encodeMessage(allocator, &writer, obj);

    return .fromSlice(io_writer.writer.buffered());
}

pub fn encodeInto(writer_obj: Object, obj: Object) EncodeError!void {
    var arena = py.arenaAllocator();
    defer arena.deinit();
    const allocator = arena.allocator();

    const state = try PyWriter.payloadFrom(writer_obj);

    try encodeMessage(allocator, &state.writer, obj);
}

fn encodeMessage(allocator: Allocator, writer: *Writer, obj: Object) EncodeError!void {
    const cls = try obj.getAttr("__class__");
    defer cls.deinit();

    var fields: FieldInfo.List = try .init(allocator, cls);
    defer fields.deinit(allocator);

    for (fields.items) |field| {
        const value = try obj.genericGetAttr(field.name_obj);
        defer value.deinit();

        if (value.isNone()) continue;

        try encodeField(allocator, writer, field, value);
    }
}

fn encodeField(allocator: Allocator, writer: *Writer, field: FieldInfo, value: Object) EncodeError!void {
    if (try field.getOptionalInnerType()) |inner_type| {
        defer inner_type.deinit();
        return encodeFieldInner(allocator, writer, field.withType(inner_type), value);
    }
    return encodeFieldInner(allocator, writer, field, value);
}

fn encodeFieldInner(allocator: Allocator, writer: *Writer, field: FieldInfo, value: Object) EncodeError!void {
    if (field.isInt()) {
        try encodeInt(writer, field, value);
    } else if (field.isFloat()) {
        try encodeFloat(writer, field, value);
    } else if (field.isBool()) {
        try encodeBool(writer, field, value);
    } else if (field.isStr()) {
        try encodeStr(writer, field, value);
    } else if (field.isBytes()) {
        try encodeBytes(writer, field, value);
    } else if (try field.isList()) {
        try encodeList(allocator, writer, field, value);
    } else if (try field.type_obj.isDataclass()) {
        try encodeSubmessage(allocator, writer, field, value);
    } else {
        return py.raise(.TypeError, "unsupported field type");
    }
}

fn encodeInt(writer: *Writer, field: FieldInfo, value: Object) !void {
    const scalar = field.scalarType(.i64);
    const tag: wire.Tag = try .init(field.proto_field, scalar.wireTypeRuntime());
    try wrap(writer.writeTag(tag));
    try writeScalarValue(writer, scalar, value);
}

fn encodeFloat(writer: *Writer, field: FieldInfo, value: Object) !void {
    const scalar = field.scalarType(.double);
    const tag: wire.Tag = try .init(field.proto_field, scalar.wireTypeRuntime());
    try wrap(writer.writeTag(tag));
    try writeScalarValue(writer, scalar, value);
}

fn encodeBool(writer: *Writer, field: FieldInfo, value: Object) !void {
    const tag: wire.Tag = try .init(field.proto_field, .varint);
    try wrap(writer.writeTag(tag));
    try writeScalarValue(writer, .bool, value);
}

fn encodeStr(writer: *Writer, field: FieldInfo, value: Object) !void {
    const tag: wire.Tag = try .init(field.proto_field, .len);
    try wrap(writer.writeTag(tag));
    const slice = try value.unicodeSlice();
    try wrap(writer.writeLen(slice));
}

fn encodeBytes(writer: *Writer, field: FieldInfo, value: Object) !void {
    const tag: wire.Tag = try .init(field.proto_field, .len);
    try wrap(writer.writeTag(tag));
    const slice = try value.bytesSlice();
    try wrap(writer.writeLen(slice));
}

fn encodeList(allocator: Allocator, writer: *Writer, field: FieldInfo, value: Object) EncodeError!void {
    const list: py.List = try .fromObject(value);
    const count = try list.len();
    if (count == 0) return;

    const elem_type = try field.getListElementType() orelse {
        return py.raise(.TypeError, "list must have element type annotation");
    };
    defer elem_type.deinit();

    const elem_field = field.withType(elem_type);

    if (try elem_type.isDataclass()) {
        for (0..count) |i| {
            const item = try list.get(i);
            defer item.deinit();
            try encodeSubmessage(allocator, writer, elem_field, item);
        }
    } else {
        try encodePackedRepeated(allocator, writer, elem_field, list, count);
    }
}

fn encodePackedRepeated(
    allocator: Allocator,
    writer: *Writer,
    elem_field: FieldInfo,
    list: py.List,
    count: usize,
) !void {
    var inner_io: Io.Writer.Allocating = .init(allocator);
    defer inner_io.deinit();

    var inner: Writer = .init(&inner_io.writer);

    for (0..count) |i| {
        const item = try list.get(i);
        defer item.deinit();
        try encodePackedElement(&inner, elem_field, item);
    }

    const tag: wire.Tag = try .init(elem_field.proto_field, .len);
    try wrap(writer.writeTag(tag));
    try wrap(writer.writeLen(inner_io.writer.buffered()));
}

fn encodePackedElement(writer: *Writer, field: FieldInfo, value: Object) !void {
    if (field.isInt()) {
        return writeScalarValue(writer, field.scalarType(.i64), value);
    } else if (field.isFloat()) {
        return writeScalarValue(writer, field.scalarType(.double), value);
    } else if (field.isBool()) {
        return writeScalarValue(writer, .bool, value);
    }
    return py.raise(.TypeError, "unsupported packed element type");
}

fn encodeSubmessage(allocator: Allocator, writer: *Writer, field: FieldInfo, value: Object) EncodeError!void {
    var inner_io: Io.Writer.Allocating = .init(allocator);
    defer inner_io.deinit();

    var inner: Writer = .init(&inner_io.writer);

    try encodeMessage(allocator, &inner, value);

    const tag: wire.Tag = try .init(field.proto_field, .len);
    try wrap(writer.writeTag(tag));
    try wrap(writer.writeLen(inner_io.writer.buffered()));
}
