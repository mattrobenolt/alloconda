const std = @import("std");

const alloconda_build = @import("alloconda");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const alloconda = b.dependency("alloconda", .{
        .target = target,
        .optimize = optimize,
    });

    const mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .strip = optimize != .Debug,
        .imports = &.{
            .{ .name = "alloconda", .module = alloconda.module("alloconda") },
        },
    });

    const lib = alloconda_build.addPythonLibrary(b, .{
        .name = "zigzon",
        .root_module = mod,
    });
    b.installArtifact(lib);
}
