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

pub const MODULE = py.module("_hello_alloconda", "Example module", .{
    .hello = py.function(hello, .{}),
});

fn hello(name: []const u8) []const u8 {
    return name;
}
```

## Module attributes

Attach constants to the module with `withAttrs`:

```zig
const VERSION: []const u8 = "0.1.0";
const DEFAULT_SIZE: i64 = 256;

pub const MODULE = py.module("_hello_alloconda", "Example module", .{
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

pub const MODULE = py.module("_hello_alloconda", "Example module", .{})
    .withTypes(.{ .Greeter = Greeter });

fn hello(_: py.Object, name: []const u8) []const u8 {
    return name;
}
```

## Wrapper types

Prefer the alloconda wrapper types (`py.Object`, `py.List`, `py.Dict`, `py.Tuple`,
`py.Bytes`) instead of raw CPython calls. Use `py.ffi.c` only when the wrappers do
not expose what you need.
