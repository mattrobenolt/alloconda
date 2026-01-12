# Compatibility Assessment: Python 3.7 – 3.9

Based on the `@hasDecl` audit and code review, supporting older Python versions (3.7, 3.8, 3.9) requires **almost no code changes**. The project is already engineered with "graceful degradation" and polyfills that support these older versions.

## Verdict
**High Feasibility / Low Effort.** 
The code currently contains the necessary guards and fallback logic to support versions as far back as 3.7 (and possibly 3.4).

## Detailed Findings

### 1. Python 3.9 Support (`PyObject_CallNoArgs`)
*   **Requirement:** `PyObject_CallNoArgs` was added in 3.9.
*   **Current State:** `src/ffi.zig` already guards this usage.
*   **Fallback:** It gracefully falls back to creating an empty tuple and calling `PyObject_CallObject`.
*   **Action:** None. Works out of the box for < 3.9.

### 2. Python 3.10 Support (`Py_IsNone`)
*   **Requirement:** `Py_IsNone` was added in 3.10.
*   **Current State:** `src/types.zig` already guards this usage.
*   **Fallback:** It falls back to `obj == ffi.pyNone()`, which relies on `_Py_NoneStruct` (available since the beginning of time).
*   **Action:** None. Works out of the box for < 3.10.

### 3. Python 3.7+ Base Support
*   **Finalization:** `Py_tp_finalize` (PEP 442) was added in 3.4.
    *   Since 3.7 > 3.4, the primary code path using `Py_tp_finalize` will be active.
    *   The `else` branch using `Py_tp_del` will remain dead code for 3.7+, which is fine.
*   **GC & Tracking:** `PyObject_GC_UnTrack` and `Py_TPFLAGS_HAVE_GC` are available since 2.x/3.x early days.
    *   These will work natively on 3.7.
*   **Dict Offsets:** `Py_tp_dictoffset` is ancient (2.2+).
    *   Will work natively.

## Implications for "Clean Up"
The original goal of Issue #41 was to *remove* unnecessary guards to clean up the code.
*   **If we want to support 3.7-3.9:** We **MUST NOT** remove the guards for `Py_IsNone` and `PyObject_CallNoArgs`. We should explicitly mark them as "Required for < 3.10 compatibility".
*   **Guards safe to remove (even for 3.7):**
    *   `Py_tp_finalize` (Always true for 3.7+)
    *   `PyObject_CallFinalizerFromDealloc` (Always true for 3.7+)
    *   `PyObject_GC_UnTrack` (Always true for 3.7+)
    *   `Py_TPFLAGS_HAVE_GC` (Always true for 3.7+)
    *   `Py_tp_dictoffset` (Always true for 3.7+)

## Python 3.6 Assessment

**Verdict: High Feasibility (Silver Path).**

You asked about the relevance of older systems in 2026:

1.  **Ubuntu 18.04 (Zombie Tier):** You are right—standard support ended in 2023. It is currently in **ESM (Expanded Security Maintenance)** until 2028. Unless you have users on paid Ubuntu Pro plans running legacy stacks, this is likely irrelevant to you.
2.  **RHEL 8 (Production Tier):** This is still very much alive. It is in **Maintenance Support until May 2029**. Many enterprise environments treat RHEL 8 as their current "stable" baseline and have not yet migrated to RHEL 9.

**Why is 3.6 not "Golden"?**
While the C API is largely compatible, 3.7 introduced modern standards that 3.6 lacks:
1.  **`contextvars` (PEP 567):** 3.6 requires the `aiocontextvars` backport for async safety.
2.  **`async`/`await` keywords:** In 3.6 these were "soft" keywords. In 3.7 they became reserved.
3.  **`PySlice_GetIndicesEx`:** This function had a messy history in 3.6 (ABI breaks). 3.7 stabilized it.

**Recommendation for Alloconda:**
If you want to support **Enterprise Linux (RHEL 8)**, you should keep 3.6. If you don't care about the corporate "Maintenance Support" crowd, 3.7 is a much cleaner baseline. Since the cost to support 3.6 is currently **zero** (the guards already exist), I recommend keeping it but not going any further back.

## Legacy Version Assessment (< 3.6)

If you wish to push support back further than 3.6, here is the breakdown of complexity:

| Version Range | Feasibility | Key Blockers / Complexities |
| :--- | :--- | :--- |
| **3.4 – 3.5** | **Medium** | **Async:** `async`/`await` syntax added in 3.5. 3.4 is the absolute floor for "modern" tooling (pip is standard). <br> **Finalization:** 3.4 introduced `Py_tp_finalize`. Before this, unsafe `tp_del` was used. |
| **3.3** | **Hard** | **Unicode Overhaul (PEP 393):** 3.3 completely redesigned the internal string representation (Flexible String Representation). The C API for Unicode changed significantly. While `PyUnicode_Check` exists, underlying access patterns might differ or be less efficient. <br> **Virtual Environments:** The `venv` module was standardized here. |
| **3.2** | **Very Hard** | **Stable ABI:** 3.2 introduced the Stable ABI (`Py_LIMITED_API`). Targeting versions before this loses that guarantee (if relevant). <br> **Strings:** Still using the older `Py_UNICODE` (wide char) vs UTF-8 confusion. |
| **3.0 – 3.1** | **Extreme** | **Text vs Bytes Migration:** The dust hadn't settled from the 2 -> 3 transition. Many C APIs were in flux. Support is strongly discouraged. |

### Recommendation: Cutoff at 3.7 (or possibly 3.4)

1.  **Golden Path (3.7+):** Effectively "free" as detailed above.
2.  **Silver Path (3.4+):** Doable. The main "modern" C API features (reliable finalization, pip availability, decent `venv`) are present. The `tp_del` fallback logic in `src/module.zig` would actually be used for 3.0-3.3, so the code is *technically* there, but testing it is a pain.
3.  **The "Dragons" Zone (< 3.4):** Not worth the effort. The differences in string handling and object finalization create a minefield of potential segfaults and subtle bugs that are hard to CI against.
