const std = @import("std");

pub fn Generator(comptime scale: []const f32) type {
    return struct {
        pub fn generate(sample: u8) ![]const u8 {
            var gpa = std.heap.GeneralPurposeAllocator(.{}){};
            const allocator = gpa.allocator();
            var buffer = std.ArrayList(u8).init(allocator);
            var i: f64 = 0;
            while (i < 1) : (i += 0.0001) {
                const note = @sin(1382 * @exp((scale[sample % scale.len] / 12) * @log(2.0)) * i);
                try buffer.append(@floatToInt(u8, (note * 256 / 2) + 256 / 2));
            }
            return buffer.toOwnedSlice();
        }
    };
}
