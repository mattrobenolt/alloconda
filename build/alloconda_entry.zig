const std = @import("std");

const user = @import("user");

comptime {
    if (!@hasDecl(user, "MODULE")) {
        @compileError("Expected `pub const MODULE = ...` in the root module");
    }

    const ModuleType = @TypeOf(user.MODULE);
    if (!@hasField(ModuleType, "name")) {
        @compileError("`MODULE` must have a `name` field");
    }
    if (!@hasDecl(ModuleType, "create")) {
        @compileError("`MODULE` must define `create()`");
    }
}

const ReturnType = @TypeOf(user.MODULE.create());
const ReturnInfo = @typeInfo(ReturnType);
const PayloadType = if (ReturnInfo == .error_union) ReturnInfo.error_union.payload else @compileError(
    "MODULE.create must return PyError!*c.PyObject",
);

comptime {
    if (@typeInfo(PayloadType) != .pointer) {
        @compileError("MODULE.create must return PyError!*c.PyObject");
    }
}

fn pyInit() callconv(.c) ?PayloadType {
    return user.MODULE.create() catch return null;
}

comptime {
    const sym = std.fmt.comptimePrint("PyInit_{s}", .{user.MODULE.name});
    @export(&pyInit, .{ .name = sym });
}
