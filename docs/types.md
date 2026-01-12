# Working with Python types

Alloconda wraps common Python container types so you can stay in Zig without
reaching for the raw C API.

Available wrappers include:

- `py.Object` for owned and borrowed objects.
- `py.Bytes` for byte strings.
- `py.List`, `py.Dict`, and `py.Tuple` for containers.
- `py.DictIter` for iterating dictionaries (yields `py.DictIter.Entry` key/value pairs).

Use these wrappers to construct values, inspect contents, and manage ownership.
If you need lower-level access, `py.ffi.c` exposes the CPython API.

## Ownership: borrowed vs owned

Every `py.Object` tracks whether it owns its reference:

```zig
pub const Object = struct {
    ptr: *c.PyObject,
    owns_ref: bool,  // true = owned, false = borrowed
};
```

**Borrowed references** point to objects owned by someone else (Python, a
container, or another Object). You must not call `deinit()` on them.

**Owned references** are yours to manage. You must call `deinit()` when done,
or transfer ownership to something else.

### Creating Objects

```zig
// Borrow from an existing PyObject* (no refcount change)
const borrowed = py.Object.borrowed(raw_ptr);

// Take ownership of an existing PyObject* (you already own it)
const owned = py.Object.owned(raw_ptr);

// Create a new owned Object from a Zig value
const obj = try py.Object.from(42);
defer obj.deinit();  // You own it, so you must release it
```

### Releasing ownership

```zig
// CORRECT: release an owned reference
const obj = try py.Object.from("hello");
defer obj.deinit();

// WRONG: calling deinit on a borrowed reference
const item = try list.get(0);  // Returns borrowed
item.deinit();  // BUG! This will panic in debug builds
```

In debug builds, calling `deinit()` on a borrowed Object will panic to help
catch this bug early.

### Converting between borrowed and owned

```zig
// Increment refcount to get an owned reference from a borrowed one
const borrowed = try list.get(0);
const owned = borrowed.incref();
defer owned.deinit();

// toPyObject() returns an owned raw pointer (increments if borrowed)
const raw_ptr = try obj.toPyObject();  // Always owned
```

### Common patterns

```zig
// Pattern 1: Create, use, release
const result = try py.Object.from(value);
defer result.deinit();
try self.setAttr("value", result);

// Pattern 2: Return ownership to Python (no defer)
fn compute(self: py.Object) !py.Object {
    const result = try py.Object.from(42);
    // Don't defer - we're transferring ownership to Python
    return result;
}

// Pattern 3: Borrow from container, use without deinit
const item = try list.get(0);  // Borrowed
const value = try item.as(i64);  // Use it
// No deinit needed - list owns the reference
```

## Type conversions

Alloconda automatically converts between Zig and Python types in function
arguments and return values.

### Conversion table

| Zig Type | Python Type | Direction | Notes |
|----------|-------------|-----------|-------|
| `py.Object` | any | both | Borrowed when receiving, owned when returning |
| `py.Bytes` | `bytes` | both | Borrowed wrapper |
| `py.List` | `list` | both | Borrowed wrapper |
| `py.Dict` | `dict` | both | Borrowed wrapper |
| `py.Tuple` | `tuple` | both | Borrowed wrapper |
| `py.Buffer` | buffer protocol | from Python | Must call `release()` |
| `[]const u8` | `str` | from Python | Borrowed view into UTF-8 data |
| `[:0]const u8` | `str` | from Python | Null-terminated borrowed view |
| `[]const u8` | `str` | to Python | Creates new str object |
| `bool` | `bool` | both | |
| `i8`–`i64` | `int` | both | OverflowError if out of range |
| `u8`–`u64` | `int` | both | OverflowError if out of range |
| `f32`, `f64` | `float` | both | |
| `?T` | `T` or `None` | both | Optional types map to None |

### The toPy/fromPy contract

When you pass an `Object` or wrapper type to `setAttr`, `call`, or similar
APIs, alloconda uses `toPy` internally. The critical invariant:

- **Owned objects**: the reference is transferred (no refcount change)
- **Borrowed objects**: the refcount is incremented (caller keeps their ref)

This means you can safely do:

```zig
const new_obj = try py.Object.from(value);
try self.setAttr("x", new_obj);
// new_obj ownership transferred - don't call deinit()
```

With a borrowed reference (no `deinit()` needed):

```zig
const item = try list.get(0);  // Borrowed from list
try self.setAttr("copy", item);
// setAttr incremented the refcount; list still owns the original
// Don't call deinit() on borrowed references
```

If you want to keep your own reference while also setting an attribute:

```zig
const other = try self.getAttr("other");  // Owned
defer other.deinit();  // We want to keep our reference

const copy = other.incref();  // Get another owned reference
try self.setAttr("copy", copy);
// copy's ownership transferred to Python - don't deinit it
```

**Important:** After passing an owned `Object` to `setAttr`, `call`, or similar
APIs, treat it as moved. Do not call `deinit()` on it.

## Slice lifetime hazards

`unicodeSlice()`, `bytesSlice()`, and `fromPy([]const u8, ...)` return
**borrowed views** into Python-owned memory. The slice is only valid while:

1. The underlying Python object is alive
2. You hold the GIL
3. You haven't called `deinit()` on the Object

```zig
// CORRECT: use slice while object is alive
const obj = try self.getAttr("name");
defer obj.deinit();
const slice = try obj.unicodeSlice();
// Use slice here - obj is still alive
try writer.writeAll(slice);

// WRONG: slice outlives object
fn dangerous(self: py.Object) ![]const u8 {
    const obj = try self.getAttr("name");
    defer obj.deinit();
    return try obj.unicodeSlice();  // BUG! Dangling pointer
}

// CORRECT: copy if you need to keep it
fn safe(self: py.Object, allocator: Allocator) ![]u8 {
    const obj = try self.getAttr("name");
    defer obj.deinit();
    const slice = try obj.unicodeSlice();
    return try allocator.dupe(u8, slice);
}
```

For longer-lived access to bytes, consider `py.Buffer` which explicitly
manages the lifetime via `release()`.

## Container element ownership

- `py.List.set` / `py.Tuple.set` transfer ownership into the container
  (the container steals the reference).
- `py.List.append` does not steal; it increments the refcount.
- `py.Dict.setItem` does not steal; it increments refcounts for key and value.
- `py.List.get` / `py.Tuple.get` / `py.Dict.getItem` return borrowed references.
- `py.DictIter` yields borrowed key/value pairs.

## Creating containers

Use tuple literals for ergonomic container creation:

```zig
// Create a list from values
const list = try py.List.from(.{1, 2, 3});
defer list.deinit();

// Create a tuple from values
const tuple = try py.Tuple.from(.{"hello", 42, true});
defer tuple.deinit();

// Or build incrementally
var list = try py.List.init(0);
errdefer list.deinit();
try list.append(1);
try list.append(2);
try list.append(3);
```

## Calling Python objects

```zig
// Call with no arguments
const result = try callable.call(.{});
defer result.deinit();

// Call with arguments
const result = try callable.call(.{"arg1", 42});
defer result.deinit();

// Call a method
const upper = try obj.callMethod("upper", .{});
defer upper.deinit();

// Call a method with arguments
const result = try obj.callMethod("format", .{value1, value2});
defer result.deinit();
```
