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
        .link_libc = true,
    });
    mod.addSystemIncludePath(python.include_path);

    const mod_tests = b.addTest(.{ .root_module = mod });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);

    const docs_obj = b.addObject(.{
        .name = "alloconda-docs",
        .root_module = mod,
    });
    const docs_install = b.addInstallDirectory(.{
        .source_dir = docs_obj.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "zig-docs",
    });
    const docs_step = b.step("docs", "Generate Zig API docs");
    docs_step.dependOn(&docs_install.step);
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
    const user_module = options.root_module;

    user_module.link_libc = true;
    user_module.addSystemIncludePath(python.include_path);

    const entry_source =
        \\const std = @import("std");
        \\const user = @import("user");
        \\
        \\comptime {
        \\    if (!@hasDecl(user, "MODULE")) {
        \\        @compileError("Expected `pub const MODULE = ...` in the root module");
        \\    }
        \\
        \\    const ModuleType = @TypeOf(user.MODULE);
        \\    if (!@hasField(ModuleType, "name")) {
        \\        @compileError("`MODULE` must have a `name` field");
        \\    }
        \\    if (!@hasDecl(ModuleType, "create")) {
        \\        @compileError("`MODULE` must define `create()`");
        \\    }
        \\}
        \\
        \\const ReturnType = @TypeOf(user.MODULE.create());
        \\
        \\fn pyInit() callconv(.c) ReturnType {
        \\    return user.MODULE.create();
        \\}
        \\
        \\comptime {
        \\    const sym = std.fmt.comptimePrint("PyInit_{s}", .{user.MODULE.name});
        \\    @export(&pyInit, .{ .name = sym });
        \\}
    ;

    const entry_files = b.addWriteFiles();
    const entry_path = entry_files.add("alloconda_entry.zig", entry_source);

    const entry_module = b.createModule(.{
        .root_source_file = entry_path,
        .target = user_module.resolved_target,
        .optimize = user_module.optimize,
        .strip = user_module.strip,
        .link_libc = true,
    });
    entry_module.addImport("user", user_module);

    const lib = b.addLibrary(.{
        .name = options.name,
        .linkage = .dynamic,
        .root_module = entry_module,
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

    if (std.process.getEnvVarOwned(b.allocator, "ALLOCONDA_PYTHON_INCLUDE")) |path| {
        if (path.len != 0) {
            return .{
                .include_path = .{ .cwd_relative = path },
            };
        }
    } else |err| switch (err) {
        error.EnvironmentVariableNotFound => {},
        else => @panic("Failed to read ALLOCONDA_PYTHON_INCLUDE"),
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
