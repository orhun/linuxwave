const std = @import("std");

/// Executable name.
const exe_name = "linuxwave";

/// Version.
const version = "0.1.5"; // managed by release.sh

/// Adds the required packages to the given executable.
///
/// This is used for providing the dependencies for main executable as well as the tests.
fn addPackages(b: *std.Build, exe: *std.build.LibExeObjStep) !void {
    exe.addModule("clap", b.createModule(.{
        .source_file = .{ .path = "libs/zig-clap/clap.zig" },
        .dependencies = &.{},
    }));
    exe.addModule("file", b.createModule(.{
        .source_file = .{ .path = "src/file.zig" },
        .dependencies = &.{},
    }));
    exe.addModule("gen", b.createModule(.{
        .source_file = .{ .path = "src/gen.zig" },
        .dependencies = &.{},
    }));
    exe.addModule("wav", b.createModule(.{
        .source_file = .{ .path = "src/wav.zig" },
        .dependencies = &.{},
    }));
}

pub fn build(b: *std.Build) !void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
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
        .root_source_file = .{ .path = "src/main.zig" },
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
    exe.addOptions("build_options", exe_options);
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

    for ([_][]const u8{ "main", "wav", "file", "gen" }) |module| {
        const test_name = b.fmt("{s}-tests", .{module});
        const test_module = b.fmt("src/{s}.zig", .{module});
        var exe_tests = b.addTest(.{
            .name = test_name,
            .root_source_file = .{ .path = test_module },
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
        exe_tests.addOptions("build_options", exe_options);
        const run_unit_tests = b.addRunArtifact(exe_tests);
        test_step.dependOn(&run_unit_tests.step);
    }
}
