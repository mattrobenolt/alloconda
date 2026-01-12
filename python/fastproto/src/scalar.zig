//! Shared scalar encoding helpers for protobuf.

const fastproto = @import("fastproto");
const wire = fastproto.wire;
const py = @import("alloconda");
const math = py.math;

const wrap = @import("errors.zig").wrap;

pub fn writeScalarValue(writer: *fastproto.Writer, scalar: wire.Scalar, value: py.Object) !void {
    switch (scalar) {
        .i32 => {
            const raw = try value.as(i64);
            const cast = try math.castOverflow(i32, raw);
            try wrap(writer.writeScalar(.i32, cast));
        },
        .i64 => {
            const raw = try value.as(i64);
            try wrap(writer.writeScalar(.i64, raw));
        },
        .u32 => {
            const masked = try py.Long.unsignedMask(value);
            const cast: u32 = @truncate(masked);
            try wrap(writer.writeScalar(.u32, cast));
        },
        .u64 => {
            const masked = try py.Long.unsignedMask(value);
            try wrap(writer.writeScalar(.u64, masked));
        },
        .sint32 => {
            const raw = try value.as(i64);
            const cast = try math.castOverflow(i32, raw);
            try wrap(writer.writeScalar(.sint32, cast));
        },
        .sint64 => {
            const raw = try value.as(i64);
            try wrap(writer.writeScalar(.sint64, raw));
        },
        .bool => {
            const raw = try value.as(bool);
            try wrap(writer.writeScalar(.bool, raw));
        },
        .fixed64 => {
            const masked = try py.Long.unsignedMask(value);
            try wrap(writer.writeScalar(.fixed64, masked));
        },
        .sfixed64 => {
            const raw = try value.as(i64);
            try wrap(writer.writeScalar(.sfixed64, raw));
        },
        .double => {
            const raw = try value.as(f64);
            try wrap(writer.writeScalar(.double, raw));
        },
        .fixed32 => {
            const masked = try py.Long.unsignedMask(value);
            const cast: u32 = @truncate(masked);
            try wrap(writer.writeScalar(.fixed32, cast));
        },
        .sfixed32 => {
            const raw = try value.as(i64);
            const cast = try math.castOverflow(i32, raw);
            try wrap(writer.writeScalar(.sfixed32, cast));
        },
        .float => {
            const raw = try value.as(f32);
            try wrap(writer.writeScalar(.float, raw));
        },
    }
}
