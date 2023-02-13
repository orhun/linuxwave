const std = @import("std");

const text = "【ｌｉｎｕｘｗａｖｅ】";

pub fn main() !void {
    std.debug.print("{s}\n", .{text});

    const stdout = std.io.getStdOut().writer();

    const scale = [_]f32{ 0, 2, 4, 5, 7, 9, 11, 12 };
    var i: f64 = 0;
    while (i < 1) : (i += 0.0001) {
        const note = 100 * @sin(1382 * @exp((scale['a' % 8 + 1] / 12) * @log(2.0)) * i);

        try stdout.print("{d}\n", .{@floatToInt(i32, note)});
    }
}

// const random_buffer = try generateRandom(2);
// std.debug.print("{d}\n", .{random_buffer});
fn generateRandom(comptime len: u8) ![]u8 {
    const file = try std.fs.openFileAbsolute("/dev/urandom", .{});
    defer file.close();
    var buffer: [len]u8 = undefined;
    _ = try file.readAll(&buffer);
    return &buffer;
}
