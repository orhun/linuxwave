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
