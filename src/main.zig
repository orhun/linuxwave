const std = @import("std");
const wav = @import("wav.zig");
const gen = @import("gen.zig");
const file = @import("file.zig");
const args = @import("args.zig");
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
    const data_len = encoder_config.getDataLength(duration) / (gen.Generator.sample_count - 2);

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
    var data: std.ArrayList(u8) = .empty;
    for (buffer) |v| {
        const gen_data = try generator.generate(allocator, v);
        defer allocator.free(gen_data);
        try data.appendSlice(allocator, gen_data);
    }

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
    const wav_data = try data.toOwnedSlice(allocator);
    defer allocator.free(wav_data);
    try wav.encode(&file_writer.interface, wav_data, encoder_config);
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
        \\Reading 96 bytes from /dev/urandom
        \\Saving to output.wav
        \\
    , result);
}
