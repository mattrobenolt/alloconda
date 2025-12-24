# Tutorial: your first module

This tutorial creates a tiny extension module that exposes `hello(name)`.

## Prerequisites

- Zig 0.15.x.
- Python 3.10+.
- `uv` for project init and running the CLI via `uvx`.
- Network access for `zig fetch` (or pass `--alloconda-path`).

## 1) Initialize a Python project (uv)

Start by creating a `pyproject.toml` with `uv`:

```bash
mkdir hello_alloconda
cd hello_alloconda
uv init
```

`uv init` writes a `pyproject.toml` with basic project metadata, including the
project name that `alloconda init` will reuse. `alloconda init` will also add
the build backend stanza automatically.

## 2) Scaffold the Zig project

From a working directory, run:

```bash
uvx alloconda init
```

If you want to use a local alloconda checkout during development, pass
`--alloconda-path ../alloconda`. Otherwise `alloconda init` will pin the
dependency via `zig fetch`.

`alloconda init` writes:

- `build.zig`
- `build.zig.zon`
- `src/root.zig`

The default module name is `_<project_name>` (so `_hello_alloconda` here).

## 3) Verify the Python package

`alloconda init` creates `python/<project_name>/__init__.py` so the CLI can
locate the package directory. If you prefer a different layout, move the
package and set `tool.alloconda.package-dir` in `pyproject.toml`.

## 4) Build and import

```bash
uvx alloconda build
uv run python -c "import hello_alloconda; print(hello_alloconda.hello('alloconda'))"
```

If `alloconda build` cannot infer your package directory, pass it explicitly:

```bash
uvx alloconda build --package-dir python/hello_alloconda
```

The CLI copies the built extension into the package directory and generates an
`__init__.py` that re-exports the extension module.

If you prefer an editable install, use:

```bash
uvx alloconda develop
uv run python -c "import hello_alloconda; print(hello_alloconda.hello('alloconda'))"
```

## 5) Edit the module

Open `src/root.zig` and add new functions or classes using `py.method` and
`py.class`. The next chapters show the available patterns.

## 6) Cross-compile your first wheel matrix

Alloconda can build a multi-platform wheel matrix from one machine. Start with a
dry run to see the matrix:

```bash
uvx alloconda wheel-all --python-version 3.14 --include-musllinux --include-windows --dry-run
```

Then run the build (headers are fetched automatically by default):

```bash
uvx alloconda wheel-all --python-version 3.14 --include-musllinux --include-windows
```

For detailed targeting and configuration, see the cross-compilation chapter.
