"""Tests for dunder slot wiring on Zig-backed classes."""

import gc
import operator

import pytest

import allotest


class TestDunderBasics:
    def test_repr_and_str(self) -> None:
        obj = allotest.DunderBasics()
        obj.value = 7
        assert repr(obj) == "DunderBasics(7)"
        assert str(obj) == "DunderBasics value=7"

    def test_len_hash_bool(self) -> None:
        obj = allotest.DunderBasics()
        obj.value = 5
        assert len(obj) == 5
        assert hash(obj) == 5
        obj.value = 0
        assert bool(obj) is False
        obj.value = 2
        assert bool(obj) is True


class TestSubscript:
    def test_get_set_del(self) -> None:
        box = allotest.SubscriptBox()
        box["alpha"] = 1
        assert box["alpha"] == 1
        box["alpha"] = 2
        assert box["alpha"] == 2
        del box["alpha"]
        with pytest.raises(KeyError):
            _ = box["alpha"]


class TestComparison:
    def test_compare_ops(self) -> None:
        p1 = allotest.ComparePoint()
        p2 = allotest.ComparePoint()
        p1.value = 1
        p2.value = 2
        assert p1 == p1
        assert p1 != p2
        assert p1 < p2
        assert p1 <= p2
        assert p2 > p1
        assert p2 >= p1


class TestArithmetic:
    def test_number_ops(self) -> None:
        a = allotest.NumberBox()
        b = allotest.NumberBox()
        a.value = 10
        b.value = 4
        assert a + b == 14
        assert a - b == 6
        assert a * 3 == 30
        assert a / 4 == 2.5
        assert -a == -10


class TestContextManager:
    def test_with_statement(self) -> None:
        lock = allotest.ContextLock()
        with lock as value:
            assert value is lock
            assert lock.entered is True
        assert lock.exited is True


class TestIteratorSlots:
    def test_iter_next(self) -> None:
        counter = allotest.IterCounter()
        counter.limit = 3
        assert list(counter) == [0, 1, 2]


class TestContainsSlot:
    def test_contains(self) -> None:
        box = allotest.ContainsBox()
        box.items = [1, 2, 3]
        assert 2 in box
        assert 4 not in box


class TestNumberSlots:
    def test_unary_conversions(self) -> None:
        box = allotest.NumberBox()
        box.value = -5
        assert abs(box) == 5
        assert +box == -5
        assert int(box) == -5
        assert float(box) == -5.0
        assert operator.index(box) == -5

    def test_bitwise_ops(self) -> None:
        box = allotest.NumberBox()
        box.value = 10
        assert ~box == ~10
        assert box & 6 == 2
        assert box | 1 == 11
        assert box ^ 3 == 9
        assert box << 2 == 40
        assert box >> 1 == 5

    def test_floor_div_mod_pow(self) -> None:
        box = allotest.NumberBox()
        box.value = 9
        assert box // 4 == 2
        assert box % 4 == 1
        assert box**2 == 81
        assert pow(box, 2, 5) == 1
        assert divmod(box, 4) == (2, 1)

    def test_matrix_multiply(self) -> None:
        left = allotest.NumberBox()
        right = allotest.NumberBox()
        left.value = 3
        right.value = 4
        assert left @ right == 12

    def test_inplace_ops(self) -> None:
        box = allotest.NumberBox()
        box.value = 8
        box += 2
        assert box.value == 10
        box -= 3
        assert box.value == 7
        box *= 2
        assert box.value == 14
        box //= 4
        assert box.value == 3
        box %= 2
        assert box.value == 1
        box **= 3
        assert box.value == 1
        box <<= 2
        assert box.value == 4
        box >>= 1
        assert box.value == 2
        box &= 3
        assert box.value == 2
        box |= 1
        assert box.value == 3
        box ^= 6
        assert box.value == 5
        box /= 2
        assert box.value == 2

        other = allotest.NumberBox()
        other.value = 5
        box @= other
        assert box.value == 10


class TestInitSlot:
    def test_init_args(self) -> None:
        box = allotest.InitBox(12)
        assert box.value == 12


class TestAttributeSlots:
    def test_getattribute_getattr(self) -> None:
        box = allotest.AttrAccessBox()
        box.value = 7
        assert box.value == 7
        assert box.shadowed == "shadowed"
        assert box.missing == "missing:missing"

    def test_setattr_delattr(self) -> None:
        box = allotest.AttrSetBox()
        box.value = "hello"
        assert box.value == "hello"
        del box.value
        with pytest.raises(AttributeError):
            _ = box.value


class TestDescriptorSlots:
    def test_descriptor_get_set_delete(self) -> None:
        class UsesDescriptor:
            value = allotest.DescriptorBox()

        obj = UsesDescriptor()
        assert isinstance(UsesDescriptor.value, allotest.DescriptorBox)
        assert obj.value == "unset"
        obj.value = "hello"
        assert obj.value == "hello"
        del obj.value
        assert obj.value == "unset"


class TestNewSlot:
    def test_new_called(self) -> None:
        box = allotest.NewBox(12)
        assert box.value == 12


class TestDelSlot:
    def test_del_called(self) -> None:
        allotest.reset_del_count()
        box = allotest.DelBox()
        box.value = 7
        del box
        gc.collect()
        assert allotest.get_del_count() == 1
