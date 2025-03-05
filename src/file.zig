//! File operations helper.

const std = @import("std");

/// Reads the given file and returns a byte array with the length of `len`.
pub fn readBytes(
    allocator: std.mem.Allocator,
    path: []const u8,
    len: usize,
) ![]u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    var list = try std.ArrayList(u8).initCapacity(allocator, len);
    var buffer = list.allocatedSlice();
    const bytes_read = try file.read(buffer);
    return buffer[0..bytes_read];
}

test "read bytes from the file" {
    // Get the current directory.
    var cwd_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const cwd = try std.posix.getcwd(&cwd_buffer);

    // Concatenate the current directory with the builder file.
    const allocator = std.testing.allocator;
    const path = try std.fs.path.join(allocator, &.{ cwd, "build.zig" });
    defer allocator.free(path);

    // Read the contents of the file and compare.
    const bytes = try readBytes(allocator, path, 9);
    try std.testing.expectEqualStrings("const std", bytes);
    defer allocator.free(bytes);
}
