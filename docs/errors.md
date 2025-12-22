# Error handling

Alloconda translates Zig errors into Python exceptions and provides helpers for
setting exceptions explicitly.

## Error unions

If a method returns `error!T` or `error!void`, alloconda catches errors and raises
`RuntimeError` with the Zig error name (unless you have already set an exception).

## Raising exceptions manually

Use the helpers in `alloconda` when you need explicit control:

- `py.raise(.TypeError, "message")`
- `py.raiseError(err, &.{ .{ .err = MyError, .kind = .ValueError } })`

`py.raiseError` lets you map specific Zig errors to Python exception kinds.
