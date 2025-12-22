# FAQ

## Why does `alloconda init` run `zig fetch`?

The scaffold adds alloconda as a Zig dependency. By default it fetches
`git+https://github.com/mattrobenolt/alloconda`, which gives you a pinned hash in
`build.zig.zon`. Use `--alloconda-path` if you want a local checkout instead.

## Why does `alloconda build` ask for a package directory?

The CLI needs a Python package directory to copy the extension into and to write
`__init__.py`. If it cannot infer one, pass `--package-dir` or set
`tool.alloconda.package-dir` in `pyproject.toml`.

## How do I rename the extension module?

Set the module name in `src/root.zig` and pass `--module` to the CLI if you need
to override symbol detection. You can also set `tool.alloconda.module-name`.
