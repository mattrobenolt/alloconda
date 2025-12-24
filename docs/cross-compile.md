# Cross-compiling wheels

Alloconda is designed to build wheels for multiple targets from a single machine.
This is a core feature: you can produce a full matrix without juggling separate
build hosts.

## How it works (high level)

- Zig handles cross compilation for the extension module.
- alloconda can fetch python-build-standalone headers for target platforms.
- `alloconda wheel-all` coordinates a build matrix across Python versions and
  platforms.

## Fetch target headers

For cross builds, fetch headers for the target Python version and platform:

```bash
uvx alloconda python fetch --version 3.14 --manylinux 2_28 --arch x86_64
```

The headers are cached locally and reused across builds.

Both `wheel` and `wheel-all` fetch missing headers automatically; use `--no-fetch`
to disable network access.

## Build a single cross-target wheel

```bash
uvx alloconda wheel \
  --python-version 3.14 \
  --manylinux 2_28 \
  --arch x86_64
```

Examples for other targets:

```bash
# macOS arm64
uvx alloconda wheel --python-version 3.14 --platform-tag macosx_14_0_arm64 --arch arm64

# Windows x86_64
uvx alloconda wheel --python-version 3.14 --platform-tag win_amd64 --arch x86_64
```

When `--python-version` is set, alloconda fetches headers automatically and uses
them to select the right extension suffix. Use `--no-fetch` to require a
pre-populated cache.

## Build a full matrix

By default, `wheel-all` targets macOS (arm64 + x86_64) and manylinux 2_28
(x86_64 + aarch64). You can extend this matrix or override it entirely.

```bash
uvx alloconda wheel-all --python-version 3.14 --include-musllinux --include-windows
```

Use `--dry-run` to inspect the matrix before building. Use `--no-fetch` when you
want to require a pre-populated header cache:

```bash
uvx alloconda wheel-all --python-version 3.14 --include-musllinux --dry-run
uvx alloconda wheel-all --python-version 3.14 --include-musllinux --no-fetch
```

To override the target list explicitly, use `--target` (repeatable):

```bash
uvx alloconda wheel-all --python-version 3.14 \\
  --target macosx_14_0_arm64 \\
  --target manylinux_2_28_x86_64
```

## Configure defaults in `tool.alloconda`

Set project defaults in `pyproject.toml` so you don’t have to repeat flags:

```toml
[tool.alloconda]
python-version = ["3.14"]
optimize = "ReleaseFast"
targets = [
  "macosx_14_0_arm64",
  "macosx_11_0_x86_64",
  "manylinux_2_28_x86_64",
  "manylinux_2_28_aarch64",
]
```

Release builds are the default; use `--debug` when you want `-Doptimize=Debug`.
