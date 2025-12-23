const std = @import("std");
pub const allocator = std.heap.c_allocator;

/// Python C API bindings.
pub const ffi = @import("ffi.zig");
pub const c = ffi.c;
pub const PyObject = ffi.c.PyObject;
pub const Py_ssize_t = ffi.c.Py_ssize_t;

const DefaultTypeStorage = extern struct {
    head: c.PyObject,
    dict: ?*c.PyObject,
};
const DefaultDictOffset: c.Py_ssize_t = @offsetOf(DefaultTypeStorage, "dict");

fn managedDictGcEnabled() bool {
    if (!@hasDecl(c, "Py_TPFLAGS_MANAGED_DICT")) return false;
    const has_visit = @hasDecl(c, "PyObject_VisitManagedDict") or @hasDecl(c, "_PyObject_VisitManagedDict");
    const has_clear = @hasDecl(c, "PyObject_ClearManagedDict") or @hasDecl(c, "_PyObject_ClearManagedDict");
    return has_visit and has_clear and @hasDecl(c, "PyObject_GC_Del");
}

const py = @This();
/// Convenience arena allocator backed by the CPython allocator.
pub fn arenaAllocator() std.heap.ArenaAllocator {
    return std.heap.ArenaAllocator.init(allocator);
}

/// Python extension module definition and constructor helpers.
pub const Module = struct {
    name: []const u8,
    doc: []const u8,
    inner: c.PyModuleDef,
    types: ?[]const Class = null,

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

    /// Attach classes to be registered when the module is created.
    pub fn withTypes(comptime self: Module, comptime types: anytype) Module {
        const defs = comptime buildClassDefs(self.name, types);
        var next = self;
        next.types = defs[0..];
        return next;
    }

    /// Create the Python module object.
    pub fn create(self: *const Module) ?*c.PyObject {
        const def_ptr = c.PyMem_Malloc(@sizeOf(c.PyModuleDef)) orelse {
            _ = c.PyErr_NoMemory();
            return null;
        };
        const def: *c.PyModuleDef = @ptrCast(@alignCast(def_ptr));
        def.* = self.inner;
        const module_obj = c.PyModule_Create(def);
        if (module_obj == null) {
            c.PyMem_Free(def_ptr);
            return null;
        }
        if (self.types) |types| {
            for (types) |class_def| {
                if (!class_def.addToModule(module_obj, self.name)) {
                    c.Py_DecRef(module_obj);
                    c.PyMem_Free(def_ptr);
                    return null;
                }
            }
        }
        return module_obj;
    }
};

/// Python class definition used with Module.withTypes.
pub const Class = struct {
    name: [:0]const u8,
    attr_name: [:0]const u8,
    slots: [*c]const c.PyType_Slot,

    fn create(self: *const Class) ?*c.PyObject {
        var spec = c.PyType_Spec{
            .name = @ptrCast(self.name.ptr),
            .basicsize = @intCast(classBasicSize()),
            .itemsize = 0,
            .flags = classFlags(),
            .slots = @constCast(self.slots),
        };
        return c.PyType_FromSpec(&spec);
    }

    fn addToModule(self: *const Class, module_obj: *c.PyObject, module_name: []const u8) bool {
        const type_obj = self.create() orelse return false;
        if (!setTypeModule(type_obj, module_name)) {
            c.Py_DecRef(type_obj);
            return false;
        }
        if (c.PyModule_AddObject(module_obj, @ptrCast(self.attr_name.ptr), type_obj) != 0) {
            c.Py_DecRef(type_obj);
            return false;
        }
        return true;
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
    };
}

fn classSlots(
    comptime methods_ptr: ?*anyopaque,
    comptime doc: ?[:0]const u8,
) [*c]const c.PyType_Slot {
    const managed_dict = @hasDecl(c, "Py_TPFLAGS_MANAGED_DICT");
    const use_dict_offset = !managed_dict and @hasDecl(c, "Py_tp_dictoffset");
    const use_gc = managedDictGcEnabled();
    const new_fn: ?*anyopaque = if (use_dict_offset)
        @ptrCast(@constCast(&allocondaTypeNew))
    else
        @ptrCast(@constCast(&c.PyType_GenericNew));
    const traverse_fn: ?*anyopaque = if (use_gc)
        @ptrCast(@constCast(&allocondaTypeTraverse))
    else
        null;
    const clear_fn: ?*anyopaque = if (use_gc)
        @ptrCast(@constCast(&allocondaTypeClear))
    else
        null;
    const free_fn: ?*anyopaque = if (use_gc)
        @ptrCast(@constCast(&c.PyObject_GC_Del))
    else
        null;
    if (doc) |doc_text| {
        if (use_dict_offset) {
            return @ptrCast(&[_]c.PyType_Slot{
                .{ .slot = c.Py_tp_methods, .pfunc = methods_ptr },
                .{ .slot = c.Py_tp_new, .pfunc = new_fn },
                .{ .slot = c.Py_tp_dictoffset, .pfunc = @ptrFromInt(@as(usize, @intCast(DefaultDictOffset))) },
                .{ .slot = c.Py_tp_doc, .pfunc = @ptrCast(@constCast(doc_text.ptr)) },
                .{ .slot = 0, .pfunc = null },
            });
        }
        if (use_gc) {
            return @ptrCast(&[_]c.PyType_Slot{
                .{ .slot = c.Py_tp_methods, .pfunc = methods_ptr },
                .{ .slot = c.Py_tp_new, .pfunc = new_fn },
                .{ .slot = c.Py_tp_traverse, .pfunc = traverse_fn },
                .{ .slot = c.Py_tp_clear, .pfunc = clear_fn },
                .{ .slot = c.Py_tp_free, .pfunc = free_fn },
                .{ .slot = c.Py_tp_doc, .pfunc = @ptrCast(@constCast(doc_text.ptr)) },
                .{ .slot = 0, .pfunc = null },
            });
        }
        return @ptrCast(&[_]c.PyType_Slot{
            .{ .slot = c.Py_tp_methods, .pfunc = methods_ptr },
            .{ .slot = c.Py_tp_new, .pfunc = new_fn },
            .{ .slot = c.Py_tp_doc, .pfunc = @ptrCast(@constCast(doc_text.ptr)) },
            .{ .slot = 0, .pfunc = null },
        });
    }

    if (use_dict_offset) {
        return @ptrCast(&[_]c.PyType_Slot{
            .{ .slot = c.Py_tp_methods, .pfunc = methods_ptr },
            .{ .slot = c.Py_tp_new, .pfunc = new_fn },
            .{ .slot = c.Py_tp_dictoffset, .pfunc = @ptrFromInt(@as(usize, @intCast(DefaultDictOffset))) },
            .{ .slot = 0, .pfunc = null },
        });
    }
    if (use_gc) {
        return @ptrCast(&[_]c.PyType_Slot{
            .{ .slot = c.Py_tp_methods, .pfunc = methods_ptr },
            .{ .slot = c.Py_tp_new, .pfunc = new_fn },
            .{ .slot = c.Py_tp_traverse, .pfunc = traverse_fn },
            .{ .slot = c.Py_tp_clear, .pfunc = clear_fn },
            .{ .slot = c.Py_tp_free, .pfunc = free_fn },
            .{ .slot = 0, .pfunc = null },
        });
    }
    return @ptrCast(&[_]c.PyType_Slot{
        .{ .slot = c.Py_tp_methods, .pfunc = methods_ptr },
        .{ .slot = c.Py_tp_new, .pfunc = new_fn },
        .{ .slot = 0, .pfunc = null },
    });
}

fn classFlags() c_uint {
    var flags: c_uint = @intCast(c.Py_TPFLAGS_DEFAULT);
    if (@hasDecl(c, "Py_TPFLAGS_MANAGED_DICT")) {
        flags |= @intCast(c.Py_TPFLAGS_MANAGED_DICT);
    }
    if (managedDictGcEnabled()) {
        flags |= @intCast(c.Py_TPFLAGS_HAVE_GC);
    }
    return flags;
}

fn classBasicSize() usize {
    if (@hasDecl(c, "Py_TPFLAGS_MANAGED_DICT")) {
        return @sizeOf(c.PyObject);
    }
    if (@hasDecl(c, "Py_tp_dictoffset")) {
        return @sizeOf(DefaultTypeStorage);
    }
    return @sizeOf(c.PyObject);
}

fn allocondaTypeNew(
    type_obj: ?*c.PyTypeObject,
    args: ?*c.PyObject,
    kwargs: ?*c.PyObject,
) callconv(.c) ?*c.PyObject {
    const obj = c.PyType_GenericNew(type_obj, args, kwargs) orelse return null;
    if (@hasDecl(c, "Py_tp_dictoffset")) {
        const offset: usize = @intCast(DefaultDictOffset);
        const base: [*]u8 = @ptrCast(@constCast(obj));
        const slot: *?*c.PyObject = @ptrCast(@alignCast(base + offset));
        slot.* = null;
    }
    return obj;
}

fn allocondaTypeTraverse(
    self: ?*c.PyObject,
    visit: c.visitproc,
    arg: ?*anyopaque,
) callconv(.c) c_int {
    const obj = self orelse return 0;
    if (@hasDecl(c, "PyObject_VisitManagedDict")) {
        return c.PyObject_VisitManagedDict(obj, visit, arg);
    }
    if (@hasDecl(c, "_PyObject_VisitManagedDict")) {
        return c._PyObject_VisitManagedDict(obj, visit, arg);
    }
    return 0;
}

fn allocondaTypeClear(self: ?*c.PyObject) callconv(.c) c_int {
    const obj = self orelse return 0;
    if (@hasDecl(c, "PyObject_ClearManagedDict")) {
        c.PyObject_ClearManagedDict(obj);
        return 0;
    }
    if (@hasDecl(c, "_PyObject_ClearManagedDict")) {
        c._PyObject_ClearManagedDict(obj);
        return 0;
    }
    return 0;
}

/// Wrapper for a Python object with ownership tracking.
pub const Object = struct {
    ptr: *c.PyObject,
    owns_ref: bool,

    /// Borrow a PyObject without changing refcount.
    pub fn borrowed(ptr: *c.PyObject) Object {
        return .{ .ptr = ptr, .owns_ref = false };
    }

    /// Own a PyObject reference.
    pub fn owned(ptr: *c.PyObject) Object {
        return .{ .ptr = ptr, .owns_ref = true };
    }

    /// Release the reference if owned.
    pub fn deinit(self: Object) void {
        if (self.owns_ref) {
            c.Py_DecRef(self.ptr);
        }
    }

    /// Convert to a Zig value.
    pub fn as(self: Object, comptime T: type) ?T {
        return fromPy(T, self.ptr);
    }

    /// Check if the object is callable.
    pub fn isCallable(self: Object) bool {
        return c.PyCallable_Check(self.ptr) != 0;
    }

    /// Check if the object is None.
    pub fn isNone(self: Object) bool {
        return py.isNone(self.ptr);
    }

    /// Check if the object is a Unicode string.
    pub fn isUnicode(self: Object) bool {
        return py.isUnicode(self.ptr);
    }

    /// Check if the object is a bytes object.
    pub fn isBytes(self: Object) bool {
        return py.isBytes(self.ptr);
    }

    /// Check if the object is a bool.
    pub fn isBool(self: Object) bool {
        return py.isBool(self.ptr);
    }

    /// Check if the object is an int.
    pub fn isLong(self: Object) bool {
        return py.isLong(self.ptr);
    }

    /// Check if the object is a float.
    pub fn isFloat(self: Object) bool {
        return py.isFloat(self.ptr);
    }

    /// Check if the object is a list.
    pub fn isList(self: Object) bool {
        return py.isList(self.ptr);
    }

    /// Check if the object is a tuple.
    pub fn isTuple(self: Object) bool {
        return py.isTuple(self.ptr);
    }

    /// Check if the object is a dict.
    pub fn isDict(self: Object) bool {
        return py.isDict(self.ptr);
    }

    /// Borrow the UTF-8 slice for a Unicode object.
    pub fn unicodeSlice(self: Object) ?[]const u8 {
        return py.unicodeSlice(self.ptr);
    }

    /// Borrow the byte slice for a bytes object.
    pub fn bytesSlice(self: Object) ?[]const u8 {
        return py.bytesSlice(self.ptr);
    }

    /// Convert the object to truthiness.
    pub fn isTrue(self: Object) ?bool {
        return py.objectIsTrue(self.ptr);
    }

    /// Call with no arguments.
    pub fn call0(self: Object) ?Object {
        if (@hasDecl(c, "PyObject_CallNoArgs")) {
            const result = c.PyObject_CallNoArgs(self.ptr);
            if (result == null) return null;
            return Object.owned(result);
        }

        const tuple = c.PyTuple_New(0) orelse return null;
        const result = c.PyObject_CallObject(self.ptr, tuple);
        c.Py_DecRef(tuple);
        if (result == null) return null;
        return Object.owned(result);
    }

    /// Call with one argument.
    pub fn call1(self: Object, arg: anytype) ?Object {
        const arg_obj = toPy(@TypeOf(arg), arg) orelse return null;
        const tuple = c.PyTuple_New(1) orelse {
            c.Py_DecRef(arg_obj);
            return null;
        };

        if (c.PyTuple_SetItem(tuple, 0, arg_obj) != 0) {
            c.Py_DecRef(arg_obj);
            c.Py_DecRef(tuple);
            return null;
        }

        const result = c.PyObject_CallObject(self.ptr, tuple);
        c.Py_DecRef(tuple);
        if (result == null) return null;
        return Object.owned(result);
    }

    /// Call with two arguments.
    pub fn call2(self: Object, arg0: anytype, arg1: anytype) ?Object {
        const arg0_obj = toPy(@TypeOf(arg0), arg0) orelse return null;
        const arg1_obj = toPy(@TypeOf(arg1), arg1) orelse {
            c.Py_DecRef(arg0_obj);
            return null;
        };
        const tuple = c.PyTuple_New(2) orelse {
            c.Py_DecRef(arg0_obj);
            c.Py_DecRef(arg1_obj);
            return null;
        };

        if (c.PyTuple_SetItem(tuple, 0, arg0_obj) != 0) {
            c.Py_DecRef(arg0_obj);
            c.Py_DecRef(arg1_obj);
            c.Py_DecRef(tuple);
            return null;
        }

        if (c.PyTuple_SetItem(tuple, 1, arg1_obj) != 0) {
            c.Py_DecRef(arg1_obj);
            c.Py_DecRef(tuple);
            return null;
        }

        const result = c.PyObject_CallObject(self.ptr, tuple);
        c.Py_DecRef(tuple);
        if (result == null) return null;
        return Object.owned(result);
    }

    /// Get an attribute by name.
    pub fn getAttr(self: Object, name: [:0]const u8) ?Object {
        const result = c.PyObject_GetAttrString(self.ptr, @ptrCast(name.ptr));
        if (result == null) return null;
        return Object.owned(result);
    }

    /// Set an attribute by name.
    pub fn setAttr(self: Object, name: [:0]const u8, value: anytype) bool {
        const value_obj = toPy(@TypeOf(value), value) orelse return false;
        if (c.PyObject_SetAttrString(self.ptr, @ptrCast(name.ptr), value_obj) != 0) {
            c.Py_DecRef(value_obj);
            return false;
        }
        c.Py_DecRef(value_obj);
        return true;
    }

    /// Call a method with no arguments.
    pub fn callMethod0(self: Object, name: [:0]const u8) ?Object {
        const meth = self.getAttr(name) orelse return null;
        defer meth.deinit();
        return meth.call0();
    }

    /// Call a method with one argument.
    pub fn callMethod1(self: Object, name: [:0]const u8, arg: anytype) ?Object {
        const meth = self.getAttr(name) orelse return null;
        defer meth.deinit();
        return meth.call1(arg);
    }

    /// Call a method with two arguments.
    pub fn callMethod2(self: Object, name: [:0]const u8, arg0: anytype, arg1: anytype) ?Object {
        const meth = self.getAttr(name) orelse return null;
        defer meth.deinit();
        return meth.call2(arg0, arg1);
    }
};

/// Wrapper for Python bytes objects.
pub const Bytes = struct {
    obj: Object,

    /// Create bytes from a slice.
    pub fn fromSlice(data: []const u8) ?Bytes {
        const obj = c.PyBytes_FromStringAndSize(data.ptr, @intCast(data.len)) orelse return null;
        return Bytes.owned(obj);
    }

    /// Borrow a bytes object without changing refcount.
    pub fn borrowed(ptr: *c.PyObject) Bytes {
        return .{ .obj = Object.borrowed(ptr) };
    }

    /// Own a bytes object reference.
    pub fn owned(ptr: *c.PyObject) Bytes {
        return .{ .obj = Object.owned(ptr) };
    }

    /// Release the reference if owned.
    pub fn deinit(self: Bytes) void {
        self.obj.deinit();
    }

    /// Return the byte length.
    pub fn len(self: Bytes) ?usize {
        const size = c.PyBytes_Size(self.obj.ptr);
        if (size < 0) return null;
        return @intCast(size);
    }

    /// Borrow the underlying bytes as a slice.
    pub fn slice(self: Bytes) ?[]const u8 {
        var byte_len: c.Py_ssize_t = 0;
        const raw = c.PyBytes_AsStringAndSize(self.obj.ptr, &byte_len) orelse return null;
        const ptr: [*]const u8 = @ptrCast(raw);
        return ptr[0..@intCast(byte_len)];
    }
};

/// Wrapper for Python list objects.
pub const List = struct {
    obj: Object,

    /// Borrow a list without changing refcount.
    pub fn borrowed(ptr: *c.PyObject) List {
        return .{ .obj = Object.borrowed(ptr) };
    }

    /// Own a list reference.
    pub fn owned(ptr: *c.PyObject) List {
        return .{ .obj = Object.owned(ptr) };
    }

    /// Create a new list with the given size.
    pub fn init(size: usize) ?List {
        const list_obj = c.PyList_New(@intCast(size)) orelse return null;
        return List.owned(list_obj);
    }

    /// Release the reference if owned.
    pub fn deinit(self: List) void {
        self.obj.deinit();
    }

    /// Get the list length.
    pub fn len(self: List) ?usize {
        const size = c.PyList_Size(self.obj.ptr);
        if (size < 0) return null;
        return @intCast(size);
    }

    /// Borrow the item at the given index.
    pub fn get(self: List, index: usize) ?Object {
        const item = c.PyList_GetItem(self.obj.ptr, @intCast(index)) orelse return null;
        return Object.borrowed(item);
    }

    /// Set the item at the given index.
    pub fn set(self: List, index: usize, value: anytype) bool {
        const value_obj = toPy(@TypeOf(value), value) orelse return false;
        if (c.PyList_SetItem(self.obj.ptr, @intCast(index), value_obj) != 0) {
            c.Py_DecRef(value_obj);
            return false;
        }
        return true;
    }

    /// Append an item to the list.
    pub fn append(self: List, value: anytype) bool {
        const value_obj = toPy(@TypeOf(value), value) orelse return false;
        defer c.Py_DecRef(value_obj);
        return c.PyList_Append(self.obj.ptr, value_obj) == 0;
    }
};

/// Wrapper for Python dict objects.
pub const Dict = struct {
    obj: Object,

    /// Borrow a dict without changing refcount.
    pub fn borrowed(ptr: *c.PyObject) Dict {
        return .{ .obj = Object.borrowed(ptr) };
    }

    /// Own a dict reference.
    pub fn owned(ptr: *c.PyObject) Dict {
        return .{ .obj = Object.owned(ptr) };
    }

    /// Create a new dict.
    pub fn init() ?Dict {
        const dict_obj = c.PyDict_New() orelse return null;
        return Dict.owned(dict_obj);
    }

    /// Release the reference if owned.
    pub fn deinit(self: Dict) void {
        self.obj.deinit();
    }

    /// Get the dict length.
    pub fn len(self: Dict) ?usize {
        const size = c.PyDict_Size(self.obj.ptr);
        if (size < 0) return null;
        return @intCast(size);
    }

    /// Borrow a value by key.
    pub fn getItem(self: Dict, key: anytype) ?Object {
        const key_obj = toPy(@TypeOf(key), key) orelse return null;
        defer c.Py_DecRef(key_obj);
        const item = c.PyDict_GetItemWithError(self.obj.ptr, key_obj);
        if (item == null) {
            if (c.PyErr_Occurred() != null) {
                return null;
            }
            return null;
        }
        return Object.borrowed(item);
    }

    /// Set a key to a value.
    pub fn setItem(self: Dict, key: anytype, value: anytype) bool {
        const key_obj = toPy(@TypeOf(key), key) orelse return false;
        defer c.Py_DecRef(key_obj);
        const value_obj = toPy(@TypeOf(value), value) orelse return false;
        defer c.Py_DecRef(value_obj);
        return c.PyDict_SetItem(self.obj.ptr, key_obj, value_obj) == 0;
    }

    /// Create an iterator over dict entries (borrowed references).
    pub fn iter(self: Dict) DictIter {
        return dictIter(self.obj.ptr);
    }
};

/// Borrowed dict key/value pair.
pub const DictEntry = struct {
    key: Object,
    value: Object,
};

/// Iterator over dict entries using PyDict_Next.
pub const DictIter = struct {
    dict: *c.PyObject,
    pos: c.Py_ssize_t = 0,

    /// Return the next borrowed entry, or null when complete.
    pub fn next(self: *DictIter) ?DictEntry {
        var key: ?*c.PyObject = null;
        var value: ?*c.PyObject = null;
        if (c.PyDict_Next(self.dict, &self.pos, &key, &value) == 0) return null;
        return .{
            .key = Object.borrowed(key orelse return null),
            .value = Object.borrowed(value orelse return null),
        };
    }
};

/// Wrapper for Python tuple objects.
pub const Tuple = struct {
    obj: Object,

    /// Borrow a tuple without changing refcount.
    pub fn borrowed(ptr: *c.PyObject) Tuple {
        return .{ .obj = Object.borrowed(ptr) };
    }

    /// Own a tuple reference.
    pub fn owned(ptr: *c.PyObject) Tuple {
        return .{ .obj = Object.owned(ptr) };
    }

    /// Release the reference if owned.
    pub fn deinit(self: Tuple) void {
        self.obj.deinit();
    }

    /// Get the tuple length.
    pub fn len(self: Tuple) ?usize {
        const size = c.PyTuple_Size(self.obj.ptr);
        if (size < 0) return null;
        return @intCast(size);
    }

    /// Borrow the item at the given index.
    pub fn get(self: Tuple, index: usize) ?Object {
        const item = c.PyTuple_GetItem(self.obj.ptr, @intCast(index)) orelse return null;
        return Object.borrowed(item);
    }
};

/// Convert a Python list into an owned slice.
pub fn listToSlice(comptime T: type, gpa: std.mem.Allocator, list: List) ?[]T {
    const size = list.len() orelse return null;
    const buffer = gpa.alloc(T, size) catch {
        raise(.MemoryError, "out of memory");
        return null;
    };
    var i: usize = 0;
    while (i < size) : (i += 1) {
        const item = list.get(i) orelse {
            gpa.free(buffer);
            return null;
        };
        const value = fromPy(T, item.ptr) orelse {
            gpa.free(buffer);
            return null;
        };
        buffer[i] = value;
    }
    return buffer;
}

/// Convert a Python tuple into an owned slice.
pub fn tupleToSlice(comptime T: type, gpa: std.mem.Allocator, tuple: Tuple) ?[]T {
    const size = tuple.len() orelse return null;
    const buffer = gpa.alloc(T, size) catch {
        raise(.MemoryError, "out of memory");
        return null;
    };
    var i: usize = 0;
    while (i < size) : (i += 1) {
        const item = tuple.get(i) orelse {
            gpa.free(buffer);
            return null;
        };
        const value = fromPy(T, item.ptr) orelse {
            gpa.free(buffer);
            return null;
        };
        buffer[i] = value;
    }
    return buffer;
}

/// Convert a Python dict into an owned slice of key/value pairs.
pub fn dictToEntries(
    comptime K: type,
    comptime V: type,
    gpa: std.mem.Allocator,
    dict: Dict,
) ?[]struct { key: K, value: V } {
    const size = dict.len() orelse return null;
    const Entry = struct { key: K, value: V };
    const buffer = gpa.alloc(Entry, size) catch {
        raise(.MemoryError, "out of memory");
        return null;
    };
    var iter = dict.iter();
    var i: usize = 0;
    while (iter.next()) |entry| {
        if (i >= size) break;
        const key = fromPy(K, entry.key.ptr) orelse {
            gpa.free(buffer);
            return null;
        };
        const value = fromPy(V, entry.value.ptr) orelse {
            gpa.free(buffer);
            return null;
        };
        buffer[i] = .{ .key = key, .value = value };
        i += 1;
    }
    return buffer[0..i];
}

/// Convert a Zig slice into a Python list.
pub fn toList(comptime T: type, values: []const T) ?List {
    var list = List.init(values.len) orelse return null;
    var i: usize = 0;
    while (i < values.len) : (i += 1) {
        if (!list.set(i, values[i])) {
            list.deinit();
            return null;
        }
    }
    return list;
}

/// Convert a Zig slice into a Python tuple.
pub fn toTuple(comptime T: type, values: []const T) ?Tuple {
    const tuple_obj = c.PyTuple_New(@intCast(values.len)) orelse return null;
    var i: usize = 0;
    while (i < values.len) : (i += 1) {
        const item_obj = toPy(T, values[i]) orelse {
            c.Py_DecRef(tuple_obj);
            return null;
        };
        if (c.PyTuple_SetItem(tuple_obj, @intCast(i), item_obj) != 0) {
            c.Py_DecRef(item_obj);
            c.Py_DecRef(tuple_obj);
            return null;
        }
    }
    return Tuple.owned(tuple_obj);
}

/// Convert a Zig slice of entries into a Python dict.
pub fn toDict(
    comptime K: type,
    comptime V: type,
    entries: []const struct { key: K, value: V },
) ?Dict {
    var dict = Dict.init() orelse return null;
    for (entries) |entry| {
        if (!dict.setItem(entry.key, entry.value)) {
            dict.deinit();
            return null;
        }
    }
    return dict;
}

/// Return true if the object is Python None.
pub fn isNone(obj: *c.PyObject) bool {
    return obj == pyNone();
}

/// Return true if the object is a Unicode string.
pub fn isUnicode(obj: *c.PyObject) bool {
    return c.PyUnicode_Check(obj) != 0;
}

/// Return true if the object is a bytes object.
pub fn isBytes(obj: *c.PyObject) bool {
    return c.PyBytes_Check(obj) != 0;
}

/// Return true if the object is a bool.
pub fn isBool(obj: *c.PyObject) bool {
    return c.PyBool_Check(obj) != 0;
}

/// Return true if the object is an int.
pub fn isLong(obj: *c.PyObject) bool {
    return c.PyLong_Check(obj) != 0;
}

/// Return true if the object is a float.
pub fn isFloat(obj: *c.PyObject) bool {
    return c.PyFloat_Check(obj) != 0;
}

/// Return true if the object is a list.
pub fn isList(obj: *c.PyObject) bool {
    return c.PyList_Check(obj) != 0;
}

/// Return true if the object is a tuple.
pub fn isTuple(obj: *c.PyObject) bool {
    return c.PyTuple_Check(obj) != 0;
}

/// Return true if the object is a dict.
pub fn isDict(obj: *c.PyObject) bool {
    return c.PyDict_Check(obj) != 0;
}

/// Borrow Python None as an Object.
pub fn none() Object {
    return Object.borrowed(pyNone());
}

/// Borrow the UTF-8 slice for a Unicode object.
pub fn unicodeSlice(obj: *c.PyObject) ?[]const u8 {
    var len: c.Py_ssize_t = 0;
    const raw = c.PyUnicode_AsUTF8AndSize(obj, &len) orelse return null;
    const ptr: [*]const u8 = @ptrCast(raw);
    return ptr[0..@intCast(len)];
}

/// Borrow the byte slice for a bytes object.
pub fn bytesSlice(obj: *c.PyObject) ?[]const u8 {
    var len: c.Py_ssize_t = 0;
    var raw: [*c]u8 = null;
    if (c.PyBytes_AsStringAndSize(obj, &raw, &len) != 0) return null;
    const ptr: [*]const u8 = @ptrCast(raw);
    return ptr[0..@intCast(len)];
}

/// Return the string representation of an object.
pub fn objectStr(obj: *c.PyObject) ?Object {
    const value = c.PyObject_Str(obj) orelse return null;
    return Object.owned(value);
}

/// Convert an object to truthiness.
pub fn objectIsTrue(obj: *c.PyObject) ?bool {
    const value = c.PyObject_IsTrue(obj);
    if (value < 0) return null;
    return value != 0;
}

/// Convert a float object to f64.
pub fn floatAsDouble(obj: *c.PyObject) ?f64 {
    const value = c.PyFloat_AsDouble(obj);
    if (c.PyErr_Occurred() != null) return null;
    return value;
}

/// Create a long from a base-10 string.
pub fn longFromString(text: [:0]const u8) ?Object {
    const value = c.PyLong_FromString(@ptrCast(text.ptr), null, 10) orelse return null;
    return Object.owned(value);
}

/// Create a dict iterator for low-level loops.
pub fn dictIter(dict: *c.PyObject) DictIter {
    return .{ .dict = dict };
}

/// Advance a dict iteration with PyDict_Next.
pub fn dictNext(
    dict: *c.PyObject,
    pos: *c.Py_ssize_t,
    key: *?*c.PyObject,
    value: *?*c.PyObject,
) bool {
    return c.PyDict_Next(dict, pos, key, value) != 0;
}

/// RAII guard for the Python GIL.
pub const GIL = struct {
    state: c.PyGILState_STATE,

    /// Acquire the GIL and return a guard.
    pub fn acquire() GIL {
        return .{ .state = c.PyGILState_Ensure() };
    }

    /// Release the GIL for this guard.
    pub fn deinit(self: *GIL) void {
        c.PyGILState_Release(self.state);
    }
};

/// Convert a Zig value to a Python object and wrap it.
pub fn toObject(value: anytype) ?Object {
    const obj = toPy(@TypeOf(value), value) orelse return null;
    return Object.owned(obj);
}

/// Import a module by name.
pub fn importModule(name: [:0]const u8) ?Object {
    const obj = c.PyImport_ImportModule(@ptrCast(name.ptr));
    if (obj == null) return null;
    return Object.owned(obj);
}

/// Built-in Python exception kinds.
pub const Exception = enum {
    TypeError,
    ValueError,
    RuntimeError,
    MemoryError,
    OverflowError,
    ZeroDivisionError,
    AttributeError,
    IndexError,
    KeyError,
};

/// Raise a Python exception of a given kind.
pub fn raise(comptime kind: Exception, msg: [:0]const u8) void {
    _ = c.PyErr_SetString(exceptionPtr(kind), msg);
}

/// Return true if a Python exception is already set.
pub fn errorOccurred() bool {
    return c.PyErr_Occurred() != null;
}

/// Mapping entry for raiseError.
pub const ErrorMap = struct {
    err: anyerror,
    kind: Exception,
    msg: ?[:0]const u8 = null,
};

/// Raise a mapped Python exception for a Zig error.
pub fn raiseError(err: anyerror, comptime mapping: []const ErrorMap) void {
    inline for (mapping) |entry| {
        if (err == entry.err) {
            if (entry.msg) |msg| {
                _ = c.PyErr_SetString(exceptionPtr(entry.kind), msg);
            } else {
                setPythonErrorKind(entry.kind, err);
            }
            return;
        }
    }
    setPythonError(err);
}

fn exceptionPtr(comptime kind: Exception) *c.PyObject {
    return switch (kind) {
        .TypeError => c.PyExc_TypeError,
        .ValueError => c.PyExc_ValueError,
        .RuntimeError => c.PyExc_RuntimeError,
        .MemoryError => c.PyExc_MemoryError,
        .OverflowError => c.PyExc_OverflowError,
        .ZeroDivisionError => c.PyExc_ZeroDivisionError,
        .AttributeError => c.PyExc_AttributeError,
        .IndexError => c.PyExc_IndexError,
        .KeyError => c.PyExc_KeyError,
    };
}

pub const MethodOptions = struct {
    name: ?[:0]const u8 = null,
    doc: ?[:0]const u8 = null,
    args: ?[]const [:0]const u8 = null,
    self: bool = false,
};

/// Wrap a Zig function as a Python method.
pub fn method(
    comptime func: anytype,
    comptime options: MethodOptions,
) MethodSpec(func) {
    return .{
        .func = func,
        .name = options.name,
        .doc = options.doc,
        .args = options.args,
        .self = options.self,
    };
}

/// Convenience module builder.
pub fn module(
    comptime name: [:0]const u8,
    comptime doc: [:0]const u8,
    comptime methods: anytype,
) Module {
    return Module.init(name, doc).with(methods);
}

fn MethodSpec(comptime func: anytype) type {
    return struct {
        func: @TypeOf(func),
        name: ?[:0]const u8 = null,
        doc: ?[:0]const u8 = null,
        args: ?[]const [:0]const u8 = null,
        self: bool = false,
    };
}

fn buildMethodDefs(comptime methods: anytype) [methodCount(methods) + 1]c.PyMethodDef {
    const info = @typeInfo(@TypeOf(methods));
    if (info != .@"struct") {
        @compileError("methods must be a struct literal");
    }

    const fields = info.@"struct".fields;
    var defs: [fields.len + 1]c.PyMethodDef = undefined;

    inline for (fields, 0..) |field, i| {
        defs[i] = buildMethodDef(field.name, @field(methods, field.name));
    }

    defs[fields.len] = .{ .ml_name = null, .ml_meth = null, .ml_flags = 0, .ml_doc = null };
    return defs;
}

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

fn buildMethodDef(comptime field_name: []const u8, comptime spec: anytype) c.PyMethodDef {
    const spec_info = @typeInfo(@TypeOf(spec));

    if (spec_info == .@"fn") {
        return buildMethodDefFromFunc(field_name, spec, null, null, null, false);
    }

    if (spec_info == .@"struct") {
        if (!@hasField(@TypeOf(spec), "func")) {
            @compileError("method spec must define a `func` field");
        }

        const doc = if (@hasField(@TypeOf(spec), "doc")) @field(spec, "doc") else null;
        const name_override = if (@hasField(@TypeOf(spec), "name")) @field(spec, "name") else null;
        const arg_names = if (@hasField(@TypeOf(spec), "args")) @field(spec, "args") else null;
        const include_self = if (@hasField(@TypeOf(spec), "self")) @field(spec, "self") else false;
        return buildMethodDefFromFunc(
            field_name,
            @field(spec, "func"),
            doc,
            name_override,
            arg_names,
            include_self,
        );
    }

    @compileError("method must be a function or alloconda.method(...)");
}

fn buildMethodDefFromFunc(
    comptime field_name: []const u8,
    comptime func: anytype,
    comptime doc: ?[:0]const u8,
    comptime name_override: ?[:0]const u8,
    comptime arg_names: ?[]const [:0]const u8,
    comptime include_self: bool,
) c.PyMethodDef {
    if (@typeInfo(@TypeOf(func)) != .@"fn") {
        @compileError("method func must be a function");
    }

    const name = name_override orelse cstr(field_name);
    validateArgNames(func, arg_names, include_self);
    const Wrapper = WrapperType(func, arg_names, include_self);

    return .{
        .ml_name = name,
        .ml_meth = @ptrCast(&Wrapper.call),
        .ml_flags = methodFlags(func, arg_names, include_self),
        .ml_doc = cPtr(doc),
    };
}

fn WrapperType(
    comptime func: anytype,
    comptime arg_names: ?[]const [:0]const u8,
    comptime include_self: bool,
) type {
    const has_keywords = arg_names != null;
    if (has_keywords) {
        return struct {
            fn call(
                self: ?*c.PyObject,
                args: ?*c.PyObject,
                kwargs: ?*c.PyObject,
            ) callconv(.c) ?*c.PyObject {
                return callImplKw(func, self, args, kwargs, arg_names.?, include_self);
            }
        };
    }
    return struct {
        fn call(
            self: ?*c.PyObject,
            args: ?*c.PyObject,
        ) callconv(.c) ?*c.PyObject {
            return callImpl(func, self, args, include_self);
        }
    };
}

fn methodFlags(
    comptime func: anytype,
    comptime arg_names: ?[]const [:0]const u8,
    comptime include_self: bool,
) c_int {
    const fn_info = @typeInfo(@TypeOf(func)).@"fn";
    const arg_count = if (include_self) fn_info.params.len - 1 else fn_info.params.len;
    const base = if (arg_count == 0 and arg_names == null) c.METH_NOARGS else c.METH_VARARGS;
    return if (arg_names == null) base else base | c.METH_KEYWORDS;
}

fn callImpl(
    comptime func: anytype,
    self_obj: ?*c.PyObject,
    args: ?*c.PyObject,
    comptime include_self: bool,
) ?*c.PyObject {
    const fn_info = @typeInfo(@TypeOf(func)).@"fn";
    const params = fn_info.params;

    const ParamTypes = comptime paramTypes(params);
    const arg_offset: usize = if (include_self) 1 else 0;
    const arg_count = params.len - arg_offset;

    if (arg_count == 0) {
        var tuple: std.meta.Tuple(ParamTypes) = undefined;
        if (include_self) {
            const self_val = fromPy(ParamTypes[0], self_obj) orelse return null;
            tuple[0] = self_val;
        }
        return callAndConvert(func, tuple);
    }

    const ArgTypes = comptime argTypes(ParamTypes, arg_offset);
    const min_args = comptime requiredParamCount(ArgTypes);
    const max_args = ArgTypes.len;

    const args_obj = args;
    const got: usize = if (args_obj) |obj| blk: {
        const size = c.PyTuple_Size(obj);
        if (size < 0) return null;
        break :blk @intCast(size);
    } else 0;

    if (got < min_args or got > max_args) {
        setArgCountError(min_args, max_args, got);
        return null;
    }

    var tuple: std.meta.Tuple(ParamTypes) = undefined;
    if (include_self) {
        const self_val = fromPy(ParamTypes[0], self_obj) orelse return null;
        tuple[0] = self_val;
    }

    inline for (ArgTypes, 0..) |T, i| {
        const param_index = i + arg_offset;
        if (i < got) {
            const item = c.PyTuple_GetItem(args_obj.?, @intCast(i)) orelse return null;
            const value = fromPy(T, item) orelse return null;
            tuple[param_index] = value;
        } else {
            if (comptime isOptionalType(T)) {
                tuple[param_index] = null;
            } else {
                setArgCountError(min_args, max_args, got);
                return null;
            }
        }
    }

    return callAndConvert(func, tuple);
}

fn callImplKw(
    comptime func: anytype,
    self_obj: ?*c.PyObject,
    args: ?*c.PyObject,
    kwargs: ?*c.PyObject,
    comptime arg_names: []const [:0]const u8,
    comptime include_self: bool,
) ?*c.PyObject {
    const fn_info = @typeInfo(@TypeOf(func)).@"fn";
    const params = fn_info.params;

    const ParamTypes = comptime paramTypes(params);
    const arg_offset: usize = if (include_self) 1 else 0;
    const ArgTypes = comptime argTypes(ParamTypes, arg_offset);
    const min_args = comptime requiredParamCount(ArgTypes);

    if (ArgTypes.len != arg_names.len) {
        @compileError("arg_names must match parameter count");
    }

    var tuple: std.meta.Tuple(ParamTypes) = undefined;
    if (include_self) {
        const self_val = fromPy(ParamTypes[0], self_obj) orelse return null;
        tuple[0] = self_val;
    }

    var values: [ArgTypes.len]?*c.PyObject = .{null} ** ArgTypes.len;
    var filled: [ArgTypes.len]bool = .{false} ** ArgTypes.len;

    const args_obj = args;
    const got: usize = if (args_obj) |obj| blk: {
        const size = c.PyTuple_Size(obj);
        if (size < 0) return null;
        break :blk @intCast(size);
    } else 0;

    if (got > ArgTypes.len) {
        setArgCountError(min_args, ArgTypes.len, got);
        return null;
    }

    for (values[0..got], 0..) |*slot, i| {
        const item = c.PyTuple_GetItem(args_obj.?, @intCast(i)) orelse return null;
        slot.* = item;
        filled[i] = true;
    }

    if (kwargs) |kw| {
        var pos: c.Py_ssize_t = 0;
        var key: ?*c.PyObject = null;
        var value: ?*c.PyObject = null;

        while (c.PyDict_Next(kw, &pos, &key, &value) != 0) {
            var len: c.Py_ssize_t = 0;
            const raw = c.PyUnicode_AsUTF8AndSize(key, &len) orelse return null;
            const key_slice = raw[0..@intCast(len)];
            var matched = false;

            inline for (arg_names, 0..) |name, i| {
                if (std.mem.eql(u8, key_slice, name)) {
                    if (filled[i]) {
                        setDuplicateArgError(name);
                        return null;
                    }
                    values[i] = value;
                    filled[i] = true;
                    matched = true;
                    break;
                }
            }

            if (!matched) {
                setUnexpectedKeywordError(key_slice);
                return null;
            }
        }
    }

    inline for (ArgTypes, 0..) |T, i| {
        const param_index = i + arg_offset;
        if (values[i]) |item| {
            const value = fromPy(T, item) orelse return null;
            tuple[param_index] = value;
        } else if (comptime isOptionalType(T)) {
            tuple[param_index] = null;
        } else {
            setMissingArgError(arg_names[i]);
            return null;
        }
    }

    return callAndConvert(func, tuple);
}

fn paramTypes(comptime params: []const std.builtin.Type.Fn.Param) []const type {
    var types: [params.len]type = undefined;
    inline for (params, 0..) |param, i| {
        types[i] = param.type orelse @compileError("method parameters must have a type");
    }
    return types[0..];
}

fn argTypes(comptime types: []const type, comptime offset: usize) []const type {
    if (offset > types.len) {
        @compileError("argument offset out of range");
    }
    return types[offset..];
}

fn validateArgNames(
    comptime func: anytype,
    comptime arg_names: ?[]const [:0]const u8,
    comptime include_self: bool,
) void {
    const params = @typeInfo(@TypeOf(func)).@"fn".params;

    if (include_self) {
        if (params.len == 0) {
            @compileError("include_self requires a self parameter");
        }
        const self_type = params[0].type orelse @compileError("self parameter must have a type");
        if (!isSelfParam(self_type)) {
            @compileError("self parameter must be alloconda.Object or ?alloconda.Object");
        }
    }

    if (arg_names) |names| {
        const expected = if (include_self) params.len - 1 else params.len;
        if (names.len != expected) {
            @compileError("arg_names must match parameter count");
        }

        inline for (names, 0..) |name, i| {
            if (name.len == 0) {
                @compileError("arg_names entries must be non-empty");
            }
            inline for (names[0..i]) |prev| {
                if (std.mem.eql(u8, name, prev)) {
                    @compileError("arg_names entries must be unique");
                }
            }
        }
    }
}

fn isSelfParam(comptime T: type) bool {
    if (T == Object) return true;
    if (isOptionalType(T)) {
        return @typeInfo(T).optional.child == Object;
    }
    return false;
}

fn callAndConvert(comptime func: anytype, args_tuple: anytype) ?*c.PyObject {
    const fn_info = @typeInfo(@TypeOf(func)).@"fn";
    const ret_type = fn_info.return_type orelse @compileError("method must return a value");
    const ret_info = @typeInfo(ret_type);

    if (ret_info == .error_union) {
        const payload = ret_info.error_union.payload;
        if (payload == void) {
            _ = @call(.auto, func, args_tuple) catch |err| {
                setPythonError(err);
                return null;
            };
            return c.Py_BuildValue("");
        }

        const value = @call(.auto, func, args_tuple) catch |err| {
            setPythonError(err);
            return null;
        };
        return toPy(payload, value);
    }

    if (ret_type == void) {
        _ = @call(.auto, func, args_tuple);
        return c.Py_BuildValue("");
    }

    const value = @call(.auto, func, args_tuple);
    return toPy(ret_type, value);
}

fn fromPy(comptime T: type, obj: ?*c.PyObject) ?T {
    if (@typeInfo(T) == .optional) {
        const child = @typeInfo(T).optional.child;
        if (obj == null) {
            return @as(T, null);
        }
        if (obj == pyNone()) {
            return @as(T, null);
        }
        const value = fromPy(child, obj) orelse return null;
        return @as(T, value);
    }

    if (obj == null) {
        _ = c.PyErr_SetString(c.PyExc_TypeError, "missing argument");
        return null;
    }

    if (T == Object) {
        return Object.borrowed(obj.?);
    }

    if (T == Bytes) {
        if (c.PyBytes_Check(obj) == 0) {
            raise(.TypeError, "expected bytes");
            return null;
        }
        return Bytes.borrowed(obj.?);
    }

    if (T == List) {
        if (c.PyList_Check(obj) == 0) {
            raise(.TypeError, "expected list");
            return null;
        }
        return List.borrowed(obj.?);
    }

    if (T == Tuple) {
        if (c.PyTuple_Check(obj) == 0) {
            raise(.TypeError, "expected tuple");
            return null;
        }
        return Tuple.borrowed(obj.?);
    }

    if (T == Dict) {
        if (c.PyDict_Check(obj) == 0) {
            raise(.TypeError, "expected dict");
            return null;
        }
        return Dict.borrowed(obj.?);
    }

    if (T == []const u8 or T == [:0]const u8) {
        var len: c.Py_ssize_t = 0;
        const raw = c.PyUnicode_AsUTF8AndSize(obj, &len) orelse return null;
        const slice_len: usize = @intCast(len);

        if (T == [:0]const u8) {
            const cptr: [*:0]const u8 = @ptrCast(raw);
            return cptr[0..slice_len :0];
        }

        const ptr: [*]const u8 = @ptrCast(raw);
        return ptr[0..slice_len];
    }

    if (T == bool) {
        const value = c.PyObject_IsTrue(obj);
        if (value < 0) return null;
        return value != 0;
    }

    switch (@typeInfo(T)) {
        .int => |info| {
            if (info.signedness == .signed) {
                const value = c.PyLong_AsLongLong(obj);
                if (c.PyErr_Occurred() != null) return null;
                return std.math.cast(T, value) orelse {
                    setOverflowError();
                    return null;
                };
            }

            const value = c.PyLong_AsUnsignedLongLong(obj);
            if (c.PyErr_Occurred() != null) return null;
            return std.math.cast(T, value) orelse {
                setOverflowError();
                return null;
            };
        },
        .float => {
            const value = c.PyFloat_AsDouble(obj);
            if (c.PyErr_Occurred() != null) return null;
            return @floatCast(value);
        },
        .pointer => |_| {},
        else => {},
    }

    @compileError(std.fmt.comptimePrint(
        "unsupported parameter type: {s}",
        .{@typeName(T)},
    ));
}

fn toPy(comptime T: type, value: T) ?*c.PyObject {
    if (@typeInfo(T) == .optional) {
        const child = @typeInfo(T).optional.child;
        if (value) |v| {
            return toPy(child, v);
        }
        return c.Py_BuildValue("");
    }

    if (T == ?*c.PyObject or T == *c.PyObject) {
        return value;
    }

    if (T == Object) {
        if (!value.owns_ref) {
            c.Py_IncRef(value.ptr);
        }
        return value.ptr;
    }

    if (T == Bytes) {
        if (!value.obj.owns_ref) {
            c.Py_IncRef(value.obj.ptr);
        }
        return value.obj.ptr;
    }

    if (T == List) {
        if (!value.obj.owns_ref) {
            c.Py_IncRef(value.obj.ptr);
        }
        return value.obj.ptr;
    }

    if (T == Tuple) {
        if (!value.obj.owns_ref) {
            c.Py_IncRef(value.obj.ptr);
        }
        return value.obj.ptr;
    }

    if (T == Dict) {
        if (!value.obj.owns_ref) {
            c.Py_IncRef(value.obj.ptr);
        }
        return value.obj.ptr;
    }

    if (T == []const u8 or T == [:0]const u8) {
        return c.PyUnicode_FromStringAndSize(value.ptr, @intCast(value.len));
    }

    if (T == bool) {
        return c.PyBool_FromLong(if (value) 1 else 0);
    }

    switch (@typeInfo(T)) {
        .int => |info| {
            if (info.signedness == .signed) {
                return c.PyLong_FromLongLong(@intCast(value));
            }

            return c.PyLong_FromUnsignedLongLong(@intCast(value));
        },
        .float => {
            return c.PyFloat_FromDouble(@floatCast(value));
        },
        .pointer => |_| {},
        else => {},
    }

    @compileError(std.fmt.comptimePrint(
        "unsupported return type: {s}",
        .{@typeName(T)},
    ));
}

fn setArgCountError(min_expected: usize, max_expected: usize, got: usize) void {
    var buf: [128]u8 = undefined;
    const fallback: [:0]const u8 = "argument count mismatch";
    const msg = if (min_expected == max_expected)
        std.fmt.bufPrintZ(
            &buf,
            "expected {d} arguments, got {d}",
            .{ min_expected, got },
        ) catch fallback
    else
        std.fmt.bufPrintZ(
            &buf,
            "expected {d} to {d} arguments, got {d}",
            .{ min_expected, max_expected, got },
        ) catch fallback;
    _ = c.PyErr_SetString(c.PyExc_TypeError, msg);
}

fn setDuplicateArgError(name: []const u8) void {
    var buf: [128]u8 = undefined;
    const fallback: [:0]const u8 = "duplicate argument";
    const msg = std.fmt.bufPrintZ(
        &buf,
        "got multiple values for argument '{s}'",
        .{name},
    ) catch fallback;
    _ = c.PyErr_SetString(c.PyExc_TypeError, msg);
}

fn setMissingArgError(name: []const u8) void {
    var buf: [128]u8 = undefined;
    const fallback: [:0]const u8 = "missing required argument";
    const msg = std.fmt.bufPrintZ(
        &buf,
        "missing required argument '{s}'",
        .{name},
    ) catch fallback;
    _ = c.PyErr_SetString(c.PyExc_TypeError, msg);
}

fn setUnexpectedKeywordError(name: []const u8) void {
    var buf: [128]u8 = undefined;
    const fallback: [:0]const u8 = "unexpected keyword argument";
    const msg = std.fmt.bufPrintZ(
        &buf,
        "got unexpected keyword argument '{s}'",
        .{name},
    ) catch fallback;
    _ = c.PyErr_SetString(c.PyExc_TypeError, msg);
}

fn setPythonError(err: anyerror) void {
    if (c.PyErr_Occurred() != null) {
        return;
    }
    setPythonErrorKind(.RuntimeError, err);
}

fn setPythonErrorKind(comptime kind: Exception, err: anyerror) void {
    var buf: [128]u8 = undefined;
    const fallback: [:0]const u8 = "alloconda error";
    const msg = std.fmt.bufPrintZ(&buf, "{s}", .{@errorName(err)}) catch fallback;
    _ = c.PyErr_SetString(exceptionPtr(kind), msg);
}

fn setTypeModule(type_obj: *c.PyObject, module_name: []const u8) bool {
    const mod_obj = c.PyUnicode_FromStringAndSize(module_name.ptr, @intCast(module_name.len)) orelse return false;
    defer c.Py_DecRef(mod_obj);
    return c.PyObject_SetAttrString(type_obj, @ptrCast(cstr("__module__").ptr), mod_obj) == 0;
}

fn setOverflowError() void {
    raise(.OverflowError, "integer out of range");
}

fn cstr(comptime s: []const u8) [:0]const u8 {
    return std.fmt.comptimePrint("{s}\x00", .{s});
}

fn shortTypeName(comptime name: [:0]const u8) [:0]const u8 {
    const plain = name[0..name.len];
    if (std.mem.lastIndexOfScalar(u8, plain, '.')) |idx| {
        if (idx + 1 >= plain.len) {
            @compileError("class name cannot end with '.'");
        }
        return cstr(plain[idx + 1 ..]);
    }
    return name;
}

fn cPtr(comptime value: ?[:0]const u8) [*c]const u8 {
    return if (value) |s| @ptrCast(s.ptr) else null;
}

fn methodCount(comptime methods: anytype) usize {
    const info = @typeInfo(@TypeOf(methods));
    if (info != .@"struct") {
        @compileError("methods must be a struct literal");
    }
    return info.@"struct".fields.len;
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
    const full_name = if (std.mem.lastIndexOfScalar(u8, raw_name, '.')) |idx| blk: {
        const prefix = raw_name[0..idx];
        if (!std.mem.eql(u8, prefix, module_name)) {
            @compileError(std.fmt.comptimePrint(
                "class name '{s}' must match module '{s}'",
                .{ raw_name, module_name },
            ));
        }
        break :blk class_def.name;
    } else std.fmt.comptimePrint("{s}.{s}\x00", .{ module_name, raw_name });

    return .{
        .name = full_name,
        .attr_name = class_def.attr_name,
        .slots = class_def.slots,
    };
}

fn requiredParamCount(comptime types: []const type) usize {
    var first_optional: ?usize = null;
    inline for (types, 0..) |T, i| {
        if (isOptionalType(T)) {
            if (first_optional == null) {
                first_optional = i;
            }
        } else if (first_optional != null) {
            @compileError("optional parameters must be trailing");
        }
    }
    return first_optional orelse types.len;
}

fn isOptionalType(comptime T: type) bool {
    return @typeInfo(T) == .optional;
}

fn pyNone() *c.PyObject {
    if (comptime @hasDecl(c, "Py_GetConstantBorrowed") and @hasDecl(c, "Py_CONSTANT_NONE")) {
        return c.Py_GetConstantBorrowed(c.Py_CONSTANT_NONE);
    }
    if (comptime @hasDecl(c, "_Py_NoneStruct")) {
        return &c._Py_NoneStruct;
    }
    @compileError("Python headers missing Py_None");
}
