const std = @import("std");
const wav = @import("wav.zig");
const gen = @import("gen.zig");
const file = @import("file.zig");
const args = @import("args.zig");
const defaults = @import("defaults.zig");
const build_options = @import("build_options");
const clap = @import("clap");

pub fn main() !void {
    // Get stderr writer.
    const stderr = std.io.getStdErr().writer();

    // Parse command-line arguments.
    var diag = clap.Diagnostic{};
    const cli = clap.parse(clap.Help, &args.params, args.parsers, .{
        .diagnostic = &diag,
    }) catch |err| {
        diag.report(stderr, err) catch {};
        return err;
    };
    defer cli.deinit();
    if (cli.args.help) {
        try stderr.print("{s}\n", .{args.banner});
        return clap.help(stderr, clap.Help, &args.params, .{});
    } else if (cli.args.version) {
        try stderr.print("{s} {s}\n", .{ build_options.exe_name, build_options.version });
        return;
    }

    // Read data from a file.
    const input_file = if (cli.args.input) |input| input else defaults.input;
    var buf: [64]u8 = undefined;
    const buffer = try file.readBytes(input_file, &buf);

    // Generate music.
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var scale = std.ArrayList(u8).init(allocator);
    var splits = std.mem.split(u8, if (cli.args.scale) |s| s else defaults.scale, ",");
    while (splits.next()) |chunk| {
        try scale.append(try std.fmt.parseInt(u8, chunk, 0));
    }
    const note = if (cli.args.note) |note| note else defaults.note;
    const volume = if (cli.args.volume) |volume| volume else defaults.volume;
    const generator = gen.Generator.init(scale.toOwnedSlice(), note, volume);
    var data = std.ArrayList(u8).init(allocator);
    for (buffer) |v| {
        var gen_data = try generator.generate(allocator, v);
        defer allocator.free(gen_data);
        try data.appendSlice(gen_data);
    }

    // Encode WAV.
    const output = if (cli.args.output) |output| output else defaults.output;
    const writer = w: {
        if (std.mem.eql(u8, output, "-")) {
            break :w std.io.getStdOut().writer();
        } else {
            const out_file = try std.fs.cwd().createFile(output, .{});
            try stderr.print("Saving to {s}\n", .{output});
            break :w out_file.writer();
        }
    };
    try wav.Encoder(@TypeOf(writer)).encode(writer, data.toOwnedSlice(), .{
        .num_channels = if (cli.args.channels) |channels| channels else defaults.channels,
        .sample_rate = if (cli.args.rate) |rate| @floatToInt(usize, rate) else defaults.sample_rate,
        .format = if (cli.args.format) |format| format else defaults.format,
    });
}
