"""Pure Python implementation of protobuf wire format encoding/decoding.

This module provides the reference implementation for fastproto. It's designed
to be correct and readable, serving as both a fallback when the Zig extension
is unavailable and as a specification for the Zig implementation to match.
"""

from __future__ import annotations

import builtins
import struct
from collections.abc import Iterator
from typing import BinaryIO, SupportsFloat, SupportsIndex, SupportsInt, cast

try:
    from collections.abc import Buffer  # type: ignore[unresolved-import]
except ImportError:
    Buffer = builtins.bytes | builtins.bytearray | memoryview

from fastproto import Scalar, WireType

__all__ = ["Reader", "Writer", "Field"]

_IntLike = SupportsInt | SupportsIndex | int | bool
_FloatLike = SupportsFloat | SupportsIndex | float


def make_tag(field_number: int, wire_type: WireType) -> int:
    """Create a tag from field number and wire type."""
    if field_number < 1:
        raise ValueError(f"field_number must be >= 1, got {field_number}")
    if field_number > 0x1FFFFFFF:
        raise ValueError(f"field_number too large: {field_number}")
    return (field_number << 3) | int(wire_type)


def parse_tag(tag: int) -> tuple[int, WireType]:
    """Parse a tag into field number and wire type."""
    wire_type = tag & 0x07
    field_number = tag >> 3
    if field_number < 1:
        raise ValueError(f"invalid field number: {field_number}")
    try:
        return field_number, WireType(wire_type)
    except ValueError:
        raise ValueError(f"invalid wire type: {wire_type}") from None


def encode_varint(value: int) -> builtins.bytes:
    """Encode an integer as a varint."""
    if value < 0:
        value = value & 0xFFFFFFFFFFFFFFFF
    result = bytearray()
    while value > 0x7F:
        result.append((value & 0x7F) | 0x80)
        value >>= 7
    result.append(value)
    return bytes(result)


def decode_varint(data: Buffer, offset: int = 0) -> tuple[int, int]:
    """Decode a varint from data at the given offset."""
    result = 0
    shift = 0
    pos = offset
    while True:
        if pos >= len(data):
            raise ValueError("truncated varint")
        byte = data[pos]
        pos += 1
        result |= (byte & 0x7F) << shift
        if not (byte & 0x80):
            break
        shift += 7
        if shift >= 64:
            raise ValueError("varint too long")
    return result, pos


def iter_varints(data: Buffer) -> Iterator[int]:
    """Iterate over varints in a packed repeated field."""
    offset = 0
    while offset < len(data):
        value, offset = decode_varint(data, offset)
        yield value


def zigzag_encode(value: int) -> int:
    """ZigZag encode a signed integer."""
    return (value << 1) ^ (value >> 63)


def zigzag_decode(value: int) -> int:
    """ZigZag decode an unsigned integer to signed."""
    return (value >> 1) ^ -(value & 1)


def _scalar_wire_type(scalar: Scalar) -> WireType:
    if scalar in {
        Scalar.i32,
        Scalar.i64,
        Scalar.u32,
        Scalar.u64,
        Scalar.sint32,
        Scalar.sint64,
        Scalar.bool,
    }:
        return WireType.VARINT
    if scalar in {Scalar.fixed64, Scalar.sfixed64, Scalar.double}:
        return WireType.FIXED64
    if scalar in {Scalar.fixed32, Scalar.sfixed32, Scalar.float}:
        return WireType.FIXED32
    raise ValueError("invalid scalar type")


def _decode_varint_scalar(scalar: Scalar, value: int) -> int | builtins.bool:
    if scalar is Scalar.i32:
        value &= 0xFFFFFFFF
        if value > 0x7FFFFFFF:
            value -= 0x100000000
        return value
    if scalar is Scalar.i64:
        if value > 0x7FFFFFFFFFFFFFFF:
            value -= 0x10000000000000000
        return value
    if scalar is Scalar.u32:
        return value & 0xFFFFFFFF
    if scalar is Scalar.u64:
        return value
    if scalar is Scalar.sint32:
        value = zigzag_decode(value & 0xFFFFFFFF)
        if value > 0x7FFFFFFF:
            value -= 0x100000000
        return value
    if scalar is Scalar.sint64:
        return zigzag_decode(value)
    if scalar is Scalar.bool:
        return value != 0
    raise ValueError("invalid scalar type")


def _decode_fixed32_scalar(scalar: Scalar, value: int) -> int | builtins.float:
    if scalar is Scalar.fixed32:
        return value
    if scalar is Scalar.sfixed32:
        if value > 0x7FFFFFFF:
            value -= 0x100000000
        return value
    if scalar is Scalar.float:
        return struct.unpack("<f", struct.pack("<I", value))[0]
    raise ValueError("invalid scalar type")


def _decode_fixed64_scalar(scalar: Scalar, value: int) -> int | builtins.float:
    if scalar is Scalar.fixed64:
        return value
    if scalar is Scalar.sfixed64:
        if value > 0x7FFFFFFFFFFFFFFF:
            value -= 0x10000000000000000
        return value
    if scalar is Scalar.double:
        return struct.unpack("<d", struct.pack("<Q", value))[0]
    raise ValueError("invalid scalar type")


def _decode_packed(
    data: Buffer, scalar: Scalar
) -> list[builtins.int | builtins.float | builtins.bool]:
    wire_type = _scalar_wire_type(scalar)
    if wire_type is WireType.VARINT:
        return [_decode_varint_scalar(scalar, value) for value in iter_varints(data)]
    if wire_type is WireType.FIXED32:
        if len(data) % 4 != 0:
            raise ValueError("packed fixed32 data length not a multiple of 4")
        values: list[builtins.int | builtins.float] = []
        for i in range(0, len(data), 4):
            raw = int.from_bytes(data[i : i + 4], "little")
            values.append(_decode_fixed32_scalar(scalar, raw))
        return values
    if wire_type is WireType.FIXED64:
        if len(data) % 8 != 0:
            raise ValueError("packed fixed64 data length not a multiple of 8")
        values = []
        for i in range(0, len(data), 8):
            raw = int.from_bytes(data[i : i + 8], "little")
            values.append(_decode_fixed64_scalar(scalar, raw))
        return values
    raise ValueError("invalid scalar type")


def _to_int(value: object) -> int:
    return int(cast(_IntLike, value))


def _to_float(value: object) -> float:
    return float(cast(_FloatLike, value))


class Reader:
    """Streaming protobuf reader."""

    __slots__ = ("_stream", "_remaining")

    def __init__(self, stream: BinaryIO) -> None:
        self._stream = stream
        self._remaining: int | None = None

    @classmethod
    def _from_stream(cls, stream: BinaryIO, remaining: int) -> Reader:
        self = cls.__new__(cls)
        self._stream = stream
        self._remaining = remaining
        return self

    def __iter__(self) -> Reader:
        return self

    def __next__(self) -> Field:
        field = self.next()
        if field is None:
            raise StopIteration
        return field

    def next(self) -> Field | None:
        if self._remaining == 0:
            return None

        tag = self._read_varint(allow_eof=self._remaining is None)
        if tag is None:
            return None
        field_number, wire_type = parse_tag(tag)

        if wire_type is WireType.VARINT:
            value = self._read_varint(allow_eof=False)
            if value is None:
                raise ValueError("truncated field")
            return Field(field_number, wire_type, value=value, reader=self)
        if wire_type is WireType.FIXED64:
            data = self._read_exact(8)
            value = int.from_bytes(data, "little")
            return Field(field_number, wire_type, value=value, reader=self)
        if wire_type is WireType.FIXED32:
            data = self._read_exact(4)
            value = int.from_bytes(data, "little")
            return Field(field_number, wire_type, value=value, reader=self)
        if wire_type is WireType.LEN:
            length = self._read_varint(allow_eof=False)
            if length is None:
                raise ValueError("truncated field")
            return Field(field_number, wire_type, length=length, reader=self)
        raise ValueError("invalid wire type")

    def remaining(self) -> int | None:
        return self._remaining

    def _read_byte(self, allow_eof: bool) -> int | None:
        if self._remaining == 0:
            if allow_eof:
                return None
            raise ValueError("truncated field")
        data = self._stream.read(1)
        if data == b"":
            if allow_eof:
                return None
            raise ValueError("truncated field")
        if self._remaining is not None:
            self._remaining -= 1
        return data[0]

    def _read_varint(self, *, allow_eof: bool) -> int | None:
        result = 0
        shift = 0
        while True:
            byte = self._read_byte(allow_eof=allow_eof and shift == 0)
            if byte is None:
                return None
            result |= (byte & 0x7F) << shift
            if not (byte & 0x80):
                return result
            shift += 7
            if shift >= 64:
                raise ValueError("varint too long")

    def _read_exact(self, n: int) -> builtins.bytes:
        if self._remaining is not None and n > self._remaining:
            raise ValueError("truncated field")
        chunks = []
        remaining = n
        while remaining:
            data = self._stream.read(remaining)
            if not data:
                raise ValueError("truncated field")
            chunks.append(data)
            remaining -= len(data)
        if self._remaining is not None:
            self._remaining -= n
        return b"".join(chunks)

    def _discard(self, n: int) -> None:
        _ = self._read_exact(n)


class Field:
    """Represents a single field from a protobuf message."""

    __slots__ = ("number", "wire_type", "_value", "_length", "_reader")

    def __init__(
        self,
        number: int,
        wire_type: WireType,
        *,
        value: int | None = None,
        length: int | None = None,
        reader: Reader | None = None,
    ) -> None:
        self.number = number
        self.wire_type = wire_type
        self._value = value
        self._length = length
        self._reader = reader

    def _require_wire_type(self, expected: WireType) -> None:
        if self.wire_type != expected:
            raise ValueError(
                f"wire type mismatch: expected {expected.name}, got {self.wire_type.name}"
            )

    def expect(self, wire_type: WireType) -> Field:
        self._require_wire_type(wire_type)
        return self

    def as_scalar(
        self, scalar: Scalar
    ) -> builtins.int | builtins.bool | builtins.float:
        expected = _scalar_wire_type(scalar)
        self._require_wire_type(expected)
        if self._value is None:
            raise ValueError("missing scalar value")
        if expected is WireType.VARINT:
            return _decode_varint_scalar(scalar, self._value)
        if expected is WireType.FIXED32:
            return _decode_fixed32_scalar(scalar, self._value)
        if expected is WireType.FIXED64:
            return _decode_fixed64_scalar(scalar, self._value)
        raise ValueError("invalid scalar type")

    def bytes(self) -> builtins.bytes:
        self._require_wire_type(WireType.LEN)
        if self._reader is None or self._length is None:
            raise ValueError("missing length data")
        return self._reader._read_exact(self._length)

    def string(self) -> str:
        data = self.bytes()
        try:
            return data.decode("utf-8")
        except UnicodeDecodeError:
            raise ValueError("invalid utf-8") from None

    def message(self) -> Reader:
        self._require_wire_type(WireType.LEN)
        if self._reader is None or self._length is None:
            raise ValueError("missing length data")
        parent = self._reader
        if parent._remaining is not None:
            if self._length > parent._remaining:
                raise ValueError("truncated field")
            parent._remaining -= self._length
        return Reader._from_stream(parent._stream, self._length)

    def skip(self) -> None:
        self._require_wire_type(WireType.LEN)
        if self._reader is None or self._length is None:
            raise ValueError("missing length data")
        self._reader._discard(self._length)

    def repeated(
        self, scalar: Scalar
    ) -> list[builtins.int | builtins.float | builtins.bool]:
        self._require_wire_type(WireType.LEN)
        data = self.bytes()
        return _decode_packed(data, scalar)


class Writer:
    """Streaming protobuf writer."""

    __slots__ = ("_stream",)

    def __init__(self, stream: BinaryIO) -> None:
        self._stream = stream

    def write_tag(self, field_number: int, wire_type: WireType) -> None:
        tag = make_tag(field_number, wire_type)
        self.write_varint(tag)

    def write_scalar(self, scalar: Scalar, value: object) -> None:
        wire_type = _scalar_wire_type(scalar)
        if wire_type is WireType.VARINT:
            if scalar is Scalar.sint32:
                encoded = zigzag_encode(_to_int(value)) & 0xFFFFFFFF
            elif scalar is Scalar.sint64:
                encoded = zigzag_encode(_to_int(value)) & 0xFFFFFFFFFFFFFFFF
            elif scalar is Scalar.bool:
                encoded = 1 if bool(value) else 0
            else:
                encoded = _to_int(value)
            self.write_varint(encoded)
            return

        if wire_type is WireType.FIXED32:
            if scalar is Scalar.float:
                raw = struct.unpack("<I", struct.pack("<f", _to_float(value)))[0]
            else:
                raw = _to_int(value) & 0xFFFFFFFF
            self._stream.write(raw.to_bytes(4, "little"))
            return

        if wire_type is WireType.FIXED64:
            if scalar is Scalar.double:
                raw = struct.unpack("<Q", struct.pack("<d", _to_float(value)))[0]
            else:
                raw = _to_int(value) & 0xFFFFFFFFFFFFFFFF
            self._stream.write(raw.to_bytes(8, "little"))
            return

        raise ValueError("invalid scalar type")

    def write_len(self, value: Buffer) -> None:
        data = bytes(value)
        self.write_varint(len(data))
        self._stream.write(data)

    def write_varint(self, value: int) -> None:
        self._stream.write(encode_varint(value))

    def flush(self) -> None:
        flush = getattr(self._stream, "flush", None)
        if flush is not None:
            flush()
