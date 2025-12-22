# Alloconda

Alloconda is a Zig-first toolkit for building Python extension modules. It has two
pieces:

- The Zig library, which provides a small wrapper API for CPython.
- The `alloconda` CLI, which builds, installs, and packages extensions.

This book is a user guide for building your own extension with alloconda.

## What alloconda is best at

Alloconda is built to cross-compile a full wheel matrix from a single machine.
If you care about shipping manylinux, musllinux, macOS, and Windows wheels without
multiple build hosts, start with the cross-compilation chapter.

## Versions

- Zig 0.15.x (the scaffold pins 0.15.2).
- Python 3.14 (current testing target).

Start with the tutorial to scaffold a minimal project and build your first module.
