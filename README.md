# alloconda

Alloconda is Zig-first Python extensions with cross-compiled wheels.

Project links:
- Docs: <https://alloconda.withmatt.com>
- Repo: <https://github.com/mattrobenolt/alloconda>
- Zig API: <https://alloconda.withmatt.com/zig-docs/>

## Quickstart (uv)

```bash
mkdir hello_alloconda
cd hello_alloconda
uv init
uvx alloconda init
uvx alloconda develop
uv run python -c "import hello_alloconda; print(hello_alloconda.hello('alloconda'))"
```

`alloconda init` scaffolds the Zig project, wires up the build backend, and
creates a default Python package under `src/<project_name>/`.

## Build wheels

```bash
uvx alloconda wheel-all --python-version 3.14 --include-musllinux --fetch
```

This builds a multi-platform wheel matrix in `dist/` using cached
python-build-standalone headers.

## Documentation

The full guide lives at <https://alloconda.withmatt.com>.
