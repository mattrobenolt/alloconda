"""Tests for Object.isDataclass() method."""

from dataclasses import dataclass

import allotest


@dataclass
class Point:
    x: int
    y: int


class RegularClass:
    def __init__(self, value: int) -> None:
        self.value = value


class TestIsDataclass:
    """Test Object.isDataclass() checks."""

    def test_dataclass_type_is_dataclass(self) -> None:
        assert allotest.is_dataclass(Point) is True

    def test_dataclass_instance_is_dataclass(self) -> None:
        point = Point(1, 2)
        assert allotest.is_dataclass(point) is True

    def test_regular_class_not_dataclass(self) -> None:
        assert allotest.is_dataclass(RegularClass) is False

    def test_regular_class_instance_not_dataclass(self) -> None:
        obj = RegularClass(42)
        assert allotest.is_dataclass(obj) is False

    def test_int_not_dataclass(self) -> None:
        assert allotest.is_dataclass(42) is False

    def test_str_not_dataclass(self) -> None:
        assert allotest.is_dataclass("hello") is False

    def test_list_not_dataclass(self) -> None:
        assert allotest.is_dataclass([1, 2, 3]) is False

    def test_dict_not_dataclass(self) -> None:
        assert allotest.is_dataclass({"a": 1}) is False

    def test_none_not_dataclass(self) -> None:
        assert allotest.is_dataclass(None) is False

    def test_builtin_type_not_dataclass(self) -> None:
        assert allotest.is_dataclass(int) is False
        assert allotest.is_dataclass(str) is False
        assert allotest.is_dataclass(list) is False
