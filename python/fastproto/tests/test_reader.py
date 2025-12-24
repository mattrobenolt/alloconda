"""Tests for the Reader class."""

import pytest

from fastproto import Reader, WireType, Writer


def _encode_varint(value: int) -> bytes:
    """Encode an integer as a varint (test helper)."""
    if value < 0:
        value = value & 0xFFFFFFFFFFFFFFFF
    result = bytearray()
    while value > 0x7F:
        result.append((value & 0x7F) | 0x80)
        value >>= 7
    result.append(value)
    return bytes(result)


def _make_tag(field_number: int, wire_type: WireType) -> int:
    """Create a tag from field number and wire type (test helper)."""
    return (field_number << 3) | wire_type


class TestReaderBasic:
    """Basic Reader functionality tests."""

    def test_empty_message(self):
        reader = Reader(b"")
        assert list(reader) == []

    def test_remaining(self):
        data = b"\x08\x01"  # field 1, varint 1
        reader = Reader(data)
        assert reader.remaining() == 2
        next(reader)
        assert reader.remaining() == 0

    def test_skip(self):
        # Two fields: field 1 = 42, field 2 = 100
        writer = Writer()
        writer.int32(1, 42)
        writer.int32(2, 100)
        data = writer.finish()

        reader = Reader(data)
        assert reader.skip() is True  # Skip field 1
        field = reader.next_field()
        assert field is not None
        assert field.number == 2
        assert field.int32() == 100
        assert reader.skip() is False  # No more fields

    def test_next_field_returns_none_at_end(self):
        reader = Reader(b"")
        assert reader.next_field() is None

    def test_iteration_protocol(self):
        writer = Writer()
        writer.int32(1, 10)
        writer.int32(2, 20)
        writer.int32(3, 30)
        data = writer.finish()

        fields = list(Reader(data))
        assert len(fields) == 3
        assert [f.number for f in fields] == [1, 2, 3]
        assert [f.int32() for f in fields] == [10, 20, 30]


class TestReaderVarintTypes:
    """Tests for reading varint-encoded types."""

    def test_int32_positive(self):
        writer = Writer()
        writer.int32(1, 42)
        data = writer.finish()

        field = next(Reader(data))
        assert field.number == 1
        assert field.wire_type == WireType.VARINT
        assert field.int32() == 42

    def test_int32_negative(self):
        writer = Writer()
        writer.int32(1, -42)
        data = writer.finish()

        field = next(Reader(data))
        assert field.int32() == -42

    def test_int32_min_max(self):
        writer = Writer()
        writer.int32(1, 2147483647)  # INT32_MAX
        writer.int32(2, -2147483648)  # INT32_MIN
        data = writer.finish()

        fields = list(Reader(data))
        assert fields[0].int32() == 2147483647
        assert fields[1].int32() == -2147483648

    def test_int64_positive(self):
        writer = Writer()
        writer.int64(1, 9223372036854775807)  # INT64_MAX
        data = writer.finish()

        field = next(Reader(data))
        assert field.int64() == 9223372036854775807

    def test_int64_negative(self):
        writer = Writer()
        writer.int64(1, -9223372036854775808)  # INT64_MIN
        data = writer.finish()

        field = next(Reader(data))
        assert field.int64() == -9223372036854775808

    def test_uint32(self):
        writer = Writer()
        writer.uint32(1, 4294967295)  # UINT32_MAX
        data = writer.finish()

        field = next(Reader(data))
        assert field.uint32() == 4294967295

    def test_uint64(self):
        writer = Writer()
        writer.uint64(1, 18446744073709551615)  # UINT64_MAX
        data = writer.finish()

        field = next(Reader(data))
        assert field.uint64() == 18446744073709551615

    def test_sint32_positive(self):
        writer = Writer()
        writer.sint32(1, 42)
        data = writer.finish()

        field = next(Reader(data))
        assert field.sint32() == 42

    def test_sint32_negative(self):
        writer = Writer()
        writer.sint32(1, -42)
        data = writer.finish()

        field = next(Reader(data))
        assert field.sint32() == -42

    def test_sint64_positive(self):
        writer = Writer()
        writer.sint64(1, 1000000000000)
        data = writer.finish()

        field = next(Reader(data))
        assert field.sint64() == 1000000000000

    def test_sint64_negative(self):
        writer = Writer()
        writer.sint64(1, -1000000000000)
        data = writer.finish()

        field = next(Reader(data))
        assert field.sint64() == -1000000000000

    def test_bool_true(self):
        writer = Writer()
        writer.bool(1, True)
        data = writer.finish()

        field = next(Reader(data))
        assert field.bool() is True

    def test_bool_false(self):
        writer = Writer()
        writer.bool(1, False)
        data = writer.finish()

        field = next(Reader(data))
        assert field.bool() is False

    def test_enum(self):
        writer = Writer()
        writer.enum(1, 3)
        data = writer.finish()

        field = next(Reader(data))
        assert field.enum() == 3


class TestReaderFixed64Types:
    """Tests for reading 64-bit fixed types."""

    def test_fixed64(self):
        writer = Writer()
        writer.fixed64(1, 0xDEADBEEFCAFEBABE)
        data = writer.finish()

        field = next(Reader(data))
        assert field.wire_type == WireType.FIXED64
        assert field.fixed64() == 0xDEADBEEFCAFEBABE

    def test_sfixed64_positive(self):
        writer = Writer()
        writer.sfixed64(1, 9223372036854775807)
        data = writer.finish()

        field = next(Reader(data))
        assert field.sfixed64() == 9223372036854775807

    def test_sfixed64_negative(self):
        writer = Writer()
        writer.sfixed64(1, -9223372036854775808)
        data = writer.finish()

        field = next(Reader(data))
        assert field.sfixed64() == -9223372036854775808

    def test_double(self):
        writer = Writer()
        writer.double(1, 3.14159265358979)
        data = writer.finish()

        field = next(Reader(data))
        assert abs(field.double() - 3.14159265358979) < 1e-10

    def test_double_special_values(self):
        import math

        writer = Writer()
        writer.double(1, float("inf"))
        writer.double(2, float("-inf"))
        writer.double(3, float("nan"))
        data = writer.finish()

        fields = list(Reader(data))
        assert fields[0].double() == float("inf")
        assert fields[1].double() == float("-inf")
        assert math.isnan(fields[2].double())


class TestReaderFixed32Types:
    """Tests for reading 32-bit fixed types."""

    def test_fixed32(self):
        writer = Writer()
        writer.fixed32(1, 0xDEADBEEF)
        data = writer.finish()

        field = next(Reader(data))
        assert field.wire_type == WireType.FIXED32
        assert field.fixed32() == 0xDEADBEEF

    def test_sfixed32_positive(self):
        writer = Writer()
        writer.sfixed32(1, 2147483647)
        data = writer.finish()

        field = next(Reader(data))
        assert field.sfixed32() == 2147483647

    def test_sfixed32_negative(self):
        writer = Writer()
        writer.sfixed32(1, -2147483648)
        data = writer.finish()

        field = next(Reader(data))
        assert field.sfixed32() == -2147483648

    def test_float(self):
        writer = Writer()
        writer.float(1, 3.14)
        data = writer.finish()

        field = next(Reader(data))
        assert abs(field.float() - 3.14) < 1e-5


class TestReaderLengthDelimited:
    """Tests for reading length-delimited types."""

    def test_string_ascii(self):
        writer = Writer()
        writer.string(1, "hello world")
        data = writer.finish()

        field = next(Reader(data))
        assert field.wire_type == WireType.LEN
        assert field.string() == "hello world"

    def test_string_unicode(self):
        writer = Writer()
        writer.string(1, "hello 世界 🌍")
        data = writer.finish()

        field = next(Reader(data))
        assert field.string() == "hello 世界 🌍"

    def test_string_empty(self):
        writer = Writer()
        writer.string(1, "")
        data = writer.finish()

        field = next(Reader(data))
        assert field.string() == ""

    def test_bytes(self):
        writer = Writer()
        writer.bytes(1, b"\x00\x01\x02\xff")
        data = writer.finish()

        field = next(Reader(data))
        assert field.bytes() == b"\x00\x01\x02\xff"

    def test_bytes_empty(self):
        writer = Writer()
        writer.bytes(1, b"")
        data = writer.finish()

        field = next(Reader(data))
        assert field.bytes() == b""

    def test_message_data(self):
        # Build a nested message manually
        inner = Writer()
        inner.string(1, "nested")
        inner_data = inner.finish()

        outer = Writer()
        outer.bytes(1, inner_data)  # Treat as raw bytes
        data = outer.finish()

        field = next(Reader(data))
        assert field.message_data() == inner_data

    def test_message_nested_reader(self):
        inner = Writer()
        inner.string(1, "nested")
        inner.int32(2, 42)
        inner_data = inner.finish()

        outer = Writer()
        outer.bytes(1, inner_data)
        data = outer.finish()

        field = next(Reader(data))
        nested_reader = field.message()
        nested_fields = list(nested_reader)

        assert len(nested_fields) == 2
        assert nested_fields[0].string() == "nested"
        assert nested_fields[1].int32() == 42


class TestReaderPackedRepeated:
    """Tests for reading packed repeated fields."""

    def test_packed_int32s(self):
        writer = Writer()
        writer.packed_int32s(1, [1, 2, 3, -1, -2])
        data = writer.finish()

        field = next(Reader(data))
        assert field.packed_int32s() == [1, 2, 3, -1, -2]

    def test_packed_int64s(self):
        writer = Writer()
        writer.packed_int64s(1, [1, 1000000000000, -1000000000000])
        data = writer.finish()

        field = next(Reader(data))
        assert field.packed_int64s() == [1, 1000000000000, -1000000000000]

    def test_packed_uint32s(self):
        writer = Writer()
        writer.packed_uint32s(1, [0, 1, 4294967295])
        data = writer.finish()

        field = next(Reader(data))
        assert field.packed_uint32s() == [0, 1, 4294967295]

    def test_packed_uint64s(self):
        writer = Writer()
        writer.packed_uint64s(1, [0, 1, 18446744073709551615])
        data = writer.finish()

        field = next(Reader(data))
        assert field.packed_uint64s() == [0, 1, 18446744073709551615]

    def test_packed_sint32s(self):
        writer = Writer()
        writer.packed_sint32s(1, [0, 1, -1, 100, -100])
        data = writer.finish()

        field = next(Reader(data))
        assert field.packed_sint32s() == [0, 1, -1, 100, -100]

    def test_packed_sint64s(self):
        writer = Writer()
        writer.packed_sint64s(1, [0, 1000000000000, -1000000000000])
        data = writer.finish()

        field = next(Reader(data))
        assert field.packed_sint64s() == [0, 1000000000000, -1000000000000]

    def test_packed_bools(self):
        writer = Writer()
        writer.packed_bools(1, [True, False, True, True, False])
        data = writer.finish()

        field = next(Reader(data))
        assert field.packed_bools() == [True, False, True, True, False]

    def test_packed_fixed32s(self):
        writer = Writer()
        writer.packed_fixed32s(1, [0, 1, 0xFFFFFFFF])
        data = writer.finish()

        field = next(Reader(data))
        assert field.packed_fixed32s() == [0, 1, 0xFFFFFFFF]

    def test_packed_sfixed32s(self):
        writer = Writer()
        writer.packed_sfixed32s(1, [0, 2147483647, -2147483648])
        data = writer.finish()

        field = next(Reader(data))
        assert field.packed_sfixed32s() == [0, 2147483647, -2147483648]

    def test_packed_floats(self):
        writer = Writer()
        writer.packed_floats(1, [1.0, 2.5, -3.5])
        data = writer.finish()

        field = next(Reader(data))
        result = field.packed_floats()
        assert len(result) == 3
        assert abs(result[0] - 1.0) < 1e-5
        assert abs(result[1] - 2.5) < 1e-5
        assert abs(result[2] - (-3.5)) < 1e-5

    def test_packed_fixed64s(self):
        writer = Writer()
        writer.packed_fixed64s(1, [0, 1, 0xFFFFFFFFFFFFFFFF])
        data = writer.finish()

        field = next(Reader(data))
        assert field.packed_fixed64s() == [0, 1, 0xFFFFFFFFFFFFFFFF]

    def test_packed_sfixed64s(self):
        writer = Writer()
        writer.packed_sfixed64s(1, [0, 9223372036854775807, -9223372036854775808])
        data = writer.finish()

        field = next(Reader(data))
        assert field.packed_sfixed64s() == [
            0,
            9223372036854775807,
            -9223372036854775808,
        ]

    def test_packed_doubles(self):
        writer = Writer()
        writer.packed_doubles(1, [1.0, 2.5, 3.14159265358979])
        data = writer.finish()

        field = next(Reader(data))
        result = field.packed_doubles()
        assert len(result) == 3
        assert result[0] == 1.0
        assert result[1] == 2.5
        assert abs(result[2] - 3.14159265358979) < 1e-10

    def test_packed_empty(self):
        # Empty packed fields are not written at all
        writer = Writer()
        writer.packed_int32s(1, [])
        writer.int32(2, 42)  # Add a field so we have something to read
        data = writer.finish()

        fields = list(Reader(data))
        assert len(fields) == 1
        assert fields[0].number == 2


class TestReaderErrors:
    """Tests for error handling."""

    def test_truncated_varint(self):
        # Varint with continuation bit but no more bytes
        data = b"\x08\x80"  # tag for field 1 varint, incomplete varint
        reader = Reader(data)
        with pytest.raises(ValueError, match="truncated"):
            next(reader)

    def test_truncated_fixed64(self):
        # Tag says fixed64 but only 4 bytes
        tag = bytes([_make_tag(1, WireType.FIXED64)])
        data = tag + b"\x00\x00\x00\x00"  # Only 4 bytes, need 8
        reader = Reader(data)
        with pytest.raises(ValueError, match="truncated"):
            next(reader)

    def test_truncated_fixed32(self):
        # Tag says fixed32 but only 2 bytes
        tag = bytes([_make_tag(1, WireType.FIXED32)])
        data = tag + b"\x00\x00"  # Only 2 bytes, need 4
        reader = Reader(data)
        with pytest.raises(ValueError, match="truncated"):
            next(reader)

    def test_truncated_length_delimited(self):
        # Tag says LEN with length 100 but only 10 bytes
        tag = bytes([_make_tag(1, WireType.LEN)])
        data = tag + _encode_varint(100) + b"0123456789"
        reader = Reader(data)
        with pytest.raises(ValueError, match="truncated"):
            next(reader)

    def test_wire_type_mismatch_varint_vs_string(self):
        writer = Writer()
        writer.string(1, "hello")
        data = writer.finish()

        field = next(Reader(data))
        with pytest.raises(ValueError, match="wire type mismatch"):
            field.int32()

    def test_wire_type_mismatch_fixed64_vs_varint(self):
        writer = Writer()
        writer.int32(1, 42)
        data = writer.finish()

        field = next(Reader(data))
        with pytest.raises(ValueError, match="wire type mismatch"):
            field.double()

    def test_packed_fixed32_wrong_length(self):
        # Length not a multiple of 4
        tag = bytes([_make_tag(1, WireType.LEN)])
        data = tag + _encode_varint(5) + b"\x00\x00\x00\x00\x00"
        field = next(Reader(data))
        with pytest.raises(ValueError, match="not a multiple of 4"):
            field.packed_fixed32s()

    def test_packed_fixed64_wrong_length(self):
        # Length not a multiple of 8
        tag = bytes([_make_tag(1, WireType.LEN)])
        data = tag + _encode_varint(10) + b"\x00" * 10
        field = next(Reader(data))
        with pytest.raises(ValueError, match="not a multiple of 8"):
            field.packed_fixed64s()


class TestReaderMemoryview:
    """Tests for Reader with memoryview input."""

    def test_memoryview_input(self):
        writer = Writer()
        writer.string(1, "hello")
        writer.int32(2, 42)
        data = writer.finish()

        # Pass as memoryview
        mv = memoryview(data)
        fields = list(Reader(mv))

        assert len(fields) == 2
        assert fields[0].string() == "hello"
        assert fields[1].int32() == 42

    def test_memoryview_slice(self):
        writer = Writer()
        writer.int32(1, 10)
        writer.int32(2, 20)
        writer.int32(3, 30)
        data = writer.finish()

        # Create a message padded with extra bytes
        padded = b"\xff\xff" + data + b"\xff\xff"
        mv = memoryview(padded)[2:-2]

        fields = list(Reader(mv))
        assert len(fields) == 3
        assert [f.int32() for f in fields] == [10, 20, 30]


class TestReaderMultipleFields:
    """Tests for messages with multiple fields."""

    def test_same_field_repeated(self):
        # Non-packed repeated fields appear multiple times
        writer = Writer()
        writer.int32(1, 10)
        writer.int32(1, 20)
        writer.int32(1, 30)
        data = writer.finish()

        fields = list(Reader(data))
        assert len(fields) == 3
        assert all(f.number == 1 for f in fields)
        assert [f.int32() for f in fields] == [10, 20, 30]

    def test_fields_out_of_order(self):
        # Protobuf allows fields in any order
        writer = Writer()
        writer.int32(3, 30)
        writer.int32(1, 10)
        writer.int32(2, 20)
        data = writer.finish()

        fields = list(Reader(data))
        assert [f.number for f in fields] == [3, 1, 2]
        assert [f.int32() for f in fields] == [30, 10, 20]

    def test_large_field_numbers(self):
        writer = Writer()
        writer.int32(1, 1)
        writer.int32(100, 100)
        writer.int32(10000, 10000)
        writer.int32(536870911, 536870911)  # Max field number (2^29 - 1)
        data = writer.finish()

        fields = list(Reader(data))
        assert [f.number for f in fields] == [1, 100, 10000, 536870911]
        assert [f.int32() for f in fields] == [1, 100, 10000, 536870911]

    def test_mixed_types(self):
        writer = Writer()
        writer.int32(1, 42)
        writer.string(2, "hello")
        writer.double(3, 3.14)
        writer.bytes(4, b"\x00\x01")
        writer.bool(5, True)
        writer.fixed32(6, 0xDEADBEEF)
        data = writer.finish()

        fields = list(Reader(data))
        assert fields[0].int32() == 42
        assert fields[1].string() == "hello"
        assert abs(fields[2].double() - 3.14) < 1e-10
        assert fields[3].bytes() == b"\x00\x01"
        assert fields[4].bool() is True
        assert fields[5].fixed32() == 0xDEADBEEF
