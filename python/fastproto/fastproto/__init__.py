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

import dataclasses
import os
import sys
from enum import IntEnum
from importlib.metadata import PackageNotFoundError, version
from typing import Any, Callable, TypeVar

if sys.version_info >= (3, 12):
    from collections.abc import Buffer
else:
    Buffer = bytes | bytearray | memoryview  # type: ignore[misc]

T = TypeVar("T")


def _not_available(*args: object, **kwargs: object) -> None:  # noqa: ARG001
    raise RuntimeError("encode/decode requires the native extension")


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


encode: Callable[[object], bytes]
decode: Callable[[type[T], bytes | Buffer], T]
encode_into: Callable[["Writer", object], None]
decode_from: Callable[[type[T], "Reader"], T]

_force_pure = os.environ.get("FASTPROTO_FORCE_PURE")
if _force_pure and _force_pure not in {"0", "false", "False"}:
    from fastproto._pure import Reader, Writer

    __speedups__ = False
    encode = _not_available  # type: ignore[assignment]
    decode = _not_available  # type: ignore[assignment]
    encode_into = _not_available  # type: ignore[assignment]
    decode_from = _not_available  # type: ignore[assignment]
else:
    try:
        from fastproto._native import (
            Reader,
            Writer,
            decode,
            decode_from,
            encode,
            encode_into,
        )

        __speedups__ = True
    except ImportError:
        from fastproto._pure import Reader, Writer

        __speedups__ = False
        encode = _not_available  # type: ignore[assignment]
        decode = _not_available  # type: ignore[assignment]
        encode_into = _not_available  # type: ignore[assignment]
        decode_from = _not_available  # type: ignore[assignment]

try:
    __version__ = version("fastproto")
except PackageNotFoundError:
    __version__ = "unknown"


def field(
    number: int,
    *,
    proto_type: str | None = None,
    default: T = ...,  # type: ignore[assignment]
    default_factory: Callable[[], T] = ...,  # type: ignore[assignment]
    **kwargs: Any,
) -> T:
    """Create a dataclass field with protobuf metadata.

    Args:
        number: The protobuf field number (must be positive integer)
        proto_type: Optional explicit proto type (e.g., "sint32", "fixed64", "double")
        default: Default value for the field
        default_factory: Factory function for default value
        **kwargs: Additional arguments passed to dataclasses.field()
    """
    metadata: dict[str, Any] = {"proto_field": number}
    if proto_type is not None:
        metadata["proto_type"] = proto_type

    field_kwargs: dict[str, Any] = {"metadata": metadata, **kwargs}
    if default is not ...:
        field_kwargs["default"] = default
    if default_factory is not ...:
        field_kwargs["default_factory"] = default_factory

    return dataclasses.field(**field_kwargs)  # type: ignore[return-value]


__all__ = (
    "Reader",
    "Writer",
    "WireType",
    "Scalar",
    "field",
    "encode",
    "decode",
    "encode_into",
    "decode_from",
)
