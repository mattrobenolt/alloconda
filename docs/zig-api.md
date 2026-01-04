# Writing modules

Alloconda exposes a small, Zig-first API for defining Python modules.

The generated API reference is published alongside this book at
[zig-docs/index.html](zig-docs/index.html).

To generate it locally:

```bash
zig build docs -Dpython-include=/path/to/python/include -p docs
```

## Module definition

Export a single module definition named `MODULE`:

```zig
const py = @import("alloconda");

pub const MODULE = py.module("Example module", .{
    .hello = py.function(hello, .{}),
});

fn hello(name: []const u8) []const u8 {
    return name;
}
```

The module name comes from `addPythonLibrary(.name=...)`.

## Module attributes

Attach constants to the module with `withAttrs`:

```zig
const VERSION: []const u8 = "0.1.0";
const DEFAULT_SIZE: i64 = 256;

pub const MODULE = py.module("Example module", .{
    .hello = py.function(hello, .{}),
}).withAttrs(.{
    .VERSION = VERSION,
    .DEFAULT_SIZE = DEFAULT_SIZE,
});
```

## Method options

`py.function`/`py.method`/`py.classmethod`/`py.staticmethod` always take an
explicit options struct. You can attach docstrings and argument names:

```zig
.hello = py.function(hello, .{
    .doc = "Echo back the provided name.",
    .args = &.{ "name" },
}),
```

If a method is defined on a class and needs `self`, use `py.method` and include
`self: py.Object` as the first parameter. For class methods, use `py.classmethod`
and accept `cls: py.Object`. For static methods, use `py.staticmethod` and omit
`self`/`cls`.

## Classes

Define classes with `py.class` and attach them via `.withTypes`:

```zig
const Greeter = py.class("Greeter", "A tiny class", .{
    .hello = py.method(hello, .{}),
});

pub const MODULE = py.module("Example module", .{})
    .withTypes(.{ .Greeter = Greeter });

fn hello(_: py.Object, name: []const u8) []const u8 {
    return name;
}
```

To allow Python subclassing, use `py.baseclass` instead of `py.class`.

Attach inline payload storage with `.withPayload`, then access it with
the typed class wrapper:

```zig
const BoxState = struct {
    value: i64,
};

const Box = py.class("Box", "Payload-backed class", .{
    .__init__ = py.method(box_init, .{ .args = &.{"value"} }),
    .get = py.method(box_get, .{}),
}).withPayload(BoxState);

fn box_init(self: py.Object, value: i64) !void {
    var state = try Box.payloadFrom(self);
    state.value = value;
}

fn box_get(self: py.Object) !i64 {
    const state = try Box.payloadFrom(self);
    return state.value;
}
```

To create an instance from Zig, use `Class.new()`:

```zig
const obj = try Box.new();
const state = try Box.payloadFrom(obj);
state.value = 42;
```

## Wrapper types

Prefer the alloconda wrapper types (`py.Object`, `py.List`, `py.Dict`, `py.Tuple`,
`py.Bytes`, `py.BytesView`) instead of raw CPython calls. Use `py.ffi.c` only when
the wrappers do not expose what you need. For bytes-like inputs, `py.Bytes.fromObjectOwned`
accepts bytes or buffer-capable objects, copying when needed to return owned bytes.
Use `py.BytesView` for zero-copy access to bytes or buffer-backed inputs.

## IO Adapters

Use `py.IoReader` and `py.IoWriter` to wrap Python binary streams (`readinto`/`write`)
with the Zig 0.15 `std.Io.Reader`/`std.Io.Writer` interfaces. For direct reads into
your buffers, initialize with an empty internal buffer (`&.{}`):

```zig
var reader: py.IoReader = try .initUnbufffered(stream);
defer reader.deinit();

var buf: [1024]u8 = undefined;
const data = try reader.readAll(&buf);
const bytes: py.Bytes = try .fromSlice(data);
```

For larger reads, allocate and free through the helper:

```zig
const result = try reader.readAllAlloc(py.allocator, size);
defer result.deinit(py.allocator);
const bytes: py.Bytes = try .fromSlice(result.slice());
```

To read until EOF:

```zig
var list: std.ArrayList(u8) = .empty;
defer list.deinit(py.allocator);
try reader.appendRemainingUnlimited(py.allocator, &list);
const bytes: py.Bytes = try .fromSlice(list.items);
```

For writing, call `writeAll` and flush:

```zig
var out_buf: [1024]u8 = undefined;
var writer: py.IoWriter = try .init(stream, &out_buf);
defer writer.deinit();
try writer.writeAll(payload);
try writer.flush();
```
