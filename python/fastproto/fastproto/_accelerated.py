"""Accelerated implementation using native Zig primitives.

This module provides the same API as _pure.py but uses native implementations
for the performance-critical low-level operations (varint encoding/decoding,
zigzag encoding, tag parsing).

The Reader and Writer classes are reimplemented to use the native primitives.
"""

import builtins
import struct
from collections.abc import Iterator

from fastproto import WireType
from fastproto._native import (
    decode_fixed32 as _native_decode_fixed32,
)
from fastproto._native import (
    decode_fixed64 as _native_decode_fixed64,
)
from fastproto._native import (
    decode_packed_bools as _native_decode_packed_bools,
)
from fastproto._native import (
    decode_packed_doubles as _native_decode_packed_doubles,
)
from fastproto._native import (
    decode_packed_fixed32s as _native_decode_packed_fixed32s,
)
from fastproto._native import (
    decode_packed_fixed64s as _native_decode_packed_fixed64s,
)
from fastproto._native import (
    decode_packed_floats as _native_decode_packed_floats,
)
from fastproto._native import (
    decode_packed_int32s as _native_decode_packed_int32s,
)
from fastproto._native import (
    decode_packed_int64s as _native_decode_packed_int64s,
)
from fastproto._native import (
    decode_packed_sfixed32s as _native_decode_packed_sfixed32s,
)
from fastproto._native import (
    decode_packed_sfixed64s as _native_decode_packed_sfixed64s,
)
from fastproto._native import (
    decode_packed_sint32s as _native_decode_packed_sint32s,
)
from fastproto._native import (
    decode_packed_sint64s as _native_decode_packed_sint64s,
)
from fastproto._native import (
    decode_packed_uint32s as _native_decode_packed_uint32s,
)
from fastproto._native import (
    decode_packed_uint64s as _native_decode_packed_uint64s,
)
from fastproto._native import (
    decode_varint as _native_decode_varint,
)
from fastproto._native import (
    double_from_bits,
    encode_double,
    encode_float,
    encode_sfixed32,
    encode_sfixed64,
    float_from_bits,
    zigzag_encode,
)
from fastproto._native import (
    encode_fixed32 as _native_encode_fixed32,
)
from fastproto._native import (
    encode_fixed64 as _native_encode_fixed64,
)
from fastproto._native import (
    encode_varint as _native_encode_varint,
)
from fastproto._native import (
    encode_varint_unsigned as _native_encode_varint_unsigned,
)
from fastproto._native import (
    fixed32_to_sfixed32 as _native_fixed32_to_sfixed32,
)
from fastproto._native import (
    fixed64_to_sfixed64 as _native_fixed64_to_sfixed64,
)
from fastproto._native import (
    make_tag as _native_make_tag,
)
from fastproto._native import (
    parse_tag as _native_parse_tag,
)
from fastproto._native import (
    varint_to_bool as _native_varint_to_bool,
)
from fastproto._native import (
    varint_to_int32 as _native_varint_to_int32,
)
from fastproto._native import (
    varint_to_int64 as _native_varint_to_int64,
)
from fastproto._native import (
    varint_to_sint32 as _native_varint_to_sint32,
)
from fastproto._native import (
    varint_to_sint64 as _native_varint_to_sint64,
)
from fastproto._native import (
    varint_to_uint32 as _native_varint_to_uint32,
)
from fastproto._native import (
    varint_to_uint64 as _native_varint_to_uint64,
)

# === Native-accelerated primitive functions ===


def make_tag(field_number: int, wire_type: WireType) -> int:
    """Create a tag from field number and wire type."""
    return _native_make_tag(field_number, int(wire_type))


def parse_tag(tag: int) -> tuple[int, WireType]:
    """Parse a tag into field number and wire type."""
    field_number, wire_type = _native_parse_tag(tag)
    return field_number, WireType(wire_type)


def encode_varint(value: int) -> bytes:
    """Encode an integer as a varint."""
    # Use unsigned variant for values that don't fit in i64
    if value >= 0x8000000000000000:  # >= 2^63
        return _native_encode_varint_unsigned(value)
    return _native_encode_varint(value)


def encode_fixed32(value: int) -> bytes:
    """Encode a fixed32 value."""
    return _native_encode_fixed32(value & 0xFFFFFFFF)


def encode_fixed64(value: int) -> bytes:
    """Encode a fixed64 value."""
    return _native_encode_fixed64(value & 0xFFFFFFFFFFFFFFFF)


def decode_varint(data: bytes | memoryview, offset: int = 0) -> tuple[int, int]:
    """Decode a varint from data at the given offset."""
    if isinstance(data, memoryview):
        data = bytes(data)
    return _native_decode_varint(data, offset)


def decode_fixed32(data: bytes | memoryview, offset: int = 0) -> tuple[int, int]:
    """Decode a fixed32 from data at the given offset."""
    if isinstance(data, memoryview):
        data = bytes(data)
    return _native_decode_fixed32(data, offset)


def decode_fixed64(data: bytes | memoryview, offset: int = 0) -> tuple[int, int]:
    """Decode a fixed64 from data at the given offset."""
    if isinstance(data, memoryview):
        data = bytes(data)
    return _native_decode_fixed64(data, offset)


def iter_varints(data: bytes | memoryview) -> Iterator[int]:
    """Iterate over varints in a packed repeated field."""
    if isinstance(data, memoryview):
        data = bytes(data)
    offset = 0
    while offset < len(data):
        value, offset = decode_varint(data, offset)
        yield value


# === Field class ===


class Field:
    """Represents a single field from a protobuf message."""

    __slots__ = ("number", "wire_type", "_data", "_value")

    def __init__(
        self,
        number: int,
        wire_type: WireType,
        data: bytes | memoryview,
        value: int | None = None,
    ) -> None:
        self.number = number
        self.wire_type = wire_type
        self._data = data
        self._value = value

    def _require_wire_type(self, expected: WireType) -> None:
        if self.wire_type != expected:
            raise ValueError(
                f"wire type mismatch: expected {expected.name}, got {self.wire_type.name}"
            )

    # === Varint types ===

    def int32(self) -> int:
        """Read as int32 (may be negative via sign extension)."""
        self._require_wire_type(WireType.VARINT)
        assert self._value is not None
        return _native_varint_to_int32(self._value)

    def int64(self) -> int:
        """Read as int64 (may be negative via sign extension)."""
        self._require_wire_type(WireType.VARINT)
        assert self._value is not None
        return _native_varint_to_int64(self._value)

    def uint32(self) -> int:
        """Read as uint32."""
        self._require_wire_type(WireType.VARINT)
        assert self._value is not None
        return _native_varint_to_uint32(self._value)

    def uint64(self) -> int:
        """Read as uint64."""
        self._require_wire_type(WireType.VARINT)
        assert self._value is not None
        return _native_varint_to_uint64(self._value)

    def sint32(self) -> int:
        """Read as sint32 (ZigZag encoded)."""
        self._require_wire_type(WireType.VARINT)
        assert self._value is not None
        return _native_varint_to_sint32(self._value)

    def sint64(self) -> int:
        """Read as sint64 (ZigZag encoded)."""
        self._require_wire_type(WireType.VARINT)
        assert self._value is not None
        return _native_varint_to_sint64(self._value)

    def bool(self) -> bool:
        """Read as bool."""
        self._require_wire_type(WireType.VARINT)
        assert self._value is not None
        return _native_varint_to_bool(self._value)

    def enum(self) -> int:
        """Read as enum (same as int32)."""
        return self.int32()

    # === Fixed 64-bit types ===

    def fixed64(self) -> int:
        """Read as fixed64."""
        self._require_wire_type(WireType.FIXED64)
        assert self._value is not None
        return self._value

    def sfixed64(self) -> int:
        """Read as sfixed64."""
        self._require_wire_type(WireType.FIXED64)
        assert self._value is not None
        return _native_fixed64_to_sfixed64(self._value)

    def double(self) -> float:
        """Read as double."""
        self._require_wire_type(WireType.FIXED64)
        assert self._value is not None
        return double_from_bits(self._value)

    # === Fixed 32-bit types ===

    def fixed32(self) -> int:
        """Read as fixed32."""
        self._require_wire_type(WireType.FIXED32)
        assert self._value is not None
        return self._value

    def sfixed32(self) -> int:
        """Read as sfixed32."""
        self._require_wire_type(WireType.FIXED32)
        assert self._value is not None
        return _native_fixed32_to_sfixed32(self._value)

    def float(self) -> float:
        """Read as float."""
        self._require_wire_type(WireType.FIXED32)
        assert self._value is not None
        return float_from_bits(self._value)

    # === Length-delimited types ===

    def string(self) -> str:
        """Read as UTF-8 string."""
        self._require_wire_type(WireType.LEN)
        if isinstance(self._data, memoryview):
            return bytes(self._data).decode("utf-8")
        return self._data.decode("utf-8")

    def bytes(self) -> bytes:
        """Read as raw bytes."""
        self._require_wire_type(WireType.LEN)
        if isinstance(self._data, memoryview):
            return bytes(self._data)
        return self._data

    def message_data(self) -> builtins.bytes:
        """Get raw message data for nested message parsing."""
        return self.bytes()

    def message(self) -> "Reader":
        """Read as embedded message, returning a new Reader."""
        self._require_wire_type(WireType.LEN)
        return Reader(self._data)

    # === Packed repeated types ===

    def packed_int32s(self) -> list[int]:
        """Read as packed repeated int32."""
        self._require_wire_type(WireType.LEN)
        data = self._data if isinstance(self._data, bytes) else bytes(self._data)
        return _native_decode_packed_int32s(data)

    def packed_int64s(self) -> list[int]:
        """Read as packed repeated int64."""
        self._require_wire_type(WireType.LEN)
        data = self._data if isinstance(self._data, bytes) else bytes(self._data)
        return _native_decode_packed_int64s(data)

    def packed_uint32s(self) -> list[int]:
        """Read as packed repeated uint32."""
        self._require_wire_type(WireType.LEN)
        data = self._data if isinstance(self._data, bytes) else bytes(self._data)
        return _native_decode_packed_uint32s(data)

    def packed_uint64s(self) -> list[int]:
        """Read as packed repeated uint64."""
        self._require_wire_type(WireType.LEN)
        data = self._data if isinstance(self._data, bytes) else bytes(self._data)
        return _native_decode_packed_uint64s(data)

    def packed_sint32s(self) -> list[int]:
        """Read as packed repeated sint32."""
        self._require_wire_type(WireType.LEN)
        data = self._data if isinstance(self._data, bytes) else bytes(self._data)
        return _native_decode_packed_sint32s(data)

    def packed_sint64s(self) -> list[int]:
        """Read as packed repeated sint64."""
        self._require_wire_type(WireType.LEN)
        data = self._data if isinstance(self._data, bytes) else bytes(self._data)
        return _native_decode_packed_sint64s(data)

    def packed_bools(self) -> list[builtins.bool]:
        """Read as packed repeated bool."""
        self._require_wire_type(WireType.LEN)
        data = self._data if isinstance(self._data, bytes) else bytes(self._data)
        return _native_decode_packed_bools(data)

    def packed_fixed32s(self) -> list[int]:
        """Read as packed repeated fixed32."""
        self._require_wire_type(WireType.LEN)
        data = self._data if isinstance(self._data, bytes) else bytes(self._data)
        return _native_decode_packed_fixed32s(data)

    def packed_sfixed32s(self) -> list[int]:
        """Read as packed repeated sfixed32."""
        self._require_wire_type(WireType.LEN)
        data = self._data if isinstance(self._data, bytes) else bytes(self._data)
        return _native_decode_packed_sfixed32s(data)

    def packed_floats(self) -> list[builtins.float]:
        """Read as packed repeated float."""
        self._require_wire_type(WireType.LEN)
        data = self._data if isinstance(self._data, bytes) else bytes(self._data)
        return _native_decode_packed_floats(data)

    def packed_fixed64s(self) -> list[int]:
        """Read as packed repeated fixed64."""
        self._require_wire_type(WireType.LEN)
        data = self._data if isinstance(self._data, bytes) else bytes(self._data)
        return _native_decode_packed_fixed64s(data)

    def packed_sfixed64s(self) -> list[int]:
        """Read as packed repeated sfixed64."""
        self._require_wire_type(WireType.LEN)
        data = self._data if isinstance(self._data, bytes) else bytes(self._data)
        return _native_decode_packed_sfixed64s(data)

    def packed_doubles(self) -> list[builtins.float]:
        """Read as packed repeated double."""
        self._require_wire_type(WireType.LEN)
        data = self._data if isinstance(self._data, bytes) else bytes(self._data)
        return _native_decode_packed_doubles(data)


# === Reader class ===


class Reader:
    """Reads fields from a protobuf-encoded message."""

    __slots__ = ("_data", "_raw", "_pos", "_len")

    def __init__(self, data: bytes | memoryview) -> None:
        if isinstance(data, memoryview):
            self._data = data
            self._raw = data.tobytes()
        else:
            self._data = memoryview(data)
            self._raw = data if isinstance(data, bytes) else bytes(data)
        self._pos = 0
        self._len = len(data)

    def __iter__(self) -> Iterator[Field]:
        return self

    def __next__(self) -> Field:
        field = self.next_field()
        if field is None:
            raise StopIteration
        return field

    def next_field(self) -> Field | None:
        """Read the next field, or return None if at end of message."""
        if self._pos >= self._len:
            return None

        # Read tag (using native decode_varint)
        tag, self._pos = decode_varint(self._raw, self._pos)
        field_number, wire_type = parse_tag(tag)

        # Read value based on wire type
        match wire_type:
            case WireType.VARINT:
                value, self._pos = decode_varint(self._raw, self._pos)
                return Field(field_number, wire_type, b"", value)

            case WireType.FIXED64:
                value, self._pos = decode_fixed64(self._raw, self._pos)
                return Field(field_number, wire_type, b"", value)

            case WireType.LEN:
                length, self._pos = decode_varint(self._raw, self._pos)
                if self._pos + length > self._len:
                    raise ValueError("truncated length-delimited field")
                data = self._data[self._pos : self._pos + length]
                self._pos += length
                return Field(field_number, wire_type, data, None)

            case WireType.FIXED32:
                value, self._pos = decode_fixed32(self._raw, self._pos)
                return Field(field_number, wire_type, b"", value)
            case _:
                raise ValueError(f"unknown wire type: {wire_type}")

    def skip(self) -> bool:
        """Skip the next field. Returns True if a field was skipped, False if at end."""
        return self.next_field() is not None

    def remaining(self) -> int:
        """Return the number of bytes remaining to be read."""
        return self._len - self._pos


# === Writer class ===


class Writer:
    """Builds a protobuf-encoded message."""

    __slots__ = ("_buffer", "_parent", "_field_num")

    def __init__(
        self, parent: "Writer" | None = None, field_num: int | None = None
    ) -> None:
        self._buffer = bytearray()
        self._parent = parent
        self._field_num = field_num

    def _write_tag(self, field_number: int, wire_type: WireType) -> None:
        self._buffer.extend(encode_varint(make_tag(field_number, wire_type)))

    # === Varint types ===

    def int32(self, field_number: int, value: int) -> None:
        """Write an int32 field."""
        self._write_tag(field_number, WireType.VARINT)
        self._buffer.extend(encode_varint(value))

    def int64(self, field_number: int, value: int) -> None:
        """Write an int64 field."""
        self._write_tag(field_number, WireType.VARINT)
        self._buffer.extend(encode_varint(value))

    def uint32(self, field_number: int, value: int) -> None:
        """Write a uint32 field."""
        self._write_tag(field_number, WireType.VARINT)
        self._buffer.extend(encode_varint(value & 0xFFFFFFFF))

    def uint64(self, field_number: int, value: int) -> None:
        """Write a uint64 field."""
        self._write_tag(field_number, WireType.VARINT)
        self._buffer.extend(encode_varint(value))

    def sint32(self, field_number: int, value: int) -> None:
        """Write a sint32 field (ZigZag encoded)."""
        self._write_tag(field_number, WireType.VARINT)
        self._buffer.extend(encode_varint(zigzag_encode(value) & 0xFFFFFFFF))

    def sint64(self, field_number: int, value: int) -> None:
        """Write a sint64 field (ZigZag encoded)."""
        self._write_tag(field_number, WireType.VARINT)
        self._buffer.extend(encode_varint(zigzag_encode(value)))

    def bool(self, field_number: int, value: bool) -> None:
        """Write a bool field."""
        self._write_tag(field_number, WireType.VARINT)
        self._buffer.extend(encode_varint(1 if value else 0))

    def enum(self, field_number: int, value: int) -> None:
        """Write an enum field (same as int32)."""
        self.int32(field_number, value)

    # === Fixed 64-bit types ===

    def fixed64(self, field_number: int, value: int) -> None:
        """Write a fixed64 field."""
        self._write_tag(field_number, WireType.FIXED64)
        self._buffer.extend(encode_fixed64(value))

    def sfixed64(self, field_number: int, value: int) -> None:
        """Write an sfixed64 field."""
        self._write_tag(field_number, WireType.FIXED64)
        self._buffer.extend(encode_sfixed64(value))

    def double(self, field_number: int, value: float) -> None:
        """Write a double field."""
        self._write_tag(field_number, WireType.FIXED64)
        self._buffer.extend(encode_double(value))

    # === Fixed 32-bit types ===

    def fixed32(self, field_number: int, value: int) -> None:
        """Write a fixed32 field."""
        self._write_tag(field_number, WireType.FIXED32)
        self._buffer.extend(encode_fixed32(value))

    def sfixed32(self, field_number: int, value: int) -> None:
        """Write an sfixed32 field."""
        self._write_tag(field_number, WireType.FIXED32)
        self._buffer.extend(encode_sfixed32(value))

    def float(self, field_number: int, value: float) -> None:
        """Write a float field."""
        self._write_tag(field_number, WireType.FIXED32)
        self._buffer.extend(encode_float(value))

    # === Length-delimited types ===

    def string(self, field_number: int, value: str) -> None:
        """Write a string field."""
        encoded = value.encode("utf-8")
        self._write_tag(field_number, WireType.LEN)
        self._buffer.extend(encode_varint(len(encoded)))
        self._buffer.extend(encoded)

    def bytes(self, field_number: int, value: bytes) -> None:
        """Write a bytes field."""
        self._write_tag(field_number, WireType.LEN)
        self._buffer.extend(encode_varint(len(value)))
        self._buffer.extend(value)

    def message(self, field_number: int) -> "Writer":
        """Start a nested message. Use as a context manager."""
        return Writer(parent=self, field_num=field_number)

    def __enter__(self) -> "Writer":
        return self

    def __exit__(self, exc_type, exc_val, exc_tb) -> None:  # type: ignore[no-untyped-def]
        if exc_type is None and self._parent is not None:
            assert self._field_num is not None
            self._parent._write_tag(self._field_num, WireType.LEN)
            self._parent._buffer.extend(encode_varint(len(self._buffer)))
            self._parent._buffer.extend(self._buffer)

    def end(self) -> None:
        """Explicitly end a nested message (alternative to context manager)."""
        if self._parent is not None:
            assert self._field_num is not None
            self._parent._write_tag(self._field_num, WireType.LEN)
            self._parent._buffer.extend(encode_varint(len(self._buffer)))
            self._parent._buffer.extend(self._buffer)

    # === Packed repeated types ===

    def packed_int32s(self, field_number: int, values: list[int]) -> None:
        """Write packed repeated int32."""
        if not values:
            return
        packed = bytearray()
        for v in values:
            packed.extend(encode_varint(v))
        self._write_tag(field_number, WireType.LEN)
        self._buffer.extend(encode_varint(len(packed)))
        self._buffer.extend(packed)

    def packed_int64s(self, field_number: int, values: list[int]) -> None:
        """Write packed repeated int64."""
        if not values:
            return
        packed = bytearray()
        for v in values:
            packed.extend(encode_varint(v))
        self._write_tag(field_number, WireType.LEN)
        self._buffer.extend(encode_varint(len(packed)))
        self._buffer.extend(packed)

    def packed_uint32s(self, field_number: int, values: list[int]) -> None:
        """Write packed repeated uint32."""
        if not values:
            return
        packed = bytearray()
        for v in values:
            packed.extend(encode_varint(v & 0xFFFFFFFF))
        self._write_tag(field_number, WireType.LEN)
        self._buffer.extend(encode_varint(len(packed)))
        self._buffer.extend(packed)

    def packed_uint64s(self, field_number: int, values: list[int]) -> None:
        """Write packed repeated uint64."""
        if not values:
            return
        packed = bytearray()
        for v in values:
            packed.extend(encode_varint(v))
        self._write_tag(field_number, WireType.LEN)
        self._buffer.extend(encode_varint(len(packed)))
        self._buffer.extend(packed)

    def packed_sint32s(self, field_number: int, values: list[int]) -> None:
        """Write packed repeated sint32."""
        if not values:
            return
        packed = bytearray()
        for v in values:
            packed.extend(encode_varint(zigzag_encode(v) & 0xFFFFFFFF))
        self._write_tag(field_number, WireType.LEN)
        self._buffer.extend(encode_varint(len(packed)))
        self._buffer.extend(packed)

    def packed_sint64s(self, field_number: int, values: list[int]) -> None:
        """Write packed repeated sint64."""
        if not values:
            return
        packed = bytearray()
        for v in values:
            packed.extend(encode_varint(zigzag_encode(v)))
        self._write_tag(field_number, WireType.LEN)
        self._buffer.extend(encode_varint(len(packed)))
        self._buffer.extend(packed)

    def packed_bools(self, field_number: int, values: list[builtins.bool]) -> None:
        """Write packed repeated bool."""
        if not values:
            return
        packed = bytearray()
        for v in values:
            packed.extend(encode_varint(1 if v else 0))
        self._write_tag(field_number, WireType.LEN)
        self._buffer.extend(encode_varint(len(packed)))
        self._buffer.extend(packed)

    def packed_fixed32s(self, field_number: int, values: list[int]) -> None:
        """Write packed repeated fixed32."""
        if not values:
            return
        packed = struct.pack(f"<{len(values)}I", *[v & 0xFFFFFFFF for v in values])
        self._write_tag(field_number, WireType.LEN)
        self._buffer.extend(encode_varint(len(packed)))
        self._buffer.extend(packed)

    def packed_sfixed32s(self, field_number: int, values: list[int]) -> None:
        """Write packed repeated sfixed32."""
        if not values:
            return
        packed = struct.pack(f"<{len(values)}i", *values)
        self._write_tag(field_number, WireType.LEN)
        self._buffer.extend(encode_varint(len(packed)))
        self._buffer.extend(packed)

    def packed_floats(self, field_number: int, values: list[builtins.float]) -> None:
        """Write packed repeated float."""
        if not values:
            return
        packed = struct.pack(f"<{len(values)}f", *values)
        self._write_tag(field_number, WireType.LEN)
        self._buffer.extend(encode_varint(len(packed)))
        self._buffer.extend(packed)

    def packed_fixed64s(self, field_number: int, values: list[int]) -> None:
        """Write packed repeated fixed64."""
        if not values:
            return
        packed = struct.pack(
            f"<{len(values)}Q", *[v & 0xFFFFFFFFFFFFFFFF for v in values]
        )
        self._write_tag(field_number, WireType.LEN)
        self._buffer.extend(encode_varint(len(packed)))
        self._buffer.extend(packed)

    def packed_sfixed64s(self, field_number: int, values: list[int]) -> None:
        """Write packed repeated sfixed64."""
        if not values:
            return
        packed = struct.pack(f"<{len(values)}q", *values)
        self._write_tag(field_number, WireType.LEN)
        self._buffer.extend(encode_varint(len(packed)))
        self._buffer.extend(packed)

    def packed_doubles(self, field_number: int, values: list[builtins.float]) -> None:
        """Write packed repeated double."""
        if not values:
            return
        packed = struct.pack(f"<{len(values)}d", *values)
        self._write_tag(field_number, WireType.LEN)
        self._buffer.extend(encode_varint(len(packed)))
        self._buffer.extend(packed)

    def finish(self) -> builtins.bytes:
        """Finish building and return the encoded message."""
        return bytes(self._buffer)

    def clear(self) -> None:
        """Clear the buffer to reuse the writer."""
        self._buffer.clear()
