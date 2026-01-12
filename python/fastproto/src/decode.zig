//! Protobuf decoding: deserialize wire format bytes into Python dataclass instances.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const fastproto = @import("fastproto");
const wire = fastproto.wire;
const Reader = fastproto.Reader;
const Field = fastproto.Field;
const py = @import("alloconda");
const Object = py.Object;

const FieldInfo = @import("FieldInfo.zig");
const PyReader = @import("Reader.zig").Reader;
const wrap = @import("errors.zig").wrap;

const DecodeError = error{ OutOfMemory, PythonError };

const FieldMap = struct {
    inner: std.AutoHashMapUnmanaged(u32, FieldInfo) = .empty,

    pub fn init(allocator: Allocator, fields: []FieldInfo) !FieldMap {
        var map: FieldMap = .{};
        errdefer map.deinit(allocator);
        for (fields) |f| try map.inner.put(allocator, f.proto_field, f);
        return map;
    }

    pub fn deinit(self: *FieldMap, allocator: Allocator) void {
        self.inner.deinit(allocator);
        self.* = undefined;
    }

    pub fn get(self: FieldMap, key: u32) ?FieldInfo {
        return self.inner.get(key);
    }
};

pub fn decode(cls: Object, data: py.BytesView) DecodeError!Object {
    var arena = py.arenaAllocator();
    defer arena.deinit();
    const allocator = arena.allocator();

    var fields: FieldInfo.List = try .init(allocator, cls);
    defer fields.deinit(allocator);

    var field_map: FieldMap = try .init(allocator, fields.items);
    defer field_map.deinit(allocator);

    const slice = try data.slice();
    var io_reader: Io.Reader = .fixed(slice);
    var reader: Reader = .init(&io_reader);

    var kwargs: py.Dict = try .init();
    errdefer kwargs.deinit();

    while (true) {
        const field = try wrap(reader.next()) orelse break;

        const field_num = field.fieldNumber();
        const info = field_map.get(field_num) orelse {
            try skipField(field);
            continue;
        };

        try decodeField(allocator, info, field, &kwargs);
    }

    return constructDataclass(cls, kwargs);
}

pub fn decodeFrom(cls: Object, reader_obj: Object) DecodeError!Object {
    var arena = py.arenaAllocator();
    defer arena.deinit();
    const allocator = arena.allocator();

    const state = try PyReader.payloadFrom(reader_obj);

    var fields: FieldInfo.List = try .init(allocator, cls);
    defer fields.deinit(allocator);

    var field_map: FieldMap = try .init(allocator, fields.items);
    defer field_map.deinit(allocator);

    var kwargs: py.Dict = try .init();
    errdefer kwargs.deinit();

    while (true) {
        const field = try wrap(state.reader.next()) orelse break;

        const field_num = field.fieldNumber();
        const info = field_map.get(field_num) orelse {
            try skipField(field);
            continue;
        };

        try decodeField(allocator, info, field, &kwargs);
    }

    return constructDataclass(cls, kwargs);
}

fn decodeField(allocator: Allocator, info: FieldInfo, field: Field, kwargs: *py.Dict) DecodeError!void {
    if (try info.getOptionalInnerType()) |inner_type| {
        defer inner_type.deinit();
        return decodeFieldInner(allocator, info.withType(inner_type), field, kwargs);
    }
    return decodeFieldInner(allocator, info, field, kwargs);
}

fn decodeFieldInner(allocator: Allocator, info: FieldInfo, field: Field, kwargs: *py.Dict) DecodeError!void {
    const is_list = try info.isList();

    if (is_list) {
        try decodeRepeatedField(allocator, info, field, kwargs);
    } else {
        const value = try decodeSingleValue(allocator, info, field);
        errdefer value.deinit();
        try kwargs.setItem(info.name, value);
    }
}

fn decodeRepeatedField(allocator: Allocator, info: FieldInfo, field: Field, kwargs: *py.Dict) DecodeError!void {
    var list: py.List = blk: {
        if (try kwargs.getItem(info.name)) |existing| {
            break :blk try .fromObject(existing);
        }
        const new_list: py.List = try .init(0);
        try kwargs.setItem(info.name, new_list.obj);
        break :blk new_list;
    };

    const elem_type = try info.getListElementType() orelse {
        return py.raise(.TypeError, "list type missing element type");
    };
    defer elem_type.deinit();

    const elem_info = info.withType(elem_type);

    switch (field) {
        .len => |len_field| {
            if (elem_info.isPackedScalar()) {
                try decodePackedRepeated(allocator, &elem_info, len_field, &list);
            } else {
                const value = try decodeLenValue(allocator, &elem_info, len_field);
                errdefer value.deinit();
                try list.append(value);
            }
        },
        else => {
            const value = try decodeSingleValue(allocator, elem_info, field);
            errdefer value.deinit();
            try list.append(value);
        },
    }
}

fn decodePackedRepeated(
    allocator: Allocator,
    info: *const FieldInfo,
    len_field: Field.Len,
    list: *py.List,
) !void {
    const data = try wrap(len_field.bytesAlloc(allocator));

    if (info.isBool()) return decodePackedVarint(bool, data, list, false, false);

    const scalar = info.scalarType(if (info.isFloat()) .double else .i64);

    try switch (scalar) {
        .float => decodePackedFixed(f32, data, list),
        .double => decodePackedFixed(f64, data, list),
        .fixed32 => decodePackedFixed(u32, data, list),
        .sfixed32 => decodePackedFixed(i32, data, list),
        .fixed64 => decodePackedFixed(u64, data, list),
        .sfixed64 => decodePackedFixed(i64, data, list),
        .sint32, .sint64 => decodePackedVarint(i64, data, list, true, false),
        .u32, .u64 => decodePackedVarint(u64, data, list, false, true),
        else => decodePackedVarint(i64, data, list, false, false),
    };
}

fn decodePackedVarint(comptime T: type, data: []const u8, list: *py.List, zigzag: bool, unsigned: bool) !void {
    var offset: usize = 0;
    while (offset < data.len) {
        const value, const bytes_read = try wrap(wire.decodeVarint(u64, data[offset..]));
        offset += bytes_read;

        if (T == bool) {
            try list.append(value != 0);
        } else if (zigzag) {
            try list.append(wire.zigzagDecode(u64, value));
        } else if (unsigned) {
            try list.append(value);
        } else {
            const signed: i64 = @bitCast(value);
            try list.append(signed);
        }
    }
}

fn decodePackedFixed(comptime T: type, data: []const u8, list: *py.List) !void {
    const size = @sizeOf(T);
    if (data.len % size != 0) {
        return py.raise(.ValueError, "packed data length not a multiple of element size");
    }
    var offset: usize = 0;
    while (offset + size <= data.len) {
        const raw: *const [size]u8 = @ptrCast(data[offset .. offset + size].ptr);
        const value: T = @bitCast(raw.*);
        try list.append(value);
        offset += size;
    }
}

fn decodeSingleValue(allocator: Allocator, info: FieldInfo, field: Field) DecodeError!Object {
    return switch (field) {
        .varint => |v| info.decodeVarint(v.value),
        .fixed64 => |f| info.decodeFixed(u64, f.value),
        .fixed32 => |f| info.decodeFixed(u32, f.value),
        .len => |l| decodeLenValue(allocator, &info, l),
    };
}

fn decodeLenValue(allocator: Allocator, info: *const FieldInfo, len_field: Field.Len) DecodeError!Object {
    if (info.isStr()) {
        const data = try wrap(len_field.stringAlloc(allocator));
        return .from(@as([]const u8, data));
    }

    if (info.isBytes()) {
        const data = try wrap(len_field.bytesAlloc(allocator));
        return (try py.Bytes.fromSlice(data)).obj;
    }

    if (try info.type_obj.isDataclass()) {
        return decodeNestedMessage(allocator, info.type_obj, len_field);
    }

    return py.raise(.TypeError, "unsupported length-delimited field type");
}

fn decodeNestedMessage(allocator: Allocator, cls: Object, len_field: Field.Len) DecodeError!Object {
    var fields: FieldInfo.List = try .init(allocator, cls);
    defer fields.deinit(allocator);

    var field_map: FieldMap = try .init(allocator, fields.items);
    defer field_map.deinit(allocator);

    var nested_reader = len_field.message();

    var kwargs: py.Dict = try .init();
    errdefer kwargs.deinit();

    while (true) {
        const field = try wrap(nested_reader.next()) orelse break;

        const field_num = field.fieldNumber();
        const info = field_map.get(field_num) orelse {
            try skipField(field);
            continue;
        };

        try decodeField(allocator, info, field, &kwargs);
    }

    return constructDataclass(cls, kwargs);
}

fn constructDataclass(cls: Object, kwargs: py.Dict) DecodeError!Object {
    const empty_args: py.Tuple = try .init(0);
    defer empty_args.deinit();

    const ffi = py.ffi;
    const result = ffi.c.PyObject_Call(cls.ptr, empty_args.obj.ptr, kwargs.obj.ptr);
    if (result == null) return error.PythonError;
    return .owned(result.?);
}

fn skipField(field: Field) !void {
    switch (field) {
        .len => |l| try wrap(l.skip()),
        else => {},
    }
}
