//! Metadata extracted from a dataclass field.
//!
//! Ownership: `name_obj` and `type_obj` are owned by the `List` returned from
//! `List.init()` and must be released via `List.deinit()`.
//! Copies of FieldInfo borrow these references and must not call deinit on them.
const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const fastproto = @import("fastproto");
const wire = fastproto.wire;
const py = @import("alloconda");
const Object = py.Object;

const FieldInfo = @This();

const DecodeError = error{ OutOfMemory, PythonError };

name: []const u8,
name_obj: Object,
proto_field: u32,
proto_type: ?[]const u8,
type_obj: Object,

pub const List = struct {
    items: []FieldInfo,

    /// Initialize by introspecting a Python dataclass.
    pub fn init(allocator: Allocator, cls: Object) !@This() {
        const dataclasses_mod = py.dataclasses();

        const fields_func = try dataclasses_mod.getAttr("fields");
        defer fields_func.deinit();

        const fields_tuple_obj = try fields_func.call(.{cls});
        defer fields_tuple_obj.deinit();

        const fields_tuple: py.Tuple = try .fromObject(fields_tuple_obj);
        const count = try fields_tuple.len();

        const result = try allocator.alloc(FieldInfo, count);
        errdefer allocator.free(result);

        for (0..count) |i| {
            const field = try fields_tuple.get(i);

            const name_obj = try field.getAttr("name");
            const name = try name_obj.unicodeSlice();

            const metadata_obj = try field.getAttr("metadata");
            defer metadata_obj.deinit();

            const proto_field_obj = try getFromMapping(metadata_obj, "proto_field") orelse {
                return py.raise(.ValueError, "field missing 'proto_field' metadata");
            };
            defer proto_field_obj.deinit();
            const proto_field: u32 = try proto_field_obj.as(u32);

            var proto_type: ?[]const u8 = null;
            if (try getFromMapping(metadata_obj, "proto_type")) |proto_type_obj| {
                defer proto_type_obj.deinit();
                proto_type = try proto_type_obj.unicodeSlice();
            }

            const type_obj = try field.getAttr("type");

            result[i] = .{
                .name = name,
                .name_obj = name_obj,
                .proto_field = proto_field,
                .proto_type = proto_type,
                .type_obj = type_obj,
            };
        }

        return .{ .items = result };
    }

    /// Release all Python references and free memory.
    pub fn deinit(self: *@This(), allocator: Allocator) void {
        for (self.items) |f| {
            f.name_obj.deinit();
            f.type_obj.deinit();
        }
        allocator.free(self.items);
        self.* = undefined;
    }

    pub fn len(self: @This()) usize {
        return self.items.len;
    }
};

/// Check if the field type is int.
pub fn isInt(self: @This()) bool {
    return self.checkBuiltinType("int");
}

/// Check if the field type is float.
pub fn isFloat(self: @This()) bool {
    return self.checkBuiltinType("float");
}

/// Check if the field type is bool.
pub fn isBool(self: @This()) bool {
    return self.checkBuiltinType("bool");
}

/// Check if the field type is str.
pub fn isStr(self: @This()) bool {
    return self.checkBuiltinType("str");
}

/// Check if the field type is bytes.
pub fn isBytes(self: @This()) bool {
    return self.checkBuiltinType("bytes");
}

/// Check if the field type is a list (typing.List or list).
pub fn isList(self: @This()) !bool {
    const list_type = getListType();
    defer list_type.deinit();
    const origin = self.type_obj.getAttrOrNull("__origin__") catch return false;
    if (origin) |orig| {
        defer orig.deinit();
        return orig.ptr == list_type.ptr;
    }
    return self.type_obj.ptr == list_type.ptr;
}

/// Get the element type for a List[T] type annotation.
pub fn getListElementType(self: @This()) !?Object {
    const args = self.type_obj.getAttrOrNull("__args__") catch return null;
    if (args) |args_tuple| {
        defer args_tuple.deinit();
        const tuple: py.Tuple = try .fromObject(args_tuple);
        if (try tuple.len() > 0) {
            return (try tuple.get(0)).incref();
        }
    }
    return null;
}

/// Check if this is an Optional[T] type (Union with None).
/// Returns the inner type T if so, otherwise null.
pub fn getOptionalInnerType(self: @This()) !?Object {
    return py.unwrapOptional(self.type_obj);
}

/// Check if this field type is a packed scalar (int, float, or bool).
pub fn isPackedScalar(self: @This()) bool {
    return self.isInt() or self.isFloat() or self.isBool();
}

/// Create a copy of this FieldInfo with a different type_obj.
/// Useful for unwrapping Optional[T] or getting list element type.
pub fn withType(self: @This(), new_type: Object) @This() {
    return .{
        .name = self.name,
        .name_obj = self.name_obj,
        .proto_field = self.proto_field,
        .proto_type = self.proto_type,
        .type_obj = new_type,
    };
}

/// Get the wire.Scalar for this field, with a default for unspecified proto_type.
pub fn scalarType(self: @This(), default: wire.Scalar) wire.Scalar {
    return wire.Scalar.fromProtoType(self.proto_type) orelse default;
}

/// Decode a varint wire value to a Python object.
pub fn decodeVarint(self: @This(), value: u64) DecodeError!Object {
    if (self.isBool()) return .from(value != 0);

    const scalar = self.scalarType(.i64);
    return switch (scalar) {
        .sint32 => .from(wire.zigzagDecode(u32, @truncate(value))),
        .sint64 => .from(wire.zigzagDecode(u64, value)),
        .u32, .u64 => .from(value),
        else => .from(@as(i64, @bitCast(value))),
    };
}

/// Decode a fixed-width wire value (32 or 64 bit) to a Python object.
pub fn decodeFixed(self: @This(), comptime T: type, value: T) DecodeError!Object {
    assert(T == u32 or T == u64);

    if (self.isFloat()) {
        const F = if (T == u32) f32 else f64;
        return .from(@as(F, @bitCast(value)));
    }

    const default: wire.Scalar = if (T == u32) .fixed32 else .fixed64;
    const scalar = self.scalarType(default);

    const is_signed = (T == u32 and scalar == .sfixed32) or (T == u64 and scalar == .sfixed64);
    if (is_signed) {
        const S = if (T == u32) i32 else i64;
        return .from(@as(S, @bitCast(value)));
    }

    return .from(value);
}

fn checkBuiltinType(self: @This(), comptime type_name: [:0]const u8) bool {
    const builtins_mod = py.builtins();
    const builtin_type = builtins_mod.getAttrOrNull(type_name) catch {
        return false;
    } orelse {
        return false;
    };
    defer builtin_type.deinit();
    return self.type_obj.ptr == builtin_type.ptr;
}

fn getListType() Object {
    const builtins_mod = py.builtins();
    const list_type = builtins_mod.getAttr("list") catch unreachable;
    return list_type;
}

fn getFromMapping(mapping: Object, key: [:0]const u8) !?Object {
    const get_method = try mapping.getAttr("get");
    defer get_method.deinit();
    const result = try get_method.call(.{key});
    if (result.isNone()) {
        result.deinit();
        return null;
    }
    return result;
}
