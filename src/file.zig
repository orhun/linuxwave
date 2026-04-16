//! File operations helper.

const std = @import("std");

/// Reads the given file and returns a byte array with the length of `len`.
pub fn readBytes(
    io: std.Io,
    allocator: std.mem.Allocator,
    path: []const u8,
    len: usize,
) ![]u8 {
    const file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);
    var read_buffer: [1024]u8 = undefined;
    var file_reader = file.reader(io, &read_buffer);
    const reader = &file_reader.interface;
    return reader.readAlloc(allocator, len);
}

test "read bytes from the file" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    // Get the current directory.
    var cwd_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const cwd_len = try std.process.currentPath(io, &cwd_buffer);
    const cwd = cwd_buffer[0..cwd_len];

    // Concatenate the current directory with the builder file.
    const path = try std.fs.path.join(allocator, &.{ cwd, "build.zig" });
    defer allocator.free(path);

    // Read the contents of the file and compare.
    const bytes = try readBytes(io, allocator, path, 9);
    try std.testing.expectEqualStrings("const std", bytes);
    defer allocator.free(bytes);
}
