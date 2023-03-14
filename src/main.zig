const std = @import("std");
const wav = @import("wav.zig");
const gen = @import("gen.zig");
const file = @import("file.zig");
const clap = @import("clap");
const build_options = @import("build_options");

// Banner text.
const banner = "【ｌｉｎｕｘｗａｖｅ】";
// Default input file.
const default_input = "/dev/urandom";
// Default output file.
const default_output = "output.wav";
// Semitones from the base note in a major musical scale.
const scale = [_]f32{ 0, 2, 3, 5, 7, 8, 10, 12 };
// Frequency of A4. (<https://en.wikipedia.org/wiki/A440_(pitch_standard)>)
const frequency: f32 = 440;
// Volume control.
const volume: u8 = 50;
// Parameters that the program can take.
const params = clap.parseParamsComptime(
    \\-i, --input   <FILE>    Sets the input file [default: /dev/urandom]
    \\-o, --output  <FILE>    Sets the output file [default: output.wav]
    \\-V, --version           Display version information.
    \\-h, --help              Display this help and exit.
);

pub fn main() !void {
    // Get stderr writer.
    const stderr = std.io.getStdErr().writer();

    // Parse command-line arguments.
    const parsers = comptime .{
        .FILE = clap.parsers.string,
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
    const input_file = if (cli.args.input) |input| input else default_input;
    var buf: [64]u8 = undefined;
    const buffer = try file.readBytes(input_file, &buf);
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
    const output = if (cli.args.output) |output| output else default_output;
    const writer = w: {
        if (std.mem.eql(u8, output, "-")) {
            break :w std.io.getStdOut().writer();
        } else {
            const out_file = try std.fs.cwd().createFile(output, .{});
            break :w out_file.writer();
        }
    };
    try wav.Encoder(@TypeOf(writer)).encode(writer, data.toOwnedSlice(), .{
        .num_channels = 1,
        .sample_rate = 24000,
        .format = .signed16_lsb,
    });
}
