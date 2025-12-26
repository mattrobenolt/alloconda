```
  ▜ ▜          ▌
▀▌▐ ▐ ▛▌▛▘▛▌▛▌▛▌▀▌
█▌▐▖▐▖▙▌▙▖▙▌▌▌▙▌█▌
```

Alloconda is Zig-first Python extensions with cross-compiled wheels.

## Supported Versions

- **Python**: 3.10 – 3.14
- **Zig**: 0.15

## Commands

### `alloconda build`

Build the extension via `zig build`, detect the `PyInit_*` symbol, and copy the
compiled library into the Python package directory.

```bash
uvx alloconda build
```

Options:
- `--release`: use `-Doptimize=ReleaseFast`
- `--module`: override the `PyInit_*` module name
- `--lib`: path to a prebuilt library
- `--package-dir`: where to install the extension
- `--ext-suffix`: override the extension suffix (useful for cross builds)
- `--zig-target`: Zig target triple for cross builds
- `--python-include`: cross-build Python include path
- `--no-init` / `--force-init`: control `__init__.py` generation

### `alloconda wheel`

Build a wheel by staging the package, copying the compiled extension, and writing
`dist-info` metadata. This is intentionally lightweight and targets the common
PEP 427 path.

```bash
uvx alloconda wheel --python-tag cp312 --abi-tag cp312 --manylinux 2_28 --arch x86_64
```

Options:
- Tag selection: `--python-tag`, `--abi-tag`, `--platform-tag`
- Manylinux/musllinux helpers: `--manylinux`, `--musllinux`, `--arch`
- `--python-version` / `--pbs-target`: use cached python-build-standalone headers
- `--ext-suffix`: override the extension suffix for cross builds
- `--out-dir`: wheel output directory (default: `dist/`)
- `--skip-build`: skip `zig build` if you already built the library
- `--no-fetch`: disable automatic header downloads

Missing python-build-standalone headers are fetched automatically when
`--python-version` is specified. Use `--no-fetch` to require a pre-populated cache.
If `--python-tag` is omitted, it defaults from `--python-version` (e.g. `cp314`).

### `alloconda wheel-all`

Build a full wheel matrix across common platforms and Python versions.

```bash
uvx alloconda wheel-all --python-version 3.14 --include-musllinux
```

Options:
- `--python-version` (repeatable) or `--all` for every available version
- `--target` to override the default platform list
- `--include-windows` to add Windows targets (experimental)
- `--no-fetch` to disable automatic header downloads
- `--dry-run` to print the matrix

### `alloconda develop`

Build and install the project in editable mode via `pip install -e .` (or `uv pip`).

```bash
uvx alloconda develop
```

Options:
- `--release`: use `-Doptimize=ReleaseFast`
- `--module`: override the `PyInit_*` module name
- `--lib`: path to a prebuilt library
- `--package-dir`: where to install the extension
- `--ext-suffix`: override the extension suffix
- `--zig-target`: Zig target triple for cross builds
- `--python-include`: cross-build Python include path
- `--skip-build`: skip the zig build step (requires existing output)
- `--no-init` / `--force-init`: control `__init__.py` generation
- `--pip-arg`: extra args passed through to pip (repeatable)
- `--uv`: use `uv pip` (auto-selected if pip is missing)

### `alloconda init`

Scaffold a Zig project for an alloconda Python extension module.

```bash
uvx alloconda init
```

This creates `build.zig`, `build.zig.zon`, `src/root.zig`, and a default package
directory at `python/<project_name>/__init__.py`.

Options:
- `--name` to override the project name
- `--module-name` to override the Python extension module name
- `--dir` to choose a target directory
- `--alloconda-path` to use a local checkout or `git+https` URL
- `--force` to overwrite existing files

If `--alloconda-path` is omitted, alloconda is fetched from GitHub and pinned in
`build.zig.zon`.

If `pyproject.toml` exists, the build backend stanza is added automatically.

### `alloconda inspect`

Inspect built wheels (inspect) or libraries (inspect-lib) and print derived
metadata. Useful for quick sanity checks in scripts.

```bash
uvx alloconda inspect dist/zigadd-0.1.0-*.whl --verify
uvx alloconda inspect-lib zig-out/lib/libzigadd.dylib
```

### `alloconda python fetch`

Fetch and cache python-build-standalone headers for cross builds.

```bash
uvx alloconda python fetch --version 3.14 --manylinux 2_28 --arch x86_64
```

The cache location can be overridden with `ALLOCONDA_PBS_CACHE` or `--cache-dir`.

## Build backend

Add this to `pyproject.toml` to use alloconda as a build backend:

```toml
[build-system]
requires = ["alloconda"]
build-backend = "alloconda.build_backend"
```

## Configuration

Alloconda reads optional defaults from `pyproject.toml`:

```toml
[tool.alloconda]
module-name = "_zigadd"
package-dir = "zigadd"
python-version = "3.14"
optimize = "ReleaseFast"
build-step = "lib"
python-tag = "cp314"
abi-tag = "cp314"
manylinux = "2_28"
arch = "x86_64"
include = ["*.pyi"]
exclude = ["tests/*"]
```

Release is the default. Use `--debug` to build with `-Doptimize=Debug`; `optimize`
only affects release builds. CLI flags and PEP 517 `--config-settings` override
these values.

Use `build-step` to run a specific Zig build step (e.g. `lib` runs `zig build lib`).
