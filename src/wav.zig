//! Waveform Audio File Format encoder.
//!
//! <https://en.wikipedia.org/wiki/WAV>

const std = @import("std");

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
};

/// WAV encoder implementation.
pub fn Encoder(comptime Writer: type) type {
    // Position of the data chunk.
    const data_chunk_pos: u32 = 36;

    return struct {
        // Encode WAV.
        pub fn encode(writer: Writer, data: []const u8, config: EncoderConfig) !void {
            try writeChunks(writer, config, data);
        }

        /// Writes the headers with placeholder values for length.
        ///
        /// This can be used while streaming the WAV file i.e. when the total length is unknown.
        pub fn writeHeader(writer: Writer, config: EncoderConfig) !void {
            try writeChunks(writer, config, null);
        }

        /// Patches the headers to seek back and patch the headers for length values.
        pub fn patchHeader(writer: Writer, seeker: anytype, data_len: u32) !void {
            const endian = std.builtin.Endian.little;
            try seeker.seekTo(4);
            try writer.writeInt(u32, data_chunk_pos + 8 + data_len - 8, endian);
            try seeker.seekTo(data_chunk_pos + 4);
            try writer.writeInt(u32, data_len, endian);
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
        fn writeChunks(writer: Writer, config: EncoderConfig, opt_data: ?[]const u8) !void {
            // Chunk configuration.
            const bytes_per_sample = config.format.getNumBytes();
            const num_channels: u16 = @intCast(config.num_channels);
            const sample_rate: u32 = @intCast(config.sample_rate);
            const byte_rate = sample_rate * @as(u32, num_channels) * bytes_per_sample;
            const block_align: u16 = num_channels * bytes_per_sample;
            const bits_per_sample: u16 = bytes_per_sample * 8;
            const data_len: u32 = if (opt_data) |data| @intCast(data.len) else 0;
            const endian = std.builtin.Endian.little;
            // Write the file header.
            try writer.writeAll(&RIFF);
            if (opt_data != null) {
                try writer.writeInt(u32, data_chunk_pos + 8 + data_len - 8, endian);
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
            if (opt_data) |data| {
                try writer.writeInt(u32, data_len, endian);
                try writer.writeAll(data);
            } else {
                try writer.writeInt(u32, 0, endian);
            }
        }
    };
}

test "encode WAV" {
    var buffer: [1000]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    const writer = stream.writer();
    try Encoder(@TypeOf(writer)).encode(writer, &[_]u8{ 0, 0, 0, 0, 0, 0, 0, 0 }, .{
        .num_channels = 1,
        .sample_rate = 44100,
        .format = .S16_LE,
    });
    try std.testing.expectEqualSlices(u8, "RIFF", buffer[0..4]);
}

test "stream out WAV" {
    var buffer: [1000]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    const endian = std.builtin.Endian.little;
    const WavEncoder = Encoder(@TypeOf(fbs).Writer);
    try WavEncoder.writeHeader(fbs.writer(), .{
        .num_channels = 1,
        .sample_rate = 44100,
        .format = .S16_LE,
    });
    try std.testing.expectEqual(@as(u64, 44), try fbs.getPos());
    try std.testing.expectEqual(@as(u32, 0), std.mem.readInt(u32, buffer[4..8], endian));
    try std.testing.expectEqual(@as(u32, 0), std.mem.readInt(u32, buffer[40..44], endian));

    const data = &[_]u8{ 0, 0, 0, 0, 0, 0, 0, 0 };
    try fbs.writer().writeAll(data);
    try std.testing.expectEqual(@as(u64, 52), try fbs.getPos());
    try WavEncoder.patchHeader(fbs.writer(), fbs.seekableStream(), data.len);
    try std.testing.expectEqual(@as(u32, 44), std.mem.readInt(u32, buffer[4..8], endian));
    try std.testing.expectEqual(@as(u32, 8), std.mem.readInt(u32, buffer[40..44], endian));
}
