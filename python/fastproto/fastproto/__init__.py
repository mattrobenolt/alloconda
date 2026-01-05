"""Fast protobuf wire format encoding/decoding.

This library provides low-level primitives for reading and writing protobuf
wire format messages without requiring .proto files or code generation.

Example usage:

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

    reader = fastproto.Reader(io.BytesIO(data))
    for field in reader:
        if field.number == 1:
            text = field.expect(fastproto.WireType.LEN).string()
            print(text)
        elif field.number == 2:
            value = field.expect(fastproto.WireType.VARINT).as_scalar(fastproto.Scalar.i64)
            print(value)

The library automatically uses a Zig-accelerated implementation when available,
falling back to a pure Python implementation otherwise. Check `__speedups__`
to see which implementation is active.
"""

import os
from enum import IntEnum
from importlib.metadata import PackageNotFoundError, version


class WireType(IntEnum):
    """Protobuf wire types."""

    VARINT = 0
    FIXED64 = 1
    LEN = 2
    FIXED32 = 5


class Scalar(IntEnum):
    """Scalar protobuf types."""

    i32 = 0
    i64 = 1
    u32 = 2
    u64 = 3
    sint32 = 4
    sint64 = 5
    bool = 6
    fixed64 = 7
    sfixed64 = 8
    double = 9
    fixed32 = 10
    sfixed32 = 11
    float = 12


_force_pure = os.environ.get("FASTPROTO_FORCE_PURE")
if _force_pure and _force_pure not in {"0", "false", "False"}:
    from fastproto._pure import Reader, Writer

    __speedups__ = False
else:
    try:
        from fastproto._native import Reader, Writer

        __speedups__ = True
    except ImportError:
        from fastproto._pure import Reader, Writer

        __speedups__ = False

try:
    __version__ = version("fastproto")
except PackageNotFoundError:
    __version__ = "unknown"

__all__ = (
    "Reader",
    "Writer",
    "WireType",
    "Scalar",
)
