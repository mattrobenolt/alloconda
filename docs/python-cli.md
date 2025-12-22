# CLI guide

The `alloconda` CLI builds, installs, and packages your extension module.

## Running via uvx

If you use `uv`, you can run the CLI without a global install:

```bash
uvx alloconda build
uvx alloconda wheel
uvx alloconda wheel-all --python-version 3.14 --include-musllinux
```

## Scaffold

```bash
uvx alloconda init --name hello_alloconda --alloconda-path ../alloconda
```

`alloconda init` creates `build.zig`, `build.zig.zon`, and `src/root.zig`. It does
not create the Python package or `pyproject.toml`, so add those yourself.

## Build

```bash
alloconda build
```

Builds the Zig project, detects the `PyInit_*` symbol, and copies the extension
into the package directory. Use `--package-dir` if the CLI cannot infer it.

## Develop

```bash
alloconda develop
```

Performs an editable install via `pip install -e .` (or `uv pip` if available).

## Wheels

```bash
alloconda wheel
alloconda wheel-all
```

`wheel` builds a single wheel for the current platform. `wheel-all` builds a
matrix across Python versions and platforms. Cross-compilation is a first-class
feature: you can target manylinux/musllinux, macOS, and Windows from one host.

## Inspect

```bash
alloconda inspect --lib zig-out/lib/libhello_alloconda.dylib
alloconda inspect --wheel dist/hello_alloconda-0.1.0-*.whl --verify
```

Inspect a built library or wheel and print derived metadata.

## Python headers for cross builds

```bash
alloconda python fetch --version 3.14 --manylinux 2_28 --arch x86_64
```

This caches python-build-standalone headers for cross compilation.

## Cross-compilation guide

See the dedicated cross-compilation chapter for the recommended workflow and
flag combinations.

## Configuration (`tool.alloconda`)

You can set defaults in `pyproject.toml`:

```toml
[tool.alloconda]
module-name = "_hello_alloconda"
package-dir = "src/hello_alloconda"
python-version = "3.14"
```

Any CLI flag can override these defaults.
