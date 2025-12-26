# Error handling

Alloconda translates Zig errors into Python exceptions and provides helpers for
setting exceptions explicitly. For bound methods, the return type determines
how values and errors are converted.

## Return types

- `T`: returned value is converted to a Python object.
- `?T`: `null` becomes `None`. Optional returns must not signal errors.
- `PyError!T`: errors become Python exceptions. The default is `RuntimeError`
  with the Zig error name unless you already set an exception.
- `PyError!void`: succeeds with `None`, errors become Python exceptions.

If you need to return `None` conditionally, use `?T` and return `null`. If you
need to signal errors, use `PyError!T` instead of optional returns.

## Raising exceptions manually

Use the helpers in `alloconda` when you need explicit control:

- `py.raise(.TypeError, "message")`
- `py.raiseError(err, &.{ .{ .err = MyError, .kind = .ValueError } })`

`py.raiseError` lets you map specific Zig errors to Python exception kinds.

```zig
fn parseCount(text: []const u8) py.PyError!usize {
    return std.fmt.parseInt(usize, text, 10) catch |err| {
        return py.raiseError(err, &.{
            .{ .err = error.Overflow, .kind = .OverflowError },
        });
    };
}
```

## Optional return guard

Optional returns are reserved for representing `None`. If a function returns
`?T` and sets a Python exception, alloconda raises a runtime error to keep the
API consistent. Use `PyError!T` when an error is possible.
