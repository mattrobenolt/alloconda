const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const python = pythonOptions(b, .{});

    const mod = b.addModule("alloconda", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .strip = optimize != .Debug,
    });
    mod.addSystemIncludePath(python.include_path);

    const mod_tests = b.addTest(.{ .root_module = mod });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
}

pub const Options = struct {
    include_path: std.Build.LazyPath,
};

pub const LibraryOptions = struct {
    name: []const u8,
    root_module: *std.Build.Module,
    python: ?Options = null,
};

pub fn addPythonLibrary(b: *std.Build, options: LibraryOptions) *std.Build.Step.Compile {
    const python = options.python orelse pythonOptions(b, .{});
    const root_module = options.root_module;

    root_module.addSystemIncludePath(python.include_path);

    const lib = b.addLibrary(.{
        .name = options.name,
        .linkage = .dynamic,
        .root_module = root_module,
    });
    lib.linker_allow_shlib_undefined = true;

    return lib;
}

pub fn pythonOptions(b: *std.Build, options: struct {
    include_path: ?[]const u8 = null,
}) Options {
    const include = b.option(
        []const u8,
        "python-include",
        "Path to Python include directory",
    );

    if (include orelse options.include_path) |path| {
        return .{
            .include_path = .{ .cwd_relative = path },
        };
    }

    const result = std.process.Child.run(.{
        .allocator = b.allocator,
        .argv = &.{ "python3-config", "--includes" },
    }) catch @panic("Failed to run python3-config. Install Python dev headers or use -Dpython-include=<path>");

    if (result.term != .Exited or result.term.Exited != 0) {
        @panic("python3-config failed. Use -Dpython-include=<path>");
    }

    const output = std.mem.trimEnd(u8, result.stdout, " \n");
    if (std.mem.startsWith(u8, output, "-I")) {
        const rest = output[2..];
        const end = std.mem.indexOf(u8, rest, " ") orelse rest.len;
        const path = rest[0..end];
        return .{
            .include_path = .{ .cwd_relative = path },
        };
    }

    @panic("Could not parse python3-config output");
}
