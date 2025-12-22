# alloconda

Alloconda is a Zig-first toolkit for building Python extension modules with a minimal,
comptime-friendly API. It mirrors PyO3's ergonomics where it makes sense in Zig,
without exposing the raw C API for common tasks.

## Highlights

- `pub const MODULE = ...` discovery with a generated `PyInit_*` wrapper.
- Method wrappers with type conversions, optional arguments, and keyword names.
- Ergonomic `Object` wrapper + `Bytes`/`List`/`Dict`/`Tuple` helpers.
- Basic class/type support via `py.class(...).withTypes(...)`.
- Error mapping helpers (`raiseError`, `Exception` enum).
- CLI that builds, discovers module name, and writes `__init__.py`.
- PEP 517 build backend for `pyproject.toml` projects.

## Quick example

```zig
const py = @import("alloconda");

const Greeter = py.class("Greeter", "A tiny class", .{
    .hello = py.method(hello, .{ .self = true }),
});

pub const MODULE = py.module("_zigadd", "Example module", .{
    .add = py.method(add, .{}),
}).withTypes(.{ .Greeter = Greeter });

fn add(a: i64, b: i64) i64 {
    return a + b;
}

fn hello(self: py.Object, name: []const u8) []const u8 {
    _ = self;
    return name;
}
```

In Python, the CLI generates an `__init__.py` that re-exports the extension.
See `python/zigadd` for a working example and tests.

## Build

```bash
alloconda build
```

Flags:
- `--release` for ReleaseFast.
- `--module` to override `PyInit_*` detection.
- `--package-dir` to pick a target package directory.

## Repo layout

- `src/root.zig`: core alloconda API.
- `python/alloconda`: CLI package.
- `python/zigadd`: demo extension module + tests.
- `python/zigzon`: ZON codec example module + tests.

## Notes

- In Zig 0.15, `py.method` requires explicit options: use `py.method(fn, .{})`.
- Class names are auto-qualified with the module name when added via `.withTypes`.
