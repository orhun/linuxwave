const std = @import("std");
const wav = @import("wav.zig");
const gen = @import("gen.zig");
const file = @import("file.zig");

const text = "【ｌｉｎｕｘｗａｖｅ】";
const random_file = "/dev/urandom";
const scale = [_]f32{ 0, 2, 3, 5, 7, 8, 10, 12 };

pub fn main() !void {
    // Print banner text.
    std.debug.print("{s}\n", .{text});

    // Read data from a file.
    var buf: [64]u8 = undefined;
    const buffer = try file.readBytes(random_file, &buf);
    std.debug.print("{d}\n", .{buffer});

    // Generate notes.
    const generator = gen.Generator(&scale);
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var data = std.ArrayList(u8).init(allocator);
    for (buffer) |v| {
        var gen_data = try generator.generate(allocator, v);
        try data.appendSlice(gen_data);
    }

    // Encode WAV.
    const stdout = std.io.getStdOut().writer();
    try wav.Encoder(@TypeOf(stdout)).encode(stdout, data.toOwnedSlice(), .{
        .num_channels = 1,
        .sample_rate = 24000,
        .format = .signed16_lsb,
    });
}
