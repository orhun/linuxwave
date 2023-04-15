const wav = @import("wav");

// Default input file.
pub const input = "/dev/urandom";
// Default output file.
pub const output = "output.wav";
// Semitones from the base note in a major musical scale.
pub const scale = "0,2,3,5,7,8,10,12";
// Default sample rate.
pub const sample_rate: usize = 24000;
// Frequency of A4. (<https://en.wikipedia.org/wiki/A440_(pitch_standard)>)
pub const note: f32 = 440;
// Default number of channels.
pub const channels: usize = 1;
// Default sample format.
pub const format = wav.Format.S16_LE;
// Default volume control.
pub const volume: u8 = 50;
// Default duration.
pub const duration: usize = 20;
