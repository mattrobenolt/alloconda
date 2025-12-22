# Writing modules

Alloconda exposes a small, Zig-first API for defining Python modules.

## Module definition

Export a single module definition named `MODULE`:

```zig
const py = @import("alloconda");

pub const MODULE = py.module("_hello_alloconda", "Example module", .{
    .hello = py.method(hello, .{}),
});

fn hello(name: []const u8) []const u8 {
    return name;
}
```

## Method options

`py.method` always takes an explicit options struct (Zig 0.15 requirement). You can
attach docstrings and argument names:

```zig
.hello = py.method(hello, .{
    .doc = "Echo back the provided name.",
    .args = &.{ "name" },
}),
```

If a method is defined on a class and needs `self`, set `.self = true` and include
`self: py.Object` as the first parameter.

## Classes

Define classes with `py.class` and attach them via `.withTypes`:

```zig
const Greeter = py.class("Greeter", "A tiny class", .{
    .hello = py.method(hello, .{ .self = true }),
});

pub const MODULE = py.module("_hello_alloconda", "Example module", .{})
    .withTypes(.{ .Greeter = Greeter });

fn hello(self: py.Object, name: []const u8) []const u8 {
    _ = self;
    return name;
}
```

## Wrapper types

Prefer the alloconda wrapper types (`py.Object`, `py.List`, `py.Dict`, `py.Tuple`,
`py.Bytes`) instead of raw CPython calls. Use `py.ffi.c` only when the wrappers do
not expose what you need.
