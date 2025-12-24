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
    .add = py.method(add, .{ .doc = "Add two integers" }),
    .add3 = py.method(add3, .{ .doc = "Add two or three integers" }),
    .add_named = py.method(add_named, .{ .doc = "Add named integers", .args = &.{ "a", "b", "c" } }),

    // Type conversions
    .identity_int = py.method(identity_int, .{ .doc = "Return an integer unchanged" }),
    .identity_float = py.method(identity_float, .{ .doc = "Return a float unchanged" }),
    .identity_bool = py.method(identity_bool, .{ .doc = "Return a bool unchanged" }),
    .identity_str = py.method(identity_str, .{ .doc = "Return a string unchanged" }),
    .identity_bytes = py.method(identity_bytes, .{ .doc = "Return bytes unchanged" }),
    .identity_optional = py.method(identity_optional, .{ .doc = "Return optional string or None" }),
    .identity_object = py.method(identity_object, .{ .doc = "Return any object unchanged" }),

    // Bytes operations
    .bytes_len = py.method(bytes_len, .{ .doc = "Return length of bytes" }),
    .bytes_slice = py.method(bytes_slice, .{ .doc = "Return slice of bytes as new bytes" }),
    .bytes_create = py.method(bytes_create, .{ .doc = "Create bytes from string" }),

    // List operations
    .list_len = py.method(list_len, .{ .doc = "Return length of list" }),
    .list_get = py.method(list_get, .{ .doc = "Get item from list by index" }),
    .list_sum = py.method(list_sum, .{ .doc = "Sum a list of integers" }),
    .list_create = py.method(list_create, .{ .doc = "Create a new list with given values" }),
    .list_append = py.method(list_append, .{ .doc = "Append value to list and return it" }),
    .list_set = py.method(list_set, .{ .doc = "Set item in list by index" }),

    // Dict operations
    .dict_len = py.method(dict_len, .{ .doc = "Return length of dict" }),
    .dict_get = py.method(dict_get, .{ .doc = "Get item from dict by key" }),
    .dict_create = py.method(dict_create, .{ .doc = "Create a new dict with one key-value pair" }),
    .dict_set = py.method(dict_set, .{ .doc = "Set item in dict by key" }),
    .dict_keys = py.method(dict_keys, .{ .doc = "Return list of dict keys via iteration" }),

    // Tuple operations
    .tuple_len = py.method(tuple_len, .{ .doc = "Return length of tuple" }),
    .tuple_get = py.method(tuple_get, .{ .doc = "Get item from tuple by index" }),
    .tuple_create = py.method(tuple_create, .{ .doc = "Create a tuple from values" }),

    // Object operations
    .obj_call0 = py.method(obj_call0, .{ .doc = "Call object with no args" }),
    .obj_call1 = py.method(obj_call1, .{ .doc = "Call object with one arg" }),
    .obj_call2 = py.method(obj_call2, .{ .doc = "Call object with two args" }),
    .obj_getattr = py.method(obj_getattr, .{ .doc = "Get attribute from object" }),
    .obj_setattr = py.method(obj_setattr, .{ .doc = "Set attribute on object" }),
    .obj_callmethod0 = py.method(obj_callmethod0, .{ .doc = "Call method with no args" }),
    .obj_callmethod1 = py.method(obj_callmethod1, .{ .doc = "Call method with one arg" }),
    .obj_is_callable = py.method(obj_is_callable, .{ .doc = "Check if object is callable" }),
    .obj_is_none = py.method(obj_is_none, .{ .doc = "Check if object is None" }),

    // Type checking
    .is_unicode = py.method(is_unicode, .{ .doc = "Check if object is unicode string" }),
    .is_bytes = py.method(is_bytes, .{ .doc = "Check if object is bytes" }),
    .is_bool = py.method(is_bool, .{ .doc = "Check if object is bool" }),
    .is_int = py.method(is_int, .{ .doc = "Check if object is int" }),
    .is_float = py.method(is_float, .{ .doc = "Check if object is float" }),
    .is_list = py.method(is_list, .{ .doc = "Check if object is list" }),
    .is_tuple = py.method(is_tuple, .{ .doc = "Check if object is tuple" }),
    .is_dict = py.method(is_dict, .{ .doc = "Check if object is dict" }),

    // Error handling - each exception type
    .raise_type_error = py.method(raise_type_error, .{ .doc = "Raise TypeError" }),
    .raise_optional_error = py.method(raise_optional_error, .{ .doc = "Raise error via optional return" }),
    .raise_value_error = py.method(raise_value_error, .{ .doc = "Raise ValueError" }),
    .raise_runtime_error = py.method(raise_runtime_error, .{ .doc = "Raise RuntimeError" }),
    .raise_zero_division = py.method(raise_zero_division, .{ .doc = "Raise ZeroDivisionError" }),
    .raise_overflow_error = py.method(raise_overflow_error, .{ .doc = "Raise OverflowError" }),
    .raise_attribute_error = py.method(raise_attribute_error, .{ .doc = "Raise AttributeError" }),
    .raise_index_error = py.method(raise_index_error, .{ .doc = "Raise IndexError" }),
    .raise_key_error = py.method(raise_key_error, .{ .doc = "Raise KeyError" }),
    .raise_memory_error = py.method(raise_memory_error, .{ .doc = "Raise MemoryError" }),
    .divide = py.method(divide, .{ .doc = "Divide two floats, raises ZeroDivisionError if b=0" }),
    .raise_mapped = py.method(raise_mapped, .{ .doc = "Test error mapping" }),

    // Python interop
    .import_math_pi = py.method(import_math_pi, .{ .doc = "Import math.pi" }),
    .call_upper = py.method(call_upper, .{ .doc = "Call .upper() on a string" }),
}).withTypes(.{
    .Adder = Adder,
    .Counter = Counter,
});

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

// ============================================================================
// Bytes Operations
// ============================================================================

const CallError = error{PythonError};

fn bytes_len(data: py.Bytes) CallError!usize {
    return data.len() orelse error.PythonError;
}

fn bytes_slice(data: py.Bytes, start: i64, end: i64) CallError!py.Bytes {
    const slice = data.slice() orelse return error.PythonError;
    const s: usize = @intCast(start);
    const e: usize = @intCast(end);
    if (s > slice.len or e > slice.len or s > e) {
        py.raise(.IndexError, "slice out of bounds");
        return error.PythonError;
    }
    return py.Bytes.fromSlice(slice[s..e]) orelse error.PythonError;
}

fn bytes_create(value: []const u8) CallError!py.Bytes {
    return py.Bytes.fromSlice(value) orelse error.PythonError;
}

// ============================================================================
// List Operations
// ============================================================================

fn list_len(list: py.List) CallError!usize {
    return list.len() orelse error.PythonError;
}

fn list_get(list: py.List, index: i64) CallError!py.Object {
    const i: usize = @intCast(index);
    const item = list.get(i) orelse return error.PythonError;
    return item.incref();
}

fn list_sum(values: py.List) CallError!i64 {
    const count = values.len() orelse return error.PythonError;
    var total: i64 = 0;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const item = values.get(i) orelse return error.PythonError;
        const value = item.as(i64) orelse return error.PythonError;
        total += value;
    }
    return total;
}

fn list_create(a: i64, b: i64, c: i64) CallError!py.List {
    var list = py.List.init(3) orelse return error.PythonError;
    const obj_a = py.toObject(a) orelse {
        list.deinit();
        return error.PythonError;
    };
    const obj_b = py.toObject(b) orelse {
        list.deinit();
        return error.PythonError;
    };
    const obj_c = py.toObject(c) orelse {
        list.deinit();
        return error.PythonError;
    };
    if (!list.set(0, obj_a) or !list.set(1, obj_b) or !list.set(2, obj_c)) {
        list.deinit();
        return error.PythonError;
    }
    return list;
}

fn list_append(list: py.List, value: i64) CallError!py.List {
    const obj = py.toObject(value) orelse return error.PythonError;
    if (!list.append(obj)) return error.PythonError;
    return list;
}

fn list_set(list: py.List, index: i64, value: i64) CallError!py.List {
    const obj = py.toObject(value) orelse return error.PythonError;
    const i: usize = @intCast(index);
    if (!list.set(i, obj)) return error.PythonError;
    return list;
}

// ============================================================================
// Dict Operations
// ============================================================================

fn dict_len(dict: py.Dict) CallError!usize {
    return dict.len() orelse error.PythonError;
}

fn dict_get(dict: py.Dict, key: []const u8) CallError!?i64 {
    const item = dict.getItem(key);
    if (item == null) {
        if (py.errorOccurred()) return error.PythonError;
        return null;
    }
    return item.?.as(i64) orelse return error.PythonError;
}

fn dict_create(key: []const u8, value: i64) CallError!py.Dict {
    var dict = py.Dict.init() orelse return error.PythonError;
    const obj = py.toObject(value) orelse {
        dict.deinit();
        return error.PythonError;
    };
    if (!dict.setItem(key, obj)) {
        dict.deinit();
        return error.PythonError;
    }
    return dict;
}

fn dict_set(dict: py.Dict, key: []const u8, value: i64) CallError!py.Dict {
    const obj = py.toObject(value) orelse return error.PythonError;
    if (!dict.setItem(key, obj)) return error.PythonError;
    return dict;
}

fn dict_keys(dict: py.Dict) CallError!py.List {
    const size = dict.len() orelse return error.PythonError;
    var list = py.List.init(size) orelse return error.PythonError;
    var iter = dict.iter();
    var i: usize = 0;
    while (iter.next()) |entry| {
        if (!list.set(i, entry.key.incref())) {
            list.deinit();
            return error.PythonError;
        }
        i += 1;
    }
    return list;
}

// ============================================================================
// Tuple Operations
// ============================================================================

fn tuple_len(tuple: py.Tuple) CallError!usize {
    return tuple.len() orelse error.PythonError;
}

fn tuple_get(tuple: py.Tuple, index: i64) CallError!py.Object {
    const i: usize = @intCast(index);
    const item = tuple.get(i) orelse return error.PythonError;
    return item.incref();
}

fn tuple_create(a: i64, b: i64) CallError!py.Object {
    const values: [2]i64 = .{ a, b };
    const tuple = py.toTuple(i64, &values) orelse return error.PythonError;
    return tuple.obj;
}

// ============================================================================
// Object Operations
// ============================================================================

fn obj_call0(obj: py.Object) CallError!py.Object {
    return obj.call0() orelse error.PythonError;
}

fn obj_call1(obj: py.Object, arg: py.Object) CallError!py.Object {
    const result = obj.call1(arg.ptr) orelse return error.PythonError;
    return result;
}

fn obj_call2(obj: py.Object, arg1: py.Object, arg2: py.Object) CallError!py.Object {
    const result = obj.call2(arg1.ptr, arg2.ptr) orelse return error.PythonError;
    return result;
}

fn obj_getattr(obj: py.Object, name: [:0]const u8) CallError!py.Object {
    return obj.getAttr(name) orelse error.PythonError;
}

fn obj_setattr(obj: py.Object, name: [:0]const u8, value: py.Object) CallError!bool {
    return obj.setAttr(name, value);
}

fn obj_callmethod0(obj: py.Object, name: [:0]const u8) CallError!py.Object {
    return obj.callMethod0(name) orelse error.PythonError;
}

fn obj_callmethod1(obj: py.Object, name: [:0]const u8, arg: py.Object) CallError!py.Object {
    return obj.callMethod1(name, arg.ptr) orelse error.PythonError;
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

fn raise_type_error() CallError!void {
    py.raise(.TypeError, "test type error");
    return error.PythonError;
}

/// Test that optional returns properly propagate exceptions set via py.raise().
/// This returns ?py.Object (not error union) and calls py.raise() + returns null.
fn raise_optional_error() ?py.Object {
    py.raise(.ValueError, "test optional error");
    return null;
}

fn raise_value_error() CallError!void {
    py.raise(.ValueError, "test value error");
    return error.PythonError;
}

fn raise_runtime_error() CallError!void {
    py.raise(.RuntimeError, "test runtime error");
    return error.PythonError;
}

fn raise_zero_division() CallError!void {
    py.raise(.ZeroDivisionError, "test zero division");
    return error.PythonError;
}

fn raise_overflow_error() CallError!void {
    py.raise(.OverflowError, "test overflow error");
    return error.PythonError;
}

fn raise_attribute_error() CallError!void {
    py.raise(.AttributeError, "test attribute error");
    return error.PythonError;
}

fn raise_index_error() CallError!void {
    py.raise(.IndexError, "test index error");
    return error.PythonError;
}

fn raise_key_error() CallError!void {
    py.raise(.KeyError, "test key error");
    return error.PythonError;
}

fn raise_memory_error() CallError!void {
    py.raise(.MemoryError, "test memory error");
    return error.PythonError;
}

const DivideError = error{DivideByZero};

fn divide(a: f64, b: f64) CallError!f64 {
    return divideInner(a, b) catch |err| {
        py.raiseError(err, &[_]py.ErrorMap{
            .{ .err = error.DivideByZero, .kind = .ZeroDivisionError, .msg = "division by zero" },
        });
        return error.PythonError;
    };
}

fn divideInner(a: f64, b: f64) DivideError!f64 {
    if (b == 0) return error.DivideByZero;
    return a / b;
}

const MappedError = error{ NotFound, InvalidInput };

fn raise_mapped(kind: []const u8) CallError!void {
    const err: MappedError = if (std.mem.eql(u8, kind, "not_found"))
        error.NotFound
    else if (std.mem.eql(u8, kind, "invalid"))
        error.InvalidInput
    else {
        py.raise(.ValueError, "unknown error kind");
        return error.PythonError;
    };

    py.raiseError(err, &[_]py.ErrorMap{
        .{ .err = error.NotFound, .kind = .KeyError, .msg = "item not found" },
        .{ .err = error.InvalidInput, .kind = .ValueError, .msg = "invalid input" },
    });
    return error.PythonError;
}

// ============================================================================
// Python Interop
// ============================================================================

fn import_math_pi() CallError!f64 {
    const math = py.importModule("math") orelse return error.PythonError;
    defer math.deinit();
    const pi_obj = math.getAttr("pi") orelse return error.PythonError;
    defer pi_obj.deinit();
    return pi_obj.as(f64) orelse error.PythonError;
}

fn call_upper(value: []const u8) CallError![]const u8 {
    const obj = py.toObject(value) orelse return error.PythonError;
    defer obj.deinit();
    const out = obj.callMethod0("upper") orelse return error.PythonError;
    defer out.deinit();
    return out.as([]const u8) orelse error.PythonError;
}

// ============================================================================
// Classes
// ============================================================================

// Simple class for basic method testing
const Adder = py.class("Adder", "Simple adder class for testing.", .{
    .add = py.method(adder_add, .{ .self = true, .doc = "Add two integers" }),
    .identity = py.method(adder_identity, .{ .self = true, .doc = "Return self" }),
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
    .get = py.method(counter_get, .{ .self = true, .doc = "Get current count" }),
    .increment = py.method(counter_increment, .{ .self = true, .doc = "Increment counter" }),
    .add = py.method(counter_add, .{ .self = true, .doc = "Add value to counter" }),
    .reset = py.method(counter_reset, .{ .self = true, .doc = "Reset counter to zero" }),
});

fn counter_get(self: py.Object) CallError!i64 {
    const count_obj = self.getAttr("_count") orelse {
        // Attribute doesn't exist - clear the AttributeError and initialize
        py.ffi.c.PyErr_Clear();
        const zero = py.toObject(@as(i64, 0)) orelse return error.PythonError;
        if (!self.setAttr("_count", zero)) return error.PythonError;
        return 0;
    };
    defer count_obj.deinit();
    return count_obj.as(i64) orelse error.PythonError;
}

fn counter_increment(self: py.Object) CallError!i64 {
    const current = counter_get(self) catch return error.PythonError;
    const new_val = current + 1;
    const new_obj = py.toObject(new_val) orelse return error.PythonError;
    if (!self.setAttr("_count", new_obj)) return error.PythonError;
    return new_val;
}

fn counter_add(self: py.Object, value: i64) CallError!i64 {
    const current = counter_get(self) catch return error.PythonError;
    const new_val = current + value;
    const new_obj = py.toObject(new_val) orelse return error.PythonError;
    if (!self.setAttr("_count", new_obj)) return error.PythonError;
    return new_val;
}

fn counter_reset(self: py.Object) CallError!void {
    const zero = py.toObject(@as(i64, 0)) orelse return error.PythonError;
    if (!self.setAttr("_count", zero)) return error.PythonError;
}
