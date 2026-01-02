# Manual Setup

This guide shows how to add alloconda to an existing Zig project. Use this when
you already have Zig code and want to expose it to Python.

For new projects, `alloconda init` handles this automatically.

## Prerequisites

- An existing Zig project with `build.zig` and `build.zig.zon`
- A Python package directory (e.g., `mypackage/`)
- `pyproject.toml` for your Python project

## Step 1: Update pyproject.toml

Add alloconda as the build backend:

```toml
[build-system]
requires = ["alloconda"]
build-backend = "alloconda.build_backend"
```

Optional configuration can be added under `[tool.alloconda]`, but defaults
usually work. See the [CLI documentation](python-cli.md) for available options.

## Step 2: Add alloconda dependency

Use `zig fetch` to add alloconda to your `build.zig.zon`:

```bash
zig fetch --save git+https://github.com/mattrobenolt/alloconda?ref=main
```

This adds alloconda to your dependencies with a pinned commit hash.

## Step 3: Update build.zig

Import alloconda's build helpers and create a Python library target.

**Before** (typical Zig project):

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ... existing module/executable setup
}
```

**After** (with alloconda):

```zig
const std = @import("std");
const alloconda_build = @import("alloconda");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Get alloconda dependency
    const alloconda = b.dependency("alloconda", .{
        .target = target,
        .optimize = optimize,
    });

    // Your existing Zig module (optional - if you have library code)
    const mylib = b.addModule("mylib", .{
        .root_source_file = b.path("src/mylib/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Python bindings module - imports both alloconda and your library
    const bindings = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .strip = optimize != .Debug,
        .imports = &.{
            .{ .name = "alloconda", .module = alloconda.module("alloconda") },
            .{ .name = "mylib", .module = mylib },
        },
    });

    // Build the Python extension library
    const lib = alloconda_build.addPythonLibrary(b, .{
        .name = "_native",
        .root_module = bindings,
    });
    b.installArtifact(lib);

    // ... keep existing test steps, executables, etc.
}
```

Key changes:

1. Import `alloconda_build` at the top
2. Get the alloconda dependency with `b.dependency("alloconda", ...)`
3. Create a module for your Python bindings that imports `alloconda`
4. Use `alloconda_build.addPythonLibrary()` to create the shared library

## Step 4: Create Python bindings

Create `src/root.zig` (or wherever your bindings module points) with your
Python module definition:

```zig
const py = @import("alloconda");
const mylib = @import("mylib");

pub const MODULE = py.module("My module description.", .{
    .some_function = py.function(someFunction, .{
        .doc = "Function documentation.",
    }),
});

fn someFunction(arg: i64) i64 {
    return mylib.doSomething(arg);
}
```

The module name comes from `addPythonLibrary(.name=...)` and should match what
your Python `__init__.py` imports. A leading underscore (e.g., `_native`) is
conventional for extension modules.

## Step 5: Update Python __init__.py

Your Python package's `__init__.py` should import from the native module:

```python
try:
    from mypackage._native import some_function
    __native__ = True
except ImportError:
    # Fallback to pure Python implementation if available
    from mypackage._pure import some_function
    __native__ = False
```

## Step 6: Build and test

```bash
# Build the extension
uvx alloconda build

# Or install in development mode
uvx alloconda develop

# Test the import
python -c "import mypackage; print(mypackage.__native__)"
```

## Project structure

A typical project after setup:

```
myproject/
├── pyproject.toml
├── build.zig
├── build.zig.zon
├── src/
│   ├── root.zig          # Python bindings (pub const MODULE)
│   └── mylib/
│       └── root.zig      # Your Zig library code
└── mypackage/
    ├── __init__.py       # Imports from _native
    └── _pure.py          # Optional pure Python fallback
```

## Next steps

- See [Writing modules](zig-api.md) for the Zig API
- See [Working with Python types](types.md) for type conversions
- See [Error handling](errors.md) for exception mapping
