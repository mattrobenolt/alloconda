"""Tests for IO adapters."""

import io

import pytest

import allotest


class TestIo:
    """Test binary IO adapters."""

    def test_io_read(self) -> None:
        stream = io.BytesIO(b"hello")
        assert allotest.io_read(stream, 4) == b"hell"
        assert allotest.io_read(stream, 4) == b"o"
        assert allotest.io_read(stream, 4) == b""

    def test_io_read_all(self) -> None:
        data = b"abc" * 1025
        stream = io.BytesIO(data)
        assert allotest.io_read(stream, -1) == data
        assert allotest.io_read(stream, -1) == b""

    def test_io_read_over_buffer(self) -> None:
        data = b"x" * 2048
        stream = io.BytesIO(data)
        assert allotest.io_read(stream, 1023) == data[:1023]
        assert allotest.io_read(stream, 1025) == data[1023:]
        assert allotest.io_read(stream, 1) == b""

    def test_write_all(self) -> None:
        stream = io.BytesIO()
        assert allotest.write_all(stream, b"hi") == 2
        assert stream.getvalue() == b"hi"

    def test_write_all_memoryview(self) -> None:
        stream = io.BytesIO()
        view = memoryview(b"data")
        assert allotest.write_all(stream, view) == 4
        assert stream.getvalue() == b"data"

    def test_io_read_type_error(self) -> None:
        with pytest.raises(AttributeError):
            allotest.io_read("not-io", 4)  # type: ignore[arg-type]

    def test_io_write_type_error(self) -> None:
        with pytest.raises(AttributeError):
            allotest.write_all("not-io", b"hi")  # type: ignore[arg-type]
