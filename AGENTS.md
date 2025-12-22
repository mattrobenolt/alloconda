# Agent Guide

This file collects the project-specific expectations for automated coding agents.
Keep it short and actionable; update it when workflows change.

## Repo overview

- `src/`: Zig alloconda core API and CPython interop wrappers.
- `python/alloconda/`: Python CLI + build backend (`alloconda.build_backend`).
- `python/zigadd/`: Demo extension module + tests + type stubs.
- `python/zigzon/`: ZON codec example module + tests + type stubs.

## Workflow basics

- This repo is a uv workspace. Use `uv add ...` for Python deps.
- Prefer `just` recipes when they exist:
  - `just zigadd` / `just zigzon`: build + pytest for examples.
  - `just lint`: `zig fmt --check` + `zlint`.
- For wheels: `alloconda wheel`, `alloconda wheel-all`, `alloconda inspect`.
- For editable installs: `alloconda develop` (uses pip or uv).

## Zig conventions

- Expose a single Python module via `pub const MODULE = ...`.
- Prefer alloconda wrappers (`py.Object`, `py.List`, `py.Dict`, `py.Tuple`, helpers).
- Avoid raw `py.ffi.c` unless the wrapper surface is missing.
- Use `py.method(fn, .{...})` explicitly (Zig 0.15 requirement).

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
