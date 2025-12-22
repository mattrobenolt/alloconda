# FAQ

## Why does `alloconda init` require `--alloconda-path`?

The scaffold uses a local path dependency in `build.zig.zon`. Point it at a local
alloconda checkout until a published Zig package is available.

## Why does `alloconda build` ask for a package directory?

The CLI needs a Python package directory to copy the extension into and to write
`__init__.py`. If it cannot infer one, pass `--package-dir` or set
`tool.alloconda.package-dir` in `pyproject.toml`.

## How do I rename the extension module?

Set the module name in `src/root.zig` and pass `--module` to the CLI if you need
to override symbol detection. You can also set `tool.alloconda.module-name`.
