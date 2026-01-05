"""Tests for the Reader class."""

import io
import socket
import tempfile

import pytest

from fastproto import Reader, Scalar, WireType, Writer


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
    return (field_number << 3) | int(wire_type)


_SCALAR_WIRE = {
    Scalar.i32: WireType.VARINT,
    Scalar.i64: WireType.VARINT,
    Scalar.u32: WireType.VARINT,
    Scalar.u64: WireType.VARINT,
    Scalar.sint32: WireType.VARINT,
    Scalar.sint64: WireType.VARINT,
    Scalar.bool: WireType.VARINT,
    Scalar.fixed64: WireType.FIXED64,
    Scalar.sfixed64: WireType.FIXED64,
    Scalar.double: WireType.FIXED64,
    Scalar.fixed32: WireType.FIXED32,
    Scalar.sfixed32: WireType.FIXED32,
    Scalar.float: WireType.FIXED32,
}


def make_reader(data: bytes) -> Reader:
    return Reader(io.BytesIO(data))


def make_writer() -> tuple[Writer, io.BytesIO]:
    stream = io.BytesIO()
    return Writer(stream), stream


def finish(writer: Writer, stream: io.BytesIO) -> bytes:
    writer.flush()
    return stream.getvalue()


def write_scalar_field(
    writer: Writer, field_number: int, scalar: Scalar, value: object
) -> None:
    writer.write_tag(field_number, _SCALAR_WIRE[scalar])
    writer.write_scalar(scalar, value)


def write_len_field(writer: Writer, field_number: int, data: bytes) -> None:
    writer.write_tag(field_number, WireType.LEN)
    writer.write_len(data)


def write_packed_field(
    writer: Writer, field_number: int, scalar: Scalar, values: list[object]
) -> None:
    if not values:
        return
    packed_stream = io.BytesIO()
    packed_writer = Writer(packed_stream)
    for value in values:
        packed_writer.write_scalar(scalar, value)
    packed_writer.flush()
    write_len_field(writer, field_number, packed_stream.getvalue())


class TestReaderBasic:
    """Basic Reader functionality tests."""

    def test_empty_message(self):
        reader = make_reader(b"")
        assert list(reader) == []

    def test_remaining(self):
        data = b"\x08\x01"  # field 1, varint 1
        reader = make_reader(data)
        assert reader.remaining() is None
        next(reader)
        assert reader.remaining() is None

    def test_skip_len_field(self):
        # Two fields: field 1 = "hello", field 2 = 100
        writer, stream = make_writer()
        write_len_field(writer, 1, b"hello")
        write_scalar_field(writer, 2, Scalar.i32, 100)
        data = finish(writer, stream)

        reader = make_reader(data)
        field = reader.next()
        assert field is not None
        field.skip()
        field = reader.next()
        assert field is not None
        assert field.number == 2
        assert field.expect(WireType.VARINT).as_scalar(Scalar.i32) == 100

    def test_next_field_returns_none_at_end(self):
        reader = make_reader(b"")
        assert reader.next() is None

    def test_iteration_protocol(self):
        writer, stream = make_writer()
        write_scalar_field(writer, 1, Scalar.i32, 10)
        write_scalar_field(writer, 2, Scalar.i32, 20)
        write_scalar_field(writer, 3, Scalar.i32, 30)
        data = finish(writer, stream)

        fields = list(make_reader(data))
        assert len(fields) == 3
        assert [f.number for f in fields] == [1, 2, 3]
        assert [f.expect(WireType.VARINT).as_scalar(Scalar.i32) for f in fields] == [
            10,
            20,
            30,
        ]


class TestReaderVarintTypes:
    """Tests for reading varint-encoded types."""

    def test_int32_positive(self):
        writer, stream = make_writer()
        write_scalar_field(writer, 1, Scalar.i32, 42)
        data = finish(writer, stream)

        field = next(make_reader(data))
        assert field.number == 1
        assert field.wire_type == WireType.VARINT
        assert field.expect(WireType.VARINT).as_scalar(Scalar.i32) == 42

    def test_int32_negative(self):
        writer, stream = make_writer()
        write_scalar_field(writer, 1, Scalar.i32, -42)
        data = finish(writer, stream)

        field = next(make_reader(data))
        assert field.expect(WireType.VARINT).as_scalar(Scalar.i32) == -42

    def test_int32_min_max(self):
        writer, stream = make_writer()
        write_scalar_field(writer, 1, Scalar.i32, 2147483647)
        write_scalar_field(writer, 2, Scalar.i32, -2147483648)
        data = finish(writer, stream)

        fields = list(make_reader(data))
        assert fields[0].expect(WireType.VARINT).as_scalar(Scalar.i32) == 2147483647
        assert fields[1].expect(WireType.VARINT).as_scalar(Scalar.i32) == -2147483648

    def test_int64_positive(self):
        writer, stream = make_writer()
        write_scalar_field(writer, 1, Scalar.i64, 9223372036854775807)
        data = finish(writer, stream)

        field = next(make_reader(data))
        assert (
            field.expect(WireType.VARINT).as_scalar(Scalar.i64) == 9223372036854775807
        )

    def test_int64_negative(self):
        writer, stream = make_writer()
        write_scalar_field(writer, 1, Scalar.i64, -9223372036854775808)
        data = finish(writer, stream)

        field = next(make_reader(data))
        assert (
            field.expect(WireType.VARINT).as_scalar(Scalar.i64) == -9223372036854775808
        )

    def test_uint32(self):
        writer, stream = make_writer()
        write_scalar_field(writer, 1, Scalar.u32, 4294967295)
        data = finish(writer, stream)

        field = next(make_reader(data))
        assert field.expect(WireType.VARINT).as_scalar(Scalar.u32) == 4294967295

    def test_uint64(self):
        writer, stream = make_writer()
        write_scalar_field(writer, 1, Scalar.u64, 18446744073709551615)
        data = finish(writer, stream)

        field = next(make_reader(data))
        assert (
            field.expect(WireType.VARINT).as_scalar(Scalar.u64) == 18446744073709551615
        )

    def test_sint32_positive(self):
        writer, stream = make_writer()
        write_scalar_field(writer, 1, Scalar.sint32, 42)
        data = finish(writer, stream)

        field = next(make_reader(data))
        assert field.expect(WireType.VARINT).as_scalar(Scalar.sint32) == 42

    def test_sint32_negative(self):
        writer, stream = make_writer()
        write_scalar_field(writer, 1, Scalar.sint32, -42)
        data = finish(writer, stream)

        field = next(make_reader(data))
        assert field.expect(WireType.VARINT).as_scalar(Scalar.sint32) == -42

    def test_sint64_positive(self):
        writer, stream = make_writer()
        write_scalar_field(writer, 1, Scalar.sint64, 1000000000000)
        data = finish(writer, stream)

        field = next(make_reader(data))
        assert field.expect(WireType.VARINT).as_scalar(Scalar.sint64) == 1000000000000

    def test_sint64_negative(self):
        writer, stream = make_writer()
        write_scalar_field(writer, 1, Scalar.sint64, -1000000000000)
        data = finish(writer, stream)

        field = next(make_reader(data))
        assert field.expect(WireType.VARINT).as_scalar(Scalar.sint64) == -1000000000000

    def test_bool_true(self):
        writer, stream = make_writer()
        write_scalar_field(writer, 1, Scalar.bool, True)
        data = finish(writer, stream)

        field = next(make_reader(data))
        assert field.expect(WireType.VARINT).as_scalar(Scalar.bool) is True

    def test_bool_false(self):
        writer, stream = make_writer()
        write_scalar_field(writer, 1, Scalar.bool, False)
        data = finish(writer, stream)

        field = next(make_reader(data))
        assert field.expect(WireType.VARINT).as_scalar(Scalar.bool) is False

    def test_enum(self):
        writer, stream = make_writer()
        write_scalar_field(writer, 1, Scalar.i32, 3)
        data = finish(writer, stream)

        field = next(make_reader(data))
        assert field.expect(WireType.VARINT).as_scalar(Scalar.i32) == 3


class TestReaderFixed64Types:
    """Tests for reading 64-bit fixed types."""

    def test_fixed64(self):
        writer, stream = make_writer()
        write_scalar_field(writer, 1, Scalar.fixed64, 0xDEADBEEFCAFEBABE)
        data = finish(writer, stream)

        field = next(make_reader(data))
        assert field.wire_type == WireType.FIXED64
        assert (
            field.expect(WireType.FIXED64).as_scalar(Scalar.fixed64)
            == 0xDEADBEEFCAFEBABE
        )

    def test_sfixed64_positive(self):
        writer, stream = make_writer()
        write_scalar_field(writer, 1, Scalar.sfixed64, 9223372036854775807)
        data = finish(writer, stream)

        field = next(make_reader(data))
        assert (
            field.expect(WireType.FIXED64).as_scalar(Scalar.sfixed64)
            == 9223372036854775807
        )

    def test_sfixed64_negative(self):
        writer, stream = make_writer()
        write_scalar_field(writer, 1, Scalar.sfixed64, -9223372036854775808)
        data = finish(writer, stream)

        field = next(make_reader(data))
        assert (
            field.expect(WireType.FIXED64).as_scalar(Scalar.sfixed64)
            == -9223372036854775808
        )

    def test_double(self):
        writer, stream = make_writer()
        write_scalar_field(writer, 1, Scalar.double, 3.14159265358979)
        data = finish(writer, stream)

        field = next(make_reader(data))
        assert (
            abs(
                field.expect(WireType.FIXED64).as_scalar(Scalar.double)
                - 3.14159265358979
            )
            < 1e-10
        )

    def test_double_special_values(self):
        import math

        writer, stream = make_writer()
        write_scalar_field(writer, 1, Scalar.double, float("inf"))
        write_scalar_field(writer, 2, Scalar.double, float("-inf"))
        write_scalar_field(writer, 3, Scalar.double, float("nan"))
        data = finish(writer, stream)

        fields = list(make_reader(data))
        assert fields[0].expect(WireType.FIXED64).as_scalar(Scalar.double) == float(
            "inf"
        )
        assert fields[1].expect(WireType.FIXED64).as_scalar(Scalar.double) == float(
            "-inf"
        )
        assert math.isnan(fields[2].expect(WireType.FIXED64).as_scalar(Scalar.double))


class TestReaderFixed32Types:
    """Tests for reading 32-bit fixed types."""

    def test_fixed32(self):
        writer, stream = make_writer()
        write_scalar_field(writer, 1, Scalar.fixed32, 0xDEADBEEF)
        data = finish(writer, stream)

        field = next(make_reader(data))
        assert field.wire_type == WireType.FIXED32
        assert field.expect(WireType.FIXED32).as_scalar(Scalar.fixed32) == 0xDEADBEEF

    def test_sfixed32_positive(self):
        writer, stream = make_writer()
        write_scalar_field(writer, 1, Scalar.sfixed32, 2147483647)
        data = finish(writer, stream)

        field = next(make_reader(data))
        assert field.expect(WireType.FIXED32).as_scalar(Scalar.sfixed32) == 2147483647

    def test_sfixed32_negative(self):
        writer, stream = make_writer()
        write_scalar_field(writer, 1, Scalar.sfixed32, -2147483648)
        data = finish(writer, stream)

        field = next(make_reader(data))
        assert field.expect(WireType.FIXED32).as_scalar(Scalar.sfixed32) == -2147483648

    def test_float(self):
        writer, stream = make_writer()
        write_scalar_field(writer, 1, Scalar.float, 3.14)
        data = finish(writer, stream)

        field = next(make_reader(data))
        assert abs(field.expect(WireType.FIXED32).as_scalar(Scalar.float) - 3.14) < 1e-5


class TestReaderLengthDelimited:
    """Tests for reading length-delimited types."""

    def test_string_ascii(self):
        writer, stream = make_writer()
        write_len_field(writer, 1, b"hello world")
        data = finish(writer, stream)

        field = next(make_reader(data))
        assert field.wire_type == WireType.LEN
        assert field.string() == "hello world"

    def test_string_unicode(self):
        writer, stream = make_writer()
        write_len_field(writer, 1, "hello 世界 🌍".encode("utf-8"))
        data = finish(writer, stream)

        field = next(make_reader(data))
        assert field.string() == "hello 世界 🌍"

    def test_string_empty(self):
        writer, stream = make_writer()
        write_len_field(writer, 1, b"")
        data = finish(writer, stream)

        field = next(make_reader(data))
        assert field.string() == ""

    def test_bytes(self):
        writer, stream = make_writer()
        write_len_field(writer, 1, b"\x00\x01\x02\xff")
        data = finish(writer, stream)

        field = next(make_reader(data))
        assert field.bytes() == b"\x00\x01\x02\xff"

    def test_bytes_empty(self):
        writer, stream = make_writer()
        write_len_field(writer, 1, b"")
        data = finish(writer, stream)

        field = next(make_reader(data))
        assert field.bytes() == b""

    def test_message_data(self):
        # Build a nested message manually
        inner, inner_stream = make_writer()
        write_len_field(inner, 1, b"nested")
        inner_data = finish(inner, inner_stream)

        outer, outer_stream = make_writer()
        write_len_field(outer, 1, inner_data)
        data = finish(outer, outer_stream)

        field = next(make_reader(data))
        assert field.bytes() == inner_data

    def test_message_nested_reader(self):
        inner, inner_stream = make_writer()
        write_len_field(inner, 1, b"nested")
        write_scalar_field(inner, 2, Scalar.i32, 42)
        inner_data = finish(inner, inner_stream)

        outer, outer_stream = make_writer()
        write_len_field(outer, 1, inner_data)
        data = finish(outer, outer_stream)

        field = next(make_reader(data))
        nested_reader = field.message()

        nested_name = None
        nested_value = None
        for nested_field in nested_reader:
            if nested_field.number == 1:
                nested_name = nested_field.string()
            elif nested_field.number == 2:
                nested_value = nested_field.expect(WireType.VARINT).as_scalar(
                    Scalar.i32
                )

        assert nested_name == "nested"
        assert nested_value == 42


class TestReaderPackedRepeated:
    """Tests for reading packed repeated fields."""

    def test_packed_int32s(self):
        writer, stream = make_writer()
        write_packed_field(writer, 1, Scalar.i32, [1, 2, 3, -1, -2])
        data = finish(writer, stream)

        field = next(make_reader(data))
        assert field.repeated(Scalar.i32) == [1, 2, 3, -1, -2]

    def test_packed_int64s(self):
        writer, stream = make_writer()
        write_packed_field(writer, 1, Scalar.i64, [1, 1000000000000, -1000000000000])
        data = finish(writer, stream)

        field = next(make_reader(data))
        assert field.repeated(Scalar.i64) == [1, 1000000000000, -1000000000000]

    def test_packed_uint32s(self):
        writer, stream = make_writer()
        write_packed_field(writer, 1, Scalar.u32, [0, 1, 4294967295])
        data = finish(writer, stream)

        field = next(make_reader(data))
        assert field.repeated(Scalar.u32) == [0, 1, 4294967295]

    def test_packed_uint64s(self):
        writer, stream = make_writer()
        write_packed_field(writer, 1, Scalar.u64, [0, 1, 18446744073709551615])
        data = finish(writer, stream)

        field = next(make_reader(data))
        assert field.repeated(Scalar.u64) == [0, 1, 18446744073709551615]

    def test_packed_sint32s(self):
        writer, stream = make_writer()
        write_packed_field(writer, 1, Scalar.sint32, [0, 1, -1, 100, -100])
        data = finish(writer, stream)

        field = next(make_reader(data))
        assert field.repeated(Scalar.sint32) == [0, 1, -1, 100, -100]

    def test_packed_sint64s(self):
        writer, stream = make_writer()
        write_packed_field(writer, 1, Scalar.sint64, [0, 1000000000000, -1000000000000])
        data = finish(writer, stream)

        field = next(make_reader(data))
        assert field.repeated(Scalar.sint64) == [0, 1000000000000, -1000000000000]

    def test_packed_bools(self):
        writer, stream = make_writer()
        write_packed_field(writer, 1, Scalar.bool, [True, False, True, True, False])
        data = finish(writer, stream)

        field = next(make_reader(data))
        assert field.repeated(Scalar.bool) == [True, False, True, True, False]

    def test_packed_fixed32s(self):
        writer, stream = make_writer()
        write_packed_field(writer, 1, Scalar.fixed32, [0, 1, 0xFFFFFFFF])
        data = finish(writer, stream)

        field = next(make_reader(data))
        assert field.repeated(Scalar.fixed32) == [0, 1, 0xFFFFFFFF]

    def test_packed_sfixed32s(self):
        writer, stream = make_writer()
        write_packed_field(writer, 1, Scalar.sfixed32, [0, 2147483647, -2147483648])
        data = finish(writer, stream)

        field = next(make_reader(data))
        assert field.repeated(Scalar.sfixed32) == [0, 2147483647, -2147483648]

    def test_packed_floats(self):
        writer, stream = make_writer()
        write_packed_field(writer, 1, Scalar.float, [1.0, 2.5, -3.5])
        data = finish(writer, stream)

        field = next(make_reader(data))
        result = field.repeated(Scalar.float)
        assert len(result) == 3
        assert abs(result[0] - 1.0) < 1e-5
        assert abs(result[1] - 2.5) < 1e-5
        assert abs(result[2] - (-3.5)) < 1e-5

    def test_packed_fixed64s(self):
        writer, stream = make_writer()
        write_packed_field(writer, 1, Scalar.fixed64, [0, 1, 0xFFFFFFFFFFFFFFFF])
        data = finish(writer, stream)

        field = next(make_reader(data))
        assert field.repeated(Scalar.fixed64) == [0, 1, 0xFFFFFFFFFFFFFFFF]

    def test_packed_sfixed64s(self):
        writer, stream = make_writer()
        write_packed_field(
            writer, 1, Scalar.sfixed64, [0, 9223372036854775807, -9223372036854775808]
        )
        data = finish(writer, stream)

        field = next(make_reader(data))
        assert field.repeated(Scalar.sfixed64) == [
            0,
            9223372036854775807,
            -9223372036854775808,
        ]

    def test_packed_doubles(self):
        writer, stream = make_writer()
        write_packed_field(writer, 1, Scalar.double, [1.0, 2.5, 3.14159265358979])
        data = finish(writer, stream)

        field = next(make_reader(data))
        result = field.repeated(Scalar.double)
        assert len(result) == 3
        assert result[0] == 1.0
        assert result[1] == 2.5
        assert abs(result[2] - 3.14159265358979) < 1e-10

    def test_packed_empty(self):
        # Empty packed fields are not written at all
        writer, stream = make_writer()
        write_packed_field(writer, 1, Scalar.i32, [])
        write_scalar_field(writer, 2, Scalar.i32, 42)
        data = finish(writer, stream)

        fields = list(make_reader(data))
        assert len(fields) == 1
        assert fields[0].number == 2


class TestReaderErrors:
    """Tests for error handling."""

    def test_truncated_varint(self):
        # Varint with continuation bit but no more bytes
        data = b"\x08\x80"  # tag for field 1 varint, incomplete varint
        reader = make_reader(data)
        with pytest.raises(ValueError, match="truncated"):
            next(reader)

    def test_truncated_fixed64(self):
        # Tag says fixed64 but only 4 bytes
        tag = bytes([_make_tag(1, WireType.FIXED64)])
        data = tag + b"\x00\x00\x00\x00"  # Only 4 bytes, need 8
        reader = make_reader(data)
        with pytest.raises(ValueError, match="truncated"):
            next(reader)

    def test_truncated_fixed32(self):
        # Tag says fixed32 but only 2 bytes
        tag = bytes([_make_tag(1, WireType.FIXED32)])
        data = tag + b"\x00\x00"  # Only 2 bytes, need 4
        reader = make_reader(data)
        with pytest.raises(ValueError, match="truncated"):
            next(reader)

    def test_truncated_length_delimited(self):
        # Tag says LEN with length 100 but only 10 bytes
        tag = bytes([_make_tag(1, WireType.LEN)])
        data = tag + _encode_varint(100) + b"0123456789"
        reader = make_reader(data)
        field = next(reader)
        with pytest.raises(ValueError, match="truncated"):
            field.bytes()

    def test_wire_type_mismatch_varint_vs_string(self):
        writer, stream = make_writer()
        write_len_field(writer, 1, b"hello")
        data = finish(writer, stream)

        field = next(make_reader(data))
        with pytest.raises(ValueError, match="wire type mismatch"):
            field.expect(WireType.VARINT)

    def test_wire_type_mismatch_fixed64_vs_varint(self):
        writer, stream = make_writer()
        write_scalar_field(writer, 1, Scalar.i32, 42)
        data = finish(writer, stream)

        field = next(make_reader(data))
        with pytest.raises(ValueError, match="wire type mismatch"):
            field.as_scalar(Scalar.double)

    def test_packed_fixed32_wrong_length(self):
        # Length not a multiple of 4
        tag = bytes([_make_tag(1, WireType.LEN)])
        data = tag + _encode_varint(5) + b"\x00\x00\x00\x00\x00"
        field = next(make_reader(data))
        with pytest.raises(ValueError, match="not a multiple of 4"):
            field.repeated(Scalar.fixed32)

    def test_packed_fixed64_wrong_length(self):
        # Length not a multiple of 8
        tag = bytes([_make_tag(1, WireType.LEN)])
        data = tag + _encode_varint(10) + b"\x00" * 10
        field = next(make_reader(data))
        with pytest.raises(ValueError, match="not a multiple of 8"):
            field.repeated(Scalar.fixed64)


class TestReaderMultipleFields:
    """Tests for messages with multiple fields."""

    def test_same_field_repeated(self):
        # Non-packed repeated fields appear multiple times
        writer, stream = make_writer()
        write_scalar_field(writer, 1, Scalar.i32, 10)
        write_scalar_field(writer, 1, Scalar.i32, 20)
        write_scalar_field(writer, 1, Scalar.i32, 30)
        data = finish(writer, stream)

        fields = list(make_reader(data))
        assert len(fields) == 3
        assert all(f.number == 1 for f in fields)
        assert [f.expect(WireType.VARINT).as_scalar(Scalar.i32) for f in fields] == [
            10,
            20,
            30,
        ]

    def test_fields_out_of_order(self):
        # Protobuf allows fields in any order
        writer, stream = make_writer()
        write_scalar_field(writer, 3, Scalar.i32, 30)
        write_scalar_field(writer, 1, Scalar.i32, 10)
        write_scalar_field(writer, 2, Scalar.i32, 20)
        data = finish(writer, stream)

        fields = list(make_reader(data))
        assert [f.number for f in fields] == [3, 1, 2]
        assert [f.expect(WireType.VARINT).as_scalar(Scalar.i32) for f in fields] == [
            30,
            10,
            20,
        ]

    def test_large_field_numbers(self):
        writer, stream = make_writer()
        write_scalar_field(writer, 1, Scalar.i32, 1)
        write_scalar_field(writer, 100, Scalar.i32, 100)
        write_scalar_field(writer, 10000, Scalar.i32, 10000)
        write_scalar_field(writer, 536870911, Scalar.i32, 536870911)
        data = finish(writer, stream)

        fields = list(make_reader(data))
        assert [f.number for f in fields] == [1, 100, 10000, 536870911]
        assert [f.expect(WireType.VARINT).as_scalar(Scalar.i32) for f in fields] == [
            1,
            100,
            10000,
            536870911,
        ]

    def test_mixed_types(self):
        writer, stream = make_writer()
        write_scalar_field(writer, 1, Scalar.i32, 42)
        write_len_field(writer, 2, b"hello")
        write_scalar_field(writer, 3, Scalar.double, 3.14)
        write_len_field(writer, 4, b"\x00\x01")
        write_scalar_field(writer, 5, Scalar.bool, True)
        write_scalar_field(writer, 6, Scalar.fixed32, 0xDEADBEEF)
        data = finish(writer, stream)

        results = {}
        for field in make_reader(data):
            match field.number:
                case 1:
                    results["int"] = field.expect(WireType.VARINT).as_scalar(Scalar.i32)
                case 2:
                    results["str"] = field.string()
                case 3:
                    results["double"] = field.expect(WireType.FIXED64).as_scalar(
                        Scalar.double
                    )
                case 4:
                    results["bytes"] = field.bytes()
                case 5:
                    results["bool"] = field.expect(WireType.VARINT).as_scalar(
                        Scalar.bool
                    )
                case 6:
                    results["fixed32"] = field.expect(WireType.FIXED32).as_scalar(
                        Scalar.fixed32
                    )

        assert results["int"] == 42
        assert results["str"] == "hello"
        assert abs(results["double"] - 3.14) < 1e-10
        assert results["bytes"] == b"\x00\x01"
        assert results["bool"] is True
        assert results["fixed32"] == 0xDEADBEEF


class TestReaderStreams:
    """Tests for reading from binary IO streams."""

    def test_bytesio(self):
        writer, stream = make_writer()
        write_scalar_field(writer, 1, Scalar.i32, 42)
        data = finish(writer, stream)

        stream = io.BytesIO(data)
        field = next(Reader(stream))
        assert field.expect(WireType.VARINT).as_scalar(Scalar.i32) == 42

    def test_file_stream(self):
        writer, stream = make_writer()
        write_scalar_field(writer, 1, Scalar.i32, 42)
        data = finish(writer, stream)

        with tempfile.TemporaryFile() as file:
            file.write(data)
            file.seek(0)
            fields = list(Reader(file))

        assert fields[0].expect(WireType.VARINT).as_scalar(Scalar.i32) == 42

    def test_socket_stream(self):
        writer, stream = make_writer()
        write_scalar_field(writer, 1, Scalar.i32, 42)
        data = finish(writer, stream)

        sock_a, sock_b = socket.socketpair()
        with sock_a, sock_b:
            sock_a.sendall(data)
            sock_a.shutdown(socket.SHUT_WR)
            with sock_b.makefile("rb") as stream:
                fields = list(Reader(stream))

        assert fields[0].expect(WireType.VARINT).as_scalar(Scalar.i32) == 42
