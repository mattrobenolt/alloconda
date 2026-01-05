"""Benchmarks for fastproto encoding and decoding."""

import io

import pytest

from fastproto import Scalar, WireType

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


def _write_scalar_field(
    writer, field_number: int, scalar: Scalar, value: object
) -> None:
    writer.write_tag(field_number, _SCALAR_WIRE[scalar])
    writer.write_scalar(scalar, value)


def _write_len_field(writer, field_number: int, data: bytes) -> None:
    writer.write_tag(field_number, WireType.LEN)
    writer.write_len(data)


def _finish(writer, stream: io.BytesIO) -> bytes:
    writer.flush()
    return stream.getvalue()


# === Test Data ===


def make_simple_message(backend) -> bytes:
    """Create a simple message with a few scalar fields."""
    stream = io.BytesIO()
    w = backend.Writer(stream)
    _write_len_field(w, 1, b"hello world")
    _write_scalar_field(w, 2, Scalar.i64, 1234567890)
    _write_scalar_field(w, 3, Scalar.bool, True)
    _write_scalar_field(w, 4, Scalar.double, 3.14159265358979)
    return _finish(w, stream)


def make_nested_message(backend) -> bytes:
    """Create a message with nested messages."""
    stream = io.BytesIO()
    w = backend.Writer(stream)
    _write_len_field(w, 1, b"parent")
    for i in range(10):
        nested_stream = io.BytesIO()
        nested = backend.Writer(nested_stream)
        _write_len_field(nested, 1, f"child_{i}".encode("utf-8"))
        _write_scalar_field(nested, 2, Scalar.i64, i * 1000)
        _write_scalar_field(nested, 3, Scalar.double, i * 1.5)
        nested_data = _finish(nested, nested_stream)
        _write_len_field(w, 2, nested_data)
    return _finish(w, stream)


def make_packed_message(backend) -> bytes:
    """Create a message with packed repeated fields."""
    stream = io.BytesIO()
    w = backend.Writer(stream)

    packed_stream = io.BytesIO()
    packed_writer = backend.Writer(packed_stream)
    for value in range(1000):
        packed_writer.write_scalar(Scalar.i64, value)
    packed_data = _finish(packed_writer, packed_stream)
    _write_len_field(w, 1, packed_data)

    packed_stream = io.BytesIO()
    packed_writer = backend.Writer(packed_stream)
    for value in range(1000):
        packed_writer.write_scalar(Scalar.double, float(value) * 0.1)
    packed_data = _finish(packed_writer, packed_stream)
    _write_len_field(w, 2, packed_data)

    return _finish(w, stream)


def make_large_string_message(backend) -> bytes:
    """Create a message with a large string."""
    stream = io.BytesIO()
    w = backend.Writer(stream)
    _write_len_field(w, 1, b"x" * 100_000)
    return _finish(w, stream)


def make_many_fields_message(backend) -> bytes:
    """Create a message with many fields."""
    stream = io.BytesIO()
    w = backend.Writer(stream)
    for i in range(1, 101):
        _write_scalar_field(w, i, Scalar.i32, i * 100)
    return _finish(w, stream)


# Pre-generate test data per backend
@pytest.fixture(scope="module")
def simple_data(backend):
    return make_simple_message(backend)


@pytest.fixture(scope="module")
def nested_data(backend):
    return make_nested_message(backend)


@pytest.fixture(scope="module")
def packed_data(backend):
    return make_packed_message(backend)


@pytest.fixture(scope="module")
def large_string_data(backend):
    return make_large_string_message(backend)


@pytest.fixture(scope="module")
def many_fields_data(backend):
    return make_many_fields_message(backend)


# === Encoding Benchmarks ===


def test_encode_simple(benchmark, backend):
    """Benchmark encoding a simple message."""

    def encode():
        stream = io.BytesIO()
        w = backend.Writer(stream)
        _write_len_field(w, 1, b"hello world")
        _write_scalar_field(w, 2, Scalar.i64, 1234567890)
        _write_scalar_field(w, 3, Scalar.bool, True)
        _write_scalar_field(w, 4, Scalar.double, 3.14159265358979)
        return _finish(w, stream)

    result = benchmark(encode)
    assert len(result) > 0


def test_encode_nested(benchmark, backend):
    """Benchmark encoding nested messages."""

    def encode():
        stream = io.BytesIO()
        w = backend.Writer(stream)
        _write_len_field(w, 1, b"parent")
        for i in range(10):
            nested_stream = io.BytesIO()
            nested = backend.Writer(nested_stream)
            _write_len_field(nested, 1, f"child_{i}".encode("utf-8"))
            _write_scalar_field(nested, 2, Scalar.i64, i * 1000)
            _write_scalar_field(nested, 3, Scalar.double, i * 1.5)
            nested_data = _finish(nested, nested_stream)
            _write_len_field(w, 2, nested_data)
        return _finish(w, stream)

    result = benchmark(encode)
    assert len(result) > 0


def test_encode_packed_int64s(benchmark, backend):
    """Benchmark encoding packed int64 array."""
    values = list(range(1000))

    def encode():
        stream = io.BytesIO()
        w = backend.Writer(stream)
        packed_stream = io.BytesIO()
        packed_writer = backend.Writer(packed_stream)
        for value in values:
            packed_writer.write_scalar(Scalar.i64, value)
        packed_data = _finish(packed_writer, packed_stream)
        _write_len_field(w, 1, packed_data)
        return _finish(w, stream)

    result = benchmark(encode)
    assert len(result) > 0


def test_encode_packed_doubles(benchmark, backend):
    """Benchmark encoding packed double array."""
    values = [float(i) * 0.1 for i in range(1000)]

    def encode():
        stream = io.BytesIO()
        w = backend.Writer(stream)
        packed_stream = io.BytesIO()
        packed_writer = backend.Writer(packed_stream)
        for value in values:
            packed_writer.write_scalar(Scalar.double, value)
        packed_data = _finish(packed_writer, packed_stream)
        _write_len_field(w, 1, packed_data)
        return _finish(w, stream)

    result = benchmark(encode)
    assert len(result) > 0


def test_encode_large_string(benchmark, backend):
    """Benchmark encoding a large string."""
    large_string = b"x" * 100_000

    def encode():
        stream = io.BytesIO()
        w = backend.Writer(stream)
        _write_len_field(w, 1, large_string)
        return _finish(w, stream)

    result = benchmark(encode)
    assert len(result) > 0


def test_encode_many_fields(benchmark, backend):
    """Benchmark encoding many fields."""

    def encode():
        stream = io.BytesIO()
        w = backend.Writer(stream)
        for i in range(1, 101):
            _write_scalar_field(w, i, Scalar.i32, i * 100)
        return _finish(w, stream)

    result = benchmark(encode)
    assert len(result) > 0


# === Decoding Benchmarks ===


def test_decode_simple(benchmark, backend, simple_data):
    """Benchmark decoding a simple message."""

    def decode():
        result = {}
        for field in backend.Reader(io.BytesIO(simple_data)):
            match field.number:
                case 1:
                    result["name"] = field.string()
                case 2:
                    result["value"] = field.expect(WireType.VARINT).as_scalar(
                        Scalar.i64
                    )
                case 3:
                    result["flag"] = field.expect(WireType.VARINT).as_scalar(
                        Scalar.bool
                    )
                case 4:
                    result["score"] = field.expect(WireType.FIXED64).as_scalar(
                        Scalar.double
                    )
        return result

    result = benchmark(decode)
    assert result["name"] == "hello world"


def test_decode_nested(benchmark, backend, nested_data):
    """Benchmark decoding nested messages."""

    def decode():
        children = []
        for field in backend.Reader(io.BytesIO(nested_data)):
            if field.number == 2:
                child = {}
                for nested in field.message():
                    match nested.number:
                        case 1:
                            child["name"] = nested.string()
                        case 2:
                            child["value"] = nested.expect(WireType.VARINT).as_scalar(
                                Scalar.i64
                            )
                        case 3:
                            child["score"] = nested.expect(WireType.FIXED64).as_scalar(
                                Scalar.double
                            )
                children.append(child)
            elif field.wire_type == WireType.LEN:
                field.skip()
        return children

    result = benchmark(decode)
    assert len(result) == 10


def test_decode_packed_int64s(benchmark, backend, packed_data):
    """Benchmark decoding packed int64 array."""

    def decode():
        for field in backend.Reader(io.BytesIO(packed_data)):
            if field.number == 1:
                return field.repeated(Scalar.i64)
            if field.wire_type == WireType.LEN:
                field.skip()
        return []

    result = benchmark(decode)
    assert len(result) == 1000


def test_decode_packed_doubles(benchmark, backend, packed_data):
    """Benchmark decoding packed double array."""

    def decode():
        for field in backend.Reader(io.BytesIO(packed_data)):
            if field.number == 2:
                return field.repeated(Scalar.double)
            if field.wire_type == WireType.LEN:
                field.skip()
        return []

    result = benchmark(decode)
    assert len(result) == 1000


def test_decode_large_string(benchmark, backend, large_string_data):
    """Benchmark decoding a large string."""

    def decode():
        for field in backend.Reader(io.BytesIO(large_string_data)):
            if field.number == 1:
                return field.string()
        return ""

    result = benchmark(decode)
    assert len(result) == 100_000


def test_decode_many_fields(benchmark, backend, many_fields_data):
    """Benchmark decoding many fields."""

    def decode():
        total = 0
        for field in backend.Reader(io.BytesIO(many_fields_data)):
            total += field.expect(WireType.VARINT).as_scalar(Scalar.i32)
        return total

    result = benchmark(decode)
    assert result > 0


def test_decode_skip_all(benchmark, backend, many_fields_data):
    """Benchmark scanning fields without parsing values."""

    def decode():
        count = 0
        for field in backend.Reader(io.BytesIO(many_fields_data)):
            count += 1
            if field.wire_type == WireType.LEN:
                field.skip()
        return count

    result = benchmark(decode)
    assert result == 100


def test_roundtrip_simple(benchmark, backend):
    """Benchmark roundtrip encoding and decoding."""

    def roundtrip():
        stream = io.BytesIO()
        w = backend.Writer(stream)
        _write_len_field(w, 1, b"hello world")
        _write_scalar_field(w, 2, Scalar.i64, 1234567890)
        _write_scalar_field(w, 3, Scalar.bool, True)
        _write_scalar_field(w, 4, Scalar.double, 3.14159265358979)
        data = _finish(w, stream)

        result = {}
        for field in backend.Reader(io.BytesIO(data)):
            match field.number:
                case 1:
                    result["name"] = field.string()
                case 2:
                    result["value"] = field.expect(WireType.VARINT).as_scalar(
                        Scalar.i64
                    )
                case 3:
                    result["flag"] = field.expect(WireType.VARINT).as_scalar(
                        Scalar.bool
                    )
                case 4:
                    result["score"] = field.expect(WireType.FIXED64).as_scalar(
                        Scalar.double
                    )
        return result

    result = benchmark(roundtrip)
    assert result["name"] == "hello world"
