const std = @import("std");

/// Executable name.
const exe_name = "linuxwave";

/// Version.
const version = std.builtin.Version{ .major = 0, .minor = 1, .patch = 0 };

pub fn build(b: *std.build.Builder) !void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    // Add main executable.
    const exe = b.addExecutable(exe_name, "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.install();

    // Add libraries.
    exe.addPackagePath("clap", "libs/zig-clap/clap.zig");

    // Add executable options.
    const exe_options = b.addOptions();
    exe.addOptions("build_options", exe_options);
    const version_str = b.fmt("{d}.{d}.{d}", .{ version.major, version.minor, version.patch });
    exe_options.addOption([]const u8, "version", version_str);
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
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    for ([_][]const u8{ "wav", "file", "gen" }) |module| {
        const test_module = try std.fmt.allocPrint(allocator, "src/{s}.zig", .{module});
        defer allocator.free(test_module);
        var exe_tests = b.addTest(test_module);
        exe_tests.setTarget(target);
        exe_tests.setBuildMode(mode);
        test_step.dependOn(&exe_tests.step);
    }
}
