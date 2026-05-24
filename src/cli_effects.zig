//! Command-line effect construction.

const std = @import("std");
const fx = @import("fx.zig");

const max_effects = 1;

/// Owns concrete CLI effect instances and exposes them as a chain.
pub const Effects = struct {
    storage: [max_effects]fx.Effect = undefined,
    count: usize = 0,

    echo: fx.Echo = undefined,

    /// Initializes effects enabled by command-line arguments.
    pub fn init(self: *Effects, cli_args: anytype) void {
        std.debug.assert(self.count == 0);

        if (echoEnabled(cli_args)) {
            self.echo = fx.Echo.init(echoConfig(cli_args));
            self.append(self.echo.effect());
        }
    }

    /// Returns the enabled effects as an ordered chain.
    pub fn chain(self: *Effects) fx.Chain {
        return .{ .effects = self.storage[0..self.count] };
    }

    fn append(self: *Effects, effect: fx.Effect) void {
        std.debug.assert(self.count < self.storage.len);
        self.storage[self.count] = effect;
        self.count += 1;
    }
};

fn echoConfig(cli_args: anytype) fx.EchoConfig {
    return .{
        .delay_ms = @field(cli_args, "echo-delay") orelse (fx.EchoConfig{}).delay_ms,
        .feedback = @field(cli_args, "echo-feedback") orelse (fx.EchoConfig{}).feedback,
        .mix = @field(cli_args, "echo-mix") orelse (fx.EchoConfig{}).mix,
    };
}

fn echoEnabled(cli_args: anytype) bool {
    return cli_args.echo != 0 or
        @field(cli_args, "echo-delay") != null or
        @field(cli_args, "echo-feedback") != null or
        @field(cli_args, "echo-mix") != null;
}

test "echo flags configure and enable echo" {
    const cli_args = .{
        .echo = @as(u8, 0),
        .@"echo-delay" = @as(?usize, 125),
        .@"echo-feedback" = @as(?f32, 0.25),
        .@"echo-mix" = @as(?f32, 0.75),
    };

    const config = echoConfig(cli_args);
    try std.testing.expect(echoEnabled(cli_args));
    try std.testing.expectEqual(@as(usize, 125), config.delay_ms);
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), config.feedback, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.75), config.mix, 0.001);
}

test "chain contains only enabled effects" {
    const disabled_args = .{
        .echo = @as(u8, 0),
        .@"echo-delay" = @as(?usize, null),
        .@"echo-feedback" = @as(?f32, null),
        .@"echo-mix" = @as(?f32, null),
    };
    var disabled: Effects = .{};
    disabled.init(disabled_args);
    try std.testing.expectEqual(@as(usize, 0), disabled.chain().effects.len);

    const enabled_args = .{
        .echo = @as(u8, 1),
        .@"echo-delay" = @as(?usize, null),
        .@"echo-feedback" = @as(?f32, null),
        .@"echo-mix" = @as(?f32, null),
    };
    var enabled: Effects = .{};
    enabled.init(enabled_args);
    try std.testing.expectEqual(@as(usize, 1), enabled.chain().effects.len);
}
