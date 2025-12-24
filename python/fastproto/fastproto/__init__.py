"""Fast protobuf wire format encoding/decoding.

This library provides low-level primitives for reading and writing protobuf
wire format messages without requiring .proto files or code generation.

Example usage:

    import fastproto

    # Writing a message
    writer = fastproto.Writer()
    writer.string(1, "hello")
    writer.int64(2, 42)
    data = writer.finish()

    # Reading a message
    for field in fastproto.Reader(data):
        if field.number == 1:
            print(field.string())
        elif field.number == 2:
            print(field.int64())

The library automatically uses a Zig-accelerated implementation when available,
falling back to a pure Python implementation otherwise. Check `__speedups__`
to see which implementation is active.
"""

import os
from enum import IntEnum
from importlib.metadata import PackageNotFoundError, version


class WireType(IntEnum):
    """Protobuf wire types."""

    VARINT = 0  # int32, int64, uint32, uint64, sint32, sint64, bool, enum
    FIXED64 = 1  # fixed64, sfixed64, double
    LEN = 2  # string, bytes, embedded messages, packed repeated fields
    FIXED32 = 5  # fixed32, sfixed32, float


_force_pure = os.environ.get("FASTPROTO_FORCE_PURE")
if _force_pure and _force_pure not in {"0", "false", "False"}:
    from fastproto._pure import Reader, Writer

    __speedups__ = False
else:
    try:
        from fastproto._accelerated import Reader, Writer

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
)
