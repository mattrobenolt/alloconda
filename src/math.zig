const std = @import("std");

const errors = @import("errors.zig");
const PyError = errors.PyError;
const raise = errors.raise;

pub fn castOverflow(comptime T: type, x: anytype) PyError!T {
    return std.math.cast(T, x) orelse raise(.OverflowError, "integer out of range");
}
