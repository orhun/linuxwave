const std = @import("std");

/// Executable name.
const exe_name = "linuxwave";

/// Version.
const version = "0.1.0-rc.4"; // managed by release.sh

/// Adds the required packages to the given executable.
///
/// This is used for providing the dependencies for main executable as well as the tests.
fn addPackages(allocator: std.mem.Allocator, exe: *std.build.LibExeObjStep) !void {
    exe.addPackagePath("clap", "libs/zig-clap/clap.zig");
    for ([_][]const u8{ "file", "gen", "wav" }) |package| {
        const path = try std.fmt.allocPrint(allocator, "src/{s}.zig", .{package});
        defer allocator.free(path);
        exe.addPackagePath(package, path);
    }
}

pub fn build(b: *std.build.Builder) !void {
    // Create an allocator.
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    // Add custom options.
    const pie = b.option(bool, "pie", "Build a Position Independent Executable") orelse true;
    const relro = b.option(bool, "relro", "Force all relocations to be read-only after processing") orelse true;
    const coverage = b.option(bool, "test-coverage", "Generate test coverage") orelse false;
    const documentation = b.option(bool, "docs", "Generate documentation") orelse false;

    // Add main executable.
    const exe = b.addExecutable(exe_name, "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    if (documentation) {
        exe.emit_docs = .emit;
    }
    exe.pie = pie;
    exe.link_z_relro = relro;
    exe.install();

    // Add packages.
    try addPackages(allocator, exe);

    // Add executable options.
    const exe_options = b.addOptions();
    exe.addOptions("build_options", exe_options);
    exe_options.addOption([]const u8, "version", version);
    exe_options.addOption([]const u8, "exe_name", exe_name);

    // Create the run step and add arguments.
    const run_cmd = exe.run();
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
        const test_module = try std.fmt.allocPrint(allocator, "src/{s}.zig", .{module});
        defer allocator.free(test_module);
        var exe_tests = b.addTest(test_module);
        if (coverage) {
            exe_tests.setExecCmd(&[_]?[]const u8{
                "kcov",
                "kcov-output",
                null,
            });
        }
        exe_tests.setTarget(target);
        exe_tests.setBuildMode(mode);
        try addPackages(allocator, exe_tests);
        exe_tests.addOptions("build_options", exe_options);
        test_step.dependOn(&exe_tests.step);
    }
}
