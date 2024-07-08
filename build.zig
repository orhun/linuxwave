const std = @import("std");

/// Executable name.
const exe_name = "linuxwave";

/// Version.
const version = "0.1.5"; // managed by release.sh

/// Adds the required packages to the given executable.
///
/// This is used for providing the dependencies for main executable as well as the tests.
fn addPackages(b: *std.Build, exe: *std.Build.Step.Compile) !void {
    exe.root_module.addImport("clap", b.createModule(.{
        .root_source_file = b.path("libs/zig-clap/clap.zig"),
    }));
    for ([_][]const u8{ "file", "gen", "wav" }) |package| {
        const path = b.fmt("src/{s}.zig", .{package});
        exe.root_module.addImport(package, b.createModule(.{
            .root_source_file = b.path(path),
        }));
    }
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

    // Add custom options.
    const pie = b.option(bool, "pie", "Build a Position Independent Executable") orelse true;
    const relro = b.option(bool, "relro", "Force all relocations to be read-only after processing") orelse true;
    const coverage = b.option(bool, "test-coverage", "Generate test coverage") orelse false;
    const documentation = b.option(bool, "docs", "Generate documentation") orelse false;

    // Add main executable.
    const exe = b.addExecutable(.{
        .name = exe_name,
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
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

    // Add packages.
    try addPackages(b, exe);

    // Add executable options.
    const exe_options = b.addOptions();
    exe.root_module.addOptions("build_options", exe_options);
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
    for ([_][]const u8{ "file", "gen", "wav" }) |module| {
        const test_name = b.fmt("{s}-tests", .{module});
        const test_module = b.fmt("src/{s}.zig", .{module});
        var exe_tests = b.addTest(.{
            .name = test_name,
            .root_source_file = b.path(test_module),
            .target = target,
            .optimize = optimize,
        });
        if (coverage) {
            exe_tests.setExecCmd(&[_]?[]const u8{
                "kcov",
                "kcov-output",
                null,
            });
        }
        try addPackages(b, exe_tests);
        exe_tests.root_module.addOptions("build_options", exe_options);
        const run_unit_tests = b.addRunArtifact(exe_tests);
        test_step.dependOn(&run_unit_tests.step);
    }
}
