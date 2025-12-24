# Agent Guide

This file collects the project-specific expectations for automated coding agents.
Keep it short and actionable; update it when workflows change.

## Repo overview

- `src/`: Zig alloconda core API and CPython interop wrappers.
- `python/alloconda/`: Python CLI + build backend (`alloconda.build_backend`).
- `python/zigadd/`: Demo extension module + tests + type stubs.
- `python/zigzon/`: ZON codec example module + tests + type stubs.

## Source file structure

The `src/` directory is organized as follows:

| File | Purpose |
|------|---------|
| `root.zig` | Public API re-exports only |
| `ffi.zig` | C bindings (`@cImport`), allocator, `pyNone()`, `cstr()`, `cPtr()` |
| `errors.zig` | `Exception` enum, `raise()`, `raiseError()`, `ErrorMap` |
| `types.zig` | `Object`, `Bytes`, `List`, `Dict`, `Tuple`, `GIL`, `fromPy`/`toPy` |
| `method.zig` | `method()`, `MethodOptions`, argument parsing, call dispatch |
| `module.zig` | `Module`, `Class`, `class()`, `module()`, type lifecycle (GC, dealloc) |

Import order: `ffi` ← `errors` ← `types` ← `method` ← `module` (no circular deps).

## Workflow basics

- This repo is a uv workspace. Use `uv add ...` for Python deps.
- Prefer `just` recipes when they exist:
  - `just zigadd` / `just zigzon`: build + pytest for examples.
  - `just lint`: `zig fmt --check` + `zlint`.
- For wheels: `alloconda wheel`, `alloconda wheel-all`, `alloconda inspect`.
- For editable installs: `alloconda develop` (uses pip or uv).

## Zig conventions

### Module usage
- Expose a single Python module via `pub const MODULE = ...`.
- Prefer alloconda wrappers (`py.Object`, `py.List`, `py.Dict`, `py.Tuple`, helpers).
- Avoid raw `py.ffi.c` unless the wrapper surface is missing.
- Use `py.method(fn, .{...})` explicitly (Zig 0.15 requirement).

### Style preferences
- Use short aliases for `std` imports when repeated often:
  ```zig
  const std = @import("std");
  const fmt = std.fmt;
  const mem = std.mem;
  const meta = std.meta;
  ```
- Prefer `switch` over `if` chains when matching on types or enums.
- For comptime type dispatch, use `switch (T) { ... }` when matching specific types,
  fall back to `switch (@typeInfo(T)) { ... }` for type categories (int, float, etc.).

### Type conversion pattern
```zig
switch (T) {
    Object => ...,
    Bytes => ...,
    []const u8, [:0]const u8 => ...,
    bool => ...,
    else => switch (@typeInfo(T)) {
        .int => ...,
        .float => ...,
        else => @compileError(...),
    },
}
```

## Python/CLI conventions

- Click commands must have clear help strings (docstrings for entrypoints).
- When adding new CLI flags, update `python/alloconda/README.md`.
- Keep `pyproject.toml` build backend entries in example projects in sync.

## Tests and validation

- Zig examples: `just zigadd`, `just zigzon`.
- CLI typing: `cd python/alloconda && ty check`.
- Linting: `just lint` when touching Zig core.

## Packaging notes

- The build backend is `alloconda.build_backend`.
- Cached python headers live under `~/.cache/alloconda/pbs`
  (override with `ALLOCONDA_PBS_CACHE`).
- Document publishing via `twine` instead of adding a publish command.

## Documentation hygiene

- Keep `README.md`, `python/alloconda/README.md`, and `PLAN.md` consistent.
- If you add/remove features, update the relevant README + plan entries.