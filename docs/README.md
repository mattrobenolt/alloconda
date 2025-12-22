# Alloconda

Alloconda is Zig-first Python extensions with cross-compiled wheels. It has two
pieces:

- The Zig library, which provides a small wrapper API for CPython.
- The `alloconda` CLI, which builds, installs, and packages extensions.

This book is a user guide for building your own extension with alloconda.
Examples assume `uv` and `uvx` are available for running the CLI.

Project links:
- Docs: <https://alloconda.withmatt.com>
- Repo: <https://github.com/mattrobenolt/alloconda>
- Zig API: [zig-docs/index.html](zig-docs/index.html)

The Zig API reference is generated from `src/root.zig` and published alongside
this book at `zig-docs/index.html`.

## What alloconda is best at

Alloconda is built to cross-compile a full wheel matrix from a single machine.
If you care about shipping manylinux, musllinux, macOS, and Windows wheels without
multiple build hosts, start with the cross-compilation chapter.

## Versions

- Zig 0.15
- Python 3.14 (current testing target).

Start with the tutorial to scaffold a minimal project and build your first module.
