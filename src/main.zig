const std = @import("std");

const text = "【ｌｉｎｕｘｗａｖｅ】";

pub fn main() !void {
    const file = try std.fs.openFileAbsolute("/dev/urandom", .{});
    defer file.close();

    var buffer: [2]u8 = undefined;
    const bytes_read = try file.readAll(&buffer);

    std.debug.print("{d}\n", .{buffer[0..bytes_read]});
    std.debug.print("{s}\n", .{text});
}
