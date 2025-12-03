const ffi = @import("alloconda").ffi;
const c = ffi.c;

fn add(a: i64, b: i64) i64 {
    return a + b;
}

fn py_add(self: ?*c.PyObject, args: ?*c.PyObject) callconv(.c) ?*c.PyObject {
    _ = self;
    var a: c_longlong = 0;
    var b: c_longlong = 0;

    if (c.PyArg_ParseTuple(args, "LL", &a, &b) == 0) {
        return null;
    }

    const result = add(a, b);
    return c.PyLong_FromLongLong(result);
}

var methods = [_]c.PyMethodDef{
    .{
        .ml_name = "add",
        .ml_meth = @ptrCast(&py_add),
        .ml_flags = c.METH_VARARGS,
        .ml_doc = "Add two integers",
    },
    .{ .ml_name = null, .ml_meth = null, .ml_flags = 0, .ml_doc = null },
};

var module_def = c.PyModuleDef{
    .m_base = ffi.PyModuleDef_HEAD_INIT, // Our hand-written constant
    .m_name = "zigadd",
    .m_doc = "A Zig extension module",
    .m_size = -1,
    .m_methods = &methods,
    .m_slots = null,
    .m_traverse = null,
    .m_clear = null,
    .m_free = null,
};

pub export fn PyInit_zigadd() ?*c.PyObject {
    return c.PyModule_Create(&module_def);
}
