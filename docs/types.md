# Working with Python types

Alloconda wraps common Python container types so you can stay in Zig without
reaching for the raw C API.

Available wrappers include:

- `py.Object` for owned and borrowed objects.
- `py.Bytes` for byte strings.
- `py.List`, `py.Dict`, and `py.Tuple` for containers.
- `py.DictIter` / `py.DictEntry` for iterating dictionaries.

Use these wrappers to construct values, inspect contents, and manage ownership.
If you need lower-level access, `py.ffi.c` exposes the CPython API.
