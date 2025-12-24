//! Protobuf wire format encoder/decoder.
//!
//! This module provides low-level primitives for reading and writing protobuf
//! wire format messages without requiring .proto files or code generation.
//!
//! Based on the protobuf encoding specification:
//! https://protobuf.dev/programming-guides/encoding/

pub const reader = @import("reader.zig");
pub const Reader = reader.Reader;
pub const Field = reader.Field;
pub const wire = @import("wire.zig");
pub const WireType = wire.WireType;
pub const Error = wire.Error;
pub const Tag = wire.Tag;
pub const writer = @import("writer.zig");
pub const Writer = writer.Writer;

test {
    @import("std").testing.refAllDecls(@This());
}
