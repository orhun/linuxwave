const std = @import("std");
const wav = @import("wav.zig");
const gen = @import("gen.zig");
const file = @import("file.zig");
const defaults = @import("defaults.zig");
const clap = @import("clap");
const build_options = @import("build_options");

// Banner text.
const banner = "【ｌｉｎｕｘｗａｖｅ】";
// Parameters that the program can take.
const params = clap.parseParamsComptime(
    \\-s, --scale       <SCALE>   Sets the musical scale [default: 0,2,3,5,7,8,10,12]
    \\-r, --rate        <HZ>      Sets the sample rate [default: 24000]
    \\-n, --note        <HZ>      Sets the frequency of the note [default: 440 (A4)]
    \\-c, --channels    <NUM>     Sets the number of channels [default: 1]
    \\-f, --format      <FORMAT>  Sets the sample format [default: S16_LE]
    \\-v, --volume      <VOL>     Sets the volume (0-100) [default: 50]
    \\-i, --input       <FILE>    Sets the input file [default: /dev/urandom]
    \\-o, --output      <FILE>    Sets the output file [default: output.wav]
    \\-V, --version               Display version information.
    \\-h, --help                  Display this help and exit.
);

pub fn main() !void {
    // Get stderr writer.
    const stderr = std.io.getStdErr().writer();

    // Parse command-line arguments.
    const parsers = comptime .{
        .NUM = clap.parsers.int(usize, 0),
        .SCALE = clap.parsers.string,
        .HZ = clap.parsers.float(f32),
        .VOL = clap.parsers.int(u8, 0),
        .FILE = clap.parsers.string,
        .FORMAT = clap.parsers.enumeration(wav.Format),
    };
    var diag = clap.Diagnostic{};
    const cli = clap.parse(clap.Help, &params, parsers, .{
        .diagnostic = &diag,
    }) catch |err| {
        diag.report(stderr, err) catch {};
        return err;
    };
    defer cli.deinit();
    if (cli.args.help) {
        try stderr.print("{s}\n", .{banner});
        return clap.help(stderr, clap.Help, &params, .{});
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
