const std = @import("std");

const alloconda_build = @import("alloconda");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const alloconda = b.dependency("alloconda", .{
        .target = target,
        .optimize = optimize,
    });

    const mod = b.addModule("fastproto", .{
        .root_source_file = b.path("src/fastproto/root.zig"),
        .target = target,
        .optimize = optimize,
        .strip = optimize != .Debug,
    });

    const fastproto: std.Build.Module.Import = .{
        .name = "fastproto",
        .module = mod,
    };

    // Python bindings module
    const bindings = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .strip = optimize != .Debug,
        .imports = &.{
            .{ .name = "alloconda", .module = alloconda.module("alloconda") },
            fastproto,
        },
    });

    // Python extension library
    const lib = alloconda_build.addPythonLibrary(b, .{
        .name = "_native",
        .root_module = bindings,
    });
    const lib_install = b.addInstallArtifact(lib, .{});
    b.getInstallStep().dependOn(&lib_install.step);

    const lib_step = b.step("lib", "Build the Python extension library");
    lib_step.dependOn(&lib_install.step);

    const exe = b.addExecutable(.{
        .name = "fastproto",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .strip = optimize != .Debug,
            .imports = &.{fastproto},
        }),
    });

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
