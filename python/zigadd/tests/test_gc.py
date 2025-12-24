"""
GC-specific tests for heap type cleanup.

These tests specifically exercise garbage collection scenarios that have
been problematic on certain Python versions (particularly 3.11).
"""

import gc
import weakref

import pytest

import zigadd


class TestAdderGC:
    """Test garbage collection of Adder instances."""

    def test_adder_gc_simple(self) -> None:
        """Basic GC test - create and delete."""
        a = zigadd.Adder()
        del a
        gc.collect()

    def test_adder_gc_with_identity(self) -> None:
        """Test GC after calling identity() which returns self."""
        a = zigadd.Adder()
        b = a.identity()
        assert b is a
        del a
        del b
        gc.collect()

    def test_adder_gc_multiple_identity_calls(self) -> None:
        """Test GC after multiple identity() calls."""
        a = zigadd.Adder()
        for _ in range(10):
            b = a.identity()
            assert b is a
        del a
        gc.collect()

    def test_adder_gc_identity_in_expression(self) -> None:
        """Test GC when identity() result is used in expression without binding."""
        a = zigadd.Adder()
        assert a.identity() is a
        assert a.identity().add(2, 3) == 5
        del a
        gc.collect()

    def test_adder_gc_multiple_instances(self) -> None:
        """Test GC with multiple Adder instances."""
        adders = [zigadd.Adder() for _ in range(10)]
        for a in adders:
            assert a.identity() is a
        del adders
        gc.collect()

    def test_adder_gc_nested_calls(self) -> None:
        """Test GC with nested identity calls."""
        a = zigadd.Adder()
        assert a.identity().identity().identity() is a
        del a
        gc.collect()

    def test_adder_weakref(self) -> None:
        """Test that Adder can be weak-referenced and GC'd properly."""
        a = zigadd.Adder()
        try:
            ref = weakref.ref(a)
            assert ref() is a
            del a
            gc.collect()
            # After GC, the weakref should be dead
            assert ref() is None
        except TypeError:
            # If weakrefs aren't supported, that's fine
            pytest.skip("Adder does not support weak references")

    def test_adder_gc_stress(self) -> None:
        """Stress test - create and destroy many instances with GC."""
        for _ in range(100):
            a = zigadd.Adder()
            _ = a.identity()
            del a
        gc.collect()

    def test_adder_survives_gc_cycle(self) -> None:
        """Test that live Adder survives GC."""
        a = zigadd.Adder()
        gc.collect()
        assert a.add(1, 2) == 3
        gc.collect()
        assert a.identity() is a
        gc.collect()


class TestGCAtShutdown:
    """
    Tests that verify cleanup during interpreter shutdown.

    These tests are designed to catch issues that only manifest when
    GC runs during Python finalization (like the Python 3.11 segfault).
    """

    def test_adder_class_basic(self) -> None:
        """
        Basic Adder test - this is the minimal case that triggered
        the Python 3.11 segfault during pytest cleanup.
        """
        adder = zigadd.Adder()
        assert adder.add(2, 5) == 7
        assert adder.identity() is adder
