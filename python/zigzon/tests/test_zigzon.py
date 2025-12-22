import math

import zigzon


def test_loads_basic() -> None:
    data = '.{ .name = "zig", .nums = .{ 1, 2, 3 }, .ok = true, .nil = null }'
    value = zigzon.loads(data)
    assert value["name"] == "zig"
    assert value["nums"] == [1, 2, 3]
    assert value["ok"] is True
    assert value["nil"] is None


def test_loads_literals() -> None:
    assert zigzon.loads(".foo") == "foo"
    assert zigzon.loads("'a'") == "a"


def test_dumps_roundtrip() -> None:
    payload = {"a": 1, "b": [True, None, 3.5], "c": "hi"}
    text = zigzon.dumps(payload)
    assert zigzon.loads(text) == payload


def test_dump_load_file(tmp_path) -> None:
    payload = {"k": "v", "n": 2}
    path = tmp_path / "data.zon"
    with path.open("w", encoding="utf-8") as handle:
        zigzon.dump(payload, handle)
    with path.open("r", encoding="utf-8") as handle:
        assert zigzon.load(handle) == payload


def test_aliases() -> None:
    data = ".{ .x = 1 }"
    assert zigzon.to_python(data) == zigzon.loads(data)
    assert zigzon.from_python({"x": 1}) == zigzon.dumps({"x": 1})


def test_float_inf_nan() -> None:
    text = zigzon.dumps([float("inf"), float("-inf"), float("nan")])
    value = zigzon.loads(text)
    assert value[0] == float("inf")
    assert value[1] == float("-inf")
    assert math.isnan(value[2])
