//! Comprehensive test module for alloconda.
//!
//! This module exercises all public alloconda APIs to ensure correct behavior
//! across Python versions and platforms. Each section maps to a corresponding
//! Python test file.

const std = @import("std");

const py = @import("alloconda");

// ============================================================================
// Module Definition
// ============================================================================

pub const MODULE = py.module("Alloconda test suite module.", .{
    // Basic function binding
    .add = py.function(add, .{ .doc = "Add two integers" }),
    .add3 = py.function(add3, .{ .doc = "Add two or three integers" }),
    .add_named = py.function(add_named, .{ .doc = "Add named integers", .args = &.{ "a", "b", "c" } }),

    // Type conversions
    .identity_int = py.function(identity_int, .{ .doc = "Return an integer unchanged" }),
    .identity_float = py.function(identity_float, .{ .doc = "Return a float unchanged" }),
    .identity_bool = py.function(identity_bool, .{ .doc = "Return a bool unchanged" }),
    .identity_str = py.function(identity_str, .{ .doc = "Return a string unchanged" }),
    .identity_bytes = py.function(identity_bytes, .{ .doc = "Return bytes unchanged" }),
    .identity_optional = py.function(identity_optional, .{ .doc = "Return optional string or None" }),
    .identity_object = py.function(identity_object, .{ .doc = "Return any object unchanged" }),
    .int64_or_uint64 = py.function(int64_or_uint64, .{ .doc = "Parse int as signed/unsigned 64-bit" }),
    .mask_u32 = py.function(mask_u32, .{ .doc = "Mask int to u32" }),
    .mask_u64 = py.function(mask_u64, .{ .doc = "Mask int to u64" }),
    // TODO: BigInt/Int disabled for now; revisit once allocator boundary is explicit.

    // Bytes operations
    .bytes_len = py.function(bytes_len, .{ .doc = "Return length of bytes" }),
    .bytes_slice = py.function(bytes_slice, .{ .doc = "Return slice of bytes as new bytes" }),
    .bytes_create = py.function(bytes_create, .{ .doc = "Create bytes from string" }),
    .buffer_len = py.function(buffer_len, .{ .doc = "Return length of buffer" }),
    .buffer_sum = py.function(buffer_sum, .{ .doc = "Return sum of buffer bytes" }),
    .bytes_view_len = py.function(bytes_view_len, .{ .doc = "Return length of bytes-like view" }),
    .bytes_view_sum = py.function(bytes_view_sum, .{ .doc = "Return sum of bytes-like view" }),
    .bytes_view_is_buffer = py.function(bytes_view_is_buffer, .{ .doc = "Return true if view wraps a buffer" }),
    .io_read = py.function(io_read, .{ .doc = "Read from a binary IO object" }),
    .write_all = py.function(write_all, .{ .doc = "Write all bytes to a binary IO object" }),

    // List operations
    .list_len = py.function(list_len, .{ .doc = "Return length of list" }),
    .list_get = py.function(list_get, .{ .doc = "Get item from list by index" }),
    .list_sum = py.function(list_sum, .{ .doc = "Sum a list of integers" }),
    .list_create = py.function(list_create, .{ .doc = "Create a new list with given values" }),
    .list_append = py.function(list_append, .{ .doc = "Append value to list and return it" }),
    .list_set = py.function(list_set, .{ .doc = "Set item in list by index" }),

    // Dict operations
    .dict_len = py.function(dict_len, .{ .doc = "Return length of dict" }),
    .dict_get = py.function(dict_get, .{ .doc = "Get item from dict by key" }),
    .dict_create = py.function(dict_create, .{ .doc = "Create a new dict with one key-value pair" }),
    .dict_set = py.function(dict_set, .{ .doc = "Set item in dict by key" }),
    .dict_keys = py.function(dict_keys, .{ .doc = "Return list of dict keys via iteration" }),

    // Tuple operations
    .tuple_len = py.function(tuple_len, .{ .doc = "Return length of tuple" }),
    .tuple_get = py.function(tuple_get, .{ .doc = "Get item from tuple by index" }),
    .tuple_create = py.function(tuple_create, .{ .doc = "Create a tuple from values" }),
    .tuple_create_manual = py.function(tuple_create_manual, .{ .doc = "Create a tuple via Tuple.init/set" }),

    // Object operations
    .obj_call0 = py.function(obj_call0, .{ .doc = "Call object with no args" }),
    .obj_call1 = py.function(obj_call1, .{ .doc = "Call object with one arg" }),
    .obj_call2 = py.function(obj_call2, .{ .doc = "Call object with two args" }),
    .obj_getattr = py.function(obj_getattr, .{ .doc = "Get attribute from object" }),
    .obj_setattr = py.function(obj_setattr, .{ .doc = "Set attribute on object" }),
    .obj_callmethod0 = py.function(obj_callmethod0, .{ .doc = "Call method with no args" }),
    .obj_callmethod1 = py.function(obj_callmethod1, .{ .doc = "Call method with one arg" }),
    .obj_is_callable = py.function(obj_is_callable, .{ .doc = "Check if object is callable" }),
    .obj_is_none = py.function(obj_is_none, .{ .doc = "Check if object is None" }),

    // Type checking
    .is_unicode = py.function(is_unicode, .{ .doc = "Check if object is unicode string" }),
    .is_bytes = py.function(is_bytes, .{ .doc = "Check if object is bytes" }),
    .is_bool = py.function(is_bool, .{ .doc = "Check if object is bool" }),
    .is_int = py.function(is_int, .{ .doc = "Check if object is int" }),
    .is_float = py.function(is_float, .{ .doc = "Check if object is float" }),
    .is_list = py.function(is_list, .{ .doc = "Check if object is list" }),
    .is_tuple = py.function(is_tuple, .{ .doc = "Check if object is tuple" }),
    .is_dict = py.function(is_dict, .{ .doc = "Check if object is dict" }),

    // Error handling - each exception type
    .raise_type_error = py.function(raise_type_error, .{ .doc = "Raise TypeError" }),
    .raise_value_error = py.function(raise_value_error, .{ .doc = "Raise ValueError" }),
    .raise_runtime_error = py.function(raise_runtime_error, .{ .doc = "Raise RuntimeError" }),
    .raise_zero_division = py.function(raise_zero_division, .{ .doc = "Raise ZeroDivisionError" }),
    .raise_overflow_error = py.function(raise_overflow_error, .{ .doc = "Raise OverflowError" }),
    .raise_attribute_error = py.function(raise_attribute_error, .{ .doc = "Raise AttributeError" }),
    .raise_index_error = py.function(raise_index_error, .{ .doc = "Raise IndexError" }),
    .raise_key_error = py.function(raise_key_error, .{ .doc = "Raise KeyError" }),
    .raise_memory_error = py.function(raise_memory_error, .{ .doc = "Raise MemoryError" }),
    .divide = py.function(divide, .{ .doc = "Divide two floats, raises ZeroDivisionError if b=0" }),
    .raise_mapped = py.function(raise_mapped, .{ .doc = "Test error mapping" }),
    .get_del_count = py.function(get_del_count, .{ .doc = "Return __del__ call count" }),
    .reset_del_count = py.function(reset_del_count, .{ .doc = "Reset __del__ call count" }),

    // Class wrapper checks
    .baseadder_expect = py.function(
        baseadder_expect,
        .{ .doc = "Check BaseAdder.fromPy on object", .args = &.{"obj"} },
    ),
    .baseadder_expect_exact = py.function(
        baseadder_expect_exact,
        .{ .doc = "Check BaseAdder.fromPyExact on object", .args = &.{"obj"} },
    ),
    .payloadbox_expect = py.function(
        payloadbox_expect,
        .{ .doc = "Check PayloadBox.fromPy on object", .args = &.{"obj"} },
    ),
    .payloadbox_payload_from = py.function(
        payloadbox_payload_from,
        .{ .doc = "Return payload value via PayloadBox.payloadFrom", .args = &.{"obj"} },
    ),

    // Python interop
    .import_math_pi = py.function(import_math_pi, .{ .doc = "Import math.pi" }),
    .call_upper = py.function(call_upper, .{ .doc = "Call .upper() on a string" }),
}).withAttrs(.{
    .VERSION = MODULE_VERSION,
    .DEFAULT_SIZE = DEFAULT_SIZE,
    .ENABLED = ENABLED,
    .OPTIONAL = OPTIONAL_NAME,
    .PI = PI,
}).withTypes(.{
    .BaseAdder = BaseAdder,
    .Adder = Adder,
    .Counter = Counter,
    .PayloadBox = PayloadBox,
    .MethodKinds = MethodKinds,
    .CallableAdder = CallableAdder,
    .DunderBasics = DunderBasics,
    .SubscriptBox = SubscriptBox,
    .ComparePoint = ComparePoint,
    .NumberBox = NumberBox,
    .ContextLock = ContextLock,
    .IterCounter = IterCounter,
    .ContainsBox = ContainsBox,
    .InitBox = InitBox,
    .AttrAccessBox = AttrAccessBox,
    .AttrSetBox = AttrSetBox,
    .DescriptorBox = DescriptorBox,
    .NewBox = NewBox,
    .DelBox = DelBox,
});

const MODULE_VERSION: []const u8 = "0.1.0";
const DEFAULT_SIZE: i64 = 256;
const ENABLED: bool = true;
const OPTIONAL_NAME: ?[]const u8 = null;
const PI: f64 = 3.14159;
var del_count: usize = 0;

// ============================================================================
// Basic Function Binding
// ============================================================================

fn add(a: i64, b: i64) i64 {
    return a + b;
}

fn add3(a: i64, b: i64, c: ?i64) i64 {
    return a + b + (c orelse 0);
}

fn add_named(a: i64, b: i64, c: ?i64) i64 {
    return a + b + (c orelse 0);
}

// ============================================================================
// Type Conversions
// ============================================================================

fn identity_int(x: i64) i64 {
    return x;
}

fn identity_float(x: f64) f64 {
    return x;
}

fn identity_bool(x: bool) bool {
    return x;
}

fn identity_str(x: []const u8) []const u8 {
    return x;
}

fn identity_bytes(x: py.Bytes) py.Bytes {
    return x;
}

fn identity_optional(x: ?[]const u8) ?[]const u8 {
    return x;
}

fn identity_object(x: py.Object) py.Object {
    return x.incref();
}

fn int64_or_uint64(value: py.Object) !py.Tuple {
    const parsed = try py.Long.fromObject(value);
    var result: py.Tuple = try .init(2);
    errdefer result.deinit();
    const is_signed = switch (parsed) {
        .signed => true,
        .unsigned => false,
    };
    try result.set(0, is_signed);
    try switch (parsed) {
        .signed => |v| result.set(1, v),
        .unsigned => |v| result.set(1, v),
    };
    return result;
}

fn mask_u32(value: py.Object) ?u32 {
    const masked = py.Long.unsignedMask(value) catch return null;
    return @truncate(masked);
}

fn mask_u64(value: py.Object) ?u64 {
    return py.Long.unsignedMask(value) catch return null;
}

// TODO: BigInt/Int disabled for now; revisit once allocator boundary is explicit.
// fn bigint_to_string(value: py.BigInt) !py.Object {
//     var big = value;
//     defer big.deinit();
//     const text = big.value.toConst().toStringAlloc(py.allocator, 10, .lower) catch {
//         return py.raise(.MemoryError, "out of memory");
//     };
//     defer py.allocator.free(text);
//     return .from(text);
// }
//
// fn bigint_roundtrip(value: py.BigInt) !py.Object {
//     var big = value;
//     defer big.deinit();
//     return big.toObject(py.allocator);
// }
//
// fn int_roundtrip(value: py.Int) !py.Object {
//     var int_value = value;
//     defer int_value.deinit();
//     return int_value.toObject();
// }

// ============================================================================
// Bytes Operations
// ============================================================================

fn bytes_len(data: py.Bytes) !usize {
    return data.len();
}

fn bytes_slice(data: py.Bytes, start: i64, end: i64) !py.Bytes {
    const slice = try data.slice();
    const s: usize = @intCast(start);
    const e: usize = @intCast(end);
    if (s > slice.len or e > slice.len or s > e) {
        return py.raise(.IndexError, "slice out of bounds");
    }
    return .fromSlice(slice[s..e]);
}

fn bytes_create(value: []const u8) !py.Bytes {
    return .fromSlice(value);
}

fn buffer_len(data: py.Buffer) !usize {
    var buffer = data;
    defer buffer.release();
    return buffer.len();
}

fn buffer_sum(data: py.Buffer) !u64 {
    var buffer = data;
    defer buffer.release();
    const slice = buffer.slice();
    var total: u64 = 0;
    for (slice) |byte| total += byte;
    return total;
}

fn bytes_view_len(data: py.BytesView) !usize {
    var view = data;
    defer view.deinit();
    return view.len();
}

fn bytes_view_sum(data: py.BytesView) !u64 {
    var view = data;
    defer view.deinit();
    const slice = try view.slice();
    var total: u64 = 0;
    for (slice) |byte| total += byte;
    return total;
}

fn bytes_view_is_buffer(data: py.BytesView) bool {
    var view = data;
    defer view.deinit();
    return view.isBuffer();
}

fn io_read(stream: py.Object, max_len: i64) !py.Bytes {
    const gpa = py.allocator;
    var reader: py.IoReader = try .initUnbuffered(stream);
    defer reader.deinit();

    if (max_len == 0) return .fromSlice(&.{});

    if (max_len < 0) {
        var buf: std.ArrayList(u8) = .empty;
        defer buf.deinit(gpa);

        try reader.appendRemainingUnlimited(gpa, &buf);
        return .fromSlice(buf.items);
    }

    const want: usize = @intCast(max_len);
    var buf: [1024]u8 = undefined;
    if (want <= buf.len) {
        const data = try reader.readAll(buf[0..want]);
        return .fromSlice(data);
    }

    var result = try reader.readAllAlloc(gpa, want);
    defer result.deinit(gpa);
    return .fromSlice(result.slice());
}

fn write_all(stream: py.Object, data: py.BytesView) !usize {
    var view = data;
    defer view.deinit();
    const slice = try view.slice();

    var writer: py.IoWriter = try .initUnbuffered(stream);
    defer writer.deinit();
    try writer.writeAll(slice);
    return slice.len;
}

// ============================================================================
// List Operations
// ============================================================================

fn list_len(list: py.List) !usize {
    return list.len();
}

fn list_get(list: py.List, index: i64) !py.Object {
    const i: usize = @intCast(index);
    const item = try list.get(i);
    return item.incref();
}

fn list_sum(values: py.List) !i64 {
    const count = try values.len();
    var total: i64 = 0;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const item = try values.get(i);
        const value = try item.as(i64);
        total += value;
    }
    return total;
}

fn list_create(a: i64, b: i64, c: i64) !py.List {
    var list: py.List = try .init(3);
    errdefer list.deinit();
    try list.set(0, a);
    try list.set(1, b);
    try list.set(2, c);
    return list;
}

fn list_append(list: py.List, value: i64) !py.List {
    try list.append(value);
    return list;
}

fn list_set(list: py.List, index: i64, value: i64) !py.List {
    const i: usize = @intCast(index);
    try list.set(i, value);
    return list;
}

// ============================================================================
// Dict Operations
// ============================================================================

fn dict_len(dict: py.Dict) !usize {
    return dict.len();
}

fn dict_get(dict: py.Dict, key: []const u8) !?i64 {
    const item = try dict.getItem(key);
    if (item == null) return null;
    const value = try item.?.as(i64);
    return @as(?i64, value);
}

fn dict_create(key: []const u8, value: i64) !py.Dict {
    var dict: py.Dict = try .init();
    errdefer dict.deinit();
    try dict.setItem(key, value);
    return dict;
}

fn dict_set(dict: py.Dict, key: []const u8, value: i64) !py.Dict {
    try dict.setItem(key, value);
    return dict;
}

fn dict_keys(dict: py.Dict) !py.List {
    const size = try dict.len();
    var list: py.List = try .init(size);
    errdefer list.deinit();
    var iter: py.DictIter = try .fromObject(dict.obj);
    var i: usize = 0;
    while (iter.next()) |entry| {
        try list.set(i, entry.key.incref());
        i += 1;
    }
    return list;
}

// ============================================================================
// Tuple Operations
// ============================================================================

fn tuple_len(tuple: py.Tuple) !usize {
    return tuple.len();
}

fn tuple_get(tuple: py.Tuple, index: i64) !py.Object {
    const i: usize = @intCast(index);
    const item = try tuple.get(i);
    return item.incref();
}

fn tuple_create(a: i64, b: i64) !py.Object {
    const values: [2]i64 = .{ a, b };
    const tuple: py.Tuple = try .fromSlice(i64, &values);
    return tuple.obj;
}

fn tuple_create_manual(a: i64, b: i64) !py.Object {
    var tuple: py.Tuple = try .init(2);
    errdefer tuple.deinit();
    try tuple.set(0, a);
    try tuple.set(1, b);
    return tuple.obj;
}

// ============================================================================
// Object Operations
// ============================================================================

fn obj_call0(obj: py.Object) !py.Object {
    return obj.call(.{});
}

fn obj_call1(obj: py.Object, arg: py.Object) !py.Object {
    return obj.call(.{arg});
}

fn obj_call2(obj: py.Object, arg1: py.Object, arg2: py.Object) !py.Object {
    return obj.call(.{ arg1, arg2 });
}

fn obj_getattr(obj: py.Object, name: [:0]const u8) !py.Object {
    return obj.getAttr(name);
}

fn obj_setattr(obj: py.Object, name: [:0]const u8, value: py.Object) !bool {
    try obj.setAttr(name, value);
    return true;
}

fn obj_callmethod0(obj: py.Object, name: [:0]const u8) !py.Object {
    return obj.callMethod(name, .{});
}

fn obj_callmethod1(obj: py.Object, name: [:0]const u8, arg: py.Object) !py.Object {
    return obj.callMethod(name, .{arg});
}

fn obj_is_callable(obj: py.Object) bool {
    return obj.isCallable();
}

fn obj_is_none(obj: py.Object) bool {
    return obj.isNone();
}

// ============================================================================
// Type Checking
// ============================================================================

fn is_unicode(obj: py.Object) bool {
    return obj.isUnicode();
}

fn is_bytes(obj: py.Object) bool {
    return obj.isBytes();
}

fn is_bool(obj: py.Object) bool {
    return obj.isBool();
}

fn is_int(obj: py.Object) bool {
    return obj.isLong();
}

fn is_float(obj: py.Object) bool {
    return obj.isFloat();
}

fn is_list(obj: py.Object) bool {
    return obj.isList();
}

fn is_tuple(obj: py.Object) bool {
    return obj.isTuple();
}

fn is_dict(obj: py.Object) bool {
    return obj.isDict();
}

// ============================================================================
// Error Handling
// ============================================================================

fn raise_type_error() py.PyError {
    return py.raise(.TypeError, "test type error");
}

fn raise_value_error() py.PyError {
    return py.raise(.ValueError, "test value error");
}

fn raise_runtime_error() py.PyError {
    return py.raise(.RuntimeError, "test runtime error");
}

fn raise_zero_division() py.PyError {
    return py.raise(.ZeroDivisionError, "test zero division");
}

fn raise_overflow_error() py.PyError {
    return py.raise(.OverflowError, "test overflow error");
}

fn raise_attribute_error() py.PyError {
    return py.raise(.AttributeError, "test attribute error");
}

fn raise_index_error() py.PyError {
    return py.raise(.IndexError, "test index error");
}

fn raise_key_error() py.PyError {
    return py.raise(.KeyError, "test key error");
}

fn raise_memory_error() py.PyError {
    return py.raise(.MemoryError, "test memory error");
}

const DivideError = error{DivideByZero};

fn divide(a: f64, b: f64) !f64 {
    return divideInner(a, b) catch |err| {
        return py.raiseError(err, &[_]py.ErrorMap{
            .{ .err = error.DivideByZero, .kind = .ZeroDivisionError, .msg = "division by zero" },
        });
    };
}

fn divideInner(a: f64, b: f64) DivideError!f64 {
    if (b == 0) return error.DivideByZero;
    return a / b;
}

const MappedError = error{ NotFound, InvalidInput };

fn raise_mapped(kind: []const u8) py.PyError {
    const err: MappedError = if (std.mem.eql(u8, kind, "not_found"))
        error.NotFound
    else if (std.mem.eql(u8, kind, "invalid"))
        error.InvalidInput
    else
        return py.raise(.ValueError, "unknown error kind");

    return py.raiseError(err, &[_]py.ErrorMap{
        .{ .err = error.NotFound, .kind = .KeyError, .msg = "item not found" },
        .{ .err = error.InvalidInput, .kind = .ValueError, .msg = "invalid input" },
    });
}

fn get_del_count() usize {
    return del_count;
}

fn reset_del_count() void {
    del_count = 0;
}

// ============================================================================
// Python Interop
// ============================================================================

fn import_math_pi() !f64 {
    const math = try py.importModule("math");
    defer math.deinit();
    const pi_obj = try math.getAttr("pi");
    defer pi_obj.deinit();
    return pi_obj.as(f64);
}

fn call_upper(value: []const u8) ![]const u8 {
    const obj: py.Object = try .from(value);
    defer obj.deinit();
    const out = try obj.callMethod("upper", .{});
    defer out.deinit();
    return out.as([]const u8);
}

// ============================================================================
// Classes
// ============================================================================

// Simple class for basic method testing
const BaseAdder = py.baseclass("BaseAdder", "Base adder class for subclassing tests.", .{
    .add = py.method(adder_add, .{ .doc = "Add two integers" }),
    .identity = py.method(adder_identity, .{ .doc = "Return self" }),
});

const Adder = py.class("Adder", "Simple adder class for testing.", .{
    .add = py.method(adder_add, .{ .doc = "Add two integers" }),
    .identity = py.method(adder_identity, .{ .doc = "Return self" }),
});

fn adder_add(_: py.Object, a: i64, b: i64) i64 {
    return a + b;
}

fn adder_identity(self: py.Object) py.Object {
    return self.incref();
}

fn baseadder_expect(obj: py.Object) !bool {
    _ = try BaseAdder.fromPy(obj);
    return true;
}

fn baseadder_expect_exact(obj: py.Object) !bool {
    _ = try BaseAdder.fromPyExact(obj);
    return true;
}

// Class with mutable state via attributes
const Counter = py.class("Counter", "Counter class with mutable state.", .{
    .get = py.method(counter_get, .{ .doc = "Get current count" }),
    .increment = py.method(counter_increment, .{ .doc = "Increment counter" }),
    .add = py.method(counter_add, .{ .doc = "Add value to counter" }),
    .reset = py.method(counter_reset, .{ .doc = "Reset counter to zero" }),
});

fn counter_get(self: py.Object) !i64 {
    const count_obj = try self.getAttrOrNull("_count") orelse {
        const zero: py.Object = try .from(@as(i64, 0));
        try self.setAttr("_count", zero);
        return 0;
    };
    defer count_obj.deinit();
    return count_obj.as(i64);
}

fn counter_increment(self: py.Object) !i64 {
    const current = counter_get(self) catch return error.PythonError;
    const new_val = current + 1;
    const new_obj: py.Object = try .from(new_val);
    try self.setAttr("_count", new_obj);
    return new_val;
}

fn counter_add(self: py.Object, value: i64) !i64 {
    const current = counter_get(self) catch return error.PythonError;
    const new_val = current + value;
    const new_obj: py.Object = try .from(new_val);
    try self.setAttr("_count", new_obj);
    return new_val;
}

fn counter_reset(self: py.Object) !void {
    const zero: py.Object = try .from(@as(i64, 0));
    try self.setAttr("_count", zero);
}

const PayloadState = struct {
    value: i64,
};

const PayloadBox = py.class("PayloadBox", "Class with native payload storage.", .{
    .__init__ = py.method(payloadbox_init, .{ .doc = "Initialize payload value", .args = &.{"value"} }),
    .get = py.method(payloadbox_get, .{ .doc = "Return payload value" }),
    .set = py.method(payloadbox_set, .{ .doc = "Set payload value", .args = &.{"value"} }),
}).withPayload(PayloadState);

fn payloadbox_init(self: py.Object, value: i64) !void {
    const box = try PayloadBox.fromPy(self);
    box.payload().* = .{ .value = value };
}

fn payloadbox_get(self: py.Object) !i64 {
    const box = try PayloadBox.fromPy(self);
    return box.payload().value;
}

fn payloadbox_set(self: py.Object, value: i64) !void {
    const box = try PayloadBox.fromPy(self);
    box.payload().value = value;
}

fn payloadbox_expect(obj: py.Object) !bool {
    _ = try PayloadBox.fromPy(obj);
    return true;
}

fn payloadbox_payload_from(obj: py.Object) !i64 {
    const state = try PayloadBox.payloadFrom(obj);
    return state.value;
}

// Class for classmethod/staticmethod testing
const MethodKinds = py.class("MethodKinds", "Class for classmethod/staticmethod testing.", .{
    .class_name = py.classmethod(methodkinds_class_name, .{ .doc = "Return class name" }),
    .sum = py.staticmethod(methodkinds_sum, .{ .doc = "Add two integers" }),
});

fn methodkinds_class_name(cls: py.Object) ![]const u8 {
    const name_obj = try cls.getAttr("__name__");
    defer name_obj.deinit();
    return name_obj.as([]const u8);
}

fn methodkinds_sum(a: i64, b: i64) i64 {
    return a + b;
}

// Callable class for __call__ testing
const CallableAdder = py.class("CallableAdder", "Callable class for __call__ testing.", .{
    .__call__ = py.method(callable_add, .{ .doc = "Add value with optional extra", .args = &.{ "value", "extra" } }),
});

fn callable_add(_: py.Object, value: i64, extra: ?i64) i64 {
    return value + (extra orelse 0);
}

// Dunder basics for __repr__/__str__/__len__/__hash__/__bool__
const DunderBasics = py.class("DunderBasics", "Class for dunder basics testing.", .{
    .__repr__ = py.method(dunder_repr, .{ .doc = "Return repr string" }),
    .__str__ = py.method(dunder_str, .{ .doc = "Return display string" }),
    .__len__ = py.method(dunder_len, .{ .doc = "Return length value" }),
    .__hash__ = py.method(dunder_hash, .{ .doc = "Return hash value" }),
    .__bool__ = py.method(dunder_bool, .{ .doc = "Return truthiness" }),
});

fn dunder_value(self: py.Object) !i64 {
    const value_obj = try self.getAttrOrNull("value") orelse return 0;

    defer value_obj.deinit();
    return value_obj.as(i64);
}

fn dunder_repr(self: py.Object) !py.Object {
    const value: i64 = try dunder_value(self);
    var buffer: [64]u8 = undefined;
    const text = std.fmt.bufPrint(&buffer, "DunderBasics({d})", .{value}) catch {
        return py.raise(.RuntimeError, "formatting failed");
    };
    return .from(text);
}

fn dunder_str(self: py.Object) !py.Object {
    const value: i64 = try dunder_value(self);
    var buffer: [80]u8 = undefined;
    const text = std.fmt.bufPrint(&buffer, "DunderBasics value={d}", .{value}) catch {
        return py.raise(.RuntimeError, "formatting failed");
    };
    return .from(text);
}

fn dunder_len(self: py.Object) !i64 {
    const value: i64 = try dunder_value(self);
    if (value < 0) {
        return py.raise(.ValueError, "length must be non-negative");
    }
    return value;
}

fn dunder_hash(self: py.Object) !i64 {
    return dunder_value(self);
}

fn dunder_bool(self: py.Object) !bool {
    const value: i64 = try dunder_value(self);
    return value != 0;
}

// Subscript operations
const SubscriptBox = py.class("SubscriptBox", "Class for subscript testing.", .{
    .__getitem__ = py.method(subscript_get, .{ .doc = "Get item by key" }),
    .__setitem__ = py.method(subscript_set, .{ .doc = "Set item by key" }),
    .__delitem__ = py.method(subscript_del, .{ .doc = "Delete item by key" }),
});

fn subscript_get(self: py.Object, key: []const u8) !i64 {
    const store_obj = try self.getAttrOrNull("_store") orelse {
        return py.raise(.KeyError, "missing key");
    };
    defer store_obj.deinit();
    const store: py.Dict = try .fromObject(store_obj);
    const item = try store.getItem(key);
    if (item == null) return py.raise(.KeyError, "missing key");
    return item.?.as(i64);
}

fn subscript_set(self: py.Object, key: []const u8, value: i64) !void {
    const store_obj = try self.getAttrOrNull("_store") orelse {
        var dict: py.Dict = try .init();
        defer dict.deinit();
        const dict_ref = dict.obj.incref();
        try self.setAttr("_store", dict_ref);
        return dict.setItem(key, value);
    };
    defer store_obj.deinit();
    const store: py.Dict = try .fromObject(store_obj);
    try store.setItem(key, value);
}

fn subscript_del(self: py.Object, key: []const u8) !void {
    const store_obj = try self.getAttrOrNull("_store") orelse {
        return py.raise(.KeyError, "missing key");
    };
    defer store_obj.deinit();
    const result = try store_obj.callMethod("__delitem__", .{key});
    result.deinit();
}

// Comparison operators
const ComparePoint = py.class("ComparePoint", "Class for comparison operator testing.", .{
    .__eq__ = py.method(point_eq, .{ .doc = "Compare equality" }),
    .__lt__ = py.method(point_lt, .{ .doc = "Compare less-than" }),
    .__le__ = py.method(point_le, .{ .doc = "Compare less-or-equal" }),
    .__gt__ = py.method(point_gt, .{ .doc = "Compare greater-than" }),
    .__ge__ = py.method(point_ge, .{ .doc = "Compare greater-or-equal" }),
    .__ne__ = py.method(point_ne, .{ .doc = "Compare not-equal" }),
});

fn point_value(obj: py.Object) !i64 {
    const value_obj = try obj.getAttr("value");
    defer value_obj.deinit();
    return value_obj.as(i64);
}

fn point_eq(self: py.Object, other: py.Object) !bool {
    return (try point_value(self)) == (try point_value(other));
}

fn point_lt(self: py.Object, other: py.Object) !bool {
    return (try point_value(self)) < (try point_value(other));
}

fn point_le(self: py.Object, other: py.Object) !bool {
    return (try point_value(self)) <= (try point_value(other));
}

fn point_gt(self: py.Object, other: py.Object) !bool {
    return (try point_value(self)) > (try point_value(other));
}

fn point_ge(self: py.Object, other: py.Object) !bool {
    return (try point_value(self)) >= (try point_value(other));
}

fn point_ne(self: py.Object, other: py.Object) !bool {
    return (try point_value(self)) != (try point_value(other));
}

// Numeric operators
const NumberBox = py.class("NumberBox", "Class for numeric operator testing.", .{
    .__add__ = py.method(number_add, .{ .doc = "Add two boxes" }),
    .__sub__ = py.method(number_sub, .{ .doc = "Subtract two boxes" }),
    .__mul__ = py.method(number_mul, .{ .doc = "Multiply by a factor" }),
    .__truediv__ = py.method(number_truediv, .{ .doc = "Divide by a factor" }),
    .__floordiv__ = py.method(number_floordiv, .{ .doc = "Floor divide by a factor" }),
    .__mod__ = py.method(number_mod, .{ .doc = "Modulo by a factor" }),
    .__pow__ = py.method(number_pow, .{ .doc = "Raise to a power" }),
    .__divmod__ = py.method(number_divmod, .{ .doc = "Divmod with a divisor" }),
    .__matmul__ = py.method(number_matmul, .{ .doc = "Matrix multiply" }),
    .__neg__ = py.method(number_neg, .{ .doc = "Negate value" }),
    .__pos__ = py.method(number_pos, .{ .doc = "Positive value" }),
    .__abs__ = py.method(number_abs, .{ .doc = "Absolute value" }),
    .__invert__ = py.method(number_invert, .{ .doc = "Bitwise invert" }),
    .__and__ = py.method(number_and, .{ .doc = "Bitwise and" }),
    .__or__ = py.method(number_or, .{ .doc = "Bitwise or" }),
    .__xor__ = py.method(number_xor, .{ .doc = "Bitwise xor" }),
    .__lshift__ = py.method(number_lshift, .{ .doc = "Left shift" }),
    .__rshift__ = py.method(number_rshift, .{ .doc = "Right shift" }),
    .__int__ = py.method(number_int, .{ .doc = "Convert to int" }),
    .__float__ = py.method(number_float, .{ .doc = "Convert to float" }),
    .__index__ = py.method(number_index, .{ .doc = "Convert to index" }),
    .__iadd__ = py.method(number_iadd, .{ .doc = "In-place add" }),
    .__isub__ = py.method(number_isub, .{ .doc = "In-place subtract" }),
    .__imul__ = py.method(number_imul, .{ .doc = "In-place multiply" }),
    .__itruediv__ = py.method(number_itruediv, .{ .doc = "In-place true divide" }),
    .__ifloordiv__ = py.method(number_ifloordiv, .{ .doc = "In-place floor divide" }),
    .__imod__ = py.method(number_imod, .{ .doc = "In-place modulo" }),
    .__ipow__ = py.method(number_ipow, .{ .doc = "In-place power" }),
    .__iand__ = py.method(number_iand, .{ .doc = "In-place and" }),
    .__ior__ = py.method(number_ior, .{ .doc = "In-place or" }),
    .__ixor__ = py.method(number_ixor, .{ .doc = "In-place xor" }),
    .__ilshift__ = py.method(number_ilshift, .{ .doc = "In-place left shift" }),
    .__irshift__ = py.method(number_irshift, .{ .doc = "In-place right shift" }),
    .__imatmul__ = py.method(number_imatmul, .{ .doc = "In-place matrix multiply" }),
});

fn number_value(obj: py.Object) !i64 {
    const value_obj = try obj.getAttr("value");
    defer value_obj.deinit();
    return value_obj.as(i64);
}

fn number_add(self: py.Object, other: py.Object) !i64 {
    return (try number_value(self)) + (try number_value(other));
}

fn number_sub(self: py.Object, other: py.Object) !i64 {
    return (try number_value(self)) - (try number_value(other));
}

fn number_mul(self: py.Object, factor: i64) !i64 {
    return (try number_value(self)) * factor;
}

fn number_truediv(self: py.Object, divisor: f64) !f64 {
    if (divisor == 0) return py.raise(.ZeroDivisionError, "division by zero");
    return @as(f64, @floatFromInt(try number_value(self))) / divisor;
}

fn number_floordiv(self: py.Object, divisor: i64) !i64 {
    if (divisor == 0) return py.raise(.ZeroDivisionError, "division by zero");
    return @divFloor(try number_value(self), divisor);
}

fn number_mod(self: py.Object, divisor: i64) !i64 {
    if (divisor == 0) return py.raise(.ZeroDivisionError, "division by zero");
    return @mod(try number_value(self), divisor);
}

fn number_pow(self: py.Object, exponent: i64, mod: ?i64) !i64 {
    if (exponent < 0) return py.raise(.ValueError, "negative exponent");
    var result: i64 = 1;
    var base: i64 = try number_value(self);
    var exp: i64 = exponent;

    if (mod) |modulus| {
        if (modulus == 0) return py.raise(.ZeroDivisionError, "pow() modulus is zero");
        base = @mod(base, modulus);
        result = @mod(result, modulus);
        while (exp > 0) : (exp >>= 1) {
            if ((exp & 1) != 0) result = @mod(result * base, modulus);
            base = @mod(base * base, modulus);
        }
        return result;
    }

    while (exp > 0) : (exp >>= 1) {
        if ((exp & 1) != 0) result *= base;
        base *= base;
    }
    return result;
}

fn number_divmod(self: py.Object, divisor: i64) !py.Tuple {
    if (divisor == 0) return py.raise(.ZeroDivisionError, "division by zero");
    const value: i64 = try number_value(self);
    const quotient: i64 = @divFloor(value, divisor);
    const remainder: i64 = @mod(value, divisor);
    var out: py.Tuple = try .init(2);
    errdefer out.deinit();
    try out.set(0, quotient);
    try out.set(1, remainder);
    return out;
}

fn number_matmul(self: py.Object, other: py.Object) !i64 {
    return (try number_value(self)) * (try number_value(other));
}

fn number_neg(self: py.Object) !i64 {
    return -(try number_value(self));
}

fn number_pos(self: py.Object) !i64 {
    return number_value(self);
}

fn number_abs(self: py.Object) !i64 {
    const value: i64 = try number_value(self);
    if (value == std.math.minInt(i64)) {
        return py.raise(.OverflowError, "absolute value overflow");
    }
    return if (value < 0) -value else value;
}

fn number_invert(self: py.Object) !i64 {
    return ~(try number_value(self));
}

fn number_and(self: py.Object, other: i64) !i64 {
    return (try number_value(self)) & other;
}

fn number_or(self: py.Object, other: i64) !i64 {
    return (try number_value(self)) | other;
}

fn number_xor(self: py.Object, other: i64) !i64 {
    return (try number_value(self)) ^ other;
}

fn number_lshift(self: py.Object, amount: i64) !i64 {
    if (amount < 0) return py.raise(.ValueError, "negative shift count");
    if (amount > 63) return py.raise(.OverflowError, "shift count out of range");
    const shift: u6 = @intCast(amount);
    return (try number_value(self)) << shift;
}

fn number_rshift(self: py.Object, amount: i64) !i64 {
    if (amount < 0) return py.raise(.ValueError, "negative shift count");
    if (amount > 63) return py.raise(.OverflowError, "shift count out of range");
    const shift: u6 = @intCast(amount);
    return (try number_value(self)) >> shift;
}

fn number_int(self: py.Object) !i64 {
    return number_value(self);
}

fn number_float(self: py.Object) !f64 {
    return @as(f64, @floatFromInt(try number_value(self)));
}

fn number_index(self: py.Object) !i64 {
    return number_value(self);
}

fn set_number_value(self: py.Object, value: i64) !void {
    try self.setAttr("value", value);
}

fn number_iadd(self: py.Object, other: i64) !py.Object {
    const next: i64 = (try number_value(self)) + other;
    try set_number_value(self, next);
    return self.incref();
}

fn number_isub(self: py.Object, other: i64) !py.Object {
    const next: i64 = (try number_value(self)) - other;
    try set_number_value(self, next);
    return self.incref();
}

fn number_imul(self: py.Object, other: i64) !py.Object {
    const next: i64 = (try number_value(self)) * other;
    try set_number_value(self, next);
    return self.incref();
}

fn number_itruediv(self: py.Object, other: i64) !py.Object {
    if (other == 0) return py.raise(.ZeroDivisionError, "division by zero");
    const next: i64 = @divTrunc(try number_value(self), other);
    try set_number_value(self, next);
    return self.incref();
}

fn number_ifloordiv(self: py.Object, other: i64) !py.Object {
    if (other == 0) return py.raise(.ZeroDivisionError, "division by zero");
    const next: i64 = @divFloor(try number_value(self), other);
    try set_number_value(self, next);
    return self.incref();
}

fn number_imod(self: py.Object, other: i64) !py.Object {
    if (other == 0) return py.raise(.ZeroDivisionError, "division by zero");
    const next: i64 = @mod(try number_value(self), other);
    try set_number_value(self, next);
    return self.incref();
}

fn number_ipow(self: py.Object, exponent: i64, mod: ?i64) !py.Object {
    const next: i64 = try number_pow(self, exponent, mod);
    try set_number_value(self, next);
    return self.incref();
}

fn number_iand(self: py.Object, other: i64) !py.Object {
    const next: i64 = (try number_value(self)) & other;
    try set_number_value(self, next);
    return self.incref();
}

fn number_ior(self: py.Object, other: i64) !py.Object {
    const next: i64 = (try number_value(self)) | other;
    try set_number_value(self, next);
    return self.incref();
}

fn number_ixor(self: py.Object, other: i64) !py.Object {
    const next: i64 = (try number_value(self)) ^ other;
    try set_number_value(self, next);
    return self.incref();
}

fn number_ilshift(self: py.Object, amount: i64) !py.Object {
    const next: i64 = try number_lshift(self, amount);
    try set_number_value(self, next);
    return self.incref();
}

fn number_irshift(self: py.Object, amount: i64) !py.Object {
    const next: i64 = try number_rshift(self, amount);
    try set_number_value(self, next);
    return self.incref();
}

fn number_imatmul(self: py.Object, other: py.Object) !py.Object {
    const next: i64 = try number_matmul(self, other);
    try set_number_value(self, next);
    return self.incref();
}

// Context manager methods
const ContextLock = py.class("ContextLock", "Class for context manager testing.", .{
    .__enter__ = py.method(context_enter, .{ .doc = "Enter context" }),
    .__exit__ = py.method(context_exit, .{ .doc = "Exit context" }),
});

fn context_enter(self: py.Object) !py.Object {
    try self.setAttr("entered", true);
    return self.incref();
}

fn context_exit(
    self: py.Object,
    _: ?py.Object,
    _: ?py.Object,
    _: ?py.Object,
) !bool {
    try self.setAttr("exited", true);
    return false;
}

// Iterator methods
const IterCounter = py.class("IterCounter", "Class for iterator slot testing.", .{
    .__iter__ = py.method(itercounter_iter, .{ .doc = "Return iterator" }),
    .__next__ = py.method(itercounter_next, .{ .doc = "Return next value" }),
});

fn itercounter_iter(self: py.Object) !py.Object {
    return self.incref();
}

fn itercounter_next(self: py.Object) !i64 {
    const limit_obj = try self.getAttrOrNull("limit") orelse {
        return py.raise(.StopIteration, "iteration complete");
    };
    defer limit_obj.deinit();
    const limit: i64 = try limit_obj.as(i64);

    var current: i64 = 0;
    if (try self.getAttrOrNull("current")) |current_obj| {
        defer current_obj.deinit();
        current = try current_obj.as(i64);
    }

    if (current >= limit) return py.raise(.StopIteration, "iteration complete");

    try self.setAttr("current", current + 1);
    return current;
}

// Contains methods
const ContainsBox = py.class("ContainsBox", "Class for __contains__ testing.", .{
    .__contains__ = py.method(contains_check, .{ .doc = "Check membership" }),
});

fn contains_check(self: py.Object, value: i64) !bool {
    const items_obj = try self.getAttrOrNull("items") orelse return false;
    defer items_obj.deinit();

    const items: py.List = try .fromObject(items_obj);
    const count: usize = try items.len();
    for (0..count) |i| {
        const item = try items.get(i);
        const item_value: i64 = try item.as(i64);
        if (item_value == value) return true;
    }
    return false;
}

// __init__ methods
const InitBox = py.class("InitBox", "Class for __init__ slot testing.", .{
    .__init__ = py.method(initbox_init, .{ .doc = "Initialize with a value" }),
});

fn initbox_init(self: py.Object, value: i64) !void {
    try self.setAttr("value", value);
}

// Attribute access methods
const AttrAccessBox = py.class("AttrAccessBox", "Class for __getattribute__/__getattr__ testing.", .{
    .__getattribute__ = py.method(attr_getattribute, .{ .doc = "Custom attribute access" }),
    .__getattr__ = py.method(attr_getattr, .{ .doc = "Fallback attribute access" }),
});

fn attr_getattribute(self: py.Object, name: py.Object) !py.Object {
    const name_slice = try name.unicodeSlice();
    if (std.mem.eql(u8, name_slice, "shadowed")) {
        return .from("shadowed");
    }

    return self.genericGetAttr(name);
}

fn attr_getattr(_: py.Object, name: []const u8) !py.Object {
    var buffer: [64]u8 = undefined;
    const text = std.fmt.bufPrint(&buffer, "missing:{s}", .{name}) catch "missing";
    return .from(text);
}

const AttrSetBox = py.class("AttrSetBox", "Class for __setattr__/__delattr__ testing.", .{
    .__setattr__ = py.method(attr_setattr, .{ .doc = "Set attribute" }),
    .__delattr__ = py.method(attr_delattr, .{ .doc = "Delete attribute" }),
});

fn attr_setattr(self: py.Object, name: py.Object, value: py.Object) !void {
    try self.genericSetAttr(name, value);
}

fn attr_delattr(self: py.Object, name: py.Object) !void {
    try self.genericDelAttr(name);
}

// Descriptor methods
const DescriptorBox = py.class("DescriptorBox", "Class for __get__/__set__/__delete__ testing.", .{
    .__get__ = py.method(descriptor_get, .{ .doc = "Descriptor get" }),
    .__set__ = py.method(descriptor_set, .{ .doc = "Descriptor set" }),
    .__delete__ = py.method(descriptor_delete, .{ .doc = "Descriptor delete" }),
});

fn descriptor_get(self: py.Object, obj: ?py.Object, owner: ?py.Object) !py.Object {
    _ = owner;
    if (obj == null) return self.incref();
    if (try self.getAttrOrNull("_value")) |value_obj| return value_obj;
    return .from("unset");
}

fn descriptor_set(self: py.Object, _: py.Object, value: py.Object) !void {
    try self.setAttr("_value", value);
}

fn descriptor_delete(self: py.Object, _: py.Object) !void {
    const name_obj: py.Object = try .from("_value");
    defer name_obj.deinit();
    try self.genericDelAttr(name_obj);
}

// __new__ methods
const NewBox = py.class("NewBox", "Class for __new__ slot testing.", .{
    .__new__ = py.classmethod(newbox_new, .{ .doc = "Allocate and initialize instance", .args = &.{"value"} }),
});

fn newbox_new(cls: py.Object, value: i64) !py.Object {
    var instance = try cls.newInstance(null, null);
    errdefer instance.deinit();
    try instance.setAttr("value", value);
    return instance;
}

// __del__ methods
const DelBox = py.class("DelBox", "Class for __del__ slot testing.", .{
    .__del__ = py.method(delbox_del, .{ .doc = "Track finalizer calls" }),
});

fn delbox_del(_: py.Object) void {
    del_count += 1;
}
