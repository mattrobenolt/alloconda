# Agent Guide

Alloconda is a Zig-first Python extension builder that facilitates creating and cross-compiling wheels. This file collects project-specific expectations for automated coding agents.

## Repo overview

- `src/`: Zig alloconda core API and CPython interop wrappers.
- `python/alloconda/`: Python CLI + build backend (`alloconda.build_backend`).
- `python/allotest/`: Comprehensive test suite exercising all alloconda APIs.
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
- **Pre-commit:** Always run `just ci` before committing. This runs clean, sync, lint (all), tests, and examples.
- **Linting:** `just lint` (Zig only) or `just lint-all` (Zig + Python).
- **Testing:**
  - `just allotest`: build + pytest for the canonical test suite.
  - `just zigadd` / `just zigzon`: build + pytest for examples.

## Zig conventions

See [ZIG_STYLE.md](ZIG_STYLE.md) for general Zig patterns and style. Below are alloconda-specific conventions.

### Linting
- Enforced by `zlint`. Key rules: `line-length` 120, `avoid-as` (casting).

### Module usage
- Expose a single Python module via `pub const MODULE = ...`.
- Prefer alloconda wrappers (`py.Object`, `py.List`, `py.Dict`, `py.Tuple`, helpers).
- Avoid raw `py.ffi.c` unless the wrapper surface is missing.
- Use `py.function`/`py.method`/`py.classmethod`/`py.staticmethod`.

### Type conversion pattern
For comptime type dispatch, match specific types first, then fall back to `@typeInfo` for categories:
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

- **Target:** Python 3.10 – 3.14.
- **Style:** strict `ruff` for linting/formatting.
- **Typing:** `ty` is used for type checking. Run `cd python/alloconda && ty check`.
- Click commands must have clear help strings (docstrings for entrypoints).
- When adding new CLI flags, update `python/alloconda/README.md`.

## Packaging & Commits

- **Backend:** `alloconda.build_backend`.
- **Commits:** Keep messages concise. A short summary line is usually enough. Avoid itemized lists.
- **IMPORTANT:** Never run `git commit` or `git push` without explicit approval from the user. Always ask first.

## Documentation hygiene

- Keep `README.md` and `python/alloconda/README.md` consistent.
- If you add/remove features, update the relevant README.
- Roadmap is tracked in [GitHub Issues](https://github.com/mattrobenolt/alloconda/issues).
