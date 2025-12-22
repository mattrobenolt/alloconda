# Patterns & tips

## Module + class pattern

Attach classes to a module via `.withTypes`:

```zig
const py = @import("alloconda");

const Greeter = py.class("Greeter", "A tiny class", .{
    .hello = py.method(hello, .{ .self = true }),
});

pub const MODULE = py.module("_example", "Example module", .{})
    .withTypes(.{ .Greeter = Greeter });

fn hello(self: py.Object, name: []const u8) []const u8 {
    _ = self;
    return name;
}
```

## Explicit method options

Zig 0.15 requires an explicit options struct:

```zig
.add = py.method(add, .{}),
```

## Override module name detection

If symbol detection picks the wrong `PyInit_*`, pass the module explicitly:

```bash
uvx alloconda build --module _my_module
```

## Control `__init__.py`

The CLI generates a re-exporting `__init__.py` by default. You can opt out or
overwrite:

- `--no-init` to skip generation
- `--force-init` to overwrite an existing file
