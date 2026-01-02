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

/// Convenience module builder.
pub fn module(
    comptime name: [:0]const u8,
    comptime doc: [:0]const u8,
    comptime methods: anytype,
) Module {
    return Module.init(name, doc).with(methods);
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

    fn create(self: *const Class) PyError!*c.PyObject {
        var spec = c.PyType_Spec{
            .name = @ptrCast(self.name.ptr),
            .basicsize = @intCast(classBasicSize()),
            .itemsize = 0,
            .flags = classFlags(),
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

/// Define a Python class with methods and an optional docstring.
pub fn class(
    comptime name: [:0]const u8,
    comptime doc: ?[:0]const u8,
    comptime methods: anytype,
) Class {
    const defs = comptime buildMethodDefs(methods);
    const methods_ptr: ?*anyopaque = @ptrCast(@constCast(&defs));
    const slots = classSlots(methods_ptr, doc);

    return .{
        .name = name,
        .attr_name = shortTypeName(name),
        .slots = slots,
        .doc = doc,
    };
}

fn classSlots(
    comptime methods_ptr: ?*anyopaque,
    comptime doc: ?[:0]const u8,
) [*c]const c.PyType_Slot {
    // For Python 3.12+, use managed dict with GC support.
    // For older Python (3.10, 3.11), use tp_dictoffset for __dict__ support.
    const use_gc = comptime managedDictGcEnabled();
    const new_fn: ?*anyopaque = @ptrCast(@constCast(&allocondaTypeNew));
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

    if (doc) |doc_text| {
        if (use_gc) {
            return @ptrCast(&[_]c.PyType_Slot{
                .{ .slot = c.Py_tp_methods, .pfunc = methods_ptr },
                .{ .slot = c.Py_tp_new, .pfunc = new_fn },
                .{ .slot = c.Py_tp_dealloc, .pfunc = dealloc_fn },
                .{ .slot = c.Py_tp_traverse, .pfunc = traverse_fn },
                .{ .slot = c.Py_tp_clear, .pfunc = clear_fn },
                .{ .slot = c.Py_tp_free, .pfunc = free_fn },
                .{ .slot = c.Py_tp_doc, .pfunc = @ptrCast(@constCast(doc_text.ptr)) },
                .{ .slot = 0, .pfunc = null },
            });
        }
        // Non-GC types (Python <3.12): use Py_tp_members with __dict__ for attribute support.
        // NOTE: We intentionally omit Py_tp_doc for non-GC types because Python
        // tries to free() the tp_doc string on heap types, which crashes with static strings.
        return @ptrCast(&[_]c.PyType_Slot{
            .{ .slot = c.Py_tp_methods, .pfunc = methods_ptr },
            .{ .slot = c.Py_tp_new, .pfunc = new_fn },
            .{ .slot = c.Py_tp_dealloc, .pfunc = dealloc_fn },
            .{ .slot = c.Py_tp_members, .pfunc = members_ptr },
            .{ .slot = 0, .pfunc = null },
        });
    }

    if (use_gc) {
        return @ptrCast(&[_]c.PyType_Slot{
            .{ .slot = c.Py_tp_methods, .pfunc = methods_ptr },
            .{ .slot = c.Py_tp_new, .pfunc = new_fn },
            .{ .slot = c.Py_tp_dealloc, .pfunc = dealloc_fn },
            .{ .slot = c.Py_tp_traverse, .pfunc = traverse_fn },
            .{ .slot = c.Py_tp_clear, .pfunc = clear_fn },
            .{ .slot = c.Py_tp_free, .pfunc = free_fn },
            .{ .slot = 0, .pfunc = null },
        });
    }
    // Non-GC types (Python <3.12): use Py_tp_members with __dict__ for attribute support.
    return @ptrCast(&[_]c.PyType_Slot{
        .{ .slot = c.Py_tp_methods, .pfunc = methods_ptr },
        .{ .slot = c.Py_tp_new, .pfunc = new_fn },
        .{ .slot = c.Py_tp_dealloc, .pfunc = dealloc_fn },
        .{ .slot = c.Py_tp_members, .pfunc = members_ptr },
        .{ .slot = 0, .pfunc = null },
    });
}

fn classFlags() c_uint {
    var flags: c_uint = @intCast(c.Py_TPFLAGS_DEFAULT);
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
