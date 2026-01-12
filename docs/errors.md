# Error handling

Alloconda translates Zig errors into Python exceptions and provides helpers for
setting exceptions explicitly.

## Automatic error propagation

In most cases, just use `try` and errors propagate automatically. The framework
handles converting Zig errors to Python exceptions:

```zig
fn process(self: *Self, obj: py.Object) !py.Object {
    const attr = try obj.getAttr("data");  // AttributeError propagates automatically
    const items = try py.List.fromObject(attr);  // TypeError propagates automatically
    return try items.getItem(0);  // IndexError propagates automatically
}
```

Only use explicit `catch` when you need to:
- Inspect the exception type
- Suppress specific exceptions
- Add additional context

## Two error paths

There are two distinct error propagation paths in alloconda:

### 1. Python exceptions (already set)

When calling Python APIs, the exception may already be set in Python's error
state. Alloconda's FFI wrappers detect this and return `error.PythonError`.
Use `try` to propagate these automatically:

```zig
const attr = try obj.getAttr("missing");  // AttributeError propagates
```

When you return `error.PythonError` from a bound function, alloconda sees that
Python already has an exception set and propagates it to the caller.

### 2. Zig errors (need translation)

When a Zig operation fails (allocation, parsing, validation), you need to
translate it into a Python exception:

```zig
fn parseConfig(text: []const u8) !Config {
    return std.json.parseFromSlice(Config, py.allocator, text, .{}) catch {
        return py.raise(.ValueError, "invalid JSON");
    };
}
```

The key distinction: `py.raise()` sets the Python exception *and* returns
`error.PythonError`, so you can do both in one step.

## Return types

The return type of your function determines how alloconda handles the result:

| Return Type | Success | Error |
|-------------|---------|-------|
| `T` | Converted to Python object | N/A (can't fail) |
| `?T` | Value or `None` | N/A (can't fail) |
| `!T` | Converted to Python object | Python exception |
| `!void` | Returns `None` | Python exception |

Zig infers the error set automatically, so prefer `!T` over explicit `py.PyError!T`.

### Using optional returns

Optional returns (`?T`) are for representing `None`, not errors:

```zig
// CORRECT: optional for "not found" semantics
fn findItem(self: py.Object, key: []const u8) ?py.Object {
    return self.getAttrOrNull(key) catch null;
}

// WRONG: don't use optional when errors are possible
fn parseNumber(text: []const u8) ?i64 {
    return std.fmt.parseInt(i64, text, 10) catch null;  // Hides error info!
}

// CORRECT: use error union for fallible operations
fn parseNumber(text: []const u8) !i64 {
    return std.fmt.parseInt(i64, text, 10) catch {
        return py.raise(.ValueError, "invalid number");
    };
}
```

If a function returns `?T` and a Python exception is set, alloconda raises a
runtime error to enforce this contract.

## Raising exceptions

### Simple exceptions

```zig
return py.raise(.TypeError, "expected string");
return py.raise(.ValueError, "value out of range");
return py.raise(.KeyError, "missing key");
```

Available exception types: `TypeError`, `ValueError`, `RuntimeError`,
`KeyError`, `IndexError`, `AttributeError`, `OverflowError`, `ZeroDivisionError`,
`MemoryError`, `StopIteration`, `OSError`, `PermissionError`.

### Mapping Zig errors

Use `py.raiseError` to map specific Zig errors to Python exceptions:

```zig
fn readFile(path: []const u8) ![]u8 {
    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        return py.raiseError(err, &.{
            .{ .err = error.FileNotFound, .kind = .OSError, .msg = "file not found" },
            .{ .err = error.AccessDenied, .kind = .PermissionError, .msg = "access denied" },
        });
    };
    defer file.close();
    return file.readToEndAlloc(py.allocator, 1024 * 1024) catch {
        return py.raise(.MemoryError, "file too large");
    };
}
```

If the error doesn't match any mapping, `raiseError` raises a `RuntimeError`
with the Zig error name.

### Inspecting or suppressing exceptions

Use explicit `catch` only when you need to inspect or suppress exceptions:

```zig
const result = obj.getAttr("missing") catch |err| {
    if (py.ffi.PyErr.exceptionMatches(.AttributeError)) {
        py.ffi.PyErr.clear();
        return py.none();  // Suppress AttributeError, return None
    }
    return err;  // Re-raise other exceptions
};
```

## Error handling in slots

Special method slots (`__len__`, `__hash__`, `__bool__`) have specific return
conventions. Alloconda handles the translation:

```zig
// __len__ returns usize, but C slot expects Py_ssize_t with -1 for error
fn myLen(self: py.Object) !usize {
    const items = try self.getAttr("items");
    defer items.deinit();
    return try py.List.fromObject(items).len();
}
```

Alloconda wraps this to return `-1` on error, per Python's slot protocol.

## Automatic error mapping

Some Zig errors are automatically mapped to Python exceptions without needing
explicit `raiseError` mappings:

| Zig Error | Python Exception |
|-----------|------------------|
| `error.OutOfMemory` | `MemoryError` |
| `error.InvalidCharacter`, `error.InvalidValue` | `ValueError` |
| `error.Overflow` | `OverflowError` |
| `error.DivisionByZero` | `ZeroDivisionError` |
| `error.EndOfStream`, `error.FileNotFound` | `OSError` |
| `error.AccessDenied` | `PermissionError` |
| (all others) | `RuntimeError` with error name as message |

```zig
fn allocateLarge(size: usize) ![]u8 {
    return py.allocator.alloc(u8, size); // Automatically becomes MemoryError
}
```

Unmapped errors become `RuntimeError` with the Zig error name:

```zig
fn mightFail() !void {
    return error.InvalidState;  // Becomes RuntimeError("InvalidState")
}
```

Use `py.raiseError` when you need a specific exception type or custom message:

```zig
return py.raiseError(err, &.{
    .{ .err = error.InvalidFormat, .kind = .ValueError, .msg = "bad format" },
});
```
