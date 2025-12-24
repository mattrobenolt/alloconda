# fastproto

Fast protobuf wire format encoding/decoding for Python.

`fastproto` provides low-level primitives for reading and writing protobuf wire format messages **without requiring `.proto` files or code generation**. It's inspired by Go's [easyproto](https://github.com/VictoriaMetrics/easyproto).

## Features

- **No codegen required** - Work directly with field numbers and wire types
- **Zero-copy reading** - Iterate over fields without copying data
- **Fast** - Optional Zig-accelerated implementation (automatic when available)
- **Pure Python fallback** - Works everywhere, even without compilation
- **Proto3 compatible** - Full support for all proto3 wire types

## Installation

```bash
uv add fastproto
```

Or with pip:

```bash
pip install fastproto
```

## Quick Start

### Writing Messages

```python
import fastproto

# Build a message
writer = fastproto.Writer()
writer.string(1, "hello")
writer.int64(2, 42)
writer.bool(3, True)
data = writer.finish()

# Nested messages
writer = fastproto.Writer()
writer.string(1, "parent")
with writer.message(2) as nested:
    nested.string(1, "child")
    nested.int32(2, 123)
data = writer.finish()
```

### Reading Messages

```python
import fastproto

# Iterate over fields
for field in fastproto.Reader(data):
    match field.number:
        case 1:
            name = field.string()
        case 2:
            value = field.int64()
        case 3:
            flag = field.bool()

# Read nested messages
for field in fastproto.Reader(data):
    if field.number == 2:
        for nested_field in field.message():
            ...
```

## API Reference

### Writer

The `Writer` class builds protobuf-encoded messages.

#### Scalar Types

```python
writer = fastproto.Writer()

# Varint types
writer.int32(field_num, value)      # Signed 32-bit (inefficient for negatives)
writer.int64(field_num, value)      # Signed 64-bit (inefficient for negatives)
writer.uint32(field_num, value)     # Unsigned 32-bit
writer.uint64(field_num, value)     # Unsigned 64-bit
writer.sint32(field_num, value)     # ZigZag-encoded (efficient for negatives)
writer.sint64(field_num, value)     # ZigZag-encoded (efficient for negatives)
writer.bool(field_num, value)       # Boolean
writer.enum(field_num, value)       # Enum (same as int32)

# Fixed-width types
writer.fixed32(field_num, value)    # Unsigned 32-bit, fixed encoding
writer.fixed64(field_num, value)    # Unsigned 64-bit, fixed encoding
writer.sfixed32(field_num, value)   # Signed 32-bit, fixed encoding
writer.sfixed64(field_num, value)   # Signed 64-bit, fixed encoding
writer.float(field_num, value)      # 32-bit float
writer.double(field_num, value)     # 64-bit double

# Length-delimited types
writer.string(field_num, value)     # UTF-8 string
writer.bytes(field_num, value)      # Raw bytes
```

#### Nested Messages

```python
# Using context manager (recommended)
with writer.message(field_num) as nested:
    nested.string(1, "value")

# Using explicit end()
nested = writer.message(field_num)
nested.string(1, "value")
nested.end()
```

#### Packed Repeated Fields

```python
writer.packed_int32s(field_num, [1, 2, 3])
writer.packed_int64s(field_num, values)
writer.packed_uint32s(field_num, values)
writer.packed_uint64s(field_num, values)
writer.packed_sint32s(field_num, values)
writer.packed_sint64s(field_num, values)
writer.packed_bools(field_num, values)
writer.packed_fixed32s(field_num, values)
writer.packed_fixed64s(field_num, values)
writer.packed_sfixed32s(field_num, values)
writer.packed_sfixed64s(field_num, values)
writer.packed_floats(field_num, values)
writer.packed_doubles(field_num, values)
```

#### Finalizing

```python
data = writer.finish()  # Returns bytes
writer.clear()          # Reset for reuse
```

### Reader

The `Reader` class parses protobuf-encoded messages.

```python
reader = fastproto.Reader(data)

# Iteration
for field in reader:
    print(field.number, field.wire_type)

# Or manually
while (field := reader.next_field()) is not None:
    ...

# Utilities
reader.remaining()  # Bytes left to read
reader.skip()       # Skip next field, returns True if skipped
```

### Field

The `Field` class represents a single parsed field.

```python
field.number      # Field number (int)
field.wire_type   # Wire type (WireType enum)

# Read as specific type (must match wire type)
field.int32()
field.int64()
field.uint32()
field.uint64()
field.sint32()
field.sint64()
field.bool()
field.enum()
field.fixed32()
field.fixed64()
field.sfixed32()
field.sfixed64()
field.float()
field.double()
field.string()
field.bytes()
field.message()       # Returns a Reader for nested message
field.message_data()  # Returns raw bytes

# Packed repeated (for LEN wire type)
field.packed_int32s()
field.packed_int64s()
field.packed_uint32s()
field.packed_uint64s()
field.packed_sint32s()
field.packed_sint64s()
field.packed_bools()
field.packed_fixed32s()
field.packed_fixed64s()
field.packed_sfixed32s()
field.packed_sfixed64s()
field.packed_floats()
field.packed_doubles()
```

### Wire Types

```python
from fastproto import WireType

WireType.VARINT   # 0: int32, int64, uint32, uint64, sint32, sint64, bool, enum
WireType.FIXED64  # 1: fixed64, sfixed64, double
WireType.LEN      # 2: string, bytes, embedded messages, packed repeated
WireType.FIXED32  # 5: fixed32, sfixed32, float
```

### Checking Implementation

```python
import fastproto

if fastproto.__speedups__:
    print("Using Zig-accelerated implementation")
else:
    print("Using pure Python implementation")
```

## Example: Timeseries Message

Here's a complete example encoding and decoding a timeseries message:

```proto
// Equivalent .proto definition (for reference only)
message Timeseries {
    string name = 1;
    repeated Sample samples = 2;
}

message Sample {
    double value = 1;
    int64 timestamp = 2;
}
```

```python
import fastproto
from dataclasses import dataclass

@dataclass
class Sample:
    value: float
    timestamp: int

    def encode(self) -> bytes:
        w = fastproto.Writer()
        w.double(1, self.value)
        w.int64(2, self.timestamp)
        return w.finish()

    @classmethod
    def decode(cls, data: bytes) -> "Sample":
        value = 0.0
        timestamp = 0
        for field in fastproto.Reader(data):
            match field.number:
                case 1: value = field.double()
                case 2: timestamp = field.int64()
        return cls(value=value, timestamp=timestamp)

@dataclass
class Timeseries:
    name: str
    samples: list[Sample]

    def encode(self) -> bytes:
        w = fastproto.Writer()
        w.string(1, self.name)
        for sample in self.samples:
            w.bytes(2, sample.encode())
        return w.finish()

    @classmethod
    def decode(cls, data: bytes) -> "Timeseries":
        name = ""
        samples = []
        for field in fastproto.Reader(data):
            match field.number:
                case 1: name = field.string()
                case 2: samples.append(Sample.decode(field.bytes()))
        return cls(name=name, samples=samples)

# Usage
ts = Timeseries(
    name="cpu_usage",
    samples=[
        Sample(value=0.75, timestamp=1700000000),
        Sample(value=0.82, timestamp=1700000001),
    ]
)

encoded = ts.encode()
decoded = Timeseries.decode(encoded)
assert decoded == ts
```

## Performance

When the Zig extension is available, `fastproto` provides significant performance improvements over pure Python:

| Operation | Pure Python | Zig | Speedup |
|-----------|-------------|-----|---------|
| Encode simple message | TBD | TBD | TBD |
| Decode simple message | TBD | TBD | TBD |
| Encode packed doubles | TBD | TBD | TBD |
| Decode packed doubles | TBD | TBD | TBD |

Run benchmarks yourself:

```bash
just bench
```

This runs parameterized benchmarks for native + pure backends in a single run
and sorts by name so the pairs are adjacent (`[native]` / `[pure]`).

## License

Apache-2.0
