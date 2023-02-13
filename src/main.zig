const std = @import("std");
const wav = @import("wav.zig");

const text = "【ｌｉｎｕｘｗａｖｅ】";

pub fn main() !void {
    std.debug.print("{s}\n", .{text});
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var list = std.ArrayList(u8).init(allocator);

    const stdout = std.io.getStdOut().writer();

    const scale = [_]f32{ 0, 2, 3, 5, 7, 8, 10, 12 };

    const random_buffer = try generateRandom(128);

    std.debug.print("{d}\n", .{random_buffer});

    for (random_buffer) |v| {
        var i: f64 = 0;

        while (i < 1) : (i += 0.0001) {
            const note = 100 * @sin(1382 * @exp((scale[v % 8] / 12) * @log(2.0)) * i);

            // try stdout.print("{d}\n", .{@floatToInt(u8, (note * 0.01 * 256 / 2) + 256 / 2)});
            try list.append(@floatToInt(u8, (note * 0.01 * 256 / 2) + 256 / 2));
        }
    }

    try wav.Saver(@TypeOf(stdout)).save(stdout, list.toOwnedSlice(), .{
        .num_channels = 1,
        .sample_rate = 44100,
        .format = .unsigned8,
    });
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
