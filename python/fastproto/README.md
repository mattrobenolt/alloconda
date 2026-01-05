# fastproto

Fast protobuf wire format encoding/decoding for Python.

`fastproto` provides low-level primitives for reading and writing protobuf wire
format messages **without requiring `.proto` files or code generation**. It's
inspired by Go's [easyproto](https://github.com/VictoriaMetrics/easyproto).

## Features

- **No codegen required** - Work directly with field numbers and wire types
- **Stream-first API** - Read and write from file-like objects
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
import io
import fastproto

stream = io.BytesIO()
writer = fastproto.Writer(stream)

writer.write_tag(1, fastproto.WireType.LEN)
writer.write_len(b"hello")

writer.write_tag(2, fastproto.WireType.VARINT)
writer.write_scalar(fastproto.Scalar.i64, 42)

writer.flush()

data = stream.getvalue()
```

### Reading Messages

```python
import io
import fastproto

reader = fastproto.Reader(io.BytesIO(data))

for field in reader:
    match field.number:
        case 1:
            name = field.expect(fastproto.WireType.LEN).string()
        case 2:
            value = field.expect(fastproto.WireType.VARINT).as_scalar(
                fastproto.Scalar.i64
            )
```

### Nested Messages

```python
import io
import fastproto

inner_stream = io.BytesIO()
inner = fastproto.Writer(inner_stream)
inner.write_tag(1, fastproto.WireType.LEN)
inner.write_len(b"child")
inner.flush()
inner_data = inner_stream.getvalue()

outer_stream = io.BytesIO()
outer = fastproto.Writer(outer_stream)
outer.write_tag(1, fastproto.WireType.LEN)
outer.write_len(inner_data)
outer.flush()

outer_data = outer_stream.getvalue()

for field in fastproto.Reader(io.BytesIO(outer_data)):
    for nested_field in field.message():
        ...
```

### Streaming IO

```python
import fastproto
import io
import socket
import tempfile

stream = io.BytesIO(data)
for field in fastproto.Reader(stream):
    ...

with tempfile.TemporaryFile() as file:
    file.write(data)
    file.seek(0)
    for field in fastproto.Reader(file):
        ...

sock_a, sock_b = socket.socketpair()
with sock_a, sock_b:
    sock_a.sendall(data)
    sock_a.shutdown(socket.SHUT_WR)
    with sock_b.makefile("rb") as stream:
        for field in fastproto.Reader(stream):
            ...
```

## API Reference

### Enums

```python
from fastproto import Scalar, WireType

WireType.VARINT
WireType.FIXED64
WireType.LEN
WireType.FIXED32

Scalar.i32
Scalar.i64
Scalar.u32
Scalar.u64
Scalar.sint32
Scalar.sint64
Scalar.bool
Scalar.fixed64
Scalar.sfixed64
Scalar.double
Scalar.fixed32
Scalar.sfixed32
Scalar.float
```

### Writer

The `Writer` class writes protobuf-encoded messages to a binary IO stream.

```python
writer = fastproto.Writer(stream)

writer.write_tag(field_number, WireType.VARINT)
writer.write_scalar(Scalar.i64, 123)

writer.write_tag(field_number, WireType.LEN)
writer.write_len(b"payload")

writer.write_varint(999)
writer.flush()
```

### Reader

The `Reader` class parses protobuf-encoded messages from binary IO streams.

```python
reader = fastproto.Reader(stream)

for field in reader:
    print(field.number, field.wire_type)

# Or manually
while (field := reader.next()) is not None:
    ...

reader.remaining()  # Bytes left to read for bounded readers
```

### Field

The `Field` class represents a single parsed field.

```python
field.number      # Field number (int)
field.wire_type   # Wire type (WireType enum)

field.expect(WireType.LEN)
field.string()
field.bytes()
field.message()
field.skip()

field.expect(WireType.VARINT).as_scalar(Scalar.i64)
field.expect(WireType.FIXED64).as_scalar(Scalar.double)

field.repeated(Scalar.i32)
```

## Benchmarks

M1 MacBook Pro, Python 3.14.2, Zig 0.15.2.
Command: `pytest benchmarks/bench_encoding.py --benchmark-only`

| Test | Native Mean (us) | Pure Mean (us) | Speedup |
| --- | --- | --- | --- |
| test_encode_simple | 1.30 | 3.43 | 2.65x |
| test_decode_simple | 2.28 | 6.68 | 2.94x |
| test_encode_large_string | 2.70 | 2.73 | 1.01x |
| test_decode_large_string | 8.74 | 9.59 | 1.10x |
| test_encode_nested | 14.40 | 31.15 | 2.16x |
| test_decode_nested | 16.27 | 56.55 | 3.47x |
| test_encode_many_fields | 16.79 | 84.36 | 5.02x |
| test_decode_many_fields | 32.56 | 151.96 | 4.67x |
| test_encode_packed_int64s | 68.83 | 496.35 | 7.21x |
| test_decode_packed_int64s | 16.33 | 269.68 | 16.51x |
| test_encode_packed_doubles | 68.83 | 523.49 | 7.61x |
| test_decode_packed_doubles | 14.75 | 295.80 | 20.05x |
| test_decode_skip_all | 22.39 | 112.70 | 5.03x |
| test_roundtrip_simple | 3.56 | 10.31 | 2.89x |
