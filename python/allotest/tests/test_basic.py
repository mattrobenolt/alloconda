"""Tests for basic function binding, arguments, and type conversions."""

import pytest

import allotest


class TestBasicBinding:
    """Test basic function binding."""

    def test_add(self) -> None:
        assert allotest.add(1, 2) == 3
        assert allotest.add(-1, 1) == 0
        assert allotest.add(0, 0) == 0

    def test_add_large_numbers(self) -> None:
        assert allotest.add(2**30, 2**30) == 2**31

    def test_add_negative(self) -> None:
        assert allotest.add(-100, -200) == -300


class TestOptionalArgs:
    """Test optional argument handling."""

    def test_add3_two_args(self) -> None:
        assert allotest.add3(1, 2) == 3

    def test_add3_three_args(self) -> None:
        assert allotest.add3(1, 2, 3) == 6

    def test_add3_explicit_none(self) -> None:
        assert allotest.add3(1, 2, None) == 3


class TestKeywordArgs:
    """Test keyword argument handling."""

    def test_add_named_positional(self) -> None:
        assert allotest.add_named(1, 2) == 3

    def test_add_named_keywords(self) -> None:
        assert allotest.add_named(a=1, b=2) == 3
        assert allotest.add_named(1, b=2) == 3

    def test_add_named_with_optional(self) -> None:
        assert allotest.add_named(a=1, b=2, c=3) == 6
        assert allotest.add_named(1, 2, c=10) == 13

    def test_add_named_unknown_kwarg(self) -> None:
        with pytest.raises(TypeError, match="unexpected keyword argument"):
            allotest.add_named(a=1, b=2, d=4)  # type: ignore[call-arg]

    def test_add_named_missing_required(self) -> None:
        with pytest.raises(TypeError, match="missing required argument"):
            allotest.add_named(a=1)  # type: ignore[call-arg]


class TestTypeConversions:
    """Test type conversions between Python and Zig."""

    def test_identity_int(self) -> None:
        assert allotest.identity_int(42) == 42
        assert allotest.identity_int(-999) == -999
        assert allotest.identity_int(0) == 0

    def test_identity_float(self) -> None:
        assert allotest.identity_float(3.14) == pytest.approx(3.14)
        assert allotest.identity_float(-0.5) == pytest.approx(-0.5)
        assert allotest.identity_float(0.0) == 0.0

    def test_identity_bool(self) -> None:
        assert allotest.identity_bool(True) is True
        assert allotest.identity_bool(False) is False

    def test_identity_str(self) -> None:
        assert allotest.identity_str("hello") == "hello"
        assert allotest.identity_str("") == ""
        assert (
            allotest.identity_str("unicode: \u00e9\u00e0\u00fc")
            == "unicode: \u00e9\u00e0\u00fc"
        )

    def test_identity_bytes(self) -> None:
        assert allotest.identity_bytes(b"hello") == b"hello"
        assert allotest.identity_bytes(b"") == b""
        assert allotest.identity_bytes(b"\x00\x01\x02") == b"\x00\x01\x02"

    def test_identity_optional_some(self) -> None:
        assert allotest.identity_optional("value") == "value"

    def test_identity_optional_none(self) -> None:
        assert allotest.identity_optional(None) is None

    def test_identity_object(self) -> None:
        obj = {"key": "value"}
        result = allotest.identity_object(obj)
        assert result is obj

        lst = [1, 2, 3]
        result = allotest.identity_object(lst)
        assert result is lst


class TestArgumentCounts:
    """Test argument count validation."""

    def test_too_few_args(self) -> None:
        with pytest.raises(TypeError, match="expected 2 arguments"):
            allotest.add(1)  # type: ignore[call-arg]

    def test_too_many_args(self) -> None:
        with pytest.raises(TypeError, match="expected 2 arguments"):
            allotest.add(1, 2, 3)  # type: ignore[call-arg]

    def test_optional_range(self) -> None:
        with pytest.raises(TypeError, match="expected 2 to 3 arguments"):
            allotest.add3(1)  # type: ignore[call-arg]
