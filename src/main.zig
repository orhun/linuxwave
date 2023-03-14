const std = @import("std");
const wav = @import("wav.zig");
const gen = @import("gen.zig");
const file = @import("file.zig");
const clap = @import("clap");

// Banner text.
const banner = "【ｌｉｎｕｘｗａｖｅ】";
// File to read.
const source_file = "/dev/urandom";
// Semitones from the base note in a major musical scale.
const scale = [_]f32{ 0, 2, 3, 5, 7, 8, 10, 12 };
// Frequency of A4. (<https://en.wikipedia.org/wiki/A440_(pitch_standard)>)
const frequency: f32 = 440;
// Volume control.
const volume: u8 = 50;
// Parameters that the program can take.
const params = clap.parseParamsComptime(
    \\-h, --help Display this help and exit.
);

pub fn main() !void {
    // Get stdout and stderr writers.
    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    // Parse command-line arguments.
    const cli = try clap.parse(clap.Help, &params, clap.parsers.default, .{});
    defer cli.deinit();
    if (cli.args.help) {
        try stderr.print("{s}\n", .{banner});
        return clap.help(stderr, clap.Help, &params, .{});
    }

    // Read data from a file.
    var buf: [64]u8 = undefined;
    const buffer = try file.readBytes(source_file, &buf);
    std.debug.print("{d}\n", .{buffer});

    // Generate music.
    const generator = gen.Generator(&scale, frequency, volume);
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var data = std.ArrayList(u8).init(allocator);
    for (buffer) |v| {
        var gen_data = try generator.generate(allocator, v);
        defer allocator.free(gen_data);
        try data.appendSlice(gen_data);
    }

    // Encode WAV.
    try wav.Encoder(@TypeOf(stdout)).encode(stdout, data.toOwnedSlice(), .{
        .num_channels = 1,
        .sample_rate = 24000,
        .format = .signed16_lsb,
    });
}
