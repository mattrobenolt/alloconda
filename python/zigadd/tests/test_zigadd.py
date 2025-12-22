import pytest

import zigadd


def test_add() -> None:
    assert zigadd.add(1, 2) == 3


def test_add3_optional() -> None:
    assert zigadd.add3(1, 2) == 3
    assert zigadd.add3(1, 2, 3) == 6


def test_add_named_keywords() -> None:
    assert zigadd.add_named(1, 2) == 3
    assert zigadd.add_named(1, b=2) == 3
    assert zigadd.add_named(a=1, b=2, c=3) == 6
    with pytest.raises(TypeError):
        zigadd.add_named(a=1, b=2, d=4)  # type: ignore[unknown-argument]


def test_adder_class() -> None:
    adder = zigadd.Adder()
    assert adder.add(2, 5) == 7
    assert adder.identity() is adder


def test_bytes_len() -> None:
    assert zigadd.bytes_len(b"zig") == 3


def test_divide() -> None:
    assert zigadd.divide(10.0, 2.0) == 5.0
    with pytest.raises(ZeroDivisionError, match="division by zero"):
        zigadd.divide(1.0, 0.0)


def test_call_twice() -> None:
    assert zigadd.call_twice(lambda x: x + 1, 3) == 8

    with pytest.raises(TypeError, match="callable"):
        zigadd.call_twice(123, 1)  # type: ignore[invalid-argument-type]


def test_greet() -> None:
    assert zigadd.greet("Zig") == "Zig"
    assert zigadd.greet("") == "Hello"


def test_is_even() -> None:
    assert zigadd.is_even(2) is True
    assert zigadd.is_even(3) is False


def test_maybe_tag() -> None:
    assert zigadd.maybe_tag("alloconda") == "alloconda"
    assert zigadd.maybe_tag("") is None


def test_sum_list() -> None:
    assert zigadd.sum_list([1, 2, 3]) == 6


def test_dict_get() -> None:
    assert zigadd.dict_get({"a": 1}, "a") == 1
    assert zigadd.dict_get({"a": 1}, "b") is None


def test_math_pi() -> None:
    assert zigadd.math_pi() == pytest.approx(3.141592653589793)


def test_to_bytes() -> None:
    assert zigadd.to_bytes("zig") == b"zig"


def test_to_upper() -> None:
    assert zigadd.to_upper("zig") == "ZIG"
