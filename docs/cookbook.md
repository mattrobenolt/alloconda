# Patterns & tips

## Module + class pattern

Attach classes to a module via `.withTypes`:

```zig
const py = @import("alloconda");

const Greeter = py.class("Greeter", "A tiny class", .{
    .hello = py.method(hello, .{}),
});

pub const MODULE = py.module("_example", "Example module", .{})
    .withTypes(.{ .Greeter = Greeter });

fn hello(_: py.Object, name: []const u8) []const u8 {
    return name;
}
```

## Error handling patterns

Use error unions for fallible functions and raise Python exceptions explicitly:

```zig
fn parseCount(text: []const u8) py.PyError!usize {
    return std.fmt.parseInt(usize, text, 10) catch |err| {
        return py.raiseError(err, &.{
            .{ .err = error.Overflow, .kind = .OverflowError },
        });
    };
}
```

If you need a standard exception, `py.raise` is the shortest path:

```zig
fn needPositive(value: i64) py.PyError!void {
    if (value <= 0) return py.raise(.ValueError, "expected positive value");
}
```

## Ownership and lifetimes

Alloconda mirrors CPython refcount rules, but the wrappers hide most of the
boilerplate. These are the common patterns:

- `py.Object.borrowed` does not change refcounts; `py.Object.owned` wraps a
  reference you already own.
- `toPyObject()` returns an owned reference (increments if borrowed).
- `toObject()` returns an owned wrapper.
- `fromObject(...)` for `py.Bytes`/`py.List`/`py.Dict`/`py.Tuple` returns a
  borrowed wrapper.

Borrowed views (like `py.Bytes.slice`) are only valid while the backing Python
object is alive.

## Buffer protocol

Access buffer-backed data with `py.Buffer` and release the view when done:

```zig
fn bufferLen(obj: py.Object) py.PyError!usize {
    var view: py.Buffer = try .fromObject(obj);
    defer view.release();
    return view.len();
}
```

## Converting collections

Use the container helpers to build Python lists/tuples and read them back:

```zig
fn makeList() py.PyError!py.List {
    return .fromSlice(u8, &.{ 1, 2, 3 });
}

fn listToSlice(list: py.List, gpa: std.mem.Allocator) py.PyError![]u8 {
    return list.toSlice(u8, gpa);
}
```

`toSlice` allocates; the caller must free the buffer.

## Iterating dicts

`py.DictIter` yields borrowed key/value pairs:

```zig
fn keysUpper(dict: py.Dict) py.PyError!py.List {
    var out: py.List = try .init(0);
    errdefer out.deinit();
    var it = dict.iter();
    while (it.next()) |entry| {
        const key = try entry.key.as([]const u8);
        try out.append([]const u8, key);
    }
    return out;
}
```

## Override module name detection

If symbol detection picks the wrong `PyInit_*`, pass the module explicitly:

```bash
uvx alloconda build --module _my_module
```

## Control `__init__.py`

The CLI generates a re-exporting `__init__.py` by default. You can opt out or
overwrite:

- `--no-init` to skip generation
- `--force-init` to overwrite an existing file
