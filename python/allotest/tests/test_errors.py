"""Tests for all exception types and error mapping."""

import pytest

import allotest


class TestExceptionTypes:
    """Test that each exception type can be raised correctly."""

    def test_type_error(self) -> None:
        with pytest.raises(TypeError, match="test type error"):
            allotest.raise_type_error()

    def test_value_error(self) -> None:
        with pytest.raises(ValueError, match="test value error"):
            allotest.raise_value_error()

    def test_runtime_error(self) -> None:
        with pytest.raises(RuntimeError, match="test runtime error"):
            allotest.raise_runtime_error()

    def test_zero_division_error(self) -> None:
        with pytest.raises(ZeroDivisionError, match="test zero division"):
            allotest.raise_zero_division()

    def test_overflow_error(self) -> None:
        with pytest.raises(OverflowError, match="test overflow error"):
            allotest.raise_overflow_error()

    def test_attribute_error(self) -> None:
        with pytest.raises(AttributeError, match="test attribute error"):
            allotest.raise_attribute_error()

    def test_index_error(self) -> None:
        with pytest.raises(IndexError, match="test index error"):
            allotest.raise_index_error()

    def test_key_error(self) -> None:
        with pytest.raises(KeyError, match="test key error"):
            allotest.raise_key_error()

    def test_memory_error(self) -> None:
        with pytest.raises(MemoryError, match="test memory error"):
            allotest.raise_memory_error()


class TestDivide:
    """Test division with error handling."""

    def test_divide_normal(self) -> None:
        assert allotest.divide(10.0, 2.0) == pytest.approx(5.0)
        assert allotest.divide(1.0, 4.0) == pytest.approx(0.25)
        assert allotest.divide(-10.0, 2.0) == pytest.approx(-5.0)

    def test_divide_by_zero(self) -> None:
        with pytest.raises(ZeroDivisionError, match="division by zero"):
            allotest.divide(1.0, 0.0)

    def test_divide_zero_by_nonzero(self) -> None:
        assert allotest.divide(0.0, 5.0) == 0.0

    def test_divide_small_numbers(self) -> None:
        result = allotest.divide(1e-10, 1e-5)
        assert result == pytest.approx(1e-5)

    def test_divide_large_numbers(self) -> None:
        result = allotest.divide(1e100, 1e50)
        assert result == pytest.approx(1e50)


class TestErrorMapping:
    """Test error mapping from Zig errors to Python exceptions."""

    def test_mapped_not_found(self) -> None:
        with pytest.raises(KeyError, match="item not found"):
            allotest.raise_mapped("not_found")

    def test_mapped_invalid(self) -> None:
        with pytest.raises(ValueError, match="invalid input"):
            allotest.raise_mapped("invalid")

    def test_mapped_unknown_kind(self) -> None:
        with pytest.raises(ValueError, match="unknown error kind"):
            allotest.raise_mapped("something_else")


class TestExceptionInheritance:
    """Test that exceptions have correct inheritance."""

    def test_type_error_is_exception(self) -> None:
        with pytest.raises(Exception):
            allotest.raise_type_error()

    def test_value_error_is_exception(self) -> None:
        with pytest.raises(Exception):
            allotest.raise_value_error()

    def test_zero_division_is_arithmetic_error(self) -> None:
        with pytest.raises(ArithmeticError):
            allotest.raise_zero_division()

    def test_overflow_is_arithmetic_error(self) -> None:
        with pytest.raises(ArithmeticError):
            allotest.raise_overflow_error()

    def test_index_error_is_lookup_error(self) -> None:
        with pytest.raises(LookupError):
            allotest.raise_index_error()

    def test_key_error_is_lookup_error(self) -> None:
        with pytest.raises(LookupError):
            allotest.raise_key_error()


class TestExceptionContext:
    """Test exceptions in various contexts."""

    def test_exception_in_list_comprehension(self) -> None:
        with pytest.raises(ZeroDivisionError):
            [allotest.divide(x, 0.0) for x in [1.0, 2.0, 3.0]]

    def test_exception_does_not_corrupt_state(self) -> None:
        # Ensure exceptions don't leave things in a bad state
        try:
            allotest.raise_value_error()
        except ValueError:
            pass

        # Should still work normally after exception
        assert allotest.add(1, 2) == 3

    def test_multiple_exceptions_in_sequence(self) -> None:
        # Raise and catch multiple different exceptions
        for _ in range(3):
            with pytest.raises(TypeError):
                allotest.raise_type_error()
            with pytest.raises(ValueError):
                allotest.raise_value_error()
            with pytest.raises(RuntimeError):
                allotest.raise_runtime_error()

    def test_exception_preserves_message(self) -> None:
        try:
            allotest.raise_value_error()
        except ValueError as e:
            assert "test value error" in str(e)
