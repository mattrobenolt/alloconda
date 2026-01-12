//! Python bindings for fastproto.
//!
//! Exposes the Zig protobuf implementation to Python.

const py = @import("alloconda");

pub const MODULE = py.module("Fast protobuf wire format encoding/decoding.", .{
    .encode = py.function(@import("encode.zig").encode, .{
        .doc = "Serialize a Python dataclass to protobuf wire format bytes.",
        .args = &.{"obj"},
    }),
    .decode = py.function(@import("decode.zig").decode, .{
        .doc = "Deserialize protobuf wire format bytes into a dataclass instance.",
        .args = &.{ "cls", "data" },
    }),
    .encode_into = py.function(@import("encode.zig").encodeInto, .{
        .doc = "Encode a dataclass into a Writer stream.",
        .args = &.{ "writer", "obj" },
    }),
    .decode_from = py.function(@import("decode.zig").decodeFrom, .{
        .doc = "Decode a dataclass from a Reader stream.",
        .args = &.{ "cls", "reader" },
    }),
}).withTypes(.{
    .Field = @import("Field.zig").Field,
    .Reader = @import("Reader.zig").Reader,
    .Writer = @import("Writer.zig").Writer,
});
