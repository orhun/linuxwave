const std = @import("std");
pub const audio = @import("audio.zig");
pub const fx = @import("fx.zig");
pub const wav = @import("wav.zig");
pub const gen = @import("gen.zig");
const file = @import("file.zig");
const args = @import("args.zig");
const cli_effects = @import("cli_effects.zig");
const defaults = @import("defaults.zig");
const build_options = @import("build_options");
const clap = @import("clap");

/// Runs `linuxwave`.
fn run(io: std.Io, allocator: std.mem.Allocator, output: *std.Io.Writer, argv: std.process.Args) !void {
    // Parse command-line arguments.
    const cli = try clap.parse(clap.Help, &args.params, args.parsers, argv, .{ .allocator = allocator });
    defer cli.deinit();
    if (cli.args.help != 0) {
        try output.print("{s}\n", .{args.banner});
        try clap.help(output, clap.Help, &args.params, args.help_options);
        try output.flush();
        return;
    }
    if (cli.args.version != 0) {
        try output.print("{s} {s}\n", .{ build_options.exe_name, build_options.version });
        try output.flush();
        return;
    }

    // Create encoder configuration.
    const encoder_config: wav.EncoderConfig = .{
        .num_channels = if (cli.args.channels) |channels| channels else defaults.channels,
        .sample_rate = if (cli.args.rate) |rate| @intFromFloat(rate) else defaults.sample_rate,
        .format = if (cli.args.format) |format| format else defaults.format,
    };
    const audio_info = encoder_config.audioInfo();

    // Create generator configuration.
    const scale = s: {
        var scale: std.ArrayList(u8) = .empty;
        var splits = std.mem.splitAny(u8, if (cli.args.scale) |s| s else defaults.scale, ",");
        while (splits.next()) |chunk| {
            try scale.append(allocator, try std.fmt.parseInt(u8, chunk, 0));
        }
        break :s try scale.toOwnedSlice(allocator);
    };
    defer allocator.free(scale);
    const generator_config = gen.GeneratorConfig{
        .scale = scale,
        .note = if (cli.args.note) |note| note else defaults.note,
        .volume = if (cli.args.volume) |volume| volume else defaults.volume,
    };
    const duration = if (cli.args.duration) |duration| duration else defaults.duration;
    const frame_count = audio_info.frameCount(duration);
    const data_len = try std.math.divCeil(usize, frame_count, gen.Generator.sample_count);

    // Read data from a file or stdin.
    const input_file = if (cli.args.input) |input| input else defaults.input;
    const buffer = b: {
        if (std.mem.eql(u8, input_file, "-")) {
            try output.print("Reading {d} bytes from stdin\n", .{data_len});
            try output.flush();
            var read_buffer: [1024]u8 = undefined;
            var stdin_reader = std.Io.File.stdin().reader(io, &read_buffer);
            const stdin = &stdin_reader.interface;
            break :b try stdin.readAlloc(allocator, data_len);
        }

        try output.print("Reading {d} bytes from {s}\n", .{ data_len, input_file });
        try output.flush();
        break :b try file.readBytes(io, allocator, input_file, data_len);
    };
    defer allocator.free(buffer);

    // Generate music.
    const generator: gen.Generator = .init(generator_config);
    var cli_fx: cli_effects.Effects = .{};
    cli_fx.init(cli.args);
    var effects = cli_fx.chain();
    defer effects.deinit(allocator);
    const fx_context: fx.Context = .{
        .audio = audio_info,
    };
    var data: std.ArrayList(f32) = .empty;
    errdefer data.deinit(allocator);
    const target_sample_count = audio_info.sampleCount(frame_count);
    for (buffer) |v| {
        if (data.items.len >= target_sample_count) break;
        {
            const gen_data = try generator.generateSamples(allocator, v, audio_info);
            defer allocator.free(gen_data);
            const remaining_sample_count = target_sample_count - data.items.len;
            try data.appendSlice(allocator, gen_data[0..@min(gen_data.len, remaining_sample_count)]);
        }
    }
    try effects.prepare(allocator, fx_context);
    try effects.process(data.items);

    // Encode WAV.
    const out = if (cli.args.output) |out| out else defaults.output;
    var write_buffer: [1024]u8 = undefined;
    var fhandle: ?std.Io.File = null;
    defer if (fhandle) |f| {
        f.close(io);
    };
    var file_writer = w: {
        if (std.mem.eql(u8, out, "-")) {
            try output.print("Writing to stdout\n", .{});
            try output.flush();
            break :w std.Io.File.stdout().writer(io, &write_buffer);
        }

        try output.print("Saving to {s}\n", .{out});
        try output.flush();
        fhandle = try std.Io.Dir.cwd().createFile(io, out, .{});
        break :w fhandle.?.writer(io, &write_buffer);
    };
    const samples = try data.toOwnedSlice(allocator);
    defer allocator.free(samples);
    try wav.encodePcmF32(&file_writer.interface, samples, encoder_config);
    try file_writer.interface.flush();
}

/// Entry-point.
pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;
    var stderr_buffer: [1024]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writer(io, &stderr_buffer);
    const stderr = &stderr_writer.interface;
    run(io, allocator, stderr, init.minimal.args) catch |err| {
        try stderr.print("Error occurred: {}\n", .{err});
        try stderr.flush();
    };
}

test "run" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    const fake_args: std.process.Args = .{ .vector = &[_][*:0]const u8{} };
    var allocating: std.Io.Writer.Allocating = .init(allocator);
    run(io, allocator, &allocating.writer, fake_args) catch |err| {
        std.debug.print("Error occurred: {s}\n", .{@errorName(err)});
        return;
    };
    const result = allocating.toOwnedSlice() catch |err| {
        std.debug.print("Error occurred: {s}\n", .{@errorName(err)});
        return;
    };
    defer allocator.free(result);
    try std.testing.expectEqualStrings(
        \\Reading 48 bytes from /dev/urandom
        \\Saving to output.wav
        \\
    , result);
}

test "run with echo flags" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    const output_path = ".zig-cache/tmp/linuxwave-echo-test.wav";
    defer std.Io.Dir.cwd().deleteFile(io, output_path) catch {};

    const argv = [_][*:0]const u8{
        "linuxwave",
        "--echo-delay",
        "1",
        "--echo-mix",
        "0.5",
        "-r",
        "1000",
        "-d",
        "1",
        "-i",
        "build.zig",
        "-o",
        output_path,
    };
    const fake_args: std.process.Args = .{ .vector = &argv };
    var allocating: std.Io.Writer.Allocating = .init(allocator);
    try run(io, allocator, &allocating.writer, fake_args);
    const result = try allocating.toOwnedSlice();
    defer allocator.free(result);

    try std.testing.expectEqualStrings(
        \\Reading 1 bytes from build.zig
        \\Saving to .zig-cache/tmp/linuxwave-echo-test.wav
        \\
    , result);

    const stat = try std.Io.Dir.cwd().statFile(io, output_path, .{});
    try std.testing.expectEqual(@as(u64, 2044), stat.size);
}
