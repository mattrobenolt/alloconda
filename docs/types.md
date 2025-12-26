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

## Ownership and lifetimes

Alloconda mirrors CPython reference semantics: APIs either return a new (owned)
reference or a borrowed reference, and some functions steal references you
hand them. The wrappers try to make these rules explicit:

- `py.Object.borrowed` does not change refcounts; `py.Object.owned` takes
  ownership of a reference you already own.
- `toPyObject()` returns an owned reference and increments if the wrapper is
  borrowed. `toObject()` returns an owned wrapper.
- `fromObject(...)` for `py.Bytes`/`py.List`/`py.Dict`/`py.Tuple` returns a
  borrowed wrapper; it does not increment.

When in doubt, assume borrowed views are only valid while the underlying
Python object is alive.

## Copies vs borrowed views

- `py.Bytes.fromSlice` copies data into a new bytes object.
- `py.Bytes.slice` returns a borrowed slice into the bytes object.
- `py.Buffer.init/fromObject` returns a buffer view that must be released with
  `Buffer.release`; `Buffer.slice` is valid until release.

## Container element ownership

- `py.List.set`/`py.Tuple.set` transfer ownership of the new reference into the
  container (the container steals the reference).
- `py.List.append` does not steal; it increments the refcount for the stored
  item.
- `py.Dict.setItem` does not steal; it increments the refcount for key/value.
- `py.List.fromSlice`/`py.Tuple.fromSlice` create containers and populate them
  by converting each element, so the container owns the resulting references.
- `py.Dict.getItem` and `py.DictIter` yield borrowed references.
