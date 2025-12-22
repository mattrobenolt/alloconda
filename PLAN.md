# Alloconda roadmap

This file tracks the current feature set and the next priorities. It is intentionally
small and pragmatic; update as we learn.

## Current feature set

- Module discovery via `pub const MODULE` and generated `PyInit_*` entrypoint.
- Method wrappers with type conversion, optional args, and keyword names.
- `Object` wrapper with ownership helpers and basic call/attr utilities.
- `Bytes`, `List`, `Dict`, `Tuple` ergonomic wrappers + dict iterator.
- Basic class/type support via `py.class` + `.withTypes`.
- Error helpers (`Exception`, `raise`, `raiseError`).
- CLI: build, wheel, wheel-all, inspect, develop, python header fetch.
- PEP 517 build backend for `pyproject.toml` projects.
- Example modules `python/zigadd` and `python/zigzon` with pytest + type stubs.

## Near-term ideas

- Method defaults and `*args/**kwargs` capture helpers.
- Properties and common dunder methods (`__repr__`, `__len__`, `__iter__`).
- Richer conversions: tuples, sequences, dict/list of primitives, bytes views.
- Buffer protocol helpers and NumPy interop surface.
- GIL helpers for `allow_threads` and background work.
- CLI polish: stub generation, abi3 selection, uv-native editable support.
- Better wheel metadata validation and `inspect --json` consumers.
- Build backend: config schema, build hooks for sdist/wheel metadata.
- `tool.alloconda` config in `pyproject.toml` (module name, package dir, tags, include/exclude).
- Document twine-based publish workflow (no built-in upload command).

## Longer-term

- Custom class storage (struct-backed types).
- Lifetime-safe `Object` wrappers across threads (opt-in).
- Multi-phase module init (PEP 489) support.
- Docs + cookbook with patterns and caveats.
