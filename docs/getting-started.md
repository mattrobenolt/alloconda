# Tutorial: your first module

This tutorial creates a tiny extension module that exposes `hello(name)`.

## Prerequisites

- Zig 0.15.x.
- Python 3.14.
- The `alloconda` CLI available on your PATH.
- A local alloconda checkout (used by `alloconda init`).
- `uv` for project init and running the CLI without a global install.

## 1) Initialize a Python project (uv)

If you use `uv`, start by creating a `pyproject.toml`:

```bash
mkdir hello_alloconda
cd hello_alloconda
uv init
```

Then add the alloconda build backend and basic metadata:

```toml
[build-system]
requires = ["alloconda"]
build-backend = "alloconda.build_backend"

[project]
name = "hello_alloconda"
version = "0.1.0"
requires-python = ">=3.14"
```

If you do not use `uv`, create the same `pyproject.toml` manually.

## 2) Scaffold the Zig project

From a working directory, run:

```bash
uvx alloconda init --name hello_alloconda --alloconda-path ../alloconda
# or, if alloconda is already installed:
# alloconda init --name hello_alloconda --alloconda-path ../alloconda
```

`alloconda init` writes:

- `build.zig`
- `build.zig.zon`
- `src/root.zig`

The default module name is `_<project_name>` (so `_hello_alloconda` here).

## 3) Create the Python package

Create a package directory and minimal `pyproject.toml` so the CLI can locate the
package and read metadata:

```bash
mkdir -p src/hello_alloconda
```

If `uv init` already created a package layout for you, adjust the directory name
or skip this step.

## 4) Build and import

```bash
alloconda build
python -c "import hello_alloconda; print(hello_alloconda.hello('alloconda'))"
```

If you are using `uvx` instead of a global install:

```bash
uvx alloconda build
```

If `alloconda build` cannot infer your package directory, pass it explicitly:

```bash
alloconda build --package-dir src/hello_alloconda
```

The CLI copies the built extension into the package directory and generates an
`__init__.py` that re-exports the extension module.

## 5) Edit the module

Open `src/root.zig` and add new functions or classes using `py.method` and
`py.class`. The next chapters show the available patterns.

## 6) Cross-compile your first wheel matrix

Alloconda can build a multi-platform wheel matrix from one machine. Start with a
dry run to see the matrix:

```bash
alloconda wheel-all --python-version 3.14 --include-musllinux --include-windows --dry-run
```

Then run the build (and fetch any missing headers automatically):

```bash
alloconda wheel-all --python-version 3.14 --include-musllinux --include-windows --fetch
```

You can also run these via `uvx`:

```bash
uvx alloconda wheel-all --python-version 3.14 --include-musllinux --include-windows --fetch
```

For detailed targeting and configuration, see the cross-compilation chapter.
