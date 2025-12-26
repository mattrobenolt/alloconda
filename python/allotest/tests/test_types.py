"""Tests for List, Dict, Tuple, Bytes, and Buffer operations."""

import pytest

import allotest


class TestBytes:
    """Test bytes operations."""

    def test_bytes_len(self) -> None:
        assert allotest.bytes_len(b"hello") == 5
        assert allotest.bytes_len(b"") == 0
        assert allotest.bytes_len(b"\x00\x01\x02") == 3

    def test_bytes_slice(self) -> None:
        data = b"hello world"
        assert allotest.bytes_slice(data, 0, 5) == b"hello"
        assert allotest.bytes_slice(data, 6, 11) == b"world"
        assert allotest.bytes_slice(data, 0, 0) == b""
        assert allotest.bytes_slice(data, 3, 3) == b""

    def test_bytes_slice_out_of_bounds(self) -> None:
        data = b"hello"
        with pytest.raises(IndexError, match="slice out of bounds"):
            allotest.bytes_slice(data, 0, 100)
        with pytest.raises(IndexError, match="slice out of bounds"):
            allotest.bytes_slice(data, 10, 20)

    def test_bytes_slice_invalid_range(self) -> None:
        data = b"hello"
        with pytest.raises(IndexError, match="slice out of bounds"):
            allotest.bytes_slice(data, 3, 1)  # start > end

    def test_bytes_create(self) -> None:
        assert allotest.bytes_create("hello") == b"hello"
        assert allotest.bytes_create("") == b""
        assert allotest.bytes_create("unicode: \u00e9") == b"unicode: \xc3\xa9"


class TestBuffer:
    """Test buffer protocol operations."""

    def test_buffer_len(self) -> None:
        assert allotest.buffer_len(b"hello") == 5
        assert allotest.buffer_len(bytearray(b"hello")) == 5
        assert allotest.buffer_len(memoryview(b"hello")) == 5
        assert allotest.buffer_len(memoryview(b"hello")[1:4]) == 3

    def test_buffer_sum(self) -> None:
        assert allotest.buffer_sum(b"\x01\x02\x03") == 6
        assert allotest.buffer_sum(bytearray(b"\x01\x02\x03")) == 6
        assert allotest.buffer_sum(memoryview(b"\x01\x02\x03")) == 6

    def test_buffer_type_error(self) -> None:
        with pytest.raises(TypeError):
            allotest.buffer_len("not-bytes")  # type: ignore[arg-type]


class TestIntConversion:
    """Test integer conversion helpers."""

    def test_int64_or_uint64_signed(self) -> None:
        kind, value = allotest.int64_or_uint64(42)
        assert kind is True
        assert value == 42
        kind, value = allotest.int64_or_uint64(-1)
        assert kind is True
        assert value == -1

    def test_int64_or_uint64_unsigned(self) -> None:
        value = 2**63
        kind, out = allotest.int64_or_uint64(value)
        assert kind is False
        assert out == value

    def test_int64_or_uint64_overflow(self) -> None:
        with pytest.raises(OverflowError):
            allotest.int64_or_uint64(2**64)
        with pytest.raises(OverflowError):
            allotest.int64_or_uint64(-(2**63) - 1)

    def test_int64_or_uint64_type_error(self) -> None:
        with pytest.raises(TypeError):
            allotest.int64_or_uint64("not-int")  # type: ignore[arg-type]

    def test_mask_u32(self) -> None:
        assert allotest.mask_u32(0xFFFFFFFF) == 0xFFFFFFFF
        assert allotest.mask_u32(0x1_0000_0000) == 0
        assert allotest.mask_u32(-1) == 0xFFFFFFFF

    def test_mask_u64(self) -> None:
        assert allotest.mask_u64(0xFFFFFFFFFFFFFFFF) == 0xFFFFFFFFFFFFFFFF
        assert allotest.mask_u64(0x1_0000_0000_0000_0000) == 0
        assert allotest.mask_u64(-1) == 0xFFFFFFFFFFFFFFFF

    def test_bigint_to_string(self) -> None:
        value = 2**200
        assert allotest.bigint_to_string(value) == str(value)
        negative = -(2**200) + 123
        assert allotest.bigint_to_string(negative) == str(negative)

    def test_bigint_roundtrip(self) -> None:
        value = 2**200
        assert allotest.bigint_roundtrip(value) == value
        negative = -(2**200) + 123
        assert allotest.bigint_roundtrip(negative) == negative

    def test_int_roundtrip(self) -> None:
        assert allotest.int_roundtrip(123) == 123
        assert allotest.int_roundtrip(-456) == -456
        value = 2**200
        assert allotest.int_roundtrip(value) == value
        negative = -(2**200) + 123
        assert allotest.int_roundtrip(negative) == negative


class TestList:
    """Test list operations."""

    def test_list_len(self) -> None:
        assert allotest.list_len([1, 2, 3]) == 3
        assert allotest.list_len([]) == 0
        assert allotest.list_len(["a", "b"]) == 2

    def test_list_get(self) -> None:
        lst = [10, 20, 30]
        assert allotest.list_get(lst, 0) == 10
        assert allotest.list_get(lst, 1) == 20
        assert allotest.list_get(lst, 2) == 30

    def test_list_get_mixed_types(self) -> None:
        lst = ["hello", 42, None]
        assert allotest.list_get(lst, 0) == "hello"
        assert allotest.list_get(lst, 1) == 42
        assert allotest.list_get(lst, 2) is None

    def test_list_sum(self) -> None:
        assert allotest.list_sum([1, 2, 3]) == 6
        assert allotest.list_sum([]) == 0
        assert allotest.list_sum([-1, 0, 1]) == 0
        assert allotest.list_sum([100]) == 100

    def test_list_create(self) -> None:
        result = allotest.list_create(1, 2, 3)
        assert result == [1, 2, 3]
        assert isinstance(result, list)

    def test_list_append(self) -> None:
        lst = [1, 2]
        result = allotest.list_append(lst, 3)
        assert result == [1, 2, 3]
        # Should modify in place and return same list
        assert result is lst

    def test_list_append_to_empty(self) -> None:
        lst: list[int] = []
        result = allotest.list_append(lst, 42)
        assert result == [42]
        assert result is lst

    def test_list_set(self) -> None:
        lst = [1, 2, 3]
        result = allotest.list_set(lst, 1, 99)
        assert result == [1, 99, 3]
        assert result is lst

    def test_list_set_first_last(self) -> None:
        lst = [10, 20, 30]
        allotest.list_set(lst, 0, 100)
        assert lst[0] == 100
        allotest.list_set(lst, 2, 300)
        assert lst[2] == 300


class TestDict:
    """Test dict operations."""

    def test_dict_len(self) -> None:
        assert allotest.dict_len({"a": 1, "b": 2}) == 2
        assert allotest.dict_len({}) == 0
        assert allotest.dict_len({"x": 1}) == 1

    def test_dict_get(self) -> None:
        d = {"a": 1, "b": 2}
        assert allotest.dict_get(d, "a") == 1
        assert allotest.dict_get(d, "b") == 2

    def test_dict_get_missing(self) -> None:
        d = {"a": 1}
        assert allotest.dict_get(d, "missing") is None

    def test_dict_get_empty(self) -> None:
        d: dict[str, int] = {}
        assert allotest.dict_get(d, "anything") is None

    def test_dict_create(self) -> None:
        result = allotest.dict_create("key", 42)
        assert result == {"key": 42}
        assert isinstance(result, dict)

    def test_dict_create_various_keys(self) -> None:
        assert allotest.dict_create("", 0) == {"": 0}
        assert allotest.dict_create("long_key_name", 999) == {"long_key_name": 999}

    def test_dict_set(self) -> None:
        d = {"a": 1}
        result = allotest.dict_set(d, "b", 2)
        assert result == {"a": 1, "b": 2}
        assert result is d

    def test_dict_set_overwrite(self) -> None:
        d = {"a": 1}
        allotest.dict_set(d, "a", 99)
        assert d["a"] == 99

    def test_dict_keys(self) -> None:
        d = {"a": 1, "b": 2, "c": 3}
        keys = allotest.dict_keys(d)
        assert isinstance(keys, list)
        assert set(keys) == {"a", "b", "c"}

    def test_dict_keys_empty(self) -> None:
        d: dict[str, int] = {}
        keys = allotest.dict_keys(d)
        assert keys == []

    def test_dict_keys_single(self) -> None:
        d = {"only": 1}
        keys = allotest.dict_keys(d)
        assert keys == ["only"]


class TestTuple:
    """Test tuple operations."""

    def test_tuple_len(self) -> None:
        assert allotest.tuple_len((1, 2, 3)) == 3
        assert allotest.tuple_len(()) == 0
        assert allotest.tuple_len((42,)) == 1

    def test_tuple_get(self) -> None:
        t = (10, 20, 30)
        assert allotest.tuple_get(t, 0) == 10
        assert allotest.tuple_get(t, 1) == 20
        assert allotest.tuple_get(t, 2) == 30

    def test_tuple_get_mixed_types(self) -> None:
        t = ("hello", 42, None)
        assert allotest.tuple_get(t, 0) == "hello"
        assert allotest.tuple_get(t, 1) == 42
        assert allotest.tuple_get(t, 2) is None

    def test_tuple_create(self) -> None:
        result = allotest.tuple_create(1, 2)
        assert result == (1, 2)
        assert isinstance(result, tuple)

    def test_tuple_create_values(self) -> None:
        assert allotest.tuple_create(0, 0) == (0, 0)
        assert allotest.tuple_create(-1, 100) == (-1, 100)

    def test_tuple_create_manual(self) -> None:
        result = allotest.tuple_create_manual(5, -1)
        assert result == (5, -1)
        assert isinstance(result, tuple)
