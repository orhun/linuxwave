//! Normalized audio sample helpers.

/// Error set for audio stream validation.
pub const Error = error{
    InvalidChannelCount,
    InvalidSampleRate,
    InvalidSampleCount,
};

/// Audio stream information.
pub const Info = struct {
    /// Number of channels.
    channels: usize,
    /// Sample rate.
    sample_rate: usize,

    /// Returns the number of interleaved samples for the given frame count.
    pub fn sampleCount(self: Info, frames: usize) usize {
        return frames * self.channels;
    }

    /// Returns the number of frames for the given duration in seconds.
    pub fn frameCount(self: Info, duration: usize) usize {
        return duration * self.sample_rate;
    }

    /// Validates the stream information.
    pub fn validate(self: Info) Error!void {
        if (self.channels == 0) return Error.InvalidChannelCount;
        if (self.sample_rate == 0) return Error.InvalidSampleRate;
    }

    /// Validates that the sample slice contains whole interleaved frames.
    pub fn validateSamples(self: Info, samples: []const f32) Error!void {
        try self.validate();
        if (samples.len % self.channels != 0) return Error.InvalidSampleCount;
    }

    /// Returns whether two stream descriptions are identical.
    pub fn eql(self: Info, other: Info) bool {
        return self.channels == other.channels and self.sample_rate == other.sample_rate;
    }
};

/// Clamps a normalized PCM sample to the supported range.
pub fn clampSample(sample: f32) f32 {
    if (sample < -1.0) return -1.0;
    if (sample > 1.0) return 1.0;
    return sample;
}
