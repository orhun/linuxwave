//! Music generator.

const std = @import("std");

/// Generator implementation.
pub const Generator = struct {
    /// Semitones from the base note in a major musical scale.
    scale: []const u8,
    /// Frequency of the note.
    ///
    /// <https://pages.mtu.edu/~suits/notefreqs.html>
    note: f32,
    /// Volume control.
    volume: u8,

    /// Creates a new instance.
    pub fn init(scale: []const u8, note: f32, volume: u8) Generator {
        return Generator{
            .scale = scale,
            .note = note,
            .volume = volume,
        };
    }

    /// Generates a sound from the given sample.
    ///
    /// Returns an array that contains the amplitudes of the sound wave at a given point in time.
    pub fn generate(self: Generator, allocator: std.mem.Allocator, sample: u8) ![]const u8 {
        var buffer = std.ArrayList(u8).init(allocator);
        var i: f64 = 0;
        while (i < 1) : (i += 0.0001) {
            // Calculate the frequency according to the equal temperament.
            // Hertz = 440 * 2^(semitone distance / 12)
            // (<http://en.wikipedia.org/wiki/Equal_temperament>)
            var amp = @sin(self.note * std.math.pi *
                std.math.pow(f32, 2, @intToFloat(f32, self.scale[sample % self.scale.len]) / 12) * i);
            // Scale the amplitude between 0 and 256.
            amp = (amp * std.math.maxInt(u8) / 2) + (std.math.maxInt(u8) / 2);
            // Apply the volume control.
            amp = amp * @intToFloat(f64, self.volume) / 100;
            try buffer.append(@floatToInt(u8, amp));
        }
        return buffer.toOwnedSlice();
    }
};

test "generate music" {
    const generator = Generator.init(&[_]u8{ 0, 1 }, 440, 100);
    const allocator = std.testing.allocator;

    var data1 = try generator.generate(allocator, 'a');
    defer allocator.free(data1);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 127, 145, 163, 181, 197, 212, 225, 235 }, data1[0..8]);
    try std.testing.expect(data1.len == 10001);

    var data2 = try generator.generate(allocator, 'b');
    defer allocator.free(data2);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 127, 144, 161, 178, 193, 208, 221, 232 }, data2[0..8]);
    try std.testing.expect(data2.len == 10001);
}
