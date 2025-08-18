//! Music generator.

const std = @import("std");

/// Generator configuration.
pub const GeneratorConfig = struct {
    /// Semitones from the base note in a major musical scale.
    scale: []const u8,
    /// Frequency of the note.
    ///
    /// <https://pages.mtu.edu/~suits/notefreqs.html>
    note: f32,
    /// Volume control.
    volume: u8,
};

/// Generator implementation.
pub const Generator = struct {
    /// Number of calculated samples per sine curve (affects perceived frequency).
    pub const sample_count: usize = 10000;

    /// Configuration.
    config: GeneratorConfig,

    /// Creates a new instance.
    pub fn init(config: GeneratorConfig) Generator {
        return Generator{ .config = config };
    }

    /// Generates a sound from the given sample.
    ///
    /// Returns an array that contains the amplitudes of the sound wave at a given point in time.
    pub fn generate(self: Generator, allocator: std.mem.Allocator, sample: u8) ![]u8 {
        var buffer = std.ArrayList(u8).init(allocator);
        var i: usize = 0;
        const N: f32 = @floatFromInt(sample_count);
        while (i < sample_count) : (i += 1) {
            // Calculate the frequency according to the equal temperament.
            // Hertz = 440 * 2^(semitone distance / 12)
            // (<http://en.wikipedia.org/wiki/Equal_temperament>)
            const tone_distance: f32 = @floatFromInt(self.config.scale[sample % self.config.scale.len]);
            const increment: f32 = @floatFromInt(i);
            var amp = @sin(self.config.note * std.math.pi * std.math.pow(f32, 2, tone_distance / 12) * (increment * 0.0001));
            // Scale the amplitude between 0 and 256.
            amp = (amp * std.math.maxInt(u8) / 2) + (std.math.maxInt(u8) / 2);
            // Apply the volume control.
            const volume: f32 = @floatFromInt(self.config.volume);
            amp = amp * volume / 100;

            // Apply the Hann window function.
            const index: f32 = @floatFromInt(i);
            const hann_window = 0.5 * (1.0 - std.math.cos(2.0 * std.math.pi * index / (N - 1)));
            amp = amp * hann_window;

            try buffer.append(@intFromFloat(amp));
        }
        return buffer.toOwnedSlice();
    }
};

test "generate music" {
    const config = GeneratorConfig{
        .scale = &[_]u8{ 0, 1 },
        .note = 440,
        .volume = 100,
    };
    const generator = Generator.init(config);
    const allocator = std.testing.allocator;

    var data1 = try generator.generate(allocator, 'a');
    defer allocator.free(data1);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 127, 145, 163, 181, 197, 212, 225, 235 }, data1[0..8]);
    try std.testing.expect(data1.len == 10000);

    var data2 = try generator.generate(allocator, 'b');
    defer allocator.free(data2);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 127, 144, 161, 178, 193, 208, 221, 232 }, data2[0..8]);
    try std.testing.expect(data2.len == 10000);
}
