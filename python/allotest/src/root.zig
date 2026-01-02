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

pub const MODULE = py.module("_allotest", "Alloconda test suite module.", .{
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
    .bigint_to_string = py.function(bigint_to_string, .{ .doc = "Convert bigint to decimal string" }),
    .bigint_roundtrip = py.function(bigint_roundtrip, .{ .doc = "Roundtrip bigint through py.BigInt" }),
    .int_roundtrip = py.function(int_roundtrip, .{ .doc = "Roundtrip int through py.Int" }),

    // Bytes operations
    .bytes_len = py.function(bytes_len, .{ .doc = "Return length of bytes" }),
    .bytes_slice = py.function(bytes_slice, .{ .doc = "Return slice of bytes as new bytes" }),
    .bytes_create = py.function(bytes_create, .{ .doc = "Create bytes from string" }),
    .buffer_len = py.function(buffer_len, .{ .doc = "Return length of buffer" }),
    .buffer_sum = py.function(buffer_sum, .{ .doc = "Return sum of buffer bytes" }),

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
    .Adder = Adder,
    .Counter = Counter,
    .MethodKinds = MethodKinds,
});

const MODULE_VERSION: []const u8 = "0.1.0";
const DEFAULT_SIZE: i64 = 256;
const ENABLED: bool = true;
const OPTIONAL_NAME: ?[]const u8 = null;
const PI: f64 = 3.14159;

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
    try result.set(bool, 0, is_signed);
    switch (parsed) {
        .signed => |v| {
            try result.set(@TypeOf(v), 1, v);
        },
        .unsigned => |v| {
            try result.set(@TypeOf(v), 1, v);
        },
    }
    return result;
}

fn mask_u32(value: py.Object) ?u32 {
    const masked = py.Long.unsignedMask(value) catch return null;
    return @truncate(masked);
}

fn mask_u64(value: py.Object) ?u64 {
    return py.Long.unsignedMask(value) catch return null;
}

fn bigint_to_string(value: py.BigInt) !py.Object {
    var big = value;
    defer big.deinit();
    const text = big.value.toConst().toStringAlloc(py.allocator, 10, .lower) catch {
        return py.raise(.MemoryError, "out of memory");
    };
    defer py.allocator.free(text);
    return .from([]const u8, text);
}

fn bigint_roundtrip(value: py.BigInt) !py.Object {
    var big = value;
    defer big.deinit();
    return big.toObject();
}

fn int_roundtrip(value: py.Int) !py.Object {
    var int_value = value;
    defer int_value.deinit();
    return int_value.toObject();
}

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
    try list.set(i64, 0, a);
    try list.set(i64, 1, b);
    try list.set(i64, 2, c);
    return list;
}

fn list_append(list: py.List, value: i64) !py.List {
    try list.append(i64, value);
    return list;
}

fn list_set(list: py.List, index: i64, value: i64) !py.List {
    const i: usize = @intCast(index);
    try list.set(i64, i, value);
    return list;
}

// ============================================================================
// Dict Operations
// ============================================================================

fn dict_len(dict: py.Dict) !usize {
    return dict.len();
}

fn dict_get(dict: py.Dict, key: []const u8) !?i64 {
    const item = try dict.getItem([]const u8, key);
    if (item == null) return null;
    const value = try item.?.as(i64);
    return @as(?i64, value);
}

fn dict_create(key: []const u8, value: i64) !py.Dict {
    var dict: py.Dict = try .init();
    errdefer dict.deinit();
    try dict.setItem([]const u8, key, i64, value);
    return dict;
}

fn dict_set(dict: py.Dict, key: []const u8, value: i64) !py.Dict {
    try dict.setItem([]const u8, key, i64, value);
    return dict;
}

fn dict_keys(dict: py.Dict) !py.List {
    const size = try dict.len();
    var list: py.List = try .init(size);
    errdefer list.deinit();
    var iter: py.DictIter = try .fromObject(dict.obj);
    var i: usize = 0;
    while (iter.next()) |entry| {
        try list.set(py.Object, i, entry.key.incref());
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
    try tuple.set(i64, 0, a);
    try tuple.set(i64, 1, b);
    return tuple.obj;
}

// ============================================================================
// Object Operations
// ============================================================================

fn obj_call0(obj: py.Object) !py.Object {
    return obj.call0();
}

fn obj_call1(obj: py.Object, arg: py.Object) !py.Object {
    return obj.call1(py.Object, arg);
}

fn obj_call2(obj: py.Object, arg1: py.Object, arg2: py.Object) !py.Object {
    return obj.call2(py.Object, arg1, py.Object, arg2);
}

fn obj_getattr(obj: py.Object, name: [:0]const u8) !py.Object {
    return obj.getAttr(name);
}

fn obj_setattr(obj: py.Object, name: [:0]const u8, value: py.Object) !bool {
    try obj.setAttr(name, py.Object, value);
    return true;
}

fn obj_callmethod0(obj: py.Object, name: [:0]const u8) !py.Object {
    return obj.callMethod0(name);
}

fn obj_callmethod1(obj: py.Object, name: [:0]const u8, arg: py.Object) !py.Object {
    return obj.callMethod1(name, py.Object, arg);
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
    const obj: py.Object = try .from([]const u8, value);
    defer obj.deinit();
    const out = try obj.callMethod0("upper");
    defer out.deinit();
    return out.as([]const u8);
}

// ============================================================================
// Classes
// ============================================================================

// Simple class for basic method testing
const Adder = py.class("Adder", "Simple adder class for testing.", .{
    .add = py.method(adder_add, .{ .doc = "Add two integers" }),
    .identity = py.method(adder_identity, .{ .doc = "Return self" }),
});

fn adder_add(self: py.Object, a: i64, b: i64) i64 {
    _ = self;
    return a + b;
}

fn adder_identity(self: py.Object) py.Object {
    return self.incref();
}

// Class with mutable state via attributes
const Counter = py.class("Counter", "Counter class with mutable state.", .{
    .get = py.method(counter_get, .{ .doc = "Get current count" }),
    .increment = py.method(counter_increment, .{ .doc = "Increment counter" }),
    .add = py.method(counter_add, .{ .doc = "Add value to counter" }),
    .reset = py.method(counter_reset, .{ .doc = "Reset counter to zero" }),
});

fn counter_get(self: py.Object) !i64 {
    const count_obj = self.getAttr("_count") catch {
        // Attribute doesn't exist - clear the AttributeError and initialize
        py.ffi.PyErr.clear();
        const zero: py.Object = try .from(i64, 0);
        try self.setAttr("_count", py.Object, zero);
        return 0;
    };
    defer count_obj.deinit();
    return count_obj.as(i64);
}

fn counter_increment(self: py.Object) !i64 {
    const current = counter_get(self) catch return error.PythonError;
    const new_val = current + 1;
    const new_obj: py.Object = try .from(i64, new_val);
    try self.setAttr("_count", py.Object, new_obj);
    return new_val;
}

fn counter_add(self: py.Object, value: i64) !i64 {
    const current = counter_get(self) catch return error.PythonError;
    const new_val = current + value;
    const new_obj: py.Object = try .from(i64, new_val);
    try self.setAttr("_count", py.Object, new_obj);
    return new_val;
}

fn counter_reset(self: py.Object) !void {
    const zero: py.Object = try .from(i64, 0);
    try self.setAttr("_count", py.Object, zero);
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
