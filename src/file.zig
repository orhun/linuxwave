const std = @import("std");

pub fn readBytes(path: []const u8, buffer: []u8) ![]u8 {
    const file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();
    const bytes_read = try file.read(buffer);
    return buffer[0..bytes_read];
}

test "read bytes from the file" {
    var cwd_buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    var cwd = try std.os.getcwd(&cwd_buffer);

    const allocator = std.testing.allocator;
    const path = try std.fs.path.join(allocator, &.{ cwd, "build.zig" });
    defer allocator.free(path);

    var buffer: [9]u8 = undefined;

    const bytes = try readBytes(path, &buffer);
    try std.testing.expectEqualStrings("const std", bytes);
}
