const std = @import("std");
const fmt = std.fmt;
const mem = std.mem;

const errors = @import("errors.zig");
const PyError = errors.PyError;
const ffi = @import("ffi.zig");
const c = ffi.c;
const cstr = ffi.cstr;
const PyObject = ffi.PyObject;
const PyMem = ffi.PyMem;
const PyModule = ffi.PyModule;
const PyType = ffi.PyType;
const PyDict = ffi.PyDict;
const PyUnicode = ffi.PyUnicode;
const PyManagedDict = ffi.PyManagedDict;
const PyGC = ffi.PyGC;
const method_mod = @import("method.zig");
const buildMethodDefs = method_mod.buildMethodDefs;
const callSlotFromSpec = method_mod.callSlotFromSpec;
const newSlotFromSpec = method_mod.newSlotFromSpec;
const delSlotFromSpec = method_mod.delSlotFromSpec;
const initSlotFromSpec = method_mod.initSlotFromSpec;
const unarySlotFromSpec = method_mod.unarySlotFromSpec;
const boolBinarySlotFromSpec = method_mod.boolBinarySlotFromSpec;
const hashSlotFromSpec = method_mod.hashSlotFromSpec;
const getAttrSlotFromSpecs = method_mod.getAttrSlotFromSpecs;
const setAttrSlotFromSpecs = method_mod.setAttrSlotFromSpecs;
const descrGetSlotFromSpec = method_mod.descrGetSlotFromSpec;
const descrSetSlotFromSpecs = method_mod.descrSetSlotFromSpecs;
const seqItemSlotFromSpec = method_mod.seqItemSlotFromSpec;
const seqRepeatSlotFromSpec = method_mod.seqRepeatSlotFromSpec;
const seqAssItemSlotFromSpecs = method_mod.seqAssItemSlotFromSpecs;
const richCompareSlotFromSpecs = method_mod.richCompareSlotFromSpecs;
const mappingSlotsFromSpecs = method_mod.mappingSlotsFromSpecs;
const numberSlotsFromSpecs = method_mod.numberSlotsFromSpecs;
const py_types = @import("types.zig");
const toPy = py_types.toPy;

// ============================================================================
// Type storage for __dict__ support
// ============================================================================

const DefaultTypeStorage = extern struct {
    head: c.PyObject,
    dict: ?*c.PyObject,
};
const DefaultDictOffset: c.Py_ssize_t = @offsetOf(DefaultTypeStorage, "dict");

// Manual definition of PyMemberDef since cimport marks it as opaque.
// This matches the C struct in structmember.h.
const PyMemberDef = extern struct {
    name: ?[*:0]const u8,
    type: c_int,
    offset: c.Py_ssize_t,
    flags: c_int,
    doc: ?[*:0]const u8,
};

// PyMemberDef for __dict__ on Python <3.12 (where MANAGED_DICT isn't available).
// T_OBJECT_EX = 16, READONLY would be 1 but we want read-write so flags = 0.
const T_OBJECT_EX: c_int = 16;
const dictMemberDef: [2]PyMemberDef = .{
    .{
        .name = "__dict__",
        .type = T_OBJECT_EX,
        .offset = DefaultDictOffset,
        .flags = 0,
        .doc = null,
    },
    .{ .name = null, .type = 0, .offset = 0, .flags = 0, .doc = null },
};

fn managedDictGcEnabled() bool {
    if (!@hasDecl(c, "Py_TPFLAGS_MANAGED_DICT")) return false;
    const has_visit = @hasDecl(c, "PyObject_VisitManagedDict") or @hasDecl(c, "_PyObject_VisitManagedDict");
    const has_clear = @hasDecl(c, "PyObject_ClearManagedDict") or @hasDecl(c, "_PyObject_ClearManagedDict");
    return has_visit and has_clear and @hasDecl(c, "PyObject_GC_Del");
}

// ============================================================================
// Module definition
// ============================================================================

/// Python extension module definition and constructor helpers.
pub const Module = struct {
    name: []const u8,
    doc: []const u8,
    inner: c.PyModuleDef,
    types: ?[]const Class = null,
    attrs: ?[]const Attribute = null,

    /// Create a module definition with name and docstring.
    pub fn init(comptime name: []const u8, comptime doc: []const u8) Module {
        return .{
            .name = name,
            .doc = doc,
            .inner = .{
                .m_base = ffi.PyModuleDef_HEAD_INIT,
                .m_name = cstr(name),
                .m_doc = cstr(doc),
                .m_size = -1,
                .m_methods = null,
                .m_slots = null,
                .m_traverse = null,
                .m_clear = null,
                .m_free = null,
            },
            .types = null,
        };
    }

    /// Attach a static method table.
    pub fn withMethods(self: Module, comptime methods: [*c]const c.PyMethodDef) Module {
        var next = self;
        next.inner.m_methods = @constCast(methods);
        return next;
    }

    /// Build and attach methods from a struct literal.
    pub fn with(self: Module, comptime methods: anytype) Module {
        const defs = comptime buildMethodDefs(methods);
        return self.withMethods(&defs);
    }

    /// Attach module-level attributes to be registered when the module is created.
    pub fn withAttrs(self: Module, comptime attrs: anytype) Module {
        const defs = comptime buildAttributeDefs(attrs);
        var next: Module = self;
        next.attrs = &defs;
        return next;
    }

    /// Attach classes to be registered when the module is created.
    pub fn withTypes(comptime self: Module, comptime types: anytype) Module {
        const defs = comptime buildClassDefs(self.name, types);
        var next = self;
        next.types = &defs;
        return next;
    }

    /// Create the Python module object.
    pub fn create(self: *const Module) PyError!*c.PyObject {
        const def_ptr = try PyMem.alloc(@sizeOf(c.PyModuleDef));
        errdefer PyMem.free(def_ptr);

        const def: *c.PyModuleDef = @ptrCast(@alignCast(def_ptr));
        def.* = self.inner;

        const module_obj = try PyModule.create(def);
        errdefer PyObject.decRef(module_obj);

        if (self.attrs) |attr_list| {
            for (attr_list) |attr| {
                const value = try attr.make();
                errdefer PyObject.decRef(value);
                try PyModule.addObject(module_obj, attr.name, value);
            }
        }

        if (self.types) |type_list| {
            for (type_list) |class_def| {
                try class_def.addToModule(module_obj, self.name);
            }
        }
        return module_obj;
    }
};

fn moduleName() []const u8 {
    const options = @import("alloconda_build_options");
    if (!@hasDecl(options, "module_name")) {
        @compileError("Module name not set. Set .name in addPythonLibrary.");
    }
    const name = options.module_name;
    if (name.len == 0) {
        @compileError("Module name cannot be empty. Set .name in addPythonLibrary.");
    }
    return name;
}

/// Convenience module builder.
pub fn module(
    comptime doc: [:0]const u8,
    comptime methods: anytype,
) Module {
    return Module.init(moduleName(), doc).with(methods);
}

// ============================================================================
// Module attribute helpers
// ============================================================================

const Attribute = struct {
    name: [:0]const u8,
    make: *const fn () PyError!*c.PyObject,
};

fn buildAttributeDefs(comptime attrs: anytype) [attrCount(attrs)]Attribute {
    const info = @typeInfo(@TypeOf(attrs));
    if (info != .@"struct") {
        @compileError("attrs must be a struct literal");
    }

    const fields = info.@"struct".fields;
    var defs: [fields.len]Attribute = undefined;

    inline for (fields, 0..) |field, i| {
        defs[i] = buildAttributeDef(field.name, @field(attrs, field.name));
    }

    return defs;
}

fn buildAttributeDef(comptime field_name: []const u8, comptime value: anytype) Attribute {
    const Value = @TypeOf(value);
    const Wrapper = struct {
        const stored: Value = value;

        fn make() PyError!*c.PyObject {
            return toPy(Value, stored);
        }
    };
    return .{
        .name = cstr(field_name),
        .make = &Wrapper.make,
    };
}

fn attrCount(comptime attrs: anytype) usize {
    const info = @typeInfo(@TypeOf(attrs));
    if (info != .@"struct") {
        @compileError("attrs must be a struct literal");
    }
    return info.@"struct".fields.len;
}

// ============================================================================
// Class definition
// ============================================================================

/// Python class definition used with Module.withTypes.
pub const Class = struct {
    name: [:0]const u8,
    attr_name: [:0]const u8,
    slots: [*c]const c.PyType_Slot,
    doc: ?[:0]const u8,
    is_basetype: bool,

    fn create(self: *const Class) PyError!*c.PyObject {
        var spec = c.PyType_Spec{
            .name = @ptrCast(self.name.ptr),
            .basicsize = @intCast(classBasicSize()),
            .itemsize = 0,
            .flags = classFlags(self.is_basetype),
            .slots = @constCast(self.slots),
        };
        return PyType.fromSpec(&spec);
    }

    fn addToModule(self: *const Class, module_obj: *c.PyObject, module_name: []const u8) PyError!void {
        const type_obj = try self.create();
        var owns_ref = true;
        errdefer if (owns_ref) PyObject.decRef(type_obj);

        try setTypeModule(type_obj, module_name);
        // For Python <3.12, we need to set tp_dictoffset manually after type creation.
        // This enables attribute storage via __dict__. The slot API doesn't support
        // setting tp_dictoffset directly, so we modify the type object here.
        if (comptime !managedDictGcEnabled()) {
            const tp: *c.PyTypeObject = @ptrCast(type_obj);
            tp.tp_dictoffset = DefaultDictOffset;
            // Set __doc__ via the attribute API for heap types on Python <3.12.
            // For heap types, Python stores __doc__ in the type dict, not tp_doc.
            // Setting tp_doc directly doesn't update the dict entry.
            if (self.doc) |doc_text| {
                const doc_obj = PyUnicode.fromSlice(doc_text[0..doc_text.len]) catch null;
                if (doc_obj) |doc| {
                    defer PyObject.decRef(doc);
                    _ = PyObject.setAttrString(type_obj, cstr("__doc__"), doc) catch {};
                }
                // If creating the string fails, we silently leave __doc__ as None.
            }
        }
        try PyModule.addObject(module_obj, self.attr_name, type_obj);
        owns_ref = false;
    }
};

const SlotConfig = struct {
    call: ?*anyopaque = null,
    init: ?*anyopaque = null,
    new: ?*anyopaque = null,
    del: ?*anyopaque = null,
    repr: ?*anyopaque = null,
    str: ?*anyopaque = null,
    hash: ?*anyopaque = null,
    richcompare: ?*anyopaque = null,
    iter: ?*anyopaque = null,
    iternext: ?*anyopaque = null,
    getattro: ?*anyopaque = null,
    setattro: ?*anyopaque = null,
    descr_get: ?*anyopaque = null,
    descr_set: ?*anyopaque = null,
    mp_length: ?*anyopaque = null,
    mp_subscript: ?*anyopaque = null,
    mp_ass_subscript: ?*anyopaque = null,
    sq_length: ?*anyopaque = null,
    sq_item: ?*anyopaque = null,
    sq_ass_item: ?*anyopaque = null,
    sq_contains: ?*anyopaque = null,
    sq_concat: ?*anyopaque = null,
    sq_repeat: ?*anyopaque = null,
    sq_inplace_concat: ?*anyopaque = null,
    sq_inplace_repeat: ?*anyopaque = null,
    nb_add: ?*anyopaque = null,
    nb_subtract: ?*anyopaque = null,
    nb_multiply: ?*anyopaque = null,
    nb_true_divide: ?*anyopaque = null,
    nb_floor_divide: ?*anyopaque = null,
    nb_remainder: ?*anyopaque = null,
    nb_power: ?*anyopaque = null,
    nb_divmod: ?*anyopaque = null,
    nb_matrix_multiply: ?*anyopaque = null,
    nb_negative: ?*anyopaque = null,
    nb_positive: ?*anyopaque = null,
    nb_absolute: ?*anyopaque = null,
    nb_invert: ?*anyopaque = null,
    nb_and: ?*anyopaque = null,
    nb_or: ?*anyopaque = null,
    nb_xor: ?*anyopaque = null,
    nb_lshift: ?*anyopaque = null,
    nb_rshift: ?*anyopaque = null,
    nb_int: ?*anyopaque = null,
    nb_float: ?*anyopaque = null,
    nb_index: ?*anyopaque = null,
    nb_bool: ?*anyopaque = null,
    nb_inplace_add: ?*anyopaque = null,
    nb_inplace_subtract: ?*anyopaque = null,
    nb_inplace_multiply: ?*anyopaque = null,
    nb_inplace_true_divide: ?*anyopaque = null,
    nb_inplace_floor_divide: ?*anyopaque = null,
    nb_inplace_remainder: ?*anyopaque = null,
    nb_inplace_power: ?*anyopaque = null,
    nb_inplace_and: ?*anyopaque = null,
    nb_inplace_or: ?*anyopaque = null,
    nb_inplace_xor: ?*anyopaque = null,
    nb_inplace_lshift: ?*anyopaque = null,
    nb_inplace_rshift: ?*anyopaque = null,
    nb_inplace_matrix_multiply: ?*anyopaque = null,
};

fn buildSlotConfig(comptime methods: anytype) SlotConfig {
    const MethodsType = @TypeOf(methods);
    const call_slot = comptime findCallSlot(methods);

    const init_slot = if (comptime @hasField(MethodsType, "__init__")) blk: {
        const spec = @field(methods, "__init__");
        const Func = @TypeOf(spec.func);
        const kind = @TypeOf(spec).kind;
        break :blk initSlotFromSpec(Func, kind, spec);
    } else null;

    const new_slot = if (comptime @hasField(MethodsType, "__new__")) blk: {
        const spec = @field(methods, "__new__");
        const Func = @TypeOf(spec.func);
        const kind = @TypeOf(spec).kind;
        break :blk newSlotFromSpec(Func, kind, spec);
    } else null;

    const del_slot = if (comptime @hasField(MethodsType, "__del__")) blk: {
        const spec = @field(methods, "__del__");
        const Func = @TypeOf(spec.func);
        const kind = @TypeOf(spec).kind;
        break :blk delSlotFromSpec(Func, kind, spec);
    } else null;

    const repr_slot = if (comptime @hasField(MethodsType, "__repr__")) blk: {
        const spec = @field(methods, "__repr__");
        const Func = @TypeOf(spec.func);
        const kind = @TypeOf(spec).kind;
        break :blk unarySlotFromSpec(Func, kind, spec, "__repr__");
    } else null;

    const str_slot = if (comptime @hasField(MethodsType, "__str__")) blk: {
        const spec = @field(methods, "__str__");
        const Func = @TypeOf(spec.func);
        const kind = @TypeOf(spec).kind;
        break :blk unarySlotFromSpec(Func, kind, spec, "__str__");
    } else null;

    const hash_slot = if (comptime @hasField(MethodsType, "__hash__")) blk: {
        const spec = @field(methods, "__hash__");
        const Func = @TypeOf(spec.func);
        const kind = @TypeOf(spec).kind;
        break :blk hashSlotFromSpec(Func, kind, spec, "__hash__");
    } else null;

    const iter_slot = if (comptime @hasField(MethodsType, "__iter__")) blk: {
        const spec = @field(methods, "__iter__");
        const Func = @TypeOf(spec.func);
        const kind = @TypeOf(spec).kind;
        break :blk unarySlotFromSpec(Func, kind, spec, "__iter__");
    } else null;

    const iternext_slot = if (comptime @hasField(MethodsType, "__next__")) blk: {
        const spec = @field(methods, "__next__");
        const Func = @TypeOf(spec.func);
        const kind = @TypeOf(spec).kind;
        break :blk unarySlotFromSpec(Func, kind, spec, "__next__");
    } else null;

    const GetAttrSpecs = struct {
        pub const getattribute = if (@hasField(MethodsType, "__getattribute__"))
            @field(methods, "__getattribute__")
        else
            null;
        pub const getattr = if (@hasField(MethodsType, "__getattr__"))
            @field(methods, "__getattr__")
        else
            null;
    };

    const getattro_slot = getAttrSlotFromSpecs(GetAttrSpecs);

    const SetAttrSpecs = struct {
        pub const set = if (@hasField(MethodsType, "__setattr__"))
            @field(methods, "__setattr__")
        else
            null;
        pub const del = if (@hasField(MethodsType, "__delattr__"))
            @field(methods, "__delattr__")
        else
            null;
    };

    const setattro_slot = setAttrSlotFromSpecs(SetAttrSpecs);

    const descr_get_slot = if (comptime @hasField(MethodsType, "__get__")) blk: {
        const spec = @field(methods, "__get__");
        const Func = @TypeOf(spec.func);
        const kind = @TypeOf(spec).kind;
        break :blk descrGetSlotFromSpec(Func, kind, spec, "__get__");
    } else null;

    const DescrSetSpecs = struct {
        pub const set = if (@hasField(MethodsType, "__set__")) @field(methods, "__set__") else null;
        pub const del = if (@hasField(MethodsType, "__delete__")) @field(methods, "__delete__") else null;
    };

    const descr_set_slot = descrSetSlotFromSpecs(DescrSetSpecs);

    const contains_slot = if (comptime @hasField(MethodsType, "__contains__")) blk: {
        const spec = @field(methods, "__contains__");
        const Func = @TypeOf(spec.func);
        const kind = @TypeOf(spec).kind;
        break :blk boolBinarySlotFromSpec(Func, kind, spec, "__contains__");
    } else null;

    const RichCompareSpecs = struct {
        pub const eq = if (@hasField(MethodsType, "__eq__")) @field(methods, "__eq__") else null;
        pub const ne = if (@hasField(MethodsType, "__ne__")) @field(methods, "__ne__") else null;
        pub const lt = if (@hasField(MethodsType, "__lt__")) @field(methods, "__lt__") else null;
        pub const le = if (@hasField(MethodsType, "__le__")) @field(methods, "__le__") else null;
        pub const gt = if (@hasField(MethodsType, "__gt__")) @field(methods, "__gt__") else null;
        pub const ge = if (@hasField(MethodsType, "__ge__")) @field(methods, "__ge__") else null;
    };

    const richcompare_slot = richCompareSlotFromSpecs(RichCompareSpecs);

    const MappingSpecs = struct {
        pub const get = if (@hasField(MethodsType, "__getitem__"))
            @field(methods, "__getitem__")
        else
            null;
        pub const set = if (@hasField(MethodsType, "__setitem__"))
            @field(methods, "__setitem__")
        else
            null;
        pub const del = if (@hasField(MethodsType, "__delitem__"))
            @field(methods, "__delitem__")
        else
            null;
        pub const len = if (@hasField(MethodsType, "__len__"))
            @field(methods, "__len__")
        else
            null;
    };

    const mapping_slots = mappingSlotsFromSpecs(MappingSpecs);

    const SequenceSpecs = struct {
        pub const get = if (@hasField(MethodsType, "__getitem__")) @field(methods, "__getitem__") else null;
        pub const set = if (@hasField(MethodsType, "__setitem__")) @field(methods, "__setitem__") else null;
        pub const del = if (@hasField(MethodsType, "__delitem__")) @field(methods, "__delitem__") else null;
        pub const contains = if (@hasField(MethodsType, "__contains__")) @field(methods, "__contains__") else null;
        pub const concat = if (@hasField(MethodsType, "__add__")) @field(methods, "__add__") else null;
        pub const repeat = if (@hasField(MethodsType, "__mul__")) @field(methods, "__mul__") else null;
        pub const inplace_concat = if (@hasField(MethodsType, "__iadd__")) @field(methods, "__iadd__") else null;
        pub const inplace_repeat = if (@hasField(MethodsType, "__imul__")) @field(methods, "__imul__") else null;
    };

    const NumberSpecs = struct {
        pub const add = if (@hasField(MethodsType, "__add__")) @field(methods, "__add__") else null;
        pub const sub = if (@hasField(MethodsType, "__sub__")) @field(methods, "__sub__") else null;
        pub const mul = if (@hasField(MethodsType, "__mul__")) @field(methods, "__mul__") else null;
        pub const truediv = if (@hasField(MethodsType, "__truediv__"))
            @field(methods, "__truediv__")
        else
            null;
        pub const floordiv = if (@hasField(MethodsType, "__floordiv__"))
            @field(methods, "__floordiv__")
        else
            null;
        pub const mod = if (@hasField(MethodsType, "__mod__")) @field(methods, "__mod__") else null;
        pub const pow = if (@hasField(MethodsType, "__pow__")) @field(methods, "__pow__") else null;
        pub const divmod = if (@hasField(MethodsType, "__divmod__")) @field(methods, "__divmod__") else null;
        pub const matmul = if (@hasField(MethodsType, "__matmul__")) @field(methods, "__matmul__") else null;
        pub const neg = if (@hasField(MethodsType, "__neg__")) @field(methods, "__neg__") else null;
        pub const pos = if (@hasField(MethodsType, "__pos__")) @field(methods, "__pos__") else null;
        pub const abs = if (@hasField(MethodsType, "__abs__")) @field(methods, "__abs__") else null;
        pub const invert = if (@hasField(MethodsType, "__invert__")) @field(methods, "__invert__") else null;
        pub const and_op = if (@hasField(MethodsType, "__and__")) @field(methods, "__and__") else null;
        pub const or_op = if (@hasField(MethodsType, "__or__")) @field(methods, "__or__") else null;
        pub const xor_op = if (@hasField(MethodsType, "__xor__")) @field(methods, "__xor__") else null;
        pub const lshift = if (@hasField(MethodsType, "__lshift__")) @field(methods, "__lshift__") else null;
        pub const rshift = if (@hasField(MethodsType, "__rshift__")) @field(methods, "__rshift__") else null;
        pub const as_int = if (@hasField(MethodsType, "__int__")) @field(methods, "__int__") else null;
        pub const as_float = if (@hasField(MethodsType, "__float__")) @field(methods, "__float__") else null;
        pub const as_index = if (@hasField(MethodsType, "__index__")) @field(methods, "__index__") else null;
        pub const bool_method = if (@hasField(MethodsType, "__bool__")) @field(methods, "__bool__") else null;
        pub const iadd = if (@hasField(MethodsType, "__iadd__")) @field(methods, "__iadd__") else null;
        pub const isub = if (@hasField(MethodsType, "__isub__")) @field(methods, "__isub__") else null;
        pub const imul = if (@hasField(MethodsType, "__imul__")) @field(methods, "__imul__") else null;
        pub const itruediv = if (@hasField(MethodsType, "__itruediv__"))
            @field(methods, "__itruediv__")
        else
            null;
        pub const ifloordiv = if (@hasField(MethodsType, "__ifloordiv__"))
            @field(methods, "__ifloordiv__")
        else
            null;
        pub const imod = if (@hasField(MethodsType, "__imod__")) @field(methods, "__imod__") else null;
        pub const ipow = if (@hasField(MethodsType, "__ipow__")) @field(methods, "__ipow__") else null;
        pub const iand = if (@hasField(MethodsType, "__iand__")) @field(methods, "__iand__") else null;
        pub const ior = if (@hasField(MethodsType, "__ior__")) @field(methods, "__ior__") else null;
        pub const ixor = if (@hasField(MethodsType, "__ixor__")) @field(methods, "__ixor__") else null;
        pub const ilshift = if (@hasField(MethodsType, "__ilshift__")) @field(methods, "__ilshift__") else null;
        pub const irshift = if (@hasField(MethodsType, "__irshift__")) @field(methods, "__irshift__") else null;
        pub const imatmul = if (@hasField(MethodsType, "__imatmul__")) @field(methods, "__imatmul__") else null;
    };

    const number_slots = numberSlotsFromSpecs(NumberSpecs);

    const seq_item_slot = if (comptime @hasField(MethodsType, "__getitem__")) blk: {
        const spec = @field(methods, "__getitem__");
        const Func = @TypeOf(spec.func);
        const kind = @TypeOf(spec).kind;
        break :blk seqItemSlotFromSpec(Func, kind, spec, "__getitem__");
    } else null;

    const seq_ass_item_slot = seqAssItemSlotFromSpecs(SequenceSpecs);

    const seq_concat_slot = if (comptime @hasField(MethodsType, "__add__")) blk: {
        const spec = @field(methods, "__add__");
        const Func = @TypeOf(spec.func);
        const kind = @TypeOf(spec).kind;
        break :blk method_mod.binarySlotFromSpec(Func, kind, spec, "__add__");
    } else null;

    const seq_repeat_slot = if (comptime @hasField(MethodsType, "__mul__")) blk: {
        const spec = @field(methods, "__mul__");
        const Func = @TypeOf(spec.func);
        const kind = @TypeOf(spec).kind;
        break :blk seqRepeatSlotFromSpec(Func, kind, spec, "__mul__");
    } else null;

    const seq_inplace_concat_slot = if (comptime @hasField(MethodsType, "__iadd__")) blk: {
        const spec = @field(methods, "__iadd__");
        const Func = @TypeOf(spec.func);
        const kind = @TypeOf(spec).kind;
        break :blk method_mod.binarySlotFromSpec(Func, kind, spec, "__iadd__");
    } else null;

    const seq_inplace_repeat_slot = if (comptime @hasField(MethodsType, "__imul__")) blk: {
        const spec = @field(methods, "__imul__");
        const Func = @TypeOf(spec.func);
        const kind = @TypeOf(spec).kind;
        break :blk seqRepeatSlotFromSpec(Func, kind, spec, "__imul__");
    } else null;

    return .{
        .call = call_slot,
        .init = init_slot,
        .new = new_slot,
        .del = del_slot,
        .repr = repr_slot,
        .str = str_slot,
        .hash = hash_slot,
        .richcompare = richcompare_slot,
        .iter = iter_slot,
        .iternext = iternext_slot,
        .getattro = getattro_slot,
        .setattro = setattro_slot,
        .descr_get = descr_get_slot,
        .descr_set = descr_set_slot,
        .mp_length = mapping_slots.length,
        .mp_subscript = mapping_slots.subscript,
        .mp_ass_subscript = mapping_slots.ass_subscript,
        .sq_length = mapping_slots.length,
        .sq_item = seq_item_slot,
        .sq_ass_item = seq_ass_item_slot,
        .sq_contains = contains_slot,
        .sq_concat = seq_concat_slot,
        .sq_repeat = seq_repeat_slot,
        .sq_inplace_concat = seq_inplace_concat_slot,
        .sq_inplace_repeat = seq_inplace_repeat_slot,
        .nb_add = number_slots.add,
        .nb_subtract = number_slots.sub,
        .nb_multiply = number_slots.mul,
        .nb_true_divide = number_slots.truediv,
        .nb_floor_divide = number_slots.floordiv,
        .nb_remainder = number_slots.mod,
        .nb_power = number_slots.pow,
        .nb_divmod = number_slots.divmod,
        .nb_matrix_multiply = number_slots.matmul,
        .nb_negative = number_slots.neg,
        .nb_positive = number_slots.pos,
        .nb_absolute = number_slots.abs,
        .nb_invert = number_slots.invert,
        .nb_and = number_slots.and_op,
        .nb_or = number_slots.or_op,
        .nb_xor = number_slots.xor_op,
        .nb_lshift = number_slots.lshift,
        .nb_rshift = number_slots.rshift,
        .nb_int = number_slots.as_int,
        .nb_float = number_slots.as_float,
        .nb_index = number_slots.as_index,
        .nb_bool = number_slots.bool_slot,
        .nb_inplace_add = number_slots.inplace_add,
        .nb_inplace_subtract = number_slots.inplace_sub,
        .nb_inplace_multiply = number_slots.inplace_mul,
        .nb_inplace_true_divide = number_slots.inplace_truediv,
        .nb_inplace_floor_divide = number_slots.inplace_floordiv,
        .nb_inplace_remainder = number_slots.inplace_mod,
        .nb_inplace_power = number_slots.inplace_pow,
        .nb_inplace_and = number_slots.inplace_and,
        .nb_inplace_or = number_slots.inplace_or,
        .nb_inplace_xor = number_slots.inplace_xor,
        .nb_inplace_lshift = number_slots.inplace_lshift,
        .nb_inplace_rshift = number_slots.inplace_rshift,
        .nb_inplace_matrix_multiply = number_slots.inplace_matmul,
    };
}

/// Define a Python class with methods and an optional docstring.
pub fn class(
    comptime name: [:0]const u8,
    comptime doc: ?[:0]const u8,
    comptime methods: anytype,
) Class {
    return defineClass(false, name, doc, methods);
}

/// Define a Python base class that can be subclassed in Python.
pub fn baseclass(
    comptime name: [:0]const u8,
    comptime doc: ?[:0]const u8,
    comptime methods: anytype,
) Class {
    return defineClass(true, name, doc, methods);
}

fn defineClass(
    comptime is_basetype: bool,
    comptime name: [:0]const u8,
    comptime doc: ?[:0]const u8,
    comptime methods: anytype,
) Class {
    const defs = comptime buildMethodDefs(methods);
    const methods_ptr: ?*anyopaque = @ptrCast(@constCast(&defs));
    const slot_config = comptime buildSlotConfig(methods);
    const slots = classSlots(methods_ptr, doc, slot_config);

    return .{
        .name = name,
        .attr_name = shortTypeName(name),
        .slots = slots,
        .doc = doc,
        .is_basetype = is_basetype,
    };
}

fn classSlots(
    comptime methods_ptr: ?*anyopaque,
    comptime doc: ?[:0]const u8,
    comptime slot_config: SlotConfig,
) [*c]const c.PyType_Slot {
    // For Python 3.12+, use managed dict with GC support.
    // For older Python (3.10, 3.11), use tp_dictoffset for __dict__ support.
    const use_gc = comptime managedDictGcEnabled();
    const new_fn: ?*anyopaque = if (slot_config.new) |custom|
        custom
    else
        @ptrCast(@constCast(&allocondaTypeNew));
    const dealloc_fn: ?*anyopaque = @ptrCast(@constCast(&allocondaTypeDealloc));
    const traverse_fn: ?*anyopaque = if (use_gc)
        @ptrCast(@constCast(&allocondaTypeTraverse))
    else
        null;
    const clear_fn: ?*anyopaque = if (use_gc)
        @ptrCast(@constCast(&allocondaTypeClear))
    else
        null;
    const free_fn: ?*anyopaque = if (use_gc)
        @ptrCast(@constCast(&PyGC.del))
    else
        null;

    // For non-GC types (Python <3.12), we use Py_tp_members with a __dict__ member
    // to enable attribute storage on instances.
    const members_ptr: ?*anyopaque = @ptrCast(@constCast(&dictMemberDef));

    const Slots = buildSlotArray(
        methods_ptr,
        doc,
        slot_config,
        use_gc,
        new_fn,
        dealloc_fn,
        traverse_fn,
        clear_fn,
        free_fn,
        members_ptr,
    );
    const SlotsWrapper = struct {
        const value = Slots;
    };
    return @ptrCast(&SlotsWrapper.value);
}

fn slotCount(
    comptime slot_config: SlotConfig,
    comptime doc: ?[:0]const u8,
    comptime use_gc: bool,
) usize {
    var count: usize = 0;
    count += 1; // Py_tp_methods
    if (slot_config.call != null) count += 1;
    if (slot_config.init != null) count += 1;
    if (slot_config.del != null) count += 1;
    if (slot_config.repr != null) count += 1;
    if (slot_config.str != null) count += 1;
    if (slot_config.hash != null) count += 1;
    if (slot_config.richcompare != null) count += 1;
    if (slot_config.iter != null) count += 1;
    if (slot_config.iternext != null) count += 1;
    if (slot_config.getattro != null) count += 1;
    if (slot_config.setattro != null) count += 1;
    if (slot_config.descr_get != null) count += 1;
    if (slot_config.descr_set != null) count += 1;
    if (slot_config.mp_length != null) count += 1;
    if (slot_config.mp_subscript != null) count += 1;
    if (slot_config.mp_ass_subscript != null) count += 1;
    if (slot_config.sq_length != null) count += 1;
    if (slot_config.sq_item != null) count += 1;
    if (slot_config.sq_ass_item != null) count += 1;
    if (slot_config.sq_contains != null) count += 1;
    if (slot_config.sq_concat != null) count += 1;
    if (slot_config.sq_repeat != null) count += 1;
    if (slot_config.sq_inplace_concat != null) count += 1;
    if (slot_config.sq_inplace_repeat != null) count += 1;
    if (slot_config.nb_add != null) count += 1;
    if (slot_config.nb_subtract != null) count += 1;
    if (slot_config.nb_multiply != null) count += 1;
    if (slot_config.nb_true_divide != null) count += 1;
    if (slot_config.nb_floor_divide != null) count += 1;
    if (slot_config.nb_remainder != null) count += 1;
    if (slot_config.nb_power != null) count += 1;
    if (slot_config.nb_divmod != null) count += 1;
    if (slot_config.nb_matrix_multiply != null) count += 1;
    if (slot_config.nb_negative != null) count += 1;
    if (slot_config.nb_positive != null) count += 1;
    if (slot_config.nb_absolute != null) count += 1;
    if (slot_config.nb_invert != null) count += 1;
    if (slot_config.nb_and != null) count += 1;
    if (slot_config.nb_or != null) count += 1;
    if (slot_config.nb_xor != null) count += 1;
    if (slot_config.nb_lshift != null) count += 1;
    if (slot_config.nb_rshift != null) count += 1;
    if (slot_config.nb_int != null) count += 1;
    if (slot_config.nb_float != null) count += 1;
    if (slot_config.nb_index != null) count += 1;
    if (slot_config.nb_bool != null) count += 1;
    if (slot_config.nb_inplace_add != null) count += 1;
    if (slot_config.nb_inplace_subtract != null) count += 1;
    if (slot_config.nb_inplace_multiply != null) count += 1;
    if (slot_config.nb_inplace_true_divide != null) count += 1;
    if (slot_config.nb_inplace_floor_divide != null) count += 1;
    if (slot_config.nb_inplace_remainder != null) count += 1;
    if (slot_config.nb_inplace_power != null) count += 1;
    if (slot_config.nb_inplace_and != null) count += 1;
    if (slot_config.nb_inplace_or != null) count += 1;
    if (slot_config.nb_inplace_xor != null) count += 1;
    if (slot_config.nb_inplace_lshift != null) count += 1;
    if (slot_config.nb_inplace_rshift != null) count += 1;
    if (slot_config.nb_inplace_matrix_multiply != null) count += 1;

    count += 2; // Py_tp_new + Py_tp_dealloc
    if (use_gc) {
        count += 3; // traverse/clear/free
    } else {
        count += 1; // Py_tp_members
    }
    if (use_gc and doc != null) count += 1;
    count += 1; // sentinel
    return count;
}

fn buildSlotArray(
    comptime methods_ptr: ?*anyopaque,
    comptime doc: ?[:0]const u8,
    comptime slot_config: SlotConfig,
    comptime use_gc: bool,
    comptime new_fn: ?*anyopaque,
    comptime dealloc_fn: ?*anyopaque,
    comptime traverse_fn: ?*anyopaque,
    comptime clear_fn: ?*anyopaque,
    comptime free_fn: ?*anyopaque,
    comptime members_ptr: ?*anyopaque,
) [slotCount(slot_config, doc, use_gc)]c.PyType_Slot {
    var slots: [slotCount(slot_config, doc, use_gc)]c.PyType_Slot = undefined;
    var i: usize = 0;

    slots[i] = .{ .slot = c.Py_tp_methods, .pfunc = methods_ptr };
    i += 1;

    if (slot_config.call) |call_fn| {
        slots[i] = .{ .slot = c.Py_tp_call, .pfunc = call_fn };
        i += 1;
    }
    if (slot_config.init) |init_fn| {
        slots[i] = .{ .slot = c.Py_tp_init, .pfunc = init_fn };
        i += 1;
    }
    if (slot_config.del) |del_fn| {
        if (comptime @hasDecl(c, "Py_tp_finalize")) {
            slots[i] = .{ .slot = c.Py_tp_finalize, .pfunc = del_fn };
        } else {
            slots[i] = .{ .slot = c.Py_tp_del, .pfunc = del_fn };
        }
        i += 1;
    }
    if (slot_config.repr) |repr_fn| {
        slots[i] = .{ .slot = c.Py_tp_repr, .pfunc = repr_fn };
        i += 1;
    }
    if (slot_config.str) |str_fn| {
        slots[i] = .{ .slot = c.Py_tp_str, .pfunc = str_fn };
        i += 1;
    }
    if (slot_config.hash) |hash_fn| {
        slots[i] = .{ .slot = c.Py_tp_hash, .pfunc = hash_fn };
        i += 1;
    }
    if (slot_config.richcompare) |rc_fn| {
        slots[i] = .{ .slot = c.Py_tp_richcompare, .pfunc = rc_fn };
        i += 1;
    }
    if (slot_config.iter) |iter_fn| {
        slots[i] = .{ .slot = c.Py_tp_iter, .pfunc = iter_fn };
        i += 1;
    }
    if (slot_config.iternext) |next_fn| {
        slots[i] = .{ .slot = c.Py_tp_iternext, .pfunc = next_fn };
        i += 1;
    }
    if (slot_config.getattro) |getattr_fn| {
        slots[i] = .{ .slot = c.Py_tp_getattro, .pfunc = getattr_fn };
        i += 1;
    }
    if (slot_config.setattro) |setattr_fn| {
        slots[i] = .{ .slot = c.Py_tp_setattro, .pfunc = setattr_fn };
        i += 1;
    }
    if (slot_config.descr_get) |get_fn| {
        slots[i] = .{ .slot = c.Py_tp_descr_get, .pfunc = get_fn };
        i += 1;
    }
    if (slot_config.descr_set) |set_fn| {
        slots[i] = .{ .slot = c.Py_tp_descr_set, .pfunc = set_fn };
        i += 1;
    }
    if (slot_config.mp_length) |len_fn| {
        slots[i] = .{ .slot = c.Py_mp_length, .pfunc = len_fn };
        i += 1;
    }
    if (slot_config.mp_subscript) |sub_fn| {
        slots[i] = .{ .slot = c.Py_mp_subscript, .pfunc = sub_fn };
        i += 1;
    }
    if (slot_config.mp_ass_subscript) |ass_fn| {
        slots[i] = .{ .slot = c.Py_mp_ass_subscript, .pfunc = ass_fn };
        i += 1;
    }
    if (slot_config.sq_length) |len_fn| {
        slots[i] = .{ .slot = c.Py_sq_length, .pfunc = len_fn };
        i += 1;
    }
    if (slot_config.sq_item) |item_fn| {
        slots[i] = .{ .slot = c.Py_sq_item, .pfunc = item_fn };
        i += 1;
    }
    if (slot_config.sq_ass_item) |ass_fn| {
        slots[i] = .{ .slot = c.Py_sq_ass_item, .pfunc = ass_fn };
        i += 1;
    }
    if (slot_config.sq_contains) |contains_fn| {
        slots[i] = .{ .slot = c.Py_sq_contains, .pfunc = contains_fn };
        i += 1;
    }
    if (slot_config.sq_concat) |concat_fn| {
        slots[i] = .{ .slot = c.Py_sq_concat, .pfunc = concat_fn };
        i += 1;
    }
    if (slot_config.sq_repeat) |repeat_fn| {
        slots[i] = .{ .slot = c.Py_sq_repeat, .pfunc = repeat_fn };
        i += 1;
    }
    if (slot_config.sq_inplace_concat) |concat_fn| {
        slots[i] = .{ .slot = c.Py_sq_inplace_concat, .pfunc = concat_fn };
        i += 1;
    }
    if (slot_config.sq_inplace_repeat) |repeat_fn| {
        slots[i] = .{ .slot = c.Py_sq_inplace_repeat, .pfunc = repeat_fn };
        i += 1;
    }
    if (slot_config.nb_add) |add_fn| {
        slots[i] = .{ .slot = c.Py_nb_add, .pfunc = add_fn };
        i += 1;
    }
    if (slot_config.nb_subtract) |sub_fn| {
        slots[i] = .{ .slot = c.Py_nb_subtract, .pfunc = sub_fn };
        i += 1;
    }
    if (slot_config.nb_multiply) |mul_fn| {
        slots[i] = .{ .slot = c.Py_nb_multiply, .pfunc = mul_fn };
        i += 1;
    }
    if (slot_config.nb_true_divide) |div_fn| {
        slots[i] = .{ .slot = c.Py_nb_true_divide, .pfunc = div_fn };
        i += 1;
    }
    if (slot_config.nb_floor_divide) |div_fn| {
        slots[i] = .{ .slot = c.Py_nb_floor_divide, .pfunc = div_fn };
        i += 1;
    }
    if (slot_config.nb_remainder) |mod_fn| {
        slots[i] = .{ .slot = c.Py_nb_remainder, .pfunc = mod_fn };
        i += 1;
    }
    if (slot_config.nb_power) |pow_fn| {
        slots[i] = .{ .slot = c.Py_nb_power, .pfunc = pow_fn };
        i += 1;
    }
    if (slot_config.nb_divmod) |divmod_fn| {
        slots[i] = .{ .slot = c.Py_nb_divmod, .pfunc = divmod_fn };
        i += 1;
    }
    if (slot_config.nb_matrix_multiply) |matmul_fn| {
        slots[i] = .{ .slot = c.Py_nb_matrix_multiply, .pfunc = matmul_fn };
        i += 1;
    }
    if (slot_config.nb_negative) |neg_fn| {
        slots[i] = .{ .slot = c.Py_nb_negative, .pfunc = neg_fn };
        i += 1;
    }
    if (slot_config.nb_positive) |pos_fn| {
        slots[i] = .{ .slot = c.Py_nb_positive, .pfunc = pos_fn };
        i += 1;
    }
    if (slot_config.nb_absolute) |abs_fn| {
        slots[i] = .{ .slot = c.Py_nb_absolute, .pfunc = abs_fn };
        i += 1;
    }
    if (slot_config.nb_invert) |invert_fn| {
        slots[i] = .{ .slot = c.Py_nb_invert, .pfunc = invert_fn };
        i += 1;
    }
    if (slot_config.nb_and) |and_fn| {
        slots[i] = .{ .slot = c.Py_nb_and, .pfunc = and_fn };
        i += 1;
    }
    if (slot_config.nb_or) |or_fn| {
        slots[i] = .{ .slot = c.Py_nb_or, .pfunc = or_fn };
        i += 1;
    }
    if (slot_config.nb_xor) |xor_fn| {
        slots[i] = .{ .slot = c.Py_nb_xor, .pfunc = xor_fn };
        i += 1;
    }
    if (slot_config.nb_lshift) |shift_fn| {
        slots[i] = .{ .slot = c.Py_nb_lshift, .pfunc = shift_fn };
        i += 1;
    }
    if (slot_config.nb_rshift) |shift_fn| {
        slots[i] = .{ .slot = c.Py_nb_rshift, .pfunc = shift_fn };
        i += 1;
    }
    if (slot_config.nb_int) |int_fn| {
        slots[i] = .{ .slot = c.Py_nb_int, .pfunc = int_fn };
        i += 1;
    }
    if (slot_config.nb_float) |float_fn| {
        slots[i] = .{ .slot = c.Py_nb_float, .pfunc = float_fn };
        i += 1;
    }
    if (slot_config.nb_index) |index_fn| {
        slots[i] = .{ .slot = c.Py_nb_index, .pfunc = index_fn };
        i += 1;
    }
    if (slot_config.nb_bool) |bool_fn| {
        slots[i] = .{ .slot = c.Py_nb_bool, .pfunc = bool_fn };
        i += 1;
    }
    if (slot_config.nb_inplace_add) |add_fn| {
        slots[i] = .{ .slot = c.Py_nb_inplace_add, .pfunc = add_fn };
        i += 1;
    }
    if (slot_config.nb_inplace_subtract) |sub_fn| {
        slots[i] = .{ .slot = c.Py_nb_inplace_subtract, .pfunc = sub_fn };
        i += 1;
    }
    if (slot_config.nb_inplace_multiply) |mul_fn| {
        slots[i] = .{ .slot = c.Py_nb_inplace_multiply, .pfunc = mul_fn };
        i += 1;
    }
    if (slot_config.nb_inplace_true_divide) |div_fn| {
        slots[i] = .{ .slot = c.Py_nb_inplace_true_divide, .pfunc = div_fn };
        i += 1;
    }
    if (slot_config.nb_inplace_floor_divide) |div_fn| {
        slots[i] = .{ .slot = c.Py_nb_inplace_floor_divide, .pfunc = div_fn };
        i += 1;
    }
    if (slot_config.nb_inplace_remainder) |mod_fn| {
        slots[i] = .{ .slot = c.Py_nb_inplace_remainder, .pfunc = mod_fn };
        i += 1;
    }
    if (slot_config.nb_inplace_power) |pow_fn| {
        slots[i] = .{ .slot = c.Py_nb_inplace_power, .pfunc = pow_fn };
        i += 1;
    }
    if (slot_config.nb_inplace_and) |and_fn| {
        slots[i] = .{ .slot = c.Py_nb_inplace_and, .pfunc = and_fn };
        i += 1;
    }
    if (slot_config.nb_inplace_or) |or_fn| {
        slots[i] = .{ .slot = c.Py_nb_inplace_or, .pfunc = or_fn };
        i += 1;
    }
    if (slot_config.nb_inplace_xor) |xor_fn| {
        slots[i] = .{ .slot = c.Py_nb_inplace_xor, .pfunc = xor_fn };
        i += 1;
    }
    if (slot_config.nb_inplace_lshift) |shift_fn| {
        slots[i] = .{ .slot = c.Py_nb_inplace_lshift, .pfunc = shift_fn };
        i += 1;
    }
    if (slot_config.nb_inplace_rshift) |shift_fn| {
        slots[i] = .{ .slot = c.Py_nb_inplace_rshift, .pfunc = shift_fn };
        i += 1;
    }
    if (slot_config.nb_inplace_matrix_multiply) |matmul_fn| {
        slots[i] = .{ .slot = c.Py_nb_inplace_matrix_multiply, .pfunc = matmul_fn };
        i += 1;
    }

    slots[i] = .{ .slot = c.Py_tp_new, .pfunc = new_fn };
    i += 1;
    slots[i] = .{ .slot = c.Py_tp_dealloc, .pfunc = dealloc_fn };
    i += 1;

    if (use_gc) {
        slots[i] = .{ .slot = c.Py_tp_traverse, .pfunc = traverse_fn };
        i += 1;
        slots[i] = .{ .slot = c.Py_tp_clear, .pfunc = clear_fn };
        i += 1;
        slots[i] = .{ .slot = c.Py_tp_free, .pfunc = free_fn };
        i += 1;
        if (doc) |doc_text| {
            slots[i] = .{ .slot = c.Py_tp_doc, .pfunc = @ptrCast(@constCast(doc_text.ptr)) };
            i += 1;
        }
    } else {
        // Non-GC types (Python <3.12): use Py_tp_members with __dict__ for attribute support.
        // NOTE: We intentionally omit Py_tp_doc for non-GC types because Python
        // tries to free() the tp_doc string on heap types, which crashes with static strings.
        slots[i] = .{ .slot = c.Py_tp_members, .pfunc = members_ptr };
        i += 1;
    }

    slots[i] = .{ .slot = 0, .pfunc = null };
    return slots;
}

fn findCallSlot(comptime methods: anytype) ?*anyopaque {
    const info = @typeInfo(@TypeOf(methods));
    if (info != .@"struct") {
        @compileError("methods must be a struct literal");
    }

    const fields = info.@"struct".fields;
    inline for (fields) |field| {
        if (mem.eql(u8, field.name, "__call__")) {
            const spec = @field(methods, field.name);
            const Func = @TypeOf(spec.func);
            const kind = @TypeOf(spec).kind;
            return callSlotFromSpec(Func, kind, spec);
        }
    }
    return null;
}

fn classFlags(is_basetype: bool) c_uint {
    var flags: c_uint = @intCast(c.Py_TPFLAGS_DEFAULT);
    if (is_basetype) {
        flags |= @intCast(c.Py_TPFLAGS_BASETYPE);
    }

    // Only use MANAGED_DICT when we have the GC helpers to support it.
    // Python 3.11 has the flag but lacks PyObject_VisitManagedDict/ClearManagedDict,
    // so we must not set it there or we get segfaults during GC.
    if (comptime managedDictGcEnabled()) {
        flags |= @intCast(c.Py_TPFLAGS_MANAGED_DICT);
        flags |= @intCast(c.Py_TPFLAGS_HAVE_GC);
    }
    return flags;
}

fn classBasicSize() usize {
    // For Python 3.12+, MANAGED_DICT handles __dict__ storage.
    // For older Python, we need space for the dict pointer (tp_dictoffset).
    if (comptime managedDictGcEnabled()) {
        return @sizeOf(c.PyObject);
    } else {
        return @sizeOf(DefaultTypeStorage);
    }
}

// ============================================================================
// Type lifecycle functions
// ============================================================================

fn allocondaTypeNew(
    type_obj: ?*c.PyTypeObject,
    args: ?*c.PyObject,
    kwargs: ?*c.PyObject,
) callconv(.c) ?*c.PyObject {
    const obj = PyType.genericNew(type_obj, args, kwargs) catch return null;
    // For non-GC types (Python <3.12), initialize the dict slot with an empty dict.
    // On 3.12+, MANAGED_DICT handles this automatically.
    // We need a real dict (not NULL) because T_OBJECT_EX raises AttributeError for NULL.
    if (comptime !managedDictGcEnabled()) {
        const offset: usize = @intCast(DefaultDictOffset);
        const base: [*]u8 = @ptrCast(@constCast(obj));
        const slot: *?*c.PyObject = @ptrCast(@alignCast(base + offset));
        slot.* = PyDict.new() catch return null;
    }
    return obj;
}

// GC traverse/clear helpers - use comptime selection to avoid referencing
// symbols that don't exist on older Python versions.
fn allocondaTypeTraverse(
    self: ?*c.PyObject,
    visit: c.visitproc,
    arg: ?*anyopaque,
) callconv(.c) c_int {
    const obj = self orelse return 0;
    return PyManagedDict.visit(obj, visit, arg);
}

fn allocondaTypeClear(self: ?*c.PyObject) callconv(.c) c_int {
    const obj = self orelse return 0;
    PyManagedDict.clear(obj);
    return 0;
}

fn allocondaTypeDealloc(self: ?*c.PyObject) callconv(.c) void {
    const obj = self orelse return;

    // Run finalizers before touching instance state.
    if (@hasDecl(c, "PyObject_CallFinalizerFromDealloc")) {
        if (c.PyObject_CallFinalizerFromDealloc(obj) < 0) {
            return;
        }
    }

    // IMPORTANT: For heap types, we must save the type reference before freeing,
    // then DECREF the type AFTER freeing the object. This is critical for Python 3.11+
    // where heap type lifecycle management changed.
    const type_obj = PyType.typePtr(obj);
    defer PyObject.decRef(@ptrCast(type_obj));

    // CRITICAL: If this type is GC-tracked, we must untrack BEFORE any cleanup.
    // Failing to do this causes the GC to find dangling pointers during collection,
    // which manifests as segfaults during interpreter shutdown (especially on 3.11).
    if (@hasDecl(c, "PyObject_GC_UnTrack") and @hasDecl(c, "Py_TPFLAGS_HAVE_GC")) {
        if ((type_obj.tp_flags & c.Py_TPFLAGS_HAVE_GC) != 0) {
            PyGC.untrack(obj);
        }
    }

    // Clear the dict if present (for Py_tp_dictoffset path on Python <3.12)
    if (@hasDecl(c, "Py_tp_dictoffset")) {
        const offset: usize = @intCast(DefaultDictOffset);
        const base: [*]u8 = @ptrCast(obj);
        const slot: *?*c.PyObject = @ptrCast(@alignCast(base + offset));
        if (slot.*) |dict| {
            PyObject.decRef(dict);
            slot.* = null;
        }
    }

    // Free the object memory using the type's tp_free slot.
    // This handles both GC and non-GC types correctly:
    // - For non-GC types: tp_free = PyObject_Free
    // - For GC types: tp_free = PyObject_GC_Del
    if (type_obj.tp_free) |free_fn| free_fn(obj);
}

// ============================================================================
// Class building helpers
// ============================================================================

fn buildClassDefs(
    comptime module_name: []const u8,
    comptime types: anytype,
) [classCount(types)]Class {
    const info = @typeInfo(@TypeOf(types));
    if (info != .@"struct") {
        @compileError("types must be a struct literal");
    }

    const fields = info.@"struct".fields;
    var defs: [fields.len]Class = undefined;

    inline for (fields, 0..) |field, i| {
        defs[i] = qualifyClass(module_name, @field(types, field.name));
    }

    return defs;
}

fn classCount(comptime types: anytype) usize {
    const info = @typeInfo(@TypeOf(types));
    if (info != .@"struct") {
        @compileError("types must be a struct literal");
    }
    return info.@"struct".fields.len;
}

fn qualifyClass(comptime module_name: []const u8, comptime class_def: Class) Class {
    const raw_name = class_def.name[0..class_def.name.len];
    const full_name = if (mem.lastIndexOfScalar(u8, raw_name, '.')) |idx| blk: {
        const prefix = raw_name[0..idx];
        if (!mem.eql(u8, prefix, module_name)) {
            @compileError(fmt.comptimePrint(
                "class name '{s}' must match module '{s}'",
                .{ raw_name, module_name },
            ));
        }
        break :blk class_def.name;
    } else fmt.comptimePrint("{s}.{s}\x00", .{ module_name, raw_name });

    return .{
        .name = full_name,
        .attr_name = class_def.attr_name,
        .slots = class_def.slots,
        .doc = class_def.doc,
        .is_basetype = class_def.is_basetype,
    };
}

fn shortTypeName(comptime name: [:0]const u8) [:0]const u8 {
    const plain = name[0..name.len];
    if (mem.lastIndexOfScalar(u8, plain, '.')) |idx| {
        if (idx + 1 >= plain.len) {
            @compileError("class name cannot end with '.'");
        }
        return cstr(plain[idx + 1 ..]);
    }
    return name;
}

fn setTypeModule(type_obj: *c.PyObject, module_name: []const u8) PyError!void {
    const mod_obj = try PyUnicode.fromSlice(module_name);
    defer PyObject.decRef(mod_obj);
    try PyObject.setAttrString(type_obj, cstr("__module__"), mod_obj);
}
