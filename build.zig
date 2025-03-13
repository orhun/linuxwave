const std = @import("std");

/// Executable name.
const exe_name = "linuxwave";

/// Version.
const version = "0.3.0"; // managed by release.sh

/// Adds the required packages to the given module.
///
/// This is used for providing the dependencies for main executable as well as the tests.
fn addPackages(b: *std.Build, mod: *std.Build.Module) !void {
    const clap = b.dependency("clap", .{}).module("clap");
    mod.addImport("clap", clap);
}

pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const optimize = b.standardOptimizeOption(.{});

    const root = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add custom options.
    const pie = b.option(bool, "pie", "Build a Position Independent Executable") orelse true;
    const relro = b.option(bool, "relro", "Force all relocations to be read-only after processing") orelse true;
    const coverage = b.option(bool, "test-coverage", "Generate test coverage") orelse false;
    const documentation = b.option(bool, "docs", "Generate documentation") orelse false;

    // Add packages.
    try addPackages(b, root);

    // Add main executable.
    const exe = b.addExecutable(.{
        .name = exe_name,
        .root_module = root,
    });
    if (documentation) {
        const install_docs = b.addInstallDirectory(.{
            .source_dir = exe.getEmittedDocs(),
            .install_dir = .prefix,
            .install_subdir = "docs",
        });
        b.getInstallStep().dependOn(&install_docs.step);
    }
    exe.pie = pie;
    exe.link_z_relro = relro;
    b.installArtifact(exe);

    // Add executable options.
    const exe_options = b.addOptions();
    root.addOptions("build_options", exe_options);
    exe_options.addOption([]const u8, "version", version);
    exe_options.addOption([]const u8, "exe_name", exe_name);

    // Create the run step and add arguments.
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Define the run step.
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Add tests.
    const test_step = b.step("test", "Run tests");
    for ([_][]const u8{ "main", "file", "gen", "wav" }) |module| {
        const test_name = b.fmt("{s}-tests", .{module});
        const test_filepath = b.fmt("src/{s}.zig", .{module});
        const test_module = b.createModule(.{
            .root_source_file = b.path(test_filepath),
            .target = target,
            .optimize = optimize,
        });
        try addPackages(b, test_module);
        var exe_tests = b.addTest(.{
            .name = test_name,
            .root_module = test_module,
        });
        if (coverage) {
            exe_tests.setExecCmd(&[_]?[]const u8{
                "kcov",
                "kcov-output",
                null,
            });
        }
        test_module.addOptions("build_options", exe_options);
        const run_unit_tests = b.addRunArtifact(exe_tests);
        test_step.dependOn(&run_unit_tests.step);
    }
}
