const py = @import("alloconda");

const Adder = py.class("Adder", "Simple adder class", .{
    .add = py.method(adder_add, .{ .self = true, .doc = "Add two integers" }),
    .identity = py.method(adder_identity, .{ .self = true, .doc = "Return self" }),
});

pub const MODULE = py.module("_zigadd", "A Zig extension module", .{
    .add = py.method(add, .{ .doc = "Add two integers" }),
    .add_named = py.method(add_named, .{ .doc = "Add named integers", .args = &.{ "a", "b", "c" } }),
    .add3 = py.method(add3, .{ .doc = "Add two or three integers" }),
    .bytes_len = py.method(bytes_len, .{ .doc = "Return the length of a bytes object" }),
    .call_twice = py.method(call_twice, .{ .doc = "Call a Python callable twice and sum the results" }),
    .dict_get = py.method(dict_get, .{ .doc = "Lookup a dict key and return an int or None" }),
    .divide = py.method(divide, .{ .doc = "Divide two floats" }),
    .greet = py.method(greet, .{ .doc = "Return the name or a fallback greeting" }),
    .is_even = py.method(is_even, .{ .doc = "Return true if a number is even" }),
    .math_pi = py.method(math_pi, .{ .doc = "Return math.pi via Python import" }),
    .maybe_tag = py.method(maybe_tag, .{ .doc = "Return the name or None if empty" }),
    .sum_list = py.method(sum_list, .{ .doc = "Sum a list of integers" }),
    .to_bytes = py.method(to_bytes, .{ .doc = "Convert a string to bytes" }),
    .to_upper = py.method(to_upper, .{ .doc = "Uppercase a string via Python method call" }),
}).withTypes(.{
    .Adder = Adder,
});

fn add(a: i64, b: i64) i64 {
    return a + b;
}

fn add_named(a: i64, b: i64, c: ?i64) i64 {
    return a + b + (c orelse 0);
}

fn add3(a: i64, b: i64, c: ?i64) i64 {
    return a + b + (c orelse 0);
}

fn bytes_len(data: py.Bytes) CallError!usize {
    return data.len() orelse error.PythonError;
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

const CallError = error{PythonError};

fn call_twice(func: py.Object, x: i64) CallError!i64 {
    if (!func.isCallable()) {
        py.raise(.TypeError, "expected a callable");
        return error.PythonError;
    }

    const first = func.call1(x) orelse return error.PythonError;
    defer first.deinit();
    const a = first.as(i64) orelse return error.PythonError;

    const second = func.call1(x) orelse return error.PythonError;
    defer second.deinit();
    const b = second.as(i64) orelse return error.PythonError;

    return a + b;
}

fn dict_get(dict: py.Dict, key: []const u8) CallError!?i64 {
    const item = dict.getItem(key);
    if (item == null) {
        if (py.errorOccurred()) return error.PythonError;
        return null;
    }
    const value = item.?.as(i64) orelse return error.PythonError;
    return value;
}

fn math_pi() CallError!f64 {
    const math = py.importModule("math") orelse return error.PythonError;
    defer math.deinit();
    const pi_obj = math.getAttr("pi") orelse return error.PythonError;
    defer pi_obj.deinit();
    return pi_obj.as(f64) orelse return error.PythonError;
}

fn greet(name: []const u8) []const u8 {
    if (name.len == 0) return "Hello";
    return name;
}

fn is_even(n: i64) bool {
    return @mod(n, 2) == 0;
}

fn maybe_tag(name: []const u8) ?[]const u8 {
    if (name.len == 0) return null;
    return name;
}

fn sum_list(values: py.List) CallError!i64 {
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

fn to_bytes(value: []const u8) CallError!py.Bytes {
    return py.Bytes.fromSlice(value) orelse error.PythonError;
}

fn to_upper(value: []const u8) CallError![]const u8 {
    const obj = py.toObject(value) orelse return error.PythonError;
    defer obj.deinit();
    const out = obj.callMethod0("upper") orelse return error.PythonError;
    defer out.deinit();
    return out.as([]const u8) orelse return error.PythonError;
}

fn adder_add(self: py.Object, a: i64, b: i64) i64 {
    _ = self;
    return a + b;
}

fn adder_identity(self: py.Object) py.Object {
    return self;
}
