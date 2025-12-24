"""Benchmarks for fastproto encoding and decoding."""

import pytest

# === Test Data ===


def make_simple_message(backend) -> bytes:
    """Create a simple message with a few scalar fields."""
    w = backend.Writer()
    w.string(1, "hello world")
    w.int64(2, 1234567890)
    w.bool(3, True)
    w.double(4, 3.14159265358979)
    return w.finish()


def make_nested_message(backend) -> bytes:
    """Create a message with nested messages."""
    w = backend.Writer()
    w.string(1, "parent")
    for i in range(10):
        with w.message(2) as nested:
            nested.string(1, f"child_{i}")
            nested.int64(2, i * 1000)
            nested.double(3, i * 1.5)
    return w.finish()


def make_packed_message(backend) -> bytes:
    """Create a message with packed repeated fields."""
    w = backend.Writer()
    w.packed_int64s(1, list(range(1000)))
    w.packed_doubles(2, [float(i) * 0.1 for i in range(1000)])
    return w.finish()


def make_large_string_message(backend) -> bytes:
    """Create a message with a large string."""
    w = backend.Writer()
    w.string(1, "x" * 100_000)
    return w.finish()


def make_many_fields_message(backend) -> bytes:
    """Create a message with many fields."""
    w = backend.Writer()
    for i in range(1, 101):
        w.int32(i, i * 100)
    return w.finish()


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
        w = backend.Writer()
        w.string(1, "hello world")
        w.int64(2, 1234567890)
        w.bool(3, True)
        w.double(4, 3.14159265358979)
        return w.finish()

    result = benchmark(encode)
    assert len(result) > 0


def test_encode_nested(benchmark, backend):
    """Benchmark encoding nested messages."""

    def encode():
        w = backend.Writer()
        w.string(1, "parent")
        for i in range(10):
            with w.message(2) as nested:
                nested.string(1, f"child_{i}")
                nested.int64(2, i * 1000)
                nested.double(3, i * 1.5)
        return w.finish()

    result = benchmark(encode)
    assert len(result) > 0


def test_encode_packed_int64s(benchmark, backend):
    """Benchmark encoding packed int64 array."""
    values = list(range(1000))

    def encode():
        w = backend.Writer()
        w.packed_int64s(1, values)
        return w.finish()

    result = benchmark(encode)
    assert len(result) > 0


def test_encode_packed_doubles(benchmark, backend):
    """Benchmark encoding packed double array."""
    values = [float(i) * 0.1 for i in range(1000)]

    def encode():
        w = backend.Writer()
        w.packed_doubles(1, values)
        return w.finish()

    result = benchmark(encode)
    assert len(result) > 0


def test_encode_large_string(benchmark, backend):
    """Benchmark encoding a large string."""
    large_string = "x" * 100_000

    def encode():
        w = backend.Writer()
        w.string(1, large_string)
        return w.finish()

    result = benchmark(encode)
    assert len(result) > 0


def test_encode_many_fields(benchmark, backend):
    """Benchmark encoding many fields."""

    def encode():
        w = backend.Writer()
        for i in range(1, 101):
            w.int32(i, i * 100)
        return w.finish()

    result = benchmark(encode)
    assert len(result) > 0


# === Decoding Benchmarks ===


def test_decode_simple(benchmark, backend, simple_data):
    """Benchmark decoding a simple message."""

    def decode():
        result = {}
        for field in backend.Reader(simple_data):
            match field.number:
                case 1:
                    result["name"] = field.string()
                case 2:
                    result["value"] = field.int64()
                case 3:
                    result["flag"] = field.bool()
                case 4:
                    result["score"] = field.double()
        return result

    result = benchmark(decode)
    assert result["name"] == "hello world"


def test_decode_nested(benchmark, backend, nested_data):
    """Benchmark decoding nested messages."""

    def decode():
        children = []
        for field in backend.Reader(nested_data):
            if field.number == 2:
                child = {}
                for nested in field.message():
                    match nested.number:
                        case 1:
                            child["name"] = nested.string()
                        case 2:
                            child["value"] = nested.int64()
                        case 3:
                            child["score"] = nested.double()
                children.append(child)
        return children

    result = benchmark(decode)
    assert len(result) == 10


def test_decode_packed_int64s(benchmark, backend, packed_data):
    """Benchmark decoding packed int64 array."""

    def decode():
        for field in backend.Reader(packed_data):
            if field.number == 1:
                return field.packed_int64s()
        return []

    result = benchmark(decode)
    assert len(result) == 1000


def test_decode_packed_doubles(benchmark, backend, packed_data):
    """Benchmark decoding packed double array."""

    def decode():
        for field in backend.Reader(packed_data):
            if field.number == 2:
                return field.packed_doubles()
        return []

    result = benchmark(decode)
    assert len(result) == 1000


def test_decode_large_string(benchmark, backend, large_string_data):
    """Benchmark decoding a large string."""

    def decode():
        for field in backend.Reader(large_string_data):
            if field.number == 1:
                return field.string()
        return ""

    result = benchmark(decode)
    assert len(result) == 100_000


def test_decode_many_fields(benchmark, backend, many_fields_data):
    """Benchmark decoding many fields."""

    def decode():
        result = {}
        for field in backend.Reader(many_fields_data):
            result[field.number] = field.int32()
        return result

    result = benchmark(decode)
    assert len(result) == 100


def test_decode_skip_all(benchmark, backend, nested_data):
    """Benchmark skipping all fields without parsing values."""

    def decode():
        reader = backend.Reader(nested_data)
        count = 0
        while reader.skip():
            count += 1
        return count

    result = benchmark(decode)
    assert result == 11  # 1 string + 10 nested messages


# === Roundtrip Benchmarks ===


def test_roundtrip_simple(benchmark, backend):
    """Benchmark full encode/decode cycle for simple message."""

    def roundtrip():
        # Encode
        w = backend.Writer()
        w.string(1, "hello world")
        w.int64(2, 1234567890)
        w.bool(3, True)
        data = w.finish()

        # Decode
        result = {}
        for field in backend.Reader(data):
            match field.number:
                case 1:
                    result["name"] = field.string()
                case 2:
                    result["value"] = field.int64()
                case 3:
                    result["flag"] = field.bool()
        return result

    result = benchmark(roundtrip)
    assert result["name"] == "hello world"
