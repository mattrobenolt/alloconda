"""Pure Python implementation of protobuf wire format encoding/decoding.

This module provides the reference implementation for fastproto. It's designed
to be correct and readable, serving as both a fallback when the Zig extension
is unavailable and as a specification for the Zig implementation to match.
"""

import builtins
import struct
from collections.abc import Iterator

try:
    from collections.abc import Buffer  # type: ignore[unresolved-import]
except ImportError:
    Buffer = bytes | bytearray | memoryview

from fastproto import WireType


def make_tag(field_number: int, wire_type: WireType) -> int:
    """Create a tag from field number and wire type."""
    if field_number < 1:
        raise ValueError(f"field_number must be >= 1, got {field_number}")
    if field_number > 0x1FFFFFFF:
        raise ValueError(f"field_number too large: {field_number}")
    return (field_number << 3) | wire_type


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


__all__ = ["Reader", "Writer", "Field"]


class Field:
    """Represents a single field from a protobuf message.

    A Field contains the raw wire data and provides methods to interpret
    it as various protobuf types. The interpretation must match the wire
    type, or a ValueError is raised.
    """

    __slots__ = ("number", "wire_type", "_data", "_value")

    def __init__(
        self,
        number: int,
        wire_type: WireType,
        data: Buffer,
        value: int | None = None,
    ) -> None:
        self.number = number
        self.wire_type = wire_type
        self._data = data  # For LEN types, this is the payload
        self._value = value  # For VARINT/FIXED types, the decoded value

    def _require_wire_type(self, expected: WireType) -> None:
        if self.wire_type != expected:
            raise ValueError(
                f"wire type mismatch: expected {expected.name}, got {self.wire_type.name}"
            )

    # === Varint types ===

    def int32(self) -> int:
        """Read as int32 (may be negative via sign extension)."""
        self._require_wire_type(WireType.VARINT)
        value = self._value
        assert value is not None
        # Mask to 32 bits, then sign extend if high bit set
        value = value & 0xFFFFFFFF
        if value > 0x7FFFFFFF:
            value -= 0x100000000
        return value

    def int64(self) -> int:
        """Read as int64 (may be negative via sign extension)."""
        self._require_wire_type(WireType.VARINT)
        value = self._value
        assert value is not None
        # Sign extend from 64 bits
        if value > 0x7FFFFFFFFFFFFFFF:
            value -= 0x10000000000000000
        return value

    def uint32(self) -> int:
        """Read as uint32."""
        self._require_wire_type(WireType.VARINT)
        assert self._value is not None
        return self._value & 0xFFFFFFFF

    def uint64(self) -> int:
        """Read as uint64."""
        self._require_wire_type(WireType.VARINT)
        assert self._value is not None
        return self._value

    def sint32(self) -> int:
        """Read as sint32 (ZigZag encoded)."""
        self._require_wire_type(WireType.VARINT)
        assert self._value is not None
        value = zigzag_decode(self._value & 0xFFFFFFFF)
        # Sign extend from 32 bits
        if value > 0x7FFFFFFF:
            value -= 0x100000000
        return value

    def sint64(self) -> int:
        """Read as sint64 (ZigZag encoded)."""
        self._require_wire_type(WireType.VARINT)
        assert self._value is not None
        return zigzag_decode(self._value)

    def bool(self) -> bool:
        """Read as bool."""
        self._require_wire_type(WireType.VARINT)
        assert self._value is not None
        return self._value != 0

    def enum(self) -> int:
        """Read as enum (same as int32)."""
        return self.int32()

    # === Fixed 64-bit types ===

    def fixed64(self) -> int:
        """Read as fixed64 (unsigned)."""
        self._require_wire_type(WireType.FIXED64)
        assert self._value is not None
        return self._value

    def sfixed64(self) -> int:
        """Read as sfixed64 (signed)."""
        self._require_wire_type(WireType.FIXED64)
        assert self._value is not None
        value = self._value
        if value > 0x7FFFFFFFFFFFFFFF:
            value -= 0x10000000000000000
        return value

    def double(self) -> float:
        """Read as double."""
        self._require_wire_type(WireType.FIXED64)
        assert self._value is not None
        return struct.unpack("<d", struct.pack("<Q", self._value))[0]

    # === Fixed 32-bit types ===

    def fixed32(self) -> int:
        """Read as fixed32 (unsigned)."""
        self._require_wire_type(WireType.FIXED32)
        assert self._value is not None
        return self._value

    def sfixed32(self) -> int:
        """Read as sfixed32 (signed)."""
        self._require_wire_type(WireType.FIXED32)
        assert self._value is not None
        value = self._value
        if value > 0x7FFFFFFF:
            value -= 0x100000000
        return value

    def float(self) -> builtins.float:
        """Read as float."""
        self._require_wire_type(WireType.FIXED32)
        assert self._value is not None
        return struct.unpack("<f", struct.pack("<I", self._value))[0]

    # === Length-delimited types ===

    def string(self) -> str:
        """Read as UTF-8 string."""
        self._require_wire_type(WireType.LEN)
        if isinstance(self._data, memoryview):
            return bytes(self._data).decode("utf-8")
        return self._data.decode("utf-8")

    def bytes(self) -> builtins.bytes:
        """Read as raw bytes."""
        self._require_wire_type(WireType.LEN)
        return bytes(self._data)

    def message_data(self) -> builtins.bytes:
        """Read as embedded message data (raw bytes for recursive parsing)."""
        return self.bytes()

    def message(self) -> "Reader":
        """Read as embedded message, returning a Reader for the nested message."""
        self._require_wire_type(WireType.LEN)
        return Reader(self._data)

    # === Packed repeated types ===

    def packed_int32s(self) -> list[int]:
        """Read as packed repeated int32."""
        self._require_wire_type(WireType.LEN)
        result = []
        for v in iter_varints(self._data):
            v = v & 0xFFFFFFFF
            if v > 0x7FFFFFFF:
                v -= 0x100000000
            result.append(v)
        return result

    def packed_int64s(self) -> list[int]:
        """Read as packed repeated int64."""
        self._require_wire_type(WireType.LEN)
        result = []
        for v in iter_varints(self._data):
            if v > 0x7FFFFFFFFFFFFFFF:
                v -= 0x10000000000000000
            result.append(v)
        return result

    def packed_uint32s(self) -> list[int]:
        """Read as packed repeated uint32."""
        self._require_wire_type(WireType.LEN)
        return [v & 0xFFFFFFFF for v in iter_varints(self._data)]

    def packed_uint64s(self) -> list[int]:
        """Read as packed repeated uint64."""
        self._require_wire_type(WireType.LEN)
        return list(iter_varints(self._data))

    def packed_sint32s(self) -> list[int]:
        """Read as packed repeated sint32 (ZigZag)."""
        self._require_wire_type(WireType.LEN)
        result = []
        for v in iter_varints(self._data):
            decoded = zigzag_decode(v & 0xFFFFFFFF)
            if decoded > 0x7FFFFFFF:
                decoded -= 0x100000000
            result.append(decoded)
        return result

    def packed_sint64s(self) -> list[int]:
        """Read as packed repeated sint64 (ZigZag)."""
        self._require_wire_type(WireType.LEN)
        return [zigzag_decode(v) for v in iter_varints(self._data)]

    def packed_bools(self) -> list[builtins.bool]:
        """Read as packed repeated bool."""
        self._require_wire_type(WireType.LEN)
        return [v != 0 for v in iter_varints(self._data)]

    def packed_fixed32s(self) -> list[int]:
        """Read as packed repeated fixed32."""
        self._require_wire_type(WireType.LEN)
        data = bytes(self._data) if isinstance(self._data, memoryview) else self._data
        if len(data) % 4 != 0:
            raise ValueError("packed fixed32 data length not a multiple of 4")
        return list(struct.unpack(f"<{len(data) // 4}I", data))

    def packed_sfixed32s(self) -> list[int]:
        """Read as packed repeated sfixed32."""
        self._require_wire_type(WireType.LEN)
        data = bytes(self._data) if isinstance(self._data, memoryview) else self._data
        if len(data) % 4 != 0:
            raise ValueError("packed sfixed32 data length not a multiple of 4")
        return list(struct.unpack(f"<{len(data) // 4}i", data))

    def packed_floats(self) -> list[builtins.float]:
        """Read as packed repeated float."""
        self._require_wire_type(WireType.LEN)
        data = bytes(self._data) if isinstance(self._data, memoryview) else self._data
        if len(data) % 4 != 0:
            raise ValueError("packed float data length not a multiple of 4")
        return list(struct.unpack(f"<{len(data) // 4}f", data))

    def packed_fixed64s(self) -> list[int]:
        """Read as packed repeated fixed64."""
        self._require_wire_type(WireType.LEN)
        data = bytes(self._data) if isinstance(self._data, memoryview) else self._data
        if len(data) % 8 != 0:
            raise ValueError("packed fixed64 data length not a multiple of 8")
        return list(struct.unpack(f"<{len(data) // 8}Q", data))

    def packed_sfixed64s(self) -> list[int]:
        """Read as packed repeated sfixed64."""
        self._require_wire_type(WireType.LEN)
        data = bytes(self._data) if isinstance(self._data, memoryview) else self._data
        if len(data) % 8 != 0:
            raise ValueError("packed sfixed64 data length not a multiple of 8")
        return list(struct.unpack(f"<{len(data) // 8}q", data))

    def packed_doubles(self) -> list[builtins.float]:
        """Read as packed repeated double."""
        self._require_wire_type(WireType.LEN)
        data = bytes(self._data) if isinstance(self._data, memoryview) else self._data
        if len(data) % 8 != 0:
            raise ValueError("packed double data length not a multiple of 8")
        return list(struct.unpack(f"<{len(data) // 8}d", data))


class Reader:
    """Reads fields from a protobuf-encoded message.

    Usage:
        reader = Reader(data)
        for field in reader:
            if field.number == 1:
                name = field.string()
            elif field.number == 2:
                value = field.int64()
    """

    __slots__ = ("_data", "_pos", "_len")

    def __init__(self, data: Buffer) -> None:
        if isinstance(data, memoryview):
            self._data = data
        else:
            self._data = memoryview(data)
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

        # Read tag
        tag, self._pos = decode_varint(self._data, self._pos)
        field_number, wire_type = parse_tag(tag)

        # Read value based on wire type
        if wire_type == WireType.VARINT:
            value, self._pos = decode_varint(self._data, self._pos)
            return Field(field_number, wire_type, b"", value)

        elif wire_type == WireType.FIXED64:
            if self._pos + 8 > self._len:
                raise ValueError("truncated fixed64")
            value = struct.unpack_from("<Q", self._data, self._pos)[0]
            self._pos += 8
            return Field(field_number, wire_type, b"", value)

        elif wire_type == WireType.LEN:
            length, self._pos = decode_varint(self._data, self._pos)
            if self._pos + length > self._len:
                raise ValueError("truncated length-delimited field")
            data = self._data[self._pos : self._pos + length]
            self._pos += length
            return Field(field_number, wire_type, data, None)

        elif wire_type == WireType.FIXED32:
            if self._pos + 4 > self._len:
                raise ValueError("truncated fixed32")
            value = struct.unpack_from("<I", self._data, self._pos)[0]
            self._pos += 4
            return Field(field_number, wire_type, b"", value)

        else:
            raise ValueError(f"unknown wire type: {wire_type}")

    def skip(self) -> bool:
        """Skip the next field. Returns True if a field was skipped, False if at end."""
        return self.next_field() is not None

    def remaining(self) -> int:
        """Return the number of bytes remaining to be read."""
        return self._len - self._pos


class Writer:
    """Builds a protobuf-encoded message.

    Usage:
        writer = Writer()
        writer.string(1, "hello")
        writer.int64(2, 42)
        data = writer.finish()

    For nested messages:
        writer = Writer()
        writer.string(1, "parent")
        with writer.message(2) as nested:
            nested.string(1, "child")
            nested.int32(2, 123)
        data = writer.finish()
    """

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
        # Sign extend negative values to 64 bits (protobuf spec)
        if value < 0:
            value = value & 0xFFFFFFFFFFFFFFFF
        self._buffer.extend(encode_varint(value))

    def int64(self, field_number: int, value: int) -> None:
        """Write an int64 field."""
        self._write_tag(field_number, WireType.VARINT)
        if value < 0:
            value = value & 0xFFFFFFFFFFFFFFFF
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
        self._buffer.extend(struct.pack("<Q", value & 0xFFFFFFFFFFFFFFFF))

    def sfixed64(self, field_number: int, value: int) -> None:
        """Write an sfixed64 field."""
        self._write_tag(field_number, WireType.FIXED64)
        self._buffer.extend(struct.pack("<q", value))

    def double(self, field_number: int, value: float) -> None:
        """Write a double field."""
        self._write_tag(field_number, WireType.FIXED64)
        self._buffer.extend(struct.pack("<d", value))

    # === Fixed 32-bit types ===

    def fixed32(self, field_number: int, value: int) -> None:
        """Write a fixed32 field."""
        self._write_tag(field_number, WireType.FIXED32)
        self._buffer.extend(struct.pack("<I", value & 0xFFFFFFFF))

    def sfixed32(self, field_number: int, value: int) -> None:
        """Write an sfixed32 field."""
        self._write_tag(field_number, WireType.FIXED32)
        self._buffer.extend(struct.pack("<i", value))

    def float(self, field_number: int, value: float) -> None:
        """Write a float field."""
        self._write_tag(field_number, WireType.FIXED32)
        self._buffer.extend(struct.pack("<f", value))

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
        """Start a nested message. Use as a context manager.

        Usage:
            with writer.message(2) as nested:
                nested.string(1, "hello")
        """
        return Writer(parent=self, field_num=field_number)

    def __enter__(self) -> "Writer":
        return self

    def __exit__(self, exc_type, exc_val, exc_tb) -> None:
        if exc_type is None and self._parent is not None:
            # Write ourselves to parent as a length-delimited field
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
        """Write a packed repeated int32 field."""
        if not values:
            return
        packed = bytearray()
        for v in values:
            if v < 0:
                v = v & 0xFFFFFFFFFFFFFFFF
            packed.extend(encode_varint(v))
        self._write_tag(field_number, WireType.LEN)
        self._buffer.extend(encode_varint(len(packed)))
        self._buffer.extend(packed)

    def packed_int64s(self, field_number: int, values: list[int]) -> None:
        """Write a packed repeated int64 field."""
        if not values:
            return
        packed = bytearray()
        for v in values:
            if v < 0:
                v = v & 0xFFFFFFFFFFFFFFFF
            packed.extend(encode_varint(v))
        self._write_tag(field_number, WireType.LEN)
        self._buffer.extend(encode_varint(len(packed)))
        self._buffer.extend(packed)

    def packed_uint32s(self, field_number: int, values: list[int]) -> None:
        """Write a packed repeated uint32 field."""
        if not values:
            return
        packed = bytearray()
        for v in values:
            packed.extend(encode_varint(v & 0xFFFFFFFF))
        self._write_tag(field_number, WireType.LEN)
        self._buffer.extend(encode_varint(len(packed)))
        self._buffer.extend(packed)

    def packed_uint64s(self, field_number: int, values: list[int]) -> None:
        """Write a packed repeated uint64 field."""
        if not values:
            return
        packed = bytearray()
        for v in values:
            packed.extend(encode_varint(v))
        self._write_tag(field_number, WireType.LEN)
        self._buffer.extend(encode_varint(len(packed)))
        self._buffer.extend(packed)

    def packed_sint32s(self, field_number: int, values: list[int]) -> None:
        """Write a packed repeated sint32 field."""
        if not values:
            return
        packed = bytearray()
        for v in values:
            packed.extend(encode_varint(zigzag_encode(v) & 0xFFFFFFFF))
        self._write_tag(field_number, WireType.LEN)
        self._buffer.extend(encode_varint(len(packed)))
        self._buffer.extend(packed)

    def packed_sint64s(self, field_number: int, values: list[int]) -> None:
        """Write a packed repeated sint64 field."""
        if not values:
            return
        packed = bytearray()
        for v in values:
            packed.extend(encode_varint(zigzag_encode(v)))
        self._write_tag(field_number, WireType.LEN)
        self._buffer.extend(encode_varint(len(packed)))
        self._buffer.extend(packed)

    def packed_bools(self, field_number: int, values: list[builtins.bool]) -> None:
        """Write a packed repeated bool field."""
        if not values:
            return
        packed = bytearray()
        for v in values:
            packed.extend(encode_varint(1 if v else 0))
        self._write_tag(field_number, WireType.LEN)
        self._buffer.extend(encode_varint(len(packed)))
        self._buffer.extend(packed)

    def packed_fixed32s(self, field_number: int, values: list[int]) -> None:
        """Write a packed repeated fixed32 field."""
        if not values:
            return
        self._write_tag(field_number, WireType.LEN)
        self._buffer.extend(encode_varint(len(values) * 4))
        for v in values:
            self._buffer.extend(struct.pack("<I", v & 0xFFFFFFFF))

    def packed_sfixed32s(self, field_number: int, values: list[int]) -> None:
        """Write a packed repeated sfixed32 field."""
        if not values:
            return
        self._write_tag(field_number, WireType.LEN)
        self._buffer.extend(encode_varint(len(values) * 4))
        for v in values:
            self._buffer.extend(struct.pack("<i", v))

    def packed_floats(self, field_number: int, values: list[builtins.float]) -> None:
        """Write a packed repeated float field."""
        if not values:
            return
        self._write_tag(field_number, WireType.LEN)
        self._buffer.extend(encode_varint(len(values) * 4))
        for v in values:
            self._buffer.extend(struct.pack("<f", v))

    def packed_fixed64s(self, field_number: int, values: list[int]) -> None:
        """Write a packed repeated fixed64 field."""
        if not values:
            return
        self._write_tag(field_number, WireType.LEN)
        self._buffer.extend(encode_varint(len(values) * 8))
        for v in values:
            self._buffer.extend(struct.pack("<Q", v & 0xFFFFFFFFFFFFFFFF))

    def packed_sfixed64s(self, field_number: int, values: list[int]) -> None:
        """Write a packed repeated sfixed64 field."""
        if not values:
            return
        self._write_tag(field_number, WireType.LEN)
        self._buffer.extend(encode_varint(len(values) * 8))
        for v in values:
            self._buffer.extend(struct.pack("<q", v))

    def packed_doubles(self, field_number: int, values: list[builtins.float]) -> None:
        """Write a packed repeated double field."""
        if not values:
            return
        self._write_tag(field_number, WireType.LEN)
        self._buffer.extend(encode_varint(len(values) * 8))
        for v in values:
            self._buffer.extend(struct.pack("<d", v))

    def finish(self) -> builtins.bytes:
        """Finish writing and return the encoded message."""
        return bytes(self._buffer)

    def clear(self) -> None:
        """Clear the buffer to reuse this writer."""
        self._buffer.clear()
