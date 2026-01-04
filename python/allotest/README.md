# allotest

Comprehensive test suite for alloconda, the Zig-based Python extension framework.

## Purpose

This module serves as the canonical test suite for the alloconda package. It exercises
all public alloconda APIs through Python integration tests, ensuring correct behavior
across Python versions and platforms.

## Test Organization

| File | Coverage |
|------|----------|
| `test_basic.py` | Function binding, argument parsing, type conversions |
| `test_types.py` | List, Dict, Tuple, and Bytes operations |
| `test_errors.py` | All exception types and error mapping |
| `test_objects.py` | Object methods, attributes, callables, type checks |
| `test_classes.py` | Class definitions, self parameter, multiple classes |
| `test_interop.py` | Python module imports and method calls |
| `test_gc.py` | Garbage collection edge cases and stress tests |
| `test_io.py` | IO adapter wrappers |

## API Coverage

### Basic Function Binding
- Positional arguments
- Optional arguments  
- Keyword arguments
- Argument count validation

### Type Conversions
- `i64`, `f64`, `bool`
- `[]const u8` (strings)
- `py.Bytes`, `py.BytesView`, `py.Buffer`, `py.List`, `py.Dict`, `py.Tuple`
- `py.Object` (any Python object)
- Optional types (`?T`)

### Collection Operations
- **Bytes**: `len`, `slice`, `fromSlice`
- **BytesView**: `len`, `slice`, `isBuffer`
- **List**: `init`, `len`, `get`, `set`, `append`
- **Dict**: `init`, `len`, `getItem`, `setItem`, `iter`
- **Tuple**: `len`, `get`, `toTuple`

### IO Operations
- `IoReader`/`IoWriter` adapters via `readinto`/`write`

### Object Operations
- `call0`, `call1`, `call2`
- `getAttr`, `setAttr`
- `callMethod0`, `callMethod1`
- Type checking (`isCallable`, `isNone`, `isUnicode`, etc.)

### Error Handling
- All exception types: `TypeError`, `ValueError`, `RuntimeError`, `MemoryError`,
  `OverflowError`, `ZeroDivisionError`, `AttributeError`, `IndexError`, `KeyError`
- Error mapping via `raiseError`

### Classes
- Basic class definitions
- Self parameter handling
- Multiple classes per module
- Mutable state via attributes
- GC and reference counting

### Python Interop
- `importModule`
- Method calls on Python objects

## Usage

Build and test:

```bash
cd python/allotest
just build test
```

Or using the workspace justfile:

```bash
just allotest
```

Run specific test file:

```bash
pytest -v tests/test_types.py
```

Run specific test class:

```bash
pytest -v tests/test_classes.py::TestCounter
```

## Adding New Tests

When adding new alloconda features:

1. Add the Zig implementation to `src/root.zig` in the appropriate section
2. Update `allotest/_allotest.pyi` with type stubs
3. Add tests to the corresponding `tests/test_*.py` file
4. Run `just build test` to verify

## Note

This module is not intended for distribution. It exists solely for testing alloconda internals.
