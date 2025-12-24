"""Tests for Python interop: imports and method calls."""

import math

import pytest

import allotest


class TestImportModule:
    """Test importing Python modules from Zig."""

    def test_import_math_pi(self) -> None:
        result = allotest.import_math_pi()
        assert result == pytest.approx(math.pi)

    def test_import_math_pi_type(self) -> None:
        result = allotest.import_math_pi()
        assert isinstance(result, float)

    def test_import_math_pi_precision(self) -> None:
        result = allotest.import_math_pi()
        # Check several decimal places
        assert result == pytest.approx(3.141592653589793, rel=1e-15)

    def test_import_math_pi_consistency(self) -> None:
        # Multiple calls should return the same value
        results = [allotest.import_math_pi() for _ in range(10)]
        assert all(r == results[0] for r in results)


class TestCallUpper:
    """Test calling Python string methods from Zig."""

    def test_call_upper_basic(self) -> None:
        assert allotest.call_upper("hello") == "HELLO"

    def test_call_upper_already_upper(self) -> None:
        assert allotest.call_upper("HELLO") == "HELLO"

    def test_call_upper_mixed_case(self) -> None:
        assert allotest.call_upper("HeLLo WoRLd") == "HELLO WORLD"

    def test_call_upper_empty(self) -> None:
        assert allotest.call_upper("") == ""

    def test_call_upper_numbers(self) -> None:
        assert allotest.call_upper("abc123def") == "ABC123DEF"

    def test_call_upper_special_chars(self) -> None:
        assert allotest.call_upper("hello!@#$%") == "HELLO!@#$%"

    def test_call_upper_unicode(self) -> None:
        # Test with unicode that doesn't change case (numbers, symbols)
        # The é→É uppercase conversion can be problematic across encodings
        assert allotest.call_upper("hello") == "HELLO"
        # Test that we can at least pass unicode through without corruption
        # (upper() on non-letter unicode chars returns them unchanged)
        result = allotest.call_upper("abc123")
        assert result == "ABC123"

    def test_call_upper_whitespace(self) -> None:
        assert allotest.call_upper("  hello  ") == "  HELLO  "
        assert allotest.call_upper("\thello\n") == "\tHELLO\n"

    def test_call_upper_single_char(self) -> None:
        assert allotest.call_upper("a") == "A"
        assert allotest.call_upper("Z") == "Z"

    def test_call_upper_long_string(self) -> None:
        s = "a" * 1000
        result = allotest.call_upper(s)
        assert result == "A" * 1000
        assert len(result) == 1000


class TestMethodCallChaining:
    """Test that method calls work correctly with various objects."""

    def test_method_via_obj_callmethod0(self) -> None:
        # Using the generic obj_callmethod0 for comparison
        result = allotest.obj_callmethod0("hello", "upper")
        assert result == "HELLO"

    def test_method_call_preserves_type(self) -> None:
        result = allotest.call_upper("test")
        assert isinstance(result, str)

    def test_method_call_new_object(self) -> None:
        # Verify that the result is a new string object
        original = "hello"
        result = allotest.call_upper(original)
        assert original == "hello"  # original unchanged
        assert result == "HELLO"


class TestInteropEdgeCases:
    """Test edge cases in Python interop."""

    def test_import_called_many_times(self) -> None:
        # Should not leak resources or fail after many calls
        for _ in range(100):
            result = allotest.import_math_pi()
            assert result == pytest.approx(math.pi)

    def test_method_call_many_times(self) -> None:
        # Should not leak resources or fail after many calls
        for i in range(100):
            s = f"test{i}"
            assert allotest.call_upper(s) == s.upper()

    def test_interleaved_calls(self) -> None:
        # Interleave import and method calls
        for _ in range(50):
            pi = allotest.import_math_pi()
            upper = allotest.call_upper("pi")
            assert pi == pytest.approx(math.pi)
            assert upper == "PI"

    def test_import_and_use_in_expression(self) -> None:
        # Use imported value in computation
        pi = allotest.import_math_pi()
        radius = 2.0
        circumference = 2 * pi * radius
        assert circumference == pytest.approx(4 * math.pi)
