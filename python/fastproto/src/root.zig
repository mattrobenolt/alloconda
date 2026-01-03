//! Python bindings for fastproto.
//!
//! Exposes the Zig protobuf implementation to Python.

const py = @import("alloconda");

pub const MODULE = py.module("Fast protobuf wire format encoding/decoding.", .{}).withTypes(.{
    .Field = @import("Field.zig").Field,
    .Reader = @import("Reader.zig").Reader,
    .Writer = @import("Writer.zig").Writer,
});
