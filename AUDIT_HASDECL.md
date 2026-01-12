# Audit of `@hasDecl` usage for CPython symbols

This report inventories all usages of `@hasDecl` guarding CPython symbols in the codebase.
The project currently supports Python 3.10 – 3.14.

## `src/module.zig`

| Symbol | Introduced In | Status for 3.10+ | Notes |
| :--- | :--- | :--- | :--- |
| `Py_tp_finalize` | **3.4** (PEP 442) | **Always Available** | Unnecessary guard. |
| `PyObject_CallFinalizerFromDealloc` | **3.4** (PEP 442) | **Always Available** | Unnecessary guard. |
| `PyObject_GC_UnTrack` | **2.7** | **Always Available** | Unnecessary guard. |
| `Py_TPFLAGS_HAVE_GC` | **2.0** | **Always Available** | Unnecessary guard. |
| `Py_tp_dictoffset` | **2.2** | **Always Available** | Unnecessary guard. Used for clearing dict on < 3.12 (managed dicts). The logic might still be needed, but the *declaration check* is likely always true. |

## `src/types.zig`

| Symbol | Introduced In | Status for 3.10+ | Notes |
| :--- | :--- | :--- | :--- |
| `Py_IsNone` | **3.10** | **Always Available** | Introduced in 3.10. Since minimum is 3.10, this is always available. |

## `src/ffi.zig`

### Constants

| Symbol | Introduced In | Status for 3.10+ | Notes |
| :--- | :--- | :--- | :--- |
| `Py_GetConstantBorrowed` | **3.13** | **Conditional** | Required for 3.13+ optimizations. |
| `Py_CONSTANT_NONE` | **3.13** | **Conditional** | Required for 3.13+. |
| `_Py_NoneStruct` | **Ancient** | **Always Available** | Fallback for < 3.13. |
| `Py_CONSTANT_NOT_IMPLEMENTED` | **3.13** | **Conditional** | Required for 3.13+. |
| `_Py_NotImplementedStruct` | **Ancient** | **Always Available** | Fallback for < 3.13. |

### Call API

| Symbol | Introduced In | Status for 3.10+ | Notes |
| :--- | :--- | :--- | :--- |
| `PyObject_CallNoArgs` | **3.9** | **Always Available** | Unnecessary guard. |

### Managed Dicts & GC

| Symbol | Introduced In | Status for 3.10+ | Notes |
| :--- | :--- | :--- | :--- |
| `Py_TPFLAGS_MANAGED_DICT` | **3.11** | **Conditional** | Required for 3.11+ managed dict support. |
| `PyObject_VisitManagedDict` | **3.12** | **Conditional** | Required for 3.12+. |
| `_PyObject_VisitManagedDict` | **3.12** | **Conditional** | Private API in 3.12. |
| `PyObject_ClearManagedDict` | **3.13** | **Conditional** | Public in 3.13. |
| `_PyObject_ClearManagedDict` | **3.12** | **Conditional** | Private API in 3.12. |
| `PyObject_GC_Del` | **3.12** | **Conditional** | Required for 3.12+ (replaces `PyObject_GC_UnTrack` + `PyObject_Free` pattern in some contexts). |

## Recommendations

1.  **Remove guards for Pre-3.10 symbols:**
    - `Py_tp_finalize`
    - `PyObject_CallFinalizerFromDealloc`
    - `PyObject_GC_UnTrack` / `Py_TPFLAGS_HAVE_GC`
    - `Py_tp_dictoffset`
    - `PyObject_CallNoArgs`
    - `Py_IsNone` (Can unconditionally use, or fallback to macro if needed, but symbol exists in 3.10+)

2.  **Retain guards for 3.11/3.12/3.13 features:**
    - Keep `Py_GetConstantBorrowed` paths.
    - Keep Managed Dict logic (`Py_TPFLAGS_MANAGED_DICT` and friends).
    - Keep `PyObject_GC_Del`.

## References

- **PEP 442 (Safe object finalization)**: https://peps.python.org/pep-0442/ (Py 3.4)
- **PyObject_CallNoArgs**: https://docs.python.org/3/c-api/call.html#c.PyObject_CallNoArgs (Py 3.9)
- **Py_IsNone**: https://docs.python.org/3/c-api/none.html#c.Py_IsNone (Py 3.10)
- **Managed Dicts**: https://docs.python.org/3/c-api/typeobj.html#c.Py_TPFLAGS_MANAGED_DICT (Py 3.11)
- **PyObject_GC_Del**: https://docs.python.org/3/c-api/gc.html#c.PyObject_GC_Del (Py 3.12)
- **Py_GetConstantBorrowed**: https://docs.python.org/3/c-api/allocation.html#c.Py_GetConstantBorrowed (Py 3.13)
