"""Tests for dataclass serialization/deserialization (encode/decode)."""

import io
from dataclasses import dataclass
from enum import IntEnum

from fastproto import Reader, Writer, decode, decode_from, encode, encode_into, field


# 1. Simple scalar fields
@dataclass
class SimpleMessage:
    i: int = field(1)
    f: float = field(2)
    b: bool = field(3)
    s: str = field(4)
    data: bytes = field(5)


def test_simple_scalars():
    msg = SimpleMessage(i=42, f=3.14, b=True, s="hello", data=b"world")
    encoded = encode(msg)
    decoded = decode(SimpleMessage, encoded)
    assert decoded == msg


# 2. Nested dataclass
@dataclass
class Inner:
    value: int = field(1)


@dataclass
class Outer:
    inner: Inner = field(1)
    name: str = field(2)


def test_nested_message():
    msg = Outer(inner=Inner(value=123), name="test")
    assert decode(Outer, encode(msg)) == msg


# 3. Packed repeated scalars (list[int], list[float])
@dataclass
class RepeatedScalars:
    values: list[int] = field(1)
    floats: list[float] = field(2)


def test_packed_repeated():
    msg = RepeatedScalars(values=[1, 2, 3, 4, 5], floats=[1.1, 2.2, 3.3])
    assert decode(RepeatedScalars, encode(msg)) == msg


# 4. Repeated messages (list[dataclass])
@dataclass
class Item:
    id: int = field(1)


@dataclass
class Container:
    items: list[Item] = field(1)


def test_repeated_messages():
    msg = Container(items=[Item(id=1), Item(id=2), Item(id=3)])
    assert decode(Container, encode(msg)) == msg


# 5. Optional fields
@dataclass
class OptionalFields:
    required: str = field(1)
    optional: str | None = field(2, default=None)


def test_optional_present():
    msg = OptionalFields(required="a", optional="b")
    assert decode(OptionalFields, encode(msg)) == msg


def test_optional_missing():
    msg = OptionalFields(required="a", optional=None)
    # When decoded, optional should be None (or default)
    decoded = decode(OptionalFields, encode(msg))
    assert isinstance(decoded, OptionalFields)
    assert decoded.required == "a"


# 6. IntEnum fields
class Status(IntEnum):
    UNKNOWN = 0
    ACTIVE = 1
    INACTIVE = 2


@dataclass
class WithEnum:
    status: int = field(1)  # Enums serialize as int


def test_enum():
    msg = WithEnum(status=Status.ACTIVE)
    decoded = decode(WithEnum, encode(msg))
    assert isinstance(decoded, WithEnum)
    assert decoded.status == 1


# 7. Explicit proto_type overrides
@dataclass
class ExplicitTypes:
    signed: int = field(1, proto_type="sint32")
    fixed: int = field(2, proto_type="fixed64")
    single_float: float = field(3, proto_type="float")


def test_explicit_proto_types():
    msg = ExplicitTypes(signed=-100, fixed=999999, single_float=2.5)
    decoded = decode(ExplicitTypes, encode(msg))
    assert isinstance(decoded, ExplicitTypes)
    assert decoded.signed == -100
    assert decoded.fixed == 999999
    # float precision may differ slightly
    assert abs(decoded.single_float - 2.5) < 0.001


# 8. Empty message
@dataclass
class Empty:
    pass


def test_empty_message():
    msg = Empty()
    assert decode(Empty, encode(msg)) == msg


# 9. Streaming encode/decode
def test_streaming_encode_decode():
    msg = SimpleMessage(i=42, f=3.14, b=True, s="hello", data=b"world")

    stream = io.BytesIO()
    writer = Writer(stream)
    encode_into(writer, msg)
    writer.flush()

    stream.seek(0)
    reader = Reader(stream)
    decoded = decode_from(SimpleMessage, reader)

    assert decoded == msg


def test_streaming_nested_message():
    msg = Outer(inner=Inner(value=123), name="test")

    stream = io.BytesIO()
    writer = Writer(stream)
    encode_into(writer, msg)
    writer.flush()

    stream.seek(0)
    reader = Reader(stream)
    decoded = decode_from(Outer, reader)

    assert decoded == msg


# 9. Unsigned integer types (uint32/uint64)
@dataclass
class UnsignedTypes:
    u32_val: int = field(1, proto_type="uint32")
    u64_val: int = field(2, proto_type="uint64")


def test_unsigned_large_values():
    msg = UnsignedTypes(u32_val=0xFFFFFFFF, u64_val=0xFFFFFFFFFFFFFFFF)
    decoded = decode(UnsignedTypes, encode(msg))
    assert isinstance(decoded, UnsignedTypes)
    assert decoded.u32_val == 0xFFFFFFFF
    assert decoded.u64_val == 0xFFFFFFFFFFFFFFFF


# 10. Packed repeated unsigned
@dataclass
class PackedUnsigned:
    u32_vals: list[int] = field(1, proto_type="uint32")
    u64_vals: list[int] = field(2, proto_type="uint64")


def test_packed_unsigned():
    msg = PackedUnsigned(
        u32_vals=[0, 1, 0x7FFFFFFF, 0xFFFFFFFF],
        u64_vals=[0, 1, 0x7FFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF],
    )
    decoded = decode(PackedUnsigned, encode(msg))
    assert isinstance(decoded, PackedUnsigned)
    assert decoded.u32_vals == [0, 1, 0x7FFFFFFF, 0xFFFFFFFF]
    assert decoded.u64_vals == [0, 1, 0x7FFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF]
