const std = @import("std");

var module_name_options: ?*std.Build.Step.Options = null;
var module_name_value: ?[]const u8 = null;

fn allocondaBuildOptions(b: *std.Build) *std.Build.Step.Options {
    if (module_name_options) |options| return options;
    const options = b.addOptions();
    module_name_options = options;
    return options;
}

fn ensureAllocondaOptions(b: *std.Build, mod: *std.Build.Module) *std.Build.Step.Options {
    const options = allocondaBuildOptions(b);
    if (mod.import_table.get("alloconda_build_options") == null) {
        mod.addOptions("alloconda_build_options", options);
    }
    return options;
}

fn setModuleNameOption(options: *std.Build.Step.Options, name: []const u8) void {
    if (module_name_value) |value| {
        if (!std.mem.eql(u8, value, name)) {
            @panic(
                "alloconda: module name already set; " ++
                    "multiple addPythonLibrary calls need distinct alloconda modules",
            );
        }
        return;
    }
    module_name_value = name;
    options.addOption([]const u8, "module_name", name);
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("alloconda", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .strip = optimize != .Debug,
        .link_libc = true,
    });

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

    // Also add include path to the alloconda module if it's imported
    if (user_module.import_table.get("alloconda")) |alloc_mod| {
        alloc_mod.addSystemIncludePath(python.include_path);
        const alloc_options = ensureAllocondaOptions(b, alloc_mod);
        setModuleNameOption(alloc_options, options.name);
    }

    const entry_source = @embedFile("build/alloconda_entry.zig");

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
    // If include_path is provided directly, use it
    if (options.include_path) |path| {
        return .{
            .include_path = .{ .cwd_relative = path },
        };
    }

    // Check for build option (only declare once per build graph)
    const include = b.option(
        []const u8,
        "python-include",
        "Path to Python include directory",
    );

    if (include) |path| {
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
