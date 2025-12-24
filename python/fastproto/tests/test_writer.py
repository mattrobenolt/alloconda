"""Tests for the Writer class."""

from fastproto import Reader, WireType, Writer


class TestWriterBasic:
    """Basic Writer functionality tests."""

    def test_empty_message(self):
        writer = Writer()
        assert writer.finish() == b""

    def test_finish_returns_bytes(self):
        writer = Writer()
        writer.int32(1, 42)
        result = writer.finish()
        assert isinstance(result, bytes)

    def test_clear(self):
        writer = Writer()
        writer.int32(1, 42)
        assert len(writer.finish()) > 0

        writer.clear()
        assert writer.finish() == b""

    def test_reuse_after_finish(self):
        writer = Writer()
        writer.int32(1, 42)
        writer.finish()

        # Can still write more
        writer.int32(2, 100)
        data2 = writer.finish()

        # data2 should contain both fields
        fields = list(Reader(data2))
        assert len(fields) == 2

    def test_reuse_after_clear(self):
        writer = Writer()
        writer.int32(1, 42)
        writer.clear()
        writer.int32(2, 100)
        data = writer.finish()

        fields = list(Reader(data))
        assert len(fields) == 1
        assert fields[0].number == 2
        assert fields[0].int32() == 100


class TestWriterVarintTypes:
    """Tests for writing varint-encoded types."""

    def test_int32_positive(self):
        writer = Writer()
        writer.int32(1, 42)
        data = writer.finish()

        field = next(Reader(data))
        assert field.wire_type == WireType.VARINT
        assert field.int32() == 42

    def test_int32_zero(self):
        writer = Writer()
        writer.int32(1, 0)
        data = writer.finish()

        field = next(Reader(data))
        assert field.int32() == 0

    def test_int32_negative(self):
        writer = Writer()
        writer.int32(1, -1)
        writer.int32(2, -42)
        writer.int32(3, -2147483648)  # INT32_MIN
        data = writer.finish()

        fields = list(Reader(data))
        assert fields[0].int32() == -1
        assert fields[1].int32() == -42
        assert fields[2].int32() == -2147483648

    def test_int32_max(self):
        writer = Writer()
        writer.int32(1, 2147483647)  # INT32_MAX
        data = writer.finish()

        field = next(Reader(data))
        assert field.int32() == 2147483647

    def test_int64_positive(self):
        writer = Writer()
        writer.int64(1, 9223372036854775807)  # INT64_MAX
        data = writer.finish()

        field = next(Reader(data))
        assert field.int64() == 9223372036854775807

    def test_int64_negative(self):
        writer = Writer()
        writer.int64(1, -9223372036854775808)  # INT64_MIN
        data = writer.finish()

        field = next(Reader(data))
        assert field.int64() == -9223372036854775808

    def test_int64_large(self):
        writer = Writer()
        writer.int64(1, 1000000000000)  # 1 trillion
        data = writer.finish()

        field = next(Reader(data))
        assert field.int64() == 1000000000000

    def test_uint32(self):
        writer = Writer()
        writer.uint32(1, 0)
        writer.uint32(2, 1)
        writer.uint32(3, 4294967295)  # UINT32_MAX
        data = writer.finish()

        fields = list(Reader(data))
        assert fields[0].uint32() == 0
        assert fields[1].uint32() == 1
        assert fields[2].uint32() == 4294967295

    def test_uint64(self):
        writer = Writer()
        writer.uint64(1, 0)
        writer.uint64(2, 18446744073709551615)  # UINT64_MAX
        data = writer.finish()

        fields = list(Reader(data))
        assert fields[0].uint64() == 0
        assert fields[1].uint64() == 18446744073709551615

    def test_sint32_positive(self):
        writer = Writer()
        writer.sint32(1, 0)
        writer.sint32(2, 1)
        writer.sint32(3, 2147483647)
        data = writer.finish()

        fields = list(Reader(data))
        assert fields[0].sint32() == 0
        assert fields[1].sint32() == 1
        assert fields[2].sint32() == 2147483647

    def test_sint32_negative(self):
        writer = Writer()
        writer.sint32(1, -1)
        writer.sint32(2, -100)
        writer.sint32(3, -2147483648)
        data = writer.finish()

        fields = list(Reader(data))
        assert fields[0].sint32() == -1
        assert fields[1].sint32() == -100
        assert fields[2].sint32() == -2147483648

    def test_sint32_efficiency(self):
        # sint32 should be more efficient for small negative numbers
        writer1 = Writer()
        writer1.int32(1, -1)
        data1 = writer1.finish()

        writer2 = Writer()
        writer2.sint32(1, -1)
        data2 = writer2.finish()

        # -1 as int32 takes 10 bytes (sign extended), sint32 takes 1 byte
        assert len(data2) < len(data1)

    def test_sint64_positive(self):
        writer = Writer()
        writer.sint64(1, 0)
        writer.sint64(2, 1000000000000)
        data = writer.finish()

        fields = list(Reader(data))
        assert fields[0].sint64() == 0
        assert fields[1].sint64() == 1000000000000

    def test_sint64_negative(self):
        writer = Writer()
        writer.sint64(1, -1)
        writer.sint64(2, -1000000000000)
        data = writer.finish()

        fields = list(Reader(data))
        assert fields[0].sint64() == -1
        assert fields[1].sint64() == -1000000000000

    def test_bool_true(self):
        writer = Writer()
        writer.bool(1, True)
        data = writer.finish()

        field = next(Reader(data))
        assert field.bool() is True

    def test_bool_false(self):
        writer = Writer()
        writer.bool(1, False)
        data = writer.finish()

        field = next(Reader(data))
        assert field.bool() is False

    def test_enum(self):
        writer = Writer()
        writer.enum(1, 0)
        writer.enum(2, 1)
        writer.enum(3, 100)
        writer.enum(4, -1)  # Negative enums are allowed in proto3
        data = writer.finish()

        fields = list(Reader(data))
        assert fields[0].enum() == 0
        assert fields[1].enum() == 1
        assert fields[2].enum() == 100
        assert fields[3].enum() == -1


class TestWriterFixed64Types:
    """Tests for writing 64-bit fixed types."""

    def test_fixed64(self):
        writer = Writer()
        writer.fixed64(1, 0)
        writer.fixed64(2, 0xDEADBEEFCAFEBABE)
        writer.fixed64(3, 0xFFFFFFFFFFFFFFFF)
        data = writer.finish()

        fields = list(Reader(data))
        assert fields[0].wire_type == WireType.FIXED64
        assert fields[0].fixed64() == 0
        assert fields[1].fixed64() == 0xDEADBEEFCAFEBABE
        assert fields[2].fixed64() == 0xFFFFFFFFFFFFFFFF

    def test_sfixed64_positive(self):
        writer = Writer()
        writer.sfixed64(1, 0)
        writer.sfixed64(2, 9223372036854775807)  # INT64_MAX
        data = writer.finish()

        fields = list(Reader(data))
        assert fields[0].sfixed64() == 0
        assert fields[1].sfixed64() == 9223372036854775807

    def test_sfixed64_negative(self):
        writer = Writer()
        writer.sfixed64(1, -1)
        writer.sfixed64(2, -9223372036854775808)  # INT64_MIN
        data = writer.finish()

        fields = list(Reader(data))
        assert fields[0].sfixed64() == -1
        assert fields[1].sfixed64() == -9223372036854775808

    def test_double(self):
        writer = Writer()
        writer.double(1, 0.0)
        writer.double(2, 3.14159265358979)
        writer.double(3, -1.5)
        data = writer.finish()

        fields = list(Reader(data))
        assert fields[0].double() == 0.0
        assert abs(fields[1].double() - 3.14159265358979) < 1e-10
        assert fields[2].double() == -1.5

    def test_double_special_values(self):
        import math

        writer = Writer()
        writer.double(1, float("inf"))
        writer.double(2, float("-inf"))
        writer.double(3, float("nan"))
        data = writer.finish()

        fields = list(Reader(data))
        assert fields[0].double() == float("inf")
        assert fields[1].double() == float("-inf")
        assert math.isnan(fields[2].double())

    def test_double_very_small(self):
        writer = Writer()
        writer.double(1, 1e-300)
        data = writer.finish()

        field = next(Reader(data))
        assert field.double() == 1e-300

    def test_double_very_large(self):
        writer = Writer()
        writer.double(1, 1e300)
        data = writer.finish()

        field = next(Reader(data))
        assert field.double() == 1e300


class TestWriterFixed32Types:
    """Tests for writing 32-bit fixed types."""

    def test_fixed32(self):
        writer = Writer()
        writer.fixed32(1, 0)
        writer.fixed32(2, 0xDEADBEEF)
        writer.fixed32(3, 0xFFFFFFFF)
        data = writer.finish()

        fields = list(Reader(data))
        assert fields[0].wire_type == WireType.FIXED32
        assert fields[0].fixed32() == 0
        assert fields[1].fixed32() == 0xDEADBEEF
        assert fields[2].fixed32() == 0xFFFFFFFF

    def test_sfixed32_positive(self):
        writer = Writer()
        writer.sfixed32(1, 0)
        writer.sfixed32(2, 2147483647)  # INT32_MAX
        data = writer.finish()

        fields = list(Reader(data))
        assert fields[0].sfixed32() == 0
        assert fields[1].sfixed32() == 2147483647

    def test_sfixed32_negative(self):
        writer = Writer()
        writer.sfixed32(1, -1)
        writer.sfixed32(2, -2147483648)  # INT32_MIN
        data = writer.finish()

        fields = list(Reader(data))
        assert fields[0].sfixed32() == -1
        assert fields[1].sfixed32() == -2147483648

    def test_float(self):
        writer = Writer()
        writer.float(1, 0.0)
        writer.float(2, 3.14)
        writer.float(3, -1.5)
        data = writer.finish()

        fields = list(Reader(data))
        assert fields[0].float() == 0.0
        assert abs(fields[1].float() - 3.14) < 1e-5
        assert fields[2].float() == -1.5

    def test_float_special_values(self):
        import math

        writer = Writer()
        writer.float(1, float("inf"))
        writer.float(2, float("-inf"))
        writer.float(3, float("nan"))
        data = writer.finish()

        fields = list(Reader(data))
        assert fields[0].float() == float("inf")
        assert fields[1].float() == float("-inf")
        assert math.isnan(fields[2].float())


class TestWriterLengthDelimited:
    """Tests for writing length-delimited types."""

    def test_string_ascii(self):
        writer = Writer()
        writer.string(1, "hello world")
        data = writer.finish()

        field = next(Reader(data))
        assert field.wire_type == WireType.LEN
        assert field.string() == "hello world"

    def test_string_unicode(self):
        writer = Writer()
        writer.string(1, "hello 世界 🌍 émoji")
        data = writer.finish()

        field = next(Reader(data))
        assert field.string() == "hello 世界 🌍 émoji"

    def test_string_empty(self):
        writer = Writer()
        writer.string(1, "")
        data = writer.finish()

        field = next(Reader(data))
        assert field.string() == ""

    def test_string_long(self):
        # Test string longer than 127 bytes (requires multi-byte length)
        long_string = "a" * 1000
        writer = Writer()
        writer.string(1, long_string)
        data = writer.finish()

        field = next(Reader(data))
        assert field.string() == long_string

    def test_bytes(self):
        writer = Writer()
        writer.bytes(1, b"\x00\x01\x02\x03\xff\xfe")
        data = writer.finish()

        field = next(Reader(data))
        assert field.bytes() == b"\x00\x01\x02\x03\xff\xfe"

    def test_bytes_empty(self):
        writer = Writer()
        writer.bytes(1, b"")
        data = writer.finish()

        field = next(Reader(data))
        assert field.bytes() == b""

    def test_bytes_large(self):
        large_bytes = bytes(range(256)) * 100  # 25600 bytes
        writer = Writer()
        writer.bytes(1, large_bytes)
        data = writer.finish()

        field = next(Reader(data))
        assert field.bytes() == large_bytes


class TestWriterNestedMessages:
    """Tests for writing nested messages."""

    def test_nested_message_context_manager(self):
        writer = Writer()
        writer.string(1, "parent")
        with writer.message(2) as nested:
            nested.string(1, "child")
            nested.int32(2, 42)
        data = writer.finish()

        fields = list(Reader(data))
        assert len(fields) == 2
        assert fields[0].string() == "parent"

        nested_fields = list(fields[1].message())
        assert len(nested_fields) == 2
        assert nested_fields[0].string() == "child"
        assert nested_fields[1].int32() == 42

    def test_nested_message_explicit_end(self):
        writer = Writer()
        writer.string(1, "parent")
        nested = writer.message(2)
        nested.string(1, "child")
        nested.int32(2, 42)
        nested.end()
        data = writer.finish()

        fields = list(Reader(data))
        assert len(fields) == 2
        assert fields[0].string() == "parent"

        nested_fields = list(fields[1].message())
        assert len(nested_fields) == 2
        assert nested_fields[0].string() == "child"
        assert nested_fields[1].int32() == 42

    def test_deeply_nested_messages(self):
        writer = Writer()
        with writer.message(1) as level1:
            level1.string(1, "level1")
            with level1.message(2) as level2:
                level2.string(1, "level2")
                with level2.message(2) as level3:
                    level3.string(1, "level3")
                    level3.int32(2, 42)
        data = writer.finish()

        l1 = next(Reader(data))
        l1_fields = list(l1.message())
        assert l1_fields[0].string() == "level1"

        l2_fields = list(l1_fields[1].message())
        assert l2_fields[0].string() == "level2"

        l3_fields = list(l2_fields[1].message())
        assert l3_fields[0].string() == "level3"
        assert l3_fields[1].int32() == 42

    def test_empty_nested_message(self):
        writer = Writer()
        with writer.message(1):
            pass  # Empty message
        data = writer.finish()

        field = next(Reader(data))
        assert field.bytes() == b""
        assert list(field.message()) == []

    def test_nested_message_with_bytes(self):
        # Manually serialize a nested message and embed it
        inner = Writer()
        inner.string(1, "inner")
        inner_data = inner.finish()

        outer = Writer()
        outer.bytes(1, inner_data)
        data = outer.finish()

        field = next(Reader(data))
        inner_fields = list(Reader(field.bytes()))
        assert inner_fields[0].string() == "inner"

    def test_multiple_nested_messages(self):
        writer = Writer()
        with writer.message(1) as msg1:
            msg1.string(1, "first")
        with writer.message(2) as msg2:
            msg2.string(1, "second")
        with writer.message(3) as msg3:
            msg3.string(1, "third")
        data = writer.finish()

        fields = list(Reader(data))
        assert len(fields) == 3
        assert list(fields[0].message())[0].string() == "first"
        assert list(fields[1].message())[0].string() == "second"
        assert list(fields[2].message())[0].string() == "third"


class TestWriterPackedRepeated:
    """Tests for writing packed repeated fields."""

    def test_packed_int32s(self):
        writer = Writer()
        writer.packed_int32s(1, [1, 2, 3, -1, -2, -3])
        data = writer.finish()

        field = next(Reader(data))
        assert field.packed_int32s() == [1, 2, 3, -1, -2, -3]

    def test_packed_int64s(self):
        writer = Writer()
        writer.packed_int64s(1, [0, 1000000000000, -1000000000000])
        data = writer.finish()

        field = next(Reader(data))
        assert field.packed_int64s() == [0, 1000000000000, -1000000000000]

    def test_packed_uint32s(self):
        writer = Writer()
        writer.packed_uint32s(1, [0, 1, 128, 4294967295])
        data = writer.finish()

        field = next(Reader(data))
        assert field.packed_uint32s() == [0, 1, 128, 4294967295]

    def test_packed_uint64s(self):
        writer = Writer()
        writer.packed_uint64s(1, [0, 1, 18446744073709551615])
        data = writer.finish()

        field = next(Reader(data))
        assert field.packed_uint64s() == [0, 1, 18446744073709551615]

    def test_packed_sint32s(self):
        writer = Writer()
        writer.packed_sint32s(1, [0, 1, -1, 100, -100, 2147483647, -2147483648])
        data = writer.finish()

        field = next(Reader(data))
        assert field.packed_sint32s() == [0, 1, -1, 100, -100, 2147483647, -2147483648]

    def test_packed_sint64s(self):
        writer = Writer()
        writer.packed_sint64s(1, [0, 1, -1, 1000000000000, -1000000000000])
        data = writer.finish()

        field = next(Reader(data))
        assert field.packed_sint64s() == [0, 1, -1, 1000000000000, -1000000000000]

    def test_packed_bools(self):
        writer = Writer()
        writer.packed_bools(1, [True, False, True, True, False, False])
        data = writer.finish()

        field = next(Reader(data))
        assert field.packed_bools() == [True, False, True, True, False, False]

    def test_packed_fixed32s(self):
        writer = Writer()
        writer.packed_fixed32s(1, [0, 1, 0xDEADBEEF, 0xFFFFFFFF])
        data = writer.finish()

        field = next(Reader(data))
        assert field.packed_fixed32s() == [0, 1, 0xDEADBEEF, 0xFFFFFFFF]

    def test_packed_sfixed32s(self):
        writer = Writer()
        writer.packed_sfixed32s(1, [0, 1, -1, 2147483647, -2147483648])
        data = writer.finish()

        field = next(Reader(data))
        assert field.packed_sfixed32s() == [0, 1, -1, 2147483647, -2147483648]

    def test_packed_floats(self):
        writer = Writer()
        writer.packed_floats(1, [0.0, 1.0, -1.0, 3.14, -2.5])
        data = writer.finish()

        field = next(Reader(data))
        result = field.packed_floats()
        assert len(result) == 5
        assert result[0] == 0.0
        assert result[1] == 1.0
        assert result[2] == -1.0
        assert abs(result[3] - 3.14) < 1e-5
        assert result[4] == -2.5

    def test_packed_fixed64s(self):
        writer = Writer()
        writer.packed_fixed64s(1, [0, 1, 0xDEADBEEFCAFEBABE, 0xFFFFFFFFFFFFFFFF])
        data = writer.finish()

        field = next(Reader(data))
        assert field.packed_fixed64s() == [0, 1, 0xDEADBEEFCAFEBABE, 0xFFFFFFFFFFFFFFFF]

    def test_packed_sfixed64s(self):
        writer = Writer()
        writer.packed_sfixed64s(
            1, [0, 1, -1, 9223372036854775807, -9223372036854775808]
        )
        data = writer.finish()

        field = next(Reader(data))
        assert field.packed_sfixed64s() == [
            0,
            1,
            -1,
            9223372036854775807,
            -9223372036854775808,
        ]

    def test_packed_doubles(self):
        writer = Writer()
        writer.packed_doubles(1, [0.0, 1.0, -1.0, 3.14159265358979, 1e100])
        data = writer.finish()

        field = next(Reader(data))
        result = field.packed_doubles()
        assert len(result) == 5
        assert result[0] == 0.0
        assert result[1] == 1.0
        assert result[2] == -1.0
        assert abs(result[3] - 3.14159265358979) < 1e-10
        assert result[4] == 1e100

    def test_packed_empty_list_not_written(self):
        writer = Writer()
        writer.packed_int32s(1, [])  # Empty - should not be written
        writer.int32(2, 42)  # Add a field so we have something
        data = writer.finish()

        fields = list(Reader(data))
        assert len(fields) == 1
        assert fields[0].number == 2

    def test_packed_single_element(self):
        writer = Writer()
        writer.packed_int32s(1, [42])
        data = writer.finish()

        field = next(Reader(data))
        assert field.packed_int32s() == [42]


class TestWriterFieldNumbers:
    """Tests for various field numbers."""

    def test_small_field_numbers(self):
        writer = Writer()
        writer.int32(1, 1)
        writer.int32(2, 2)
        writer.int32(15, 15)
        data = writer.finish()

        fields = list(Reader(data))
        assert [f.number for f in fields] == [1, 2, 15]

    def test_large_field_numbers(self):
        writer = Writer()
        writer.int32(16, 16)
        writer.int32(100, 100)
        writer.int32(1000, 1000)
        writer.int32(100000, 100000)
        data = writer.finish()

        fields = list(Reader(data))
        assert [f.number for f in fields] == [16, 100, 1000, 100000]

    def test_max_field_number(self):
        # Maximum field number is 2^29 - 1 = 536870911
        writer = Writer()
        writer.int32(536870911, 42)
        data = writer.finish()

        field = next(Reader(data))
        assert field.number == 536870911
        assert field.int32() == 42

    def test_fields_out_of_order(self):
        # Protobuf allows fields in any order
        writer = Writer()
        writer.int32(3, 3)
        writer.int32(1, 1)
        writer.int32(2, 2)
        data = writer.finish()

        fields = list(Reader(data))
        assert [f.number for f in fields] == [3, 1, 2]
        assert [f.int32() for f in fields] == [3, 1, 2]


class TestWriterRepeatedFields:
    """Tests for non-packed repeated fields."""

    def test_repeated_int32(self):
        writer = Writer()
        writer.int32(1, 10)
        writer.int32(1, 20)
        writer.int32(1, 30)
        data = writer.finish()

        fields = list(Reader(data))
        assert len(fields) == 3
        assert all(f.number == 1 for f in fields)
        assert [f.int32() for f in fields] == [10, 20, 30]

    def test_repeated_string(self):
        writer = Writer()
        writer.string(1, "one")
        writer.string(1, "two")
        writer.string(1, "three")
        data = writer.finish()

        fields = list(Reader(data))
        assert len(fields) == 3
        assert [f.string() for f in fields] == ["one", "two", "three"]

    def test_repeated_nested_message(self):
        writer = Writer()
        with writer.message(1) as msg:
            msg.int32(1, 1)
        with writer.message(1) as msg:
            msg.int32(1, 2)
        with writer.message(1) as msg:
            msg.int32(1, 3)
        data = writer.finish()

        fields = list(Reader(data))
        assert len(fields) == 3
        values = [list(f.message())[0].int32() for f in fields]
        assert values == [1, 2, 3]


class TestWriterMixedTypes:
    """Tests for messages with mixed field types."""

    def test_all_types_in_one_message(self):
        writer = Writer()
        writer.int32(1, -42)
        writer.int64(2, 1000000000000)
        writer.uint32(3, 4294967295)
        writer.uint64(4, 18446744073709551615)
        writer.sint32(5, -100)
        writer.sint64(6, -1000000000000)
        writer.bool(7, True)
        writer.enum(8, 3)
        writer.fixed64(9, 0xDEADBEEFCAFEBABE)
        writer.sfixed64(10, -1)
        writer.double(11, 3.14)
        writer.fixed32(12, 0xDEADBEEF)
        writer.sfixed32(13, -1)
        writer.float(14, 2.5)
        writer.string(15, "hello")
        writer.bytes(16, b"\x00\x01\x02")
        data = writer.finish()

        fields = {f.number: f for f in Reader(data)}

        assert fields[1].int32() == -42
        assert fields[2].int64() == 1000000000000
        assert fields[3].uint32() == 4294967295
        assert fields[4].uint64() == 18446744073709551615
        assert fields[5].sint32() == -100
        assert fields[6].sint64() == -1000000000000
        assert fields[7].bool() is True
        assert fields[8].enum() == 3
        assert fields[9].fixed64() == 0xDEADBEEFCAFEBABE
        assert fields[10].sfixed64() == -1
        assert abs(fields[11].double() - 3.14) < 1e-10
        assert fields[12].fixed32() == 0xDEADBEEF
        assert fields[13].sfixed32() == -1
        assert abs(fields[14].float() - 2.5) < 1e-5
        assert fields[15].string() == "hello"
