# Packaging

Alloconda provides a PEP 517 build backend so standard tooling can build wheels
for your extension.

## Build backend setup

Add this to `pyproject.toml`:

```toml
[build-system]
requires = ["alloconda"]
build-backend = "alloconda.build_backend"
```

## Building wheels

You can either use the alloconda CLI via `uvx`:

```bash
uvx alloconda wheel
```

Or use standard PEP 517 tooling, such as `uv build --package your-project`. The
build backend reads `pyproject.toml` metadata and `tool.alloconda` settings.

For cross-compilation and multi-target builds, prefer the CLI (`wheel` /
`wheel-all`) so you can control the target matrix directly.

## Publishing

Alloconda does not ship a publish command. Use `twine` to upload built wheels.
