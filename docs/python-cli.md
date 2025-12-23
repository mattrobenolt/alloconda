# CLI guide

The `alloconda` CLI builds, installs, and packages your extension module. This
guide assumes you run it via `uvx`.

## Running via uvx

Use `uvx` to run the CLI:

```bash
uvx alloconda build
uvx alloconda wheel
uvx alloconda wheel-all --python-version 3.14 --include-musllinux
```

## Scaffold

```bash
uvx alloconda init --name hello_alloconda
```

`alloconda init` creates `build.zig`, `build.zig.zon`, `src/root.zig`, and a
`python/<project_name>/__init__.py` package directory. If a `pyproject.toml`
exists, it adds the `build-system` block automatically.
Pass `--alloconda-path` to use a local alloconda checkout instead of fetching.

## Build

```bash
uvx alloconda build
```

Builds the Zig project, detects the `PyInit_*` symbol, and copies the extension
into the package directory. Use `--package-dir` if the CLI cannot infer it.

## Develop

```bash
uvx alloconda develop
```

Performs an editable install via `pip install -e .` (or `uv pip` if available).

## Wheels

```bash
uvx alloconda wheel
uvx alloconda wheel-all
```

`wheel` builds a single wheel for the current platform. `wheel-all` builds a
matrix across Python versions and platforms. Cross-compilation is a first-class
feature: you can target manylinux/musllinux, macOS, and Windows from one host.

## Inspect

```bash
uvx alloconda inspect --lib zig-out/lib/libhello_alloconda.dylib
uvx alloconda inspect --wheel dist/hello_alloconda-0.1.0-*.whl --verify
```

Inspect a built library or wheel and print derived metadata.

## Python headers for cross builds

```bash
uvx alloconda python fetch --version 3.14 --manylinux 2_28 --arch x86_64
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
package-dir = "python/hello_alloconda"
python-version = "3.14"
```

Any CLI flag can override these defaults.
