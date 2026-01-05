"""Tests for the Writer class."""

import io
import socket
import tempfile

from fastproto import Reader, Scalar, WireType, Writer

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


class TestWriterBasic:
    """Basic Writer functionality tests."""

    def test_empty_message(self):
        writer, stream = make_writer()
        writer.flush()
        assert stream.getvalue() == b""

    def test_write_and_read_roundtrip(self):
        writer, stream = make_writer()
        write_scalar_field(writer, 1, Scalar.i32, 42)
        data = finish(writer, stream)

        field = next(Reader(io.BytesIO(data)))
        assert field.expect(WireType.VARINT).as_scalar(Scalar.i32) == 42

    def test_multiple_fields(self):
        writer, stream = make_writer()
        write_scalar_field(writer, 1, Scalar.i32, 42)
        write_len_field(writer, 2, b"hello")
        data = finish(writer, stream)

        results = {}
        for field in Reader(io.BytesIO(data)):
            match field.number:
                case 1:
                    results["int"] = field.expect(WireType.VARINT).as_scalar(Scalar.i32)
                case 2:
                    results["str"] = field.string()

        assert results["int"] == 42
        assert results["str"] == "hello"


class TestWriterVarintTypes:
    """Tests for writing varint-encoded types."""

    def test_int32_positive(self):
        writer, stream = make_writer()
        write_scalar_field(writer, 1, Scalar.i32, 42)
        data = finish(writer, stream)

        field = next(Reader(io.BytesIO(data)))
        assert field.wire_type == WireType.VARINT
        assert field.expect(WireType.VARINT).as_scalar(Scalar.i32) == 42

    def test_int32_zero(self):
        writer, stream = make_writer()
        write_scalar_field(writer, 1, Scalar.i32, 0)
        data = finish(writer, stream)

        field = next(Reader(io.BytesIO(data)))
        assert field.expect(WireType.VARINT).as_scalar(Scalar.i32) == 0

    def test_int32_negative(self):
        writer, stream = make_writer()
        write_scalar_field(writer, 1, Scalar.i32, -1)
        write_scalar_field(writer, 2, Scalar.i32, -42)
        write_scalar_field(writer, 3, Scalar.i32, -2147483648)
        data = finish(writer, stream)

        fields = list(Reader(io.BytesIO(data)))
        assert fields[0].expect(WireType.VARINT).as_scalar(Scalar.i32) == -1
        assert fields[1].expect(WireType.VARINT).as_scalar(Scalar.i32) == -42
        assert fields[2].expect(WireType.VARINT).as_scalar(Scalar.i32) == -2147483648

    def test_int32_max(self):
        writer, stream = make_writer()
        write_scalar_field(writer, 1, Scalar.i32, 2147483647)
        data = finish(writer, stream)

        field = next(Reader(io.BytesIO(data)))
        assert field.expect(WireType.VARINT).as_scalar(Scalar.i32) == 2147483647

    def test_int64_positive(self):
        writer, stream = make_writer()
        write_scalar_field(writer, 1, Scalar.i64, 9223372036854775807)
        data = finish(writer, stream)

        field = next(Reader(io.BytesIO(data)))
        assert (
            field.expect(WireType.VARINT).as_scalar(Scalar.i64) == 9223372036854775807
        )

    def test_int64_negative(self):
        writer, stream = make_writer()
        write_scalar_field(writer, 1, Scalar.i64, -9223372036854775808)
        data = finish(writer, stream)

        field = next(Reader(io.BytesIO(data)))
        assert (
            field.expect(WireType.VARINT).as_scalar(Scalar.i64) == -9223372036854775808
        )

    def test_int64_large(self):
        writer, stream = make_writer()
        write_scalar_field(writer, 1, Scalar.i64, 1000000000000)
        data = finish(writer, stream)

        field = next(Reader(io.BytesIO(data)))
        assert field.expect(WireType.VARINT).as_scalar(Scalar.i64) == 1000000000000

    def test_uint32(self):
        writer, stream = make_writer()
        write_scalar_field(writer, 1, Scalar.u32, 0)
        write_scalar_field(writer, 2, Scalar.u32, 1)
        write_scalar_field(writer, 3, Scalar.u32, 4294967295)
        data = finish(writer, stream)

        fields = list(Reader(io.BytesIO(data)))
        assert fields[0].expect(WireType.VARINT).as_scalar(Scalar.u32) == 0
        assert fields[1].expect(WireType.VARINT).as_scalar(Scalar.u32) == 1
        assert fields[2].expect(WireType.VARINT).as_scalar(Scalar.u32) == 4294967295

    def test_uint64(self):
        writer, stream = make_writer()
        write_scalar_field(writer, 1, Scalar.u64, 0)
        write_scalar_field(writer, 2, Scalar.u64, 18446744073709551615)
        data = finish(writer, stream)

        fields = list(Reader(io.BytesIO(data)))
        assert fields[0].expect(WireType.VARINT).as_scalar(Scalar.u64) == 0
        assert (
            fields[1].expect(WireType.VARINT).as_scalar(Scalar.u64)
            == 18446744073709551615
        )

    def test_sint32_positive(self):
        writer, stream = make_writer()
        write_scalar_field(writer, 1, Scalar.sint32, 0)
        write_scalar_field(writer, 2, Scalar.sint32, 1)
        write_scalar_field(writer, 3, Scalar.sint32, 2147483647)
        data = finish(writer, stream)

        fields = list(Reader(io.BytesIO(data)))
        assert fields[0].expect(WireType.VARINT).as_scalar(Scalar.sint32) == 0
        assert fields[1].expect(WireType.VARINT).as_scalar(Scalar.sint32) == 1
        assert fields[2].expect(WireType.VARINT).as_scalar(Scalar.sint32) == 2147483647

    def test_sint32_negative(self):
        writer, stream = make_writer()
        write_scalar_field(writer, 1, Scalar.sint32, -1)
        write_scalar_field(writer, 2, Scalar.sint32, -100)
        write_scalar_field(writer, 3, Scalar.sint32, -2147483648)
        data = finish(writer, stream)

        fields = list(Reader(io.BytesIO(data)))
        assert fields[0].expect(WireType.VARINT).as_scalar(Scalar.sint32) == -1
        assert fields[1].expect(WireType.VARINT).as_scalar(Scalar.sint32) == -100
        assert fields[2].expect(WireType.VARINT).as_scalar(Scalar.sint32) == -2147483648

    def test_sint32_efficiency(self):
        writer1, stream1 = make_writer()
        write_scalar_field(writer1, 1, Scalar.i32, -1)
        data1 = finish(writer1, stream1)

        writer2, stream2 = make_writer()
        write_scalar_field(writer2, 1, Scalar.sint32, -1)
        data2 = finish(writer2, stream2)

        assert len(data2) < len(data1)

    def test_sint64_positive(self):
        writer, stream = make_writer()
        write_scalar_field(writer, 1, Scalar.sint64, 0)
        write_scalar_field(writer, 2, Scalar.sint64, 1000000000000)
        data = finish(writer, stream)

        fields = list(Reader(io.BytesIO(data)))
        assert fields[0].expect(WireType.VARINT).as_scalar(Scalar.sint64) == 0
        assert (
            fields[1].expect(WireType.VARINT).as_scalar(Scalar.sint64) == 1000000000000
        )

    def test_sint64_negative(self):
        writer, stream = make_writer()
        write_scalar_field(writer, 1, Scalar.sint64, -1)
        write_scalar_field(writer, 2, Scalar.sint64, -1000000000000)
        data = finish(writer, stream)

        fields = list(Reader(io.BytesIO(data)))
        assert fields[0].expect(WireType.VARINT).as_scalar(Scalar.sint64) == -1
        assert (
            fields[1].expect(WireType.VARINT).as_scalar(Scalar.sint64) == -1000000000000
        )

    def test_bool_true(self):
        writer, stream = make_writer()
        write_scalar_field(writer, 1, Scalar.bool, True)
        data = finish(writer, stream)

        field = next(Reader(io.BytesIO(data)))
        assert field.expect(WireType.VARINT).as_scalar(Scalar.bool) is True

    def test_bool_false(self):
        writer, stream = make_writer()
        write_scalar_field(writer, 1, Scalar.bool, False)
        data = finish(writer, stream)

        field = next(Reader(io.BytesIO(data)))
        assert field.expect(WireType.VARINT).as_scalar(Scalar.bool) is False

    def test_enum(self):
        writer, stream = make_writer()
        write_scalar_field(writer, 1, Scalar.i32, 0)
        write_scalar_field(writer, 2, Scalar.i32, 1)
        write_scalar_field(writer, 3, Scalar.i32, 100)
        write_scalar_field(writer, 4, Scalar.i32, -1)
        data = finish(writer, stream)

        fields = list(Reader(io.BytesIO(data)))
        assert fields[0].expect(WireType.VARINT).as_scalar(Scalar.i32) == 0
        assert fields[1].expect(WireType.VARINT).as_scalar(Scalar.i32) == 1
        assert fields[2].expect(WireType.VARINT).as_scalar(Scalar.i32) == 100
        assert fields[3].expect(WireType.VARINT).as_scalar(Scalar.i32) == -1


class TestWriterFixed64Types:
    """Tests for writing 64-bit fixed types."""

    def test_fixed64(self):
        writer, stream = make_writer()
        write_scalar_field(writer, 1, Scalar.fixed64, 0)
        write_scalar_field(writer, 2, Scalar.fixed64, 0xDEADBEEFCAFEBABE)
        write_scalar_field(writer, 3, Scalar.fixed64, 0xFFFFFFFFFFFFFFFF)
        data = finish(writer, stream)

        fields = list(Reader(io.BytesIO(data)))
        assert fields[0].expect(WireType.FIXED64).as_scalar(Scalar.fixed64) == 0
        assert (
            fields[1].expect(WireType.FIXED64).as_scalar(Scalar.fixed64)
            == 0xDEADBEEFCAFEBABE
        )
        assert (
            fields[2].expect(WireType.FIXED64).as_scalar(Scalar.fixed64)
            == 0xFFFFFFFFFFFFFFFF
        )

    def test_sfixed64(self):
        writer, stream = make_writer()
        write_scalar_field(writer, 1, Scalar.sfixed64, 0)
        write_scalar_field(writer, 2, Scalar.sfixed64, 9223372036854775807)
        write_scalar_field(writer, 3, Scalar.sfixed64, -9223372036854775808)
        data = finish(writer, stream)

        fields = list(Reader(io.BytesIO(data)))
        assert fields[0].expect(WireType.FIXED64).as_scalar(Scalar.sfixed64) == 0
        assert (
            fields[1].expect(WireType.FIXED64).as_scalar(Scalar.sfixed64)
            == 9223372036854775807
        )
        assert (
            fields[2].expect(WireType.FIXED64).as_scalar(Scalar.sfixed64)
            == -9223372036854775808
        )

    def test_double(self):
        writer, stream = make_writer()
        write_scalar_field(writer, 1, Scalar.double, 1.5)
        write_scalar_field(writer, 2, Scalar.double, 3.14159265358979)
        data = finish(writer, stream)

        fields = list(Reader(io.BytesIO(data)))
        assert fields[0].expect(WireType.FIXED64).as_scalar(Scalar.double) == 1.5
        assert (
            abs(
                fields[1].expect(WireType.FIXED64).as_scalar(Scalar.double)
                - 3.14159265358979
            )
            < 1e-10
        )


class TestWriterFixed32Types:
    """Tests for writing 32-bit fixed types."""

    def test_fixed32(self):
        writer, stream = make_writer()
        write_scalar_field(writer, 1, Scalar.fixed32, 0)
        write_scalar_field(writer, 2, Scalar.fixed32, 0xDEADBEEF)
        write_scalar_field(writer, 3, Scalar.fixed32, 0xFFFFFFFF)
        data = finish(writer, stream)

        fields = list(Reader(io.BytesIO(data)))
        assert fields[0].expect(WireType.FIXED32).as_scalar(Scalar.fixed32) == 0
        assert (
            fields[1].expect(WireType.FIXED32).as_scalar(Scalar.fixed32) == 0xDEADBEEF
        )
        assert (
            fields[2].expect(WireType.FIXED32).as_scalar(Scalar.fixed32) == 0xFFFFFFFF
        )

    def test_sfixed32(self):
        writer, stream = make_writer()
        write_scalar_field(writer, 1, Scalar.sfixed32, 0)
        write_scalar_field(writer, 2, Scalar.sfixed32, 2147483647)
        write_scalar_field(writer, 3, Scalar.sfixed32, -2147483648)
        data = finish(writer, stream)

        fields = list(Reader(io.BytesIO(data)))
        assert fields[0].expect(WireType.FIXED32).as_scalar(Scalar.sfixed32) == 0
        assert (
            fields[1].expect(WireType.FIXED32).as_scalar(Scalar.sfixed32) == 2147483647
        )
        assert (
            fields[2].expect(WireType.FIXED32).as_scalar(Scalar.sfixed32) == -2147483648
        )

    def test_float(self):
        writer, stream = make_writer()
        write_scalar_field(writer, 1, Scalar.float, 1.5)
        write_scalar_field(writer, 2, Scalar.float, 3.14)
        data = finish(writer, stream)

        fields = list(Reader(io.BytesIO(data)))
        assert (
            abs(fields[0].expect(WireType.FIXED32).as_scalar(Scalar.float) - 1.5) < 1e-6
        )
        assert (
            abs(fields[1].expect(WireType.FIXED32).as_scalar(Scalar.float) - 3.14)
            < 1e-5
        )


class TestWriterLengthDelimited:
    """Tests for writing length-delimited types."""

    def test_string(self):
        writer, stream = make_writer()
        write_len_field(writer, 1, b"hello")
        data = finish(writer, stream)

        field = next(Reader(io.BytesIO(data)))
        assert field.string() == "hello"

    def test_bytes(self):
        writer, stream = make_writer()
        write_len_field(writer, 1, b"\x00\x01\x02")
        data = finish(writer, stream)

        field = next(Reader(io.BytesIO(data)))
        assert field.bytes() == b"\x00\x01\x02"

    def test_nested_message(self):
        nested_writer, nested_stream = make_writer()
        write_len_field(nested_writer, 1, b"nested")
        nested_data = finish(nested_writer, nested_stream)

        writer, stream = make_writer()
        write_len_field(writer, 1, nested_data)
        data = finish(writer, stream)

        field = next(Reader(io.BytesIO(data)))
        nested_value = None
        for nested_field in field.message():
            if nested_field.number == 1:
                nested_value = nested_field.string()
        assert nested_value == "nested"


class TestWriterPackedRepeated:
    """Tests for writing packed repeated fields."""

    def test_packed_int32s(self):
        writer, stream = make_writer()
        write_packed_field(writer, 1, Scalar.i32, [1, 2, 3])
        data = finish(writer, stream)

        field = next(Reader(io.BytesIO(data)))
        assert field.repeated(Scalar.i32) == [1, 2, 3]

    def test_packed_doubles(self):
        writer, stream = make_writer()
        write_packed_field(writer, 1, Scalar.double, [1.0, 2.5, 3.14159])
        data = finish(writer, stream)

        field = next(Reader(io.BytesIO(data)))
        result = field.repeated(Scalar.double)
        assert len(result) == 3
        assert result[0] == 1.0
        assert result[1] == 2.5
        assert abs(result[2] - 3.14159) < 1e-10


class TestWriterStreams:
    """Tests for writing to binary IO streams."""

    def test_bytesio(self):
        stream = io.BytesIO()
        writer = Writer(stream)
        write_scalar_field(writer, 1, Scalar.i32, 42)
        writer.flush()

        field = next(Reader(io.BytesIO(stream.getvalue())))
        assert field.expect(WireType.VARINT).as_scalar(Scalar.i32) == 42

    def test_file_stream(self):
        with tempfile.TemporaryFile() as file:
            writer = Writer(file)
            write_scalar_field(writer, 1, Scalar.i32, 42)
            writer.flush()
            file.seek(0)
            fields = list(Reader(file))

        assert fields[0].expect(WireType.VARINT).as_scalar(Scalar.i32) == 42

    def test_socket_stream(self):
        sock_a, sock_b = socket.socketpair()
        with sock_a, sock_b:
            with sock_a.makefile("wb") as out_stream:
                writer = Writer(out_stream)
                write_scalar_field(writer, 1, Scalar.i32, 42)
                writer.flush()

            sock_a.shutdown(socket.SHUT_WR)
            with sock_b.makefile("rb") as in_stream:
                fields = list(Reader(in_stream))

        assert fields[0].expect(WireType.VARINT).as_scalar(Scalar.i32) == 42
