# zigadd

Tiny Zig-backed extension module used to exercise Alloconda.

## Highlights

- Keyword arguments via `add_named`.
- Bytes/list/dict helpers: `bytes_len`, `sum_list`, `dict_get`.
- Error mapping: `divide` raises `ZeroDivisionError`.
- Class support: `Adder` exposes instance methods.
- Type hints live in `zigadd/_zigadd.pyi` (re-exported via `__init__.pyi`).

## Quick usage

```python
import zigadd

zigadd.add(1, 2)
zigadd.add_named(a=1, b=2, c=3)
zigadd.bytes_len(b"zig")
zigadd.sum_list([1, 2, 3])
zigadd.dict_get({"a": 1}, "a")

adder = zigadd.Adder()
adder.add(2, 5)
adder.identity()
```
