//! Audio effects.

const std = @import("std");
const audio = @import("audio.zig");

/// Error set for effects.
pub const Error = audio.Error || error{
    InvalidDelay,
    Unprepared,
};

/// Errors that can occur while preparing an effect for a stream.
pub const PrepareError = Error || std.mem.Allocator.Error;

/// Errors that can occur while processing samples.
pub const ProcessError = Error;

/// Runtime context passed to effects.
pub const Context = struct {
    /// Audio stream information.
    audio: audio.Info,
};

/// Type-erased effect.
pub const Effect = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    /// Type-erased effect operations.
    pub const VTable = struct {
        prepare: ?*const fn (*anyopaque, std.mem.Allocator, Context) PrepareError!void = null,
        process: *const fn (*anyopaque, []f32) ProcessError!void,
        reset: ?*const fn (*anyopaque) void = null,
        deinit: ?*const fn (*anyopaque, std.mem.Allocator) void = null,
    };

    /// Prepares the effect for the provided stream.
    pub fn prepare(self: Effect, allocator: std.mem.Allocator, context: Context) PrepareError!void {
        if (self.vtable.prepare) |prepareFn| {
            try prepareFn(self.ptr, allocator, context);
        }
    }

    /// Processes normalized interleaved PCM samples in-place.
    pub fn process(self: Effect, samples: []f32) ProcessError!void {
        try self.vtable.process(self.ptr, samples);
    }

    /// Resets any state held by the effect.
    pub fn reset(self: Effect) void {
        if (self.vtable.reset) |resetFn| {
            resetFn(self.ptr);
        }
    }

    /// Frees resources held by the effect.
    pub fn deinit(self: Effect, allocator: std.mem.Allocator) void {
        if (self.vtable.deinit) |deinitFn| {
            deinitFn(self.ptr, allocator);
        }
    }
};

/// Ordered collection of effects.
pub const Chain = struct {
    effects: []const Effect = &.{},
    info: ?audio.Info = null,

    /// Prepares each effect for the provided stream.
    pub fn prepare(self: *Chain, allocator: std.mem.Allocator, context: Context) PrepareError!void {
        try context.audio.validate();
        for (self.effects) |effect| {
            try effect.prepare(allocator, context);
        }
        self.info = context.audio;
    }

    /// Processes samples through each effect in order.
    pub fn process(self: Chain, samples: []f32) ProcessError!void {
        const info = self.info orelse return Error.Unprepared;
        try info.validateSamples(samples);
        for (self.effects) |effect| {
            try effect.process(samples);
        }
    }

    /// Resets all effects in the chain.
    pub fn reset(self: Chain) void {
        for (self.effects) |effect| {
            effect.reset();
        }
    }

    /// Frees resources held by effects in the chain.
    pub fn deinit(self: Chain, allocator: std.mem.Allocator) void {
        for (self.effects) |effect| {
            effect.deinit(allocator);
        }
    }
};

/// Echo effect configuration.
pub const EchoConfig = struct {
    /// Echo delay in milliseconds.
    delay_ms: usize = 250,
    /// Amount of delayed signal fed back into the delay line. Clamped to 0.0-1.0.
    feedback: f32 = 0.35,
    /// Wet/dry mix. 0 is dry, 1 is fully delayed.
    mix: f32 = 0.35,
};

/// Simple delay-line echo effect.
pub const Echo = struct {
    config: EchoConfig,
    info: ?audio.Info = null,
    delay: []f32 = &.{},
    pos: usize = 0,

    /// Creates a new echo effect.
    pub fn init(config: EchoConfig) Echo {
        return .{
            .config = config,
        };
    }

    /// Frees resources owned by the echo effect.
    pub fn deinit(self: *Echo, allocator: std.mem.Allocator) void {
        if (self.delay.len > 0) {
            allocator.free(self.delay);
        }
        self.delay = &.{};
        self.info = null;
        self.pos = 0;
    }

    /// Returns a type-erased effect wrapper.
    pub fn effect(self: *Echo) Effect {
        return .{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    const vtable: Effect.VTable = .{
        .prepare = prepareErased,
        .process = processErased,
        .reset = resetErased,
        .deinit = deinitErased,
    };

    fn prepareErased(ptr: *anyopaque, allocator: std.mem.Allocator, context: Context) PrepareError!void {
        const self: *Echo = @ptrCast(@alignCast(ptr));
        try self.prepare(allocator, context);
    }

    fn processErased(ptr: *anyopaque, samples: []f32) ProcessError!void {
        const self: *Echo = @ptrCast(@alignCast(ptr));
        try self.process(samples);
    }

    fn resetErased(ptr: *anyopaque) void {
        const self: *Echo = @ptrCast(@alignCast(ptr));
        self.reset();
    }

    fn deinitErased(ptr: *anyopaque, allocator: std.mem.Allocator) void {
        const self: *Echo = @ptrCast(@alignCast(ptr));
        self.deinit(allocator);
    }

    /// Allocates the delay line for the provided stream.
    pub fn prepare(self: *Echo, allocator: std.mem.Allocator, context: Context) PrepareError!void {
        try context.audio.validate();
        const delay_samples = self.delaySampleCount(context.audio);
        if (delay_samples == 0) return Error.InvalidDelay;

        if (self.info) |info| {
            if (info.eql(context.audio) and self.delay.len == delay_samples) {
                self.reset();
                return;
            }
        }

        if (self.delay.len > 0) {
            allocator.free(self.delay);
            self.delay = &.{};
            self.info = null;
            self.pos = 0;
        }

        self.delay = try allocator.alloc(f32, delay_samples);
        self.info = context.audio;
        self.reset();
    }

    /// Processes normalized interleaved PCM samples in-place.
    pub fn process(self: *Echo, samples: []f32) ProcessError!void {
        const info = self.info orelse return Error.Unprepared;
        if (self.delay.len == 0) return Error.Unprepared;
        try info.validateSamples(samples);

        const feedback = std.math.clamp(self.config.feedback, 0.0, 1.0);
        const mix = std.math.clamp(self.config.mix, 0.0, 1.0);

        for (samples) |*sample| {
            const dry = sample.*;
            const delayed = self.delay[self.pos];
            sample.* = audio.clampSample((dry * (1.0 - mix)) + (delayed * mix));
            self.delay[self.pos] = audio.clampSample(dry + (delayed * feedback));
            self.pos = (self.pos + 1) % self.delay.len;
        }
    }

    /// Clears the delay line.
    pub fn reset(self: *Echo) void {
        @memset(self.delay, 0);
        self.pos = 0;
    }

    fn delaySampleCount(self: Echo, info: audio.Info) usize {
        const delay_frames = info.sample_rate * self.config.delay_ms / 1000;
        return info.sampleCount(delay_frames);
    }
};

test "empty chain leaves samples unchanged" {
    const allocator = std.testing.allocator;
    var samples = [_]f32{ 0.25, -0.25 };
    var chain: Chain = .{};
    try chain.prepare(allocator, .{ .audio = .{ .channels = 1, .sample_rate = 1000 } });
    try chain.process(&samples);
    try std.testing.expectEqualSlices(f32, &[_]f32{ 0.25, -0.25 }, &samples);
}

test "echo applies delayed signal" {
    const allocator = std.testing.allocator;
    const info: audio.Info = .{ .channels = 1, .sample_rate = 1000 };

    var echo = Echo.init(.{
        .delay_ms = 1,
        .feedback = 0.5,
        .mix = 0.5,
    });
    defer echo.deinit(allocator);

    var samples = [_]f32{ 1.0, 0.0, 0.0 };
    var chain: Chain = .{ .effects = &.{echo.effect()} };
    try chain.prepare(allocator, .{ .audio = info });
    try chain.process(&samples);

    try std.testing.expectApproxEqAbs(@as(f32, 0.5), samples[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), samples[1], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), samples[2], 0.001);
}

test "echo clamps negative feedback to zero" {
    const allocator = std.testing.allocator;
    const info: audio.Info = .{ .channels = 1, .sample_rate = 1000 };

    var echo = Echo.init(.{
        .delay_ms = 1,
        .feedback = -0.5,
        .mix = 1.0,
    });
    defer echo.deinit(allocator);

    var samples = [_]f32{ 1.0, 0.0, 0.0 };
    var chain: Chain = .{ .effects = &.{echo.effect()} };
    try chain.prepare(allocator, .{ .audio = info });
    try chain.process(&samples);

    try std.testing.expectApproxEqAbs(@as(f32, 0.0), samples[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), samples[1], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), samples[2], 0.001);
}

test "chain rejects incomplete interleaved frame" {
    const allocator = std.testing.allocator;
    var samples = [_]f32{ 0.25, -0.25, 0.5 };
    var chain: Chain = .{};
    try chain.prepare(allocator, .{ .audio = .{ .channels = 2, .sample_rate = 1000 } });
    try std.testing.expectError(
        audio.Error.InvalidSampleCount,
        chain.process(&samples),
    );
}

test "chain rejects process before prepare" {
    var samples = [_]f32{ 0.25, -0.25 };
    const chain: Chain = .{};
    try std.testing.expectError(Error.Unprepared, chain.process(&samples));
}

test "echo can be prepared for a new stream" {
    const allocator = std.testing.allocator;
    const info: audio.Info = .{ .channels = 1, .sample_rate = 1000 };

    var echo = Echo.init(.{
        .delay_ms = 1,
    });
    defer echo.deinit(allocator);

    try echo.prepare(allocator, .{ .audio = info });
    try std.testing.expectEqual(@as(usize, 1), echo.delay.len);

    try echo.prepare(allocator, .{ .audio = .{ .channels = 2, .sample_rate = 1000 } });
    try std.testing.expectEqual(@as(usize, 2), echo.delay.len);
}
