//! Alloconda - Zig bindings for the Python C API
//!
//! This module provides ergonomic Zig wrappers for building Python extension modules.

// Core FFI and C bindings
const errors = @import("errors.zig");
pub const Exception = errors.Exception;
pub const ErrorMap = errors.ErrorMap;
pub const PyError = errors.PyError;
pub const raise = errors.raise;
pub const errorOccurred = errors.errorOccurred;
pub const raiseError = errors.raiseError;
pub const ffi = @import("ffi.zig");
pub const c = ffi.c;
pub const PyObject = c.PyObject;
pub const Py_ssize_t = c.Py_ssize_t;
pub const allocator = ffi.allocator;
pub const arenaAllocator = ffi.arenaAllocator;
pub const exceptionMatches = ffi.PyErr.exceptionMatches;
const method_mod = @import("method.zig");
pub const MethodOptions = method_mod.MethodOptions;
pub const MethodKind = method_mod.MethodKind;
pub const function = method_mod.function;
pub const method = method_mod.method;
pub const classmethod = method_mod.classmethod;
pub const staticmethod = method_mod.staticmethod;
const module_mod = @import("module.zig");
pub const Module = module_mod.Module;
pub const class = module_mod.class;
pub const baseclass = module_mod.baseclass;
pub const module = module_mod.module;
const types = @import("types.zig");
pub const Object = types.Object;
pub const Bytes = types.Bytes;
pub const BytesView = types.BytesView;
pub const Buffer = types.Buffer;
pub const BigInt = types.BigInt;
pub const Int = types.Int;
pub const List = types.List;
pub const Dict = types.Dict;
pub const Tuple = types.Tuple;
pub const DictEntry = types.DictEntry;
pub const DictIter = types.DictIter;
pub const GIL = types.GIL;
pub const Long = types.Long;
pub const importModule = types.importModule;
pub const fromPy = types.fromPy;
pub const toPy = types.toPy;
pub const none = types.none;
