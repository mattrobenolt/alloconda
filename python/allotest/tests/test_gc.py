"""GC-specific tests for heap type cleanup.

These tests specifically exercise garbage collection scenarios that have
been problematic on certain Python versions (particularly 3.11).

Note: Basic GC tests for classes are in test_classes.py. This file focuses
on edge cases and stress testing.
"""

import gc
import sys

import allotest


class TestGCStress:
    """Stress tests for garbage collection."""

    def test_rapid_create_destroy_cycle(self) -> None:
        """Rapidly create and destroy instances in a tight loop."""
        for _ in range(1000):
            a = allotest.Adder()
            _ = a.add(1, 2)
            del a
        gc.collect()

    def test_many_instances_at_once(self) -> None:
        """Create many instances, then delete them all."""
        instances = [allotest.Adder() for _ in range(500)]
        for inst in instances:
            _ = inst.identity()
        del instances
        gc.collect()

    def test_nested_references(self) -> None:
        """Test GC with nested reference patterns."""
        a = allotest.Adder()
        refs = [a.identity() for _ in range(100)]
        assert all(r is a for r in refs)
        del refs
        gc.collect()
        # Original should still work
        assert a.add(1, 2) == 3
        del a
        gc.collect()

    def test_alternating_classes(self) -> None:
        """Alternate between creating different class types."""
        objects = []
        for i in range(200):
            if i % 2 == 0:
                objects.append(allotest.Adder())
            else:
                objects.append(allotest.Counter())
        del objects
        gc.collect()

    def test_gc_during_method_calls(self) -> None:
        """Force GC during method execution."""
        adder = allotest.Adder()
        for i in range(100):
            result = adder.add(i, i)
            if i % 10 == 0:
                gc.collect()
            assert result == i * 2


class TestReferencePatterns:
    """Test various reference patterns that might trip up GC."""

    def test_identity_chain_gc(self) -> None:
        """Test GC after long identity chains."""
        a = allotest.Adder()
        ref = a
        for _ in range(100):
            ref = ref.identity()
        assert ref is a
        del ref
        gc.collect()
        del a
        gc.collect()

    def test_temporary_references(self) -> None:
        """Test that temporary references are cleaned up."""
        for _ in range(100):
            # identity() returns self with incref'd reference
            _ = allotest.Adder().identity().identity().identity()
        gc.collect()

    def test_reference_in_container(self) -> None:
        """Test GC with instances stored in containers."""
        lst = []
        for _ in range(50):
            a = allotest.Adder()
            lst.append(a)
            lst.append(a.identity())
        del lst
        gc.collect()

    def test_dict_with_instances(self) -> None:
        """Test GC with instances as dict values."""
        d = {}
        for i in range(50):
            d[f"adder_{i}"] = allotest.Adder()
            d[f"counter_{i}"] = allotest.Counter()
        # Access all values
        for v in d.values():
            if isinstance(v, allotest.Adder):
                v.add(1, 2)
            else:
                v.increment()
        del d
        gc.collect()


class TestCounterGC:
    """Test GC of Counter instances with state."""

    def test_counter_with_state_gc(self) -> None:
        """Test GC of counter that has accumulated state."""
        c = allotest.Counter()
        for _ in range(100):
            c.increment()
        assert c.get() == 100
        del c
        gc.collect()

    def test_counter_reset_then_gc(self) -> None:
        """Test GC after counter operations including reset."""
        c = allotest.Counter()
        c.add(1000)
        c.reset()
        c.increment()
        assert c.get() == 1
        del c
        gc.collect()

    def test_many_counters_with_state(self) -> None:
        """Test GC of many counters, each with different state."""
        counters = []
        for i in range(100):
            c = allotest.Counter()
            c.add(i)
            counters.append(c)
        # Verify state
        for i, c in enumerate(counters):
            assert c.get() == i
        del counters
        gc.collect()


class TestGCAtShutdown:
    """
    Tests that verify cleanup during interpreter shutdown.

    These tests are designed to catch issues that only manifest when
    GC runs during Python finalization (like the Python 3.11 segfault).
    """

    def test_basic_class_usage(self) -> None:
        """
        Basic usage test - exercises code paths that triggered
        the Python 3.11 segfault during pytest cleanup.
        """
        adder = allotest.Adder()
        assert adder.add(2, 5) == 7
        assert adder.identity() is adder

    def test_counter_at_shutdown(self) -> None:
        """Counter instance that will be cleaned up at shutdown."""
        counter = allotest.Counter()
        counter.increment()
        counter.add(10)
        assert counter.get() == 11

    def test_multiple_instances_at_shutdown(self) -> None:
        """Multiple instances of both classes at shutdown."""
        adders = [allotest.Adder() for _ in range(5)]
        counters = [allotest.Counter() for _ in range(5)]
        for a in adders:
            _ = a.identity()
        for c in counters:
            c.increment()


class TestRefCount:
    """Test reference counting behavior."""

    def test_identity_refcount(self) -> None:
        """Test that identity properly manages refcount."""
        a = allotest.Adder()
        initial_count = sys.getrefcount(a)
        b = a.identity()
        # b should be the same object with incremented refcount
        assert b is a
        assert sys.getrefcount(a) == initial_count + 1
        del b
        assert sys.getrefcount(a) == initial_count

    def test_object_identity_refcount(self) -> None:
        """Test that identity_object properly manages refcount."""
        obj = {"test": "value"}
        initial_count = sys.getrefcount(obj)
        result = allotest.identity_object(obj)
        assert result is obj
        # Note: exact refcount may vary due to internal handling
        del result
        gc.collect()
        assert sys.getrefcount(obj) == initial_count
