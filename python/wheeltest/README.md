# wheeltest

Multi-Python version wheel testing harness for alloconda projects.

This tool builds native wheels for multiple Python versions and runs the test
suite against each one, ensuring your Zig extension works correctly across all
supported Python versions.

## Installation

`wheeltest` is part of the alloconda workspace. After syncing:

```bash
uv sync --all-packages
```

The `wheeltest` command will be available.

## Usage

### Test all configured versions

```bash
wheeltest zigadd
```

This reads `python-version` from `[tool.alloconda]` in the package's
`pyproject.toml` and tests each version.

### Test specific version(s)

```bash
wheeltest zigadd -p 3.13
wheeltest zigadd -p 3.12 -p 3.13 -p 3.14
```

### Use existing wheels (skip build)

```bash
wheeltest zigadd --no-build
```

Useful when you've already built wheels and just want to re-run tests.

### Build only (skip tests)

```bash
wheeltest zigadd --build-only
```

### Dry run

```bash
wheeltest zigadd --dry-run
```

Shows what would be done without actually doing it.

### Pass arguments to pytest

```bash
wheeltest zigadd -- -v -k test_add
```

Everything after `--` is passed to pytest.

## Configuration

Add the Python versions to test in your package's `pyproject.toml`:

```toml
[tool.alloconda]
python-version = ["3.12", "3.13", "3.14"]
```

## How It Works

1. **Find package**: Locates the package directory (e.g., `python/zigadd/`)
2. **Read config**: Gets Python versions from `[tool.alloconda]`
3. **Clean dist/**: Removes existing wheels before building (skipped with `--no-build`)
4. **Build wheels**: Runs `alloconda wheel --python-version X.Y` for each version
5. **Create venvs**: Uses `uv venv --python X.Y` for isolated environments
6. **Install**: Installs the wheel and pytest via `uv pip install`
7. **Test**: Copies tests to a temp directory and runs pytest

Tests are copied to a temp directory to avoid importing from the source tree
instead of the installed wheel.

## Working Directory

Venvs are created in `.wheeltest/` inside the package directory. This is
gitignored by default.

## Requirements

- `alloconda` must be available (for building wheels)
- `uv` must be installed (for venv management)
- Python versions must be available via uv (downloads automatically if needed)
- Package must have a `tests/` directory