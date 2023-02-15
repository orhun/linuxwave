const std = @import("std");

pub fn readBytes(path: []const u8, comptime len: u8) ![]u8 {
    const file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();
    var buffer: [len]u8 = undefined;
    _ = try file.readAll(&buffer);
    return &buffer;
}
