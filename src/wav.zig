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

/// Format of the waveform data.
pub const Format = enum {
    unsigned8,
    signed16_lsb,
    signed24_lsb,
    signed32_lsb,

    /// Returns the bytes per sample.
    pub fn getNumBytes(self: Format) u16 {
        return switch (self) {
            .unsigned8 => 1,
            .signed16_lsb => 2,
            .signed24_lsb => 3,
            .signed32_lsb => 4,
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
            try seeker.seekTo(4);
            try writer.writeIntLittle(u32, data_chunk_pos + 8 + data_len - 8);
            try seeker.seekTo(data_chunk_pos + 4);
            try writer.writeIntLittle(u32, data_len);
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
            const num_channels = @intCast(u16, config.num_channels);
            const sample_rate = @intCast(u32, config.sample_rate);
            const byte_rate = sample_rate * @as(u32, num_channels) * bytes_per_sample;
            const block_align: u16 = num_channels * bytes_per_sample;
            const bits_per_sample: u16 = bytes_per_sample * 8;
            const data_len = if (opt_data) |data| @intCast(u32, data.len) else 0;
            // Write the file header.
            try writer.writeAll(&RIFF);
            if (opt_data != null) {
                try writer.writeIntLittle(u32, data_chunk_pos + 8 + data_len - 8);
            } else {
                try writer.writeIntLittle(u32, 0);
            }
            try writer.writeAll(&WAVE);
            // Write the format chunk.
            try writer.writeAll(&FMT_);
            // Encode with pulse-code modulation (LPCM).
            try writer.writeIntLittle(u32, 16);
            // Uncompressed.
            try writer.writeIntLittle(u16, 1);
            try writer.writeIntLittle(u16, num_channels);
            try writer.writeIntLittle(u32, sample_rate);
            try writer.writeIntLittle(u32, byte_rate);
            try writer.writeIntLittle(u16, block_align);
            try writer.writeIntLittle(u16, bits_per_sample);
            // Write the data chunk.
            try writer.writeAll(&DATA);
            if (opt_data) |data| {
                try writer.writeIntLittle(u32, data_len);
                try writer.writeAll(data);
            } else {
                try writer.writeIntLittle(u32, 0);
            }
        }
    };
}

test "encode WAV" {
    var buffer: [1000]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    var writer = stream.writer();
    try Encoder(@TypeOf(writer)).encode(writer, &[_]u8{ 0, 0, 0, 0, 0, 0, 0, 0 }, .{
        .num_channels = 1,
        .sample_rate = 44100,
        .format = .signed16_lsb,
    });
    try std.testing.expectEqualSlices(u8, "RIFF", buffer[0..4]);
}

test "stream out WAV" {
    var buffer: [1000]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    const WavEncoder = Encoder(@TypeOf(fbs).Writer);
    try WavEncoder.writeHeader(fbs.writer(), .{
        .num_channels = 1,
        .sample_rate = 44100,
        .format = .signed16_lsb,
    });
    try std.testing.expectEqual(@as(u64, 44), try fbs.getPos());
    try std.testing.expectEqual(@as(u32, 0), std.mem.readIntLittle(u32, buffer[4..8]));
    try std.testing.expectEqual(@as(u32, 0), std.mem.readIntLittle(u32, buffer[40..44]));

    const data = &[_]u8{ 0, 0, 0, 0, 0, 0, 0, 0 };
    try fbs.writer().writeAll(data);
    try std.testing.expectEqual(@as(u64, 52), try fbs.getPos());
    try WavEncoder.patchHeader(fbs.writer(), fbs.seekableStream(), data.len);
    try std.testing.expectEqual(@as(u32, 44), std.mem.readIntLittle(u32, buffer[4..8]));
    try std.testing.expectEqual(@as(u32, 8), std.mem.readIntLittle(u32, buffer[40..44]));
}
