//! Waveform Audio File Format encoder.
//!
//! <https://en.wikipedia.org/wiki/WAV>

const std = @import("std");
const audio = @import("audio.zig");

/// File header.
const RIFF = [4]u8{ 'R', 'I', 'F', 'F' };
/// RIFF type.
const WAVE = [4]u8{ 'W', 'A', 'V', 'E' };
/// Chunk name for the information about how the waveform data is stored.
const FMT_ = [4]u8{ 'f', 'm', 't', ' ' };
/// Chunk name for the digital audio sample data.
const DATA = [4]u8{ 'd', 'a', 't', 'a' };
// Total length of the header.
const header_len: u32 = 44;
const data_chunk_pos: u32 = 36;

/// Format of the waveform data.
pub const Format = enum {
    /// Unsigned 8-bit.
    U8,
    /// Signed 16-bit little-endian.
    S16_LE,
    /// Signed 24-bit little-endian.
    S24_LE,
    /// Signed 32-bit little-endian.
    S32_LE,

    /// Returns the bytes per sample.
    pub fn getNumBytes(self: Format) u16 {
        return switch (self) {
            .U8 => 1,
            .S16_LE => 2,
            .S24_LE => 3,
            .S32_LE => 4,
        };
    }
};

/// Encoder configuration.
pub const EncoderConfig = struct {
    /// Number of channels.
    num_channels: usize,
    /// Sample rate.
    sample_rate: usize,
    /// Sample format.
    format: Format,

    /// Returns the data length needed for given duration.
    pub fn getDataLength(self: EncoderConfig, duration: usize) usize {
        return duration * (self.sample_rate * self.num_channels * self.format.getNumBytes()) - header_len;
    }

    /// Returns the number of audio frames needed for given duration.
    pub fn getFrameCount(self: EncoderConfig, duration: usize) usize {
        return duration * self.sample_rate;
    }

    /// Returns the normalized audio stream information for this encoder.
    pub fn audioInfo(self: EncoderConfig) audio.Info {
        return .{
            .channels = self.num_channels,
            .sample_rate = self.sample_rate,
        };
    }
};

pub fn encode(writer: *std.Io.Writer, data: []const u8, config: EncoderConfig) !void {
    try writeChunks(writer, config, data);
}

/// Encodes normalized interleaved PCM samples as WAV.
pub fn encodePcmF32(writer: *std.Io.Writer, samples: []const f32, config: EncoderConfig) !void {
    try config.audioInfo().validateSamples(samples);

    const data_len = samples.len * config.format.getNumBytes();
    try writeHeaderForDataLen(writer, config, @intCast(data_len), true);

    const endian = std.builtin.Endian.little;
    for (samples) |sample| {
        const value = audio.clampSample(sample);
        switch (config.format) {
            .U8 => {
                const encoded: u8 = @intFromFloat((value * 0.5 + 0.5) * @as(f32, @floatFromInt(std.math.maxInt(u8))));
                try writer.writeByte(encoded);
            },
            .S16_LE => {
                const encoded = sampleToSigned(i16, value);
                try writer.writeInt(i16, encoded, endian);
            },
            .S24_LE => {
                const encoded = sampleToSigned(i24, value);
                try writer.writeInt(i24, encoded, endian);
            },
            .S32_LE => {
                const encoded = sampleToSigned(i32, value);
                try writer.writeInt(i32, encoded, endian);
            },
        }
    }
}

fn sampleToSigned(comptime T: type, sample: f32) T {
    if (sample <= -1.0) return std.math.minInt(T);
    if (sample >= 1.0) return std.math.maxInt(T);

    const value: f64 = @floatCast(sample);
    const max: f64 = @floatFromInt(std.math.maxInt(T));
    return @intFromFloat(value * max);
}

/// Writes the headers with placeholder values for length.
///
/// This can be used while streaming the WAV file i.e. when the total length is unknown.
pub fn writeHeader(writer: *std.Io.Writer, config: EncoderConfig) !void {
    try writeChunks(writer, config, null);
}

/// Writes the WAV chunks with optional data.
///
/// <WAVE-form> → RIFF('WAVE'
///                    <fmt-ck>            // Format
///                    [<fact-ck>]         // Fact chunk
///                    [<cue-ck>]          // Cue points
///                    [<playlist-ck>]     // Playlist
///                    [<assoc-data-list>] // Associated data list
///                    <wave-data> )       // Wave data
fn writeChunks(writer: *std.Io.Writer, config: EncoderConfig, opt_data: ?[]const u8) !void {
    const data_len: u32 = if (opt_data) |data| @intCast(data.len) else 0;
    try writeHeaderForDataLen(writer, config, data_len, opt_data != null);
    if (opt_data) |data| {
        try writer.writeAll(data);
    }
}

fn writeHeaderForDataLen(writer: *std.Io.Writer, config: EncoderConfig, data_len: u32, known_data_len: bool) !void {
    // Chunk configuration.
    const bytes_per_sample = config.format.getNumBytes();
    const num_channels: u16 = @intCast(config.num_channels);
    const sample_rate: u32 = @intCast(config.sample_rate);
    const byte_rate = sample_rate * @as(u32, num_channels) * bytes_per_sample;
    const block_align: u16 = num_channels * bytes_per_sample;
    const bits_per_sample: u16 = bytes_per_sample * 8;
    const endian = std.builtin.Endian.little;
    // Write the file header.
    try writer.writeAll(&RIFF);
    if (known_data_len) {
        try writer.writeInt(u32, data_chunk_pos + data_len, endian);
    } else {
        try writer.writeInt(u32, 0, endian);
    }
    try writer.writeAll(&WAVE);
    // Write the format chunk.
    try writer.writeAll(&FMT_);
    // Encode with pulse-code modulation (LPCM).
    try writer.writeInt(u32, 16, endian);
    // Uncompressed.
    try writer.writeInt(u16, 1, endian);
    try writer.writeInt(u16, num_channels, endian);
    try writer.writeInt(u32, sample_rate, endian);
    try writer.writeInt(u32, byte_rate, endian);
    try writer.writeInt(u16, block_align, endian);
    try writer.writeInt(u16, bits_per_sample, endian);
    // Write the data chunk.
    try writer.writeAll(&DATA);
    try writer.writeInt(u32, data_len, endian);
}

test "encode WAV" {
    var buffer: [1000]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);
    try encode(&writer, &[_]u8{ 0, 0, 0, 0, 0, 0, 0, 0 }, .{
        .num_channels = 1,
        .sample_rate = 44100,
        .format = .S16_LE,
    });
    try std.testing.expectEqualSlices(u8, "RIFF", buffer[0..4]);
}

test "encode normalized PCM" {
    var buffer: [1000]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);
    try encodePcmF32(&writer, &[_]f32{ -1.0, 0.0, 1.0 }, .{
        .num_channels = 1,
        .sample_rate = 44100,
        .format = .U8,
    });
    const result = std.Io.Writer.buffered(&writer);

    try std.testing.expectEqualSlices(u8, "RIFF", result[0..4]);
    try std.testing.expectEqual(@as(usize, header_len + 3), result.len);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0, 127, 255 }, result[header_len..][0..3]);
}

test "encode signed PCM rails" {
    var buffer: [1000]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);
    try encodePcmF32(&writer, &[_]f32{ -1.0, 0.0, 1.0 }, .{
        .num_channels = 1,
        .sample_rate = 44100,
        .format = .S16_LE,
    });
    const result = std.Io.Writer.buffered(&writer);

    try std.testing.expectEqualSlices(u8, &[_]u8{ 0x00, 0x80, 0x00, 0x00, 0xff, 0x7f }, result[header_len..][0..6]);
}
