# Dataclass Serde (Future)

This document captures ideas for a higher-level API that automatically serializes/deserializes Python dataclasses to protobuf wire format.

## Motivation

The low-level `Reader`/`Writer` API is flexible but verbose. A dataclass-based API would:

1. Reduce boilerplate for common use cases
2. Provide type safety through Python's type hints
3. Exercise the Zig/Python interop heavily (good for testing alloconda)
4. Differentiate fastproto from other protobuf libraries

## Proposed API

```python
from dataclasses import dataclass
import fastproto
from fastproto import field

@dataclass
class Sample:
    value: float = field(1, proto_type="double")
    timestamp: int = field(2, proto_type="int64")

@dataclass  
class Timeseries:
    name: str = field(1)
    samples: list[Sample] = field(2)

# Encoding
ts = Timeseries(name="cpu", samples=[Sample(1.5, 1000)])
data = fastproto.encode(ts)

# Decoding
ts2 = fastproto.decode(Timeseries, data)
```

## Design Questions

### Field Number Assignment

**Option A: Explicit via `field()` (recommended)**
```python
value: float = field(1)
```
- Pros: Safe, matches protobuf semantics, survives field reordering
- Cons: More verbose

**Option B: Implicit by field order**
```python
value: float      # becomes field 1
timestamp: int    # becomes field 2
```
- Pros: Minimal syntax
- Cons: Fragile, reordering breaks compatibility

### Type Mapping

How do we infer the wire type from Python types?

| Python Type | Default Proto Type | Notes |
|-------------|-------------------|-------|
| `int` | `int64` | Could be configurable |
| `float` | `double` | Could be `float` for 32-bit |
| `bool` | `bool` | |
| `str` | `string` | |
| `bytes` | `bytes` | |
| `list[int]` | `packed int64` | Repeated field |
| `list[float]` | `packed double` | |
| `SomeDataclass` | `message` | Nested message |
| `list[SomeDataclass]` | `repeated message` | |

For ambiguous cases, allow explicit override:
```python
value: int = field(1, proto_type="sint32")
```

### Nested Messages

Dataclass fields that are other dataclasses become nested messages:
```python
@dataclass
class Inner:
    x: int = field(1)

@dataclass
class Outer:
    inner: Inner = field(1)  # Nested message
    inners: list[Inner] = field(2)  # Repeated nested
```

### Optional Fields

```python
from typing import Optional

@dataclass
class Message:
    required: str = field(1)
    optional: Optional[str] = field(2, default=None)
```

### Enums

```python
from enum import IntEnum

class Status(IntEnum):
    UNKNOWN = 0
    ACTIVE = 1
    INACTIVE = 2

@dataclass
class Message:
    status: Status = field(1)
```

## Implementation Notes

The `field()` function would return a `dataclasses.field()` with metadata:
```python
def field(number: int, *, proto_type: str | None = None, **kwargs):
    metadata = {"proto_field": number}
    if proto_type:
        metadata["proto_type"] = proto_type
    return dataclasses.field(metadata=metadata, **kwargs)
```

Encoding/decoding would use `dataclasses.fields()` to introspect:
```python
def encode(obj) -> bytes:
    w = Writer()
    for f in dataclasses.fields(obj):
        field_num = f.metadata["proto_field"]
        value = getattr(obj, f.name)
        # dispatch based on type...
    return w.finish()
```

## Open Questions

1. Should we use a decorator (`@fastproto.message`) or just detect dataclasses?
2. How to handle inheritance?
3. Should we support `__slots__` dataclasses?
4. Performance: introspect once and cache, or every time?
5. Validation: should we validate values match declared types?

## Prior Art

- **Pydantic**: Uses `BaseModel` inheritance, heavy validation
- **cattrs**: Structure/unstructure pattern, very flexible  
- **betterproto**: Dataclass-based protobuf, requires .proto files
- **msgspec**: Struct-based, extremely fast, good model to study

## Status

Not implemented. Focus is on the low-level `Reader`/`Writer` API first.