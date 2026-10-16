const wav = @import("wav.zig");
const clap = @import("clap");

// Banner text.
pub const banner =
    \\
    \\ ▜ ▘
    \\ ▐ ▌▛▌▌▌▚▘▌▌▌▀▌▌▌█▌ — Generate music from the entropy of Linux 🐧🎵
    \\ ▐▖▌▌▌▙▌▞▖▚▚▘█▌▚▘▙▖   https://github.com/orhun/linuxwave
    \\
    \\Options:
;

// Parameters that the program can take.
pub const params = clap.parseParamsComptime(
    \\-s, --scale       <SCALE>   Sets the musical scale [default: 0,2,3,5,7,8,10,12]
    \\-n, --note        <HZ>      Sets the frequency of the note [default: 440 (A4)]
    \\-r, --rate        <HZ>      Sets the sample rate [default: 24000]
    \\-c, --channels    <NUM>     Sets the number of channels [default: 1]
    \\-f, --format      <FORMAT>  Sets the sample format [default: S16_LE]
    \\-v, --volume      <VOL>     Sets the volume (0-100) [default: 50]
    \\-d, --duration    <SECS>    Sets the duration [default: 20]
    \\-e, --echo                  Enables the echo effect
    \\    --echo-delay <MS>       Sets echo delay in milliseconds [default: 250]
    \\    --echo-feedback <MIX>   Sets echo feedback (0.0-1.0) [default: 0.35]
    \\    --echo-mix <MIX>        Sets echo wet/dry mix (0.0-1.0) [default: 0.35]
    \\-i, --input       <FILE>    Sets the input file [default: /dev/urandom]
    \\-o, --output      <FILE>    Sets the output file [default: output.wav]
    \\-V, --version               Display version information.
    \\-h, --help                  Display this help and exit.
);

// Style options for the help text.
pub const help_options = clap.HelpOptions{ .spacing_between_parameters = 0, .indent = 2, .description_on_new_line = false };

/// Argument parsers.
pub const parsers = .{
    .NUM = clap.parsers.int(usize, 0),
    .SCALE = clap.parsers.string,
    .HZ = clap.parsers.float(f32),
    .VOL = clap.parsers.int(u8, 0),
    .SECS = clap.parsers.int(usize, 0),
    .MS = clap.parsers.int(usize, 0),
    .MIX = clap.parsers.float(f32),
    .FILE = clap.parsers.string,
    .FORMAT = clap.parsers.enumeration(wav.Format),
};
