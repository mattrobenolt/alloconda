"""Tests for Object operations, callables, and attributes."""

import pytest

import allotest


class TestObjCall:
    """Test calling Python objects from Zig."""

    def test_call0(self) -> None:
        def func() -> int:
            return 42

        assert allotest.obj_call0(func) == 42

    def test_call0_lambda(self) -> None:
        result = allotest.obj_call0(lambda: "hello")
        assert result == "hello"

    def test_call0_builtin(self) -> None:
        result = allotest.obj_call0(list)
        assert result == []

    def test_call1(self) -> None:
        def func(x: int) -> int:
            return x * 2

        assert allotest.obj_call1(func, 21) == 42

    def test_call1_lambda(self) -> None:
        result = allotest.obj_call1(lambda x: x.upper(), "hello")
        assert result == "HELLO"

    def test_call1_builtin(self) -> None:
        result = allotest.obj_call1(str, 123)
        assert result == "123"

    def test_call2(self) -> None:
        def func(a: int, b: int) -> int:
            return a + b

        assert allotest.obj_call2(func, 10, 32) == 42

    def test_call2_lambda(self) -> None:
        result = allotest.obj_call2(lambda a, b: a * b, 6, 7)
        assert result == 42

    def test_call2_builtin(self) -> None:
        result = allotest.obj_call2(pow, 2, 10)
        assert result == 1024

    def test_call_not_callable(self) -> None:
        with pytest.raises(TypeError):
            allotest.obj_call0(42)

    def test_call_wrong_arg_count(self) -> None:
        with pytest.raises(TypeError):
            allotest.obj_call1(lambda: 1, "unused")


class TestObjAttributes:
    """Test getting and setting attributes on objects."""

    def test_getattr(self) -> None:
        class Obj:
            value = 42

        assert allotest.obj_getattr(Obj(), "value") == 42

    def test_getattr_method(self) -> None:
        result = allotest.obj_getattr("hello", "upper")
        assert callable(result)

    def test_getattr_missing(self) -> None:
        class Obj:
            pass

        with pytest.raises(AttributeError):
            allotest.obj_getattr(Obj(), "nonexistent")

    def test_setattr(self) -> None:
        class Obj:
            pass

        obj = Obj()
        result = allotest.obj_setattr(obj, "value", 42)
        assert result is True
        assert obj.value == 42  # type: ignore[attr-defined]

    def test_setattr_overwrite(self) -> None:
        class Obj:
            value = 1

        obj = Obj()
        allotest.obj_setattr(obj, "value", 999)
        assert obj.value == 999

    def test_setattr_multiple(self) -> None:
        class Obj:
            pass

        obj = Obj()
        allotest.obj_setattr(obj, "a", 1)
        allotest.obj_setattr(obj, "b", "two")
        allotest.obj_setattr(obj, "c", [3])
        assert obj.a == 1  # type: ignore[attr-defined]
        assert obj.b == "two"  # type: ignore[attr-defined]
        assert obj.c == [3]  # type: ignore[attr-defined]


class TestObjMethods:
    """Test calling methods on objects."""

    def test_callmethod0(self) -> None:
        result = allotest.obj_callmethod0("hello", "upper")
        assert result == "HELLO"

    def test_callmethod0_list(self) -> None:
        lst = [3, 1, 2]
        lst_copy = lst.copy()
        allotest.obj_callmethod0(lst, "sort")
        assert lst == [1, 2, 3]
        assert lst_copy == [3, 1, 2]  # copy unchanged

    def test_callmethod0_returns_none(self) -> None:
        lst = [1, 2, 3]
        result = allotest.obj_callmethod0(lst, "clear")
        assert result is None
        assert lst == []

    def test_callmethod1(self) -> None:
        result = allotest.obj_callmethod1("hello world", "split", " ")
        assert result == ["hello", "world"]

    def test_callmethod1_list_append(self) -> None:
        lst = [1, 2]
        allotest.obj_callmethod1(lst, "append", 3)
        assert lst == [1, 2, 3]

    def test_callmethod1_str_count(self) -> None:
        result = allotest.obj_callmethod1("hello", "count", "l")
        assert result == 2

    def test_callmethod_missing_method(self) -> None:
        with pytest.raises(AttributeError):
            allotest.obj_callmethod0("hello", "nonexistent")

    def test_callmethod_wrong_args(self) -> None:
        with pytest.raises(TypeError):
            allotest.obj_callmethod1("hello", "upper", "unused")


class TestIsCallable:
    """Test callable detection."""

    def test_function_is_callable(self) -> None:
        def func() -> None:
            pass

        assert allotest.obj_is_callable(func) is True

    def test_lambda_is_callable(self) -> None:
        assert allotest.obj_is_callable(lambda: None) is True

    def test_class_is_callable(self) -> None:
        class Cls:
            pass

        assert allotest.obj_is_callable(Cls) is True

    def test_builtin_is_callable(self) -> None:
        assert allotest.obj_is_callable(len) is True
        assert allotest.obj_is_callable(print) is True
        assert allotest.obj_is_callable(str) is True

    def test_method_is_callable(self) -> None:
        assert allotest.obj_is_callable("hello".upper) is True

    def test_int_not_callable(self) -> None:
        assert allotest.obj_is_callable(42) is False

    def test_string_not_callable(self) -> None:
        assert allotest.obj_is_callable("hello") is False

    def test_list_not_callable(self) -> None:
        assert allotest.obj_is_callable([1, 2, 3]) is False

    def test_none_not_callable(self) -> None:
        assert allotest.obj_is_callable(None) is False

    def test_callable_instance(self) -> None:
        class Callable:
            def __call__(self) -> int:
                return 42

        assert allotest.obj_is_callable(Callable()) is True


class TestIsNone:
    """Test None detection."""

    def test_none_is_none(self) -> None:
        assert allotest.obj_is_none(None) is True

    def test_int_is_not_none(self) -> None:
        assert allotest.obj_is_none(0) is False
        assert allotest.obj_is_none(42) is False

    def test_string_is_not_none(self) -> None:
        assert allotest.obj_is_none("") is False
        assert allotest.obj_is_none("None") is False

    def test_false_is_not_none(self) -> None:
        assert allotest.obj_is_none(False) is False

    def test_empty_collections_not_none(self) -> None:
        assert allotest.obj_is_none([]) is False
        assert allotest.obj_is_none({}) is False
        assert allotest.obj_is_none(()) is False


class TestTypeChecks:
    """Test type checking functions."""

    def test_is_unicode(self) -> None:
        assert allotest.is_unicode("hello") is True
        assert allotest.is_unicode("") is True
        assert allotest.is_unicode("\u00e9") is True
        assert allotest.is_unicode(b"hello") is False
        assert allotest.is_unicode(42) is False

    def test_is_bytes(self) -> None:
        assert allotest.is_bytes(b"hello") is True
        assert allotest.is_bytes(b"") is True
        assert allotest.is_bytes("hello") is False
        assert allotest.is_bytes(42) is False

    def test_is_bool(self) -> None:
        assert allotest.is_bool(True) is True
        assert allotest.is_bool(False) is True
        # Note: In Python, bool is a subclass of int, so behavior may vary
        assert allotest.is_bool(1) is False
        assert allotest.is_bool(0) is False
        assert allotest.is_bool("True") is False

    def test_is_int(self) -> None:
        assert allotest.is_int(42) is True
        assert allotest.is_int(0) is True
        assert allotest.is_int(-999) is True
        assert allotest.is_int(3.14) is False
        assert allotest.is_int("42") is False
        # Note: bool is a subclass of int in Python
        assert allotest.is_int(True) is True

    def test_is_float(self) -> None:
        assert allotest.is_float(3.14) is True
        assert allotest.is_float(0.0) is True
        assert allotest.is_float(-1.5) is True
        assert allotest.is_float(42) is False
        assert allotest.is_float("3.14") is False

    def test_is_list(self) -> None:
        assert allotest.is_list([]) is True
        assert allotest.is_list([1, 2, 3]) is True
        assert allotest.is_list(()) is False
        assert allotest.is_list("hello") is False

    def test_is_tuple(self) -> None:
        assert allotest.is_tuple(()) is True
        assert allotest.is_tuple((1, 2, 3)) is True
        assert allotest.is_tuple([]) is False
        assert allotest.is_tuple("hello") is False

    def test_is_dict(self) -> None:
        assert allotest.is_dict({}) is True
        assert allotest.is_dict({"a": 1}) is True
        assert allotest.is_dict([]) is False
        assert allotest.is_dict("hello") is False
