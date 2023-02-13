const std = @import("std");

pub const Format = enum {
    unsigned8,
    signed16_lsb,
    signed24_lsb,
    signed32_lsb,

    pub fn getNumBytes(self: Format) u16 {
        return switch (self) {
            .unsigned8 => 1,
            .signed16_lsb => 2,
            .signed24_lsb => 3,
            .signed32_lsb => 4,
        };
    }
};

pub const PreloadedInfo = struct {
    num_channels: usize,
    sample_rate: usize,
    format: Format,
    num_samples: usize,

    pub fn getNumBytes(self: PreloadedInfo) usize {
        return self.num_samples * self.num_channels * self.format.getNumBytes();
    }
};

// verbose is comptime so we can avoid using std.debug.warn which doesn't
// exist on some targets (e.g. wasm)
pub fn Loader(comptime Reader: type, comptime verbose: bool) type {
    return struct {
        fn readIdentifier(reader: *Reader) ![4]u8 {
            var quad: [4]u8 = undefined;
            try reader.readNoEof(&quad);
            return quad;
        }

        fn preloadError(comptime message: []const u8) !PreloadedInfo {
            if (verbose) {
                std.log.warn("{s}\n", .{message});
            }
            return error.WavLoadFailed;
        }

        pub fn preload(reader: *Reader) !PreloadedInfo {
            // read RIFF chunk descriptor (12 bytes)
            const chunk_id = try readIdentifier(reader);
            if (!std.mem.eql(u8, &chunk_id, "RIFF")) {
                return preloadError("missing \"RIFF\" header");
            }
            try reader.skipBytes(4, .{}); // ignore chunk_size
            const format_id = try readIdentifier(reader);
            if (!std.mem.eql(u8, &format_id, "WAVE")) {
                return preloadError("missing \"WAVE\" identifier");
            }

            // read "fmt" sub-chunk
            const subchunk1_id = try readIdentifier(reader);
            if (!std.mem.eql(u8, &subchunk1_id, "fmt ")) {
                return preloadError("missing \"fmt \" header");
            }
            const subchunk1_size = try reader.readIntLittle(u32);
            if (subchunk1_size != 16) {
                return preloadError("not PCM (subchunk1_size != 16)");
            }
            const audio_format = try reader.readIntLittle(u16);
            if (audio_format != 1) {
                return preloadError("not integer PCM (audio_format != 1)");
            }
            const num_channels = try reader.readIntLittle(u16);
            const sample_rate = try reader.readIntLittle(u32);
            const byte_rate = try reader.readIntLittle(u32);
            const block_align = try reader.readIntLittle(u16);
            const bits_per_sample = try reader.readIntLittle(u16);

            if (num_channels < 1 or num_channels > 16) {
                return preloadError("invalid number of channels");
            }
            if (sample_rate < 1 or sample_rate > 192000) {
                return preloadError("invalid sample_rate");
            }
            const format: Format = switch (bits_per_sample) {
                8 => .unsigned8,
                16 => .signed16_lsb,
                24 => .signed24_lsb,
                32 => .signed32_lsb,
                else => return preloadError("invalid number of bits per sample"),
            };
            const bytes_per_sample = format.getNumBytes();
            if (byte_rate != sample_rate * num_channels * bytes_per_sample) {
                return preloadError("invalid byte_rate");
            }
            if (block_align != num_channels * bytes_per_sample) {
                return preloadError("invalid block_align");
            }

            // read "data" sub-chunk header
            const subchunk2_id = try readIdentifier(reader);
            if (!std.mem.eql(u8, &subchunk2_id, "data")) {
                return preloadError("missing \"data\" header");
            }
            const subchunk2_size = try reader.readIntLittle(u32);
            if ((subchunk2_size % (num_channels * bytes_per_sample)) != 0) {
                return preloadError("invalid subchunk2_size");
            }
            const num_samples = subchunk2_size / (num_channels * bytes_per_sample);

            return PreloadedInfo{
                .num_channels = num_channels,
                .sample_rate = sample_rate,
                .format = format,
                .num_samples = num_samples,
            };
        }

        pub fn load(
            reader: *Reader,
            preloaded: PreloadedInfo,
            out_buffer: []u8,
        ) !void {
            const num_bytes = preloaded.getNumBytes();
            std.debug.assert(out_buffer.len >= num_bytes);
            try reader.readNoEof(out_buffer[0..num_bytes]);
        }
    };
}

pub const SaveInfo = struct {
    num_channels: usize,
    sample_rate: usize,
    format: Format,
};

pub fn Saver(comptime Writer: type) type {
    const data_chunk_pos: u32 = 36; // location of "data" header

    return struct {
        fn writeHelper(writer: Writer, info: SaveInfo, maybe_data: ?[]const u8) !void {
            const bytes_per_sample = info.format.getNumBytes();

            const num_channels = @intCast(u16, info.num_channels);
            const sample_rate = @intCast(u32, info.sample_rate);
            const byte_rate = sample_rate * @as(u32, num_channels) * bytes_per_sample;
            const block_align: u16 = num_channels * bytes_per_sample;
            const bits_per_sample: u16 = bytes_per_sample * 8;
            const data_len = if (maybe_data) |data| @intCast(u32, data.len) else 0;

            try writer.writeAll("RIFF");
            if (maybe_data != null) {
                try writer.writeIntLittle(u32, data_chunk_pos + 8 + data_len - 8);
            } else {
                try writer.writeIntLittle(u32, 0);
            }
            try writer.writeAll("WAVE");

            try writer.writeAll("fmt ");
            try writer.writeIntLittle(u32, 16); // PCM
            try writer.writeIntLittle(u16, 1); // uncompressed
            try writer.writeIntLittle(u16, num_channels);
            try writer.writeIntLittle(u32, sample_rate);
            try writer.writeIntLittle(u32, byte_rate);
            try writer.writeIntLittle(u16, block_align);
            try writer.writeIntLittle(u16, bits_per_sample);

            try writer.writeAll("data");
            if (maybe_data) |data| {
                try writer.writeIntLittle(u32, data_len);
                try writer.writeAll(data);
            } else {
                try writer.writeIntLittle(u32, 0);
            }
        }

        // write wav header with placeholder values for length. use this when
        // you are going to stream to the wav file and won't know the length
        // till you are done.
        pub fn writeHeader(writer: Writer, info: SaveInfo) !void {
            try writeHelper(writer, info, null);
        }

        // after streaming, call this to seek back and patch the wav header
        // with length values.
        pub fn patchHeader(writer: Writer, seeker: anytype, data_len: usize) !void {
            const data_len_u32 = @intCast(u32, data_len);

            try seeker.seekTo(4);
            try writer.writeIntLittle(u32, data_chunk_pos + 8 + data_len_u32 - 8);
            try seeker.seekTo(data_chunk_pos + 4);
            try writer.writeIntLittle(u32, data_len_u32);
        }

        // save a prepared wav (header and data) in one shot.
        pub fn save(writer: Writer, data: []const u8, info: SaveInfo) !void {
            try writeHelper(writer, info, data);
        }
    };
}

test "basic coverage (loading)" {
    const null_wav = [_]u8{
        0x52, 0x49, 0x46, 0x46, 0x7C, 0x00, 0x00, 0x00, 0x57, 0x41, 0x56,
        0x45, 0x66, 0x6D, 0x74, 0x20, 0x10, 0x00, 0x00, 0x00, 0x01, 0x00,
        0x01, 0x00, 0x44, 0xAC, 0x00, 0x00, 0x88, 0x58, 0x01, 0x00, 0x02,
        0x00, 0x10, 0x00, 0x64, 0x61, 0x74, 0x61, 0x58, 0x00, 0x00, 0x00,
        0x00, 0x00, 0xFF, 0xFF, 0x02, 0x00, 0xFF, 0xFF, 0x00, 0x00, 0x00,
        0x00, 0xFF, 0xFF, 0x02, 0x00, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0xFE, 0xFF, 0x01, 0x00, 0x01,
        0x00, 0xFE, 0xFF, 0x03, 0x00, 0xFD, 0xFF, 0x02, 0x00, 0xFF, 0xFF,
        0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0xFF, 0xFF, 0x01, 0x00, 0xFE,
        0xFF, 0x02, 0x00, 0xFF, 0xFF, 0x00, 0x00, 0x01, 0x00, 0xFF, 0xFF,
        0x00, 0x00, 0x01, 0x00, 0xFE, 0xFF, 0x02, 0x00, 0xFF, 0xFF, 0x00,
        0x00, 0x00, 0x00, 0xFF, 0xFF, 0x03, 0x00, 0xFC, 0xFF, 0x03, 0x00,
    };

    var stream = std.io.fixedBufferStream(&null_wav);
    var reader = stream.reader();
    const MyLoader = Loader(@TypeOf(reader), true);
    const preloaded = try MyLoader.preload(&reader);

    try std.testing.expectEqual(@as(usize, 1), preloaded.num_channels);
    try std.testing.expectEqual(@as(usize, 44100), preloaded.sample_rate);
    try std.testing.expectEqual(@as(Format, .signed16_lsb), preloaded.format);
    try std.testing.expectEqual(@as(usize, 44), preloaded.num_samples);

    var buffer: [88]u8 = undefined;
    try MyLoader.load(&reader, preloaded, &buffer);
}

test "basic coverage (saving)" {
    var buffer: [1000]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    var writer = stream.writer();
    try Saver(@TypeOf(writer)).save(writer, &[_]u8{ 0, 0, 0, 0, 0, 0, 0, 0 }, .{
        .num_channels = 1,
        .sample_rate = 44100,
        .format = .signed16_lsb,
    });

    try std.testing.expectEqualSlices(u8, "RIFF", buffer[0..4]);
}

test "basic coverage (streaming out)" {
    var buffer: [1000]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    const MySaver = Saver(@TypeOf(fbs).Writer);

    try MySaver.writeHeader(fbs.writer(), .{
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

    try MySaver.patchHeader(fbs.writer(), fbs.seekableStream(), data.len);
    try std.testing.expectEqual(@as(u32, 44), std.mem.readIntLittle(u32, buffer[4..8]));
    try std.testing.expectEqual(@as(u32, 8), std.mem.readIntLittle(u32, buffer[40..44]));
}
