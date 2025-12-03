const std = @import("std");
const mem = std.mem;

pub const c = @cImport({
    @cDefine("PY_SSIZE_T_CLEAN", {});
    @cInclude("Python.h");
});

/// PyModuleDef_HEAD_INIT - initializer for PyModuleDef.m_base
pub const PyModuleDef_HEAD_INIT = mem.zeroes(c.PyModuleDef_Base);
