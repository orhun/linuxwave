const std = @import("std");
const wav = @import("wav.zig");
const gen = @import("gen.zig");
const file = @import("file.zig");
const args = @import("args.zig");
const defaults = @import("defaults.zig");
const build_options = @import("build_options");
const clap = @import("clap");

/// Runs `linuxwave`.
fn run(allocator: std.mem.Allocator, output: anytype) !void {
    // Parse command-line arguments.
    const cli = try clap.parse(clap.Help, &args.params, args.parsers, .{});
    defer cli.deinit();
    if (cli.args.help) {
        try output.print("{s}\n\n", .{args.banner});
        return clap.help(output, clap.Help, &args.params, .{});
    } else if (cli.args.version) {
        try output.print("{s} {s}\n", .{ build_options.exe_name, build_options.version });
        return;
    }

    // Create encoder configuration.
    const encoder_config = wav.EncoderConfig{
        .num_channels = if (cli.args.channels) |channels| channels else defaults.channels,
        .sample_rate = if (cli.args.rate) |rate| @floatToInt(usize, rate) else defaults.sample_rate,
        .format = if (cli.args.format) |format| format else defaults.format,
    };

    // Create generator configuration.
    var scale = s: {
        var scale = std.ArrayList(u8).init(allocator);
        var splits = std.mem.split(u8, if (cli.args.scale) |s| s else defaults.scale, ",");
        while (splits.next()) |chunk| {
            try scale.append(try std.fmt.parseInt(u8, chunk, 0));
        }
        break :s scale.toOwnedSlice();
    };
    defer allocator.free(scale);
    const generator_config = gen.GeneratorConfig{
        .scale = scale,
        .note = if (cli.args.note) |note| note else defaults.note,
        .volume = if (cli.args.volume) |volume| volume else defaults.volume,
    };
    const duration = if (cli.args.duration) |duration| duration else defaults.duration;
    const data_len = encoder_config.getDataLength(duration) / (gen.Generator.sample_count - 2);

    // Read data from a file.
    const input_file = if (cli.args.input) |input| input else defaults.input;
    const buffer = try file.readBytes(allocator, input_file, data_len);
    defer allocator.free(buffer);

    // Generate music.
    const generator = gen.Generator.init(generator_config);
    var data = std.ArrayList(u8).init(allocator);
    for (buffer) |v| {
        var gen_data = try generator.generate(allocator, v);
        defer allocator.free(gen_data);
        try data.appendSlice(gen_data);
    }

    // Encode WAV.
    const out = if (cli.args.output) |out| out else defaults.output;
    const writer = w: {
        if (std.mem.eql(u8, out, "-")) {
            break :w std.io.getStdOut().writer();
        } else {
            try output.print("Saving to {s}\n", .{out});
            const out_file = try std.fs.cwd().createFile(out, .{});
            break :w out_file.writer();
        }
    };
    const wav_data = data.toOwnedSlice();
    defer allocator.free(wav_data);
    try wav.Encoder(@TypeOf(writer)).encode(writer, wav_data, encoder_config);
}

/// Entry-point.
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const stderr = std.io.getStdErr().writer();
    run(allocator, stderr) catch |err| {
        try stderr.print("Error occurred: {}\n", .{err});
    };
}

test "run" {
    const allocator = std.testing.allocator;
    var buffer = std.ArrayList(u8).init(allocator);
    const output = buffer.writer();
    try run(allocator, output);
    const result = buffer.toOwnedSlice();
    defer allocator.free(result);
    try std.testing.expectEqualStrings("Saving to output.wav\n", result);
}
