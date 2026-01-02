"""Tests for class definitions, self parameter, and multiple classes."""

import gc
import weakref

import pytest

import allotest


class TestAdder:
    """Test the Adder class."""

    def test_create_instance(self) -> None:
        adder = allotest.Adder()
        assert adder is not None

    def test_add(self) -> None:
        adder = allotest.Adder()
        assert adder.add(2, 3) == 5
        assert adder.add(0, 0) == 0
        assert adder.add(-1, 1) == 0

    def test_add_large_numbers(self) -> None:
        adder = allotest.Adder()
        assert adder.add(2**30, 2**30) == 2**31

    def test_identity(self) -> None:
        adder = allotest.Adder()
        result = adder.identity()
        assert result is adder

    def test_identity_multiple_calls(self) -> None:
        adder = allotest.Adder()
        for _ in range(10):
            result = adder.identity()
            assert result is adder

    def test_chained_identity(self) -> None:
        adder = allotest.Adder()
        result = adder.identity().identity().identity()
        assert result is adder

    def test_chained_methods(self) -> None:
        adder = allotest.Adder()
        result = adder.identity().add(10, 20)
        assert result == 30

    def test_multiple_instances(self) -> None:
        adder1 = allotest.Adder()
        adder2 = allotest.Adder()
        assert adder1 is not adder2
        assert adder1.add(1, 2) == adder2.add(1, 2)


class TestCounter:
    """Test the Counter class with mutable state."""

    def test_create_instance(self) -> None:
        counter = allotest.Counter()
        assert counter is not None

    def test_initial_value(self) -> None:
        counter = allotest.Counter()
        assert counter.get() == 0

    def test_increment(self) -> None:
        counter = allotest.Counter()
        assert counter.increment() == 1
        assert counter.increment() == 2
        assert counter.increment() == 3

    def test_increment_returns_new_value(self) -> None:
        counter = allotest.Counter()
        for expected in range(1, 11):
            assert counter.increment() == expected

    def test_add_positive(self) -> None:
        counter = allotest.Counter()
        assert counter.add(10) == 10
        assert counter.add(5) == 15

    def test_add_negative(self) -> None:
        counter = allotest.Counter()
        counter.add(10)
        assert counter.add(-3) == 7

    def test_add_zero(self) -> None:
        counter = allotest.Counter()
        counter.add(5)
        assert counter.add(0) == 5

    def test_reset(self) -> None:
        counter = allotest.Counter()
        counter.increment()
        counter.increment()
        counter.reset()
        assert counter.get() == 0

    def test_reset_multiple_times(self) -> None:
        counter = allotest.Counter()
        counter.add(100)
        counter.reset()
        counter.add(50)
        counter.reset()
        assert counter.get() == 0

    def test_get_after_operations(self) -> None:
        counter = allotest.Counter()
        counter.increment()
        counter.add(9)
        assert counter.get() == 10

    def test_multiple_instances_independent(self) -> None:
        counter1 = allotest.Counter()
        counter2 = allotest.Counter()

        counter1.add(10)
        counter2.add(20)

        assert counter1.get() == 10
        assert counter2.get() == 20

        counter1.increment()
        assert counter1.get() == 11
        assert counter2.get() == 20


class TestMultipleClasses:
    """Test having multiple classes in one module."""

    def test_both_classes_exist(self) -> None:
        assert hasattr(allotest, "Adder")
        assert hasattr(allotest, "Counter")

    def test_classes_are_different(self) -> None:
        assert allotest.Adder is not allotest.Counter

    def test_instances_are_different_types(self) -> None:
        adder = allotest.Adder()
        counter = allotest.Counter()
        assert type(adder) is not type(counter)
        assert isinstance(adder, allotest.Adder)
        assert isinstance(counter, allotest.Counter)

    def test_interleaved_usage(self) -> None:
        adder = allotest.Adder()
        counter = allotest.Counter()

        counter.increment()
        result = adder.add(counter.get(), 10)
        assert result == 11

        counter.add(result)
        assert counter.get() == 12


class TestClassDocstrings:
    """Test that class docstrings are preserved."""

    def test_adder_has_docstring(self) -> None:
        assert allotest.Adder.__doc__ is not None
        assert "adder" in allotest.Adder.__doc__.lower()

    def test_counter_has_docstring(self) -> None:
        assert allotest.Counter.__doc__ is not None
        assert "counter" in allotest.Counter.__doc__.lower()


class TestSelfParameter:
    """Test that self parameter handling works correctly."""

    def test_self_is_correct_instance(self) -> None:
        # identity() returns self, so we can verify it's the same object
        adder = allotest.Adder()
        assert adder.identity() is adder

    def test_self_preserved_across_calls(self) -> None:
        counter = allotest.Counter()
        counter.increment()
        counter.increment()
        # If self wasn't properly maintained, state would be lost
        assert counter.get() == 2

    def test_self_with_method_returning_value(self) -> None:
        adder = allotest.Adder()
        # Method uses self (even if ignored) and returns computed value
        result = adder.add(100, 200)
        assert result == 300


class TestClassAndStaticMethods:
    """Test @classmethod and @staticmethod bindings."""

    def test_classmethod_on_class(self) -> None:
        assert allotest.MethodKinds.class_name() == "MethodKinds"

    def test_classmethod_on_instance(self) -> None:
        assert allotest.MethodKinds().class_name() == "MethodKinds"

    def test_staticmethod_on_class(self) -> None:
        assert allotest.MethodKinds.sum(1, 2) == 3

    def test_staticmethod_on_instance(self) -> None:
        assert allotest.MethodKinds().sum(2, 3) == 5


class TestCallableClasses:
    def test_call_positional(self) -> None:
        adder = allotest.CallableAdder()
        assert adder(10) == 10

    def test_call_keyword(self) -> None:
        adder = allotest.CallableAdder()
        assert adder(value=4, extra=6) == 10


class TestClassGC:
    """Test garbage collection of class instances."""

    def test_simple_gc(self) -> None:
        adder = allotest.Adder()
        del adder
        gc.collect()

    def test_gc_with_identity(self) -> None:
        adder = allotest.Adder()
        _ = adder.identity()
        del adder
        gc.collect()

    def test_gc_multiple_instances(self) -> None:
        instances = [allotest.Adder() for _ in range(100)]
        for inst in instances:
            _ = inst.identity()
        del instances
        gc.collect()

    def test_gc_counter(self) -> None:
        counter = allotest.Counter()
        counter.increment()
        counter.add(10)
        del counter
        gc.collect()

    def test_gc_mixed_classes(self) -> None:
        adders = [allotest.Adder() for _ in range(10)]
        counters = [allotest.Counter() for _ in range(10)]
        for a in adders:
            a.add(1, 2)
        for c in counters:
            c.increment()
        del adders
        del counters
        gc.collect()

    def test_weakref_adder(self) -> None:
        adder = allotest.Adder()
        try:
            ref = weakref.ref(adder)
            assert ref() is adder
            del adder
            gc.collect()
            assert ref() is None
        except TypeError:
            pytest.skip("Adder does not support weak references")

    def test_weakref_counter(self) -> None:
        counter = allotest.Counter()
        try:
            ref = weakref.ref(counter)
            assert ref() is counter
            del counter
            gc.collect()
            assert ref() is None
        except TypeError:
            pytest.skip("Counter does not support weak references")

    def test_instance_survives_gc(self) -> None:
        adder = allotest.Adder()
        gc.collect()
        assert adder.add(1, 2) == 3
        gc.collect()
        assert adder.identity() is adder


class TestClassEdgeCases:
    """Test edge cases in class behavior."""

    def test_many_method_calls(self) -> None:
        adder = allotest.Adder()
        for i in range(1000):
            assert adder.add(i, 1) == i + 1

    def test_counter_stress(self) -> None:
        counter = allotest.Counter()
        for _ in range(1000):
            counter.increment()
        assert counter.get() == 1000

    def test_rapid_creation_deletion(self) -> None:
        for _ in range(100):
            adder = allotest.Adder()
            adder.add(1, 2)
            del adder
        gc.collect()

    def test_instances_in_list(self) -> None:
        adders = [allotest.Adder() for _ in range(10)]
        results = [a.add(i, i) for i, a in enumerate(adders)]
        assert results == [i * 2 for i in range(10)]

    def test_instance_as_dict_value(self) -> None:
        adder = allotest.Adder()
        counter = allotest.Counter()
        d = {"adder": adder, "counter": counter}
        assert adder.add(1, 2) == 3
        assert counter.increment() == 1
        # Verify they're still accessible via dict
        assert d["adder"] is adder
        assert d["counter"] is counter
