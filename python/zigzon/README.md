# zigzon

ZON (Zig Object Notation) codec implemented in Zig and exposed to Python.

## Usage

```python
import zigzon

data = '.{ .name = "zig", .nums = .{ 1, 2, 3 }, .ok = true, .nil = null }'
value = zigzon.loads(data)
print(value["name"])

text = zigzon.dumps({"a": 1, "b": [True, None]})
print(text)

with open("data.zon", "w", encoding="utf-8") as handle:
    zigzon.dump({"hello": "zig"}, handle)

with open("data.zon", "r", encoding="utf-8") as handle:
    value = zigzon.load(handle)
    print(value)

doc = zigzon.ZonDocument()
doc.set_text('.{ .hello = "world" }')
print(doc.loads())
```
