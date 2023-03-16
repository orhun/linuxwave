const wav = @import("wav.zig");
const clap = @import("clap");

// Banner text.
pub const banner = "【ｌｉｎｕｘｗａｖｅ】";

// Parameters that the program can take.
pub const params = clap.parseParamsComptime(
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

/// Argument parsers.
pub const parsers = .{
    .NUM = clap.parsers.int(usize, 0),
    .SCALE = clap.parsers.string,
    .HZ = clap.parsers.float(f32),
    .VOL = clap.parsers.int(u8, 0),
    .FILE = clap.parsers.string,
    .FORMAT = clap.parsers.enumeration(wav.Format),
};
