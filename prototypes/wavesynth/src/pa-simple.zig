// hand-converted PulseAudio Simple API

/// An audio stream
pub const Stream = struct {
    handle: *pa_simple,

    /// Create a new "sample upload" connection to the server.
    pub fn openUpload() !Stream {
        return open(server, name, .upload, dev, stream_name, ss, map, attr);
    }

    /// Create a new record connection to the server.
    pub fn openRecord() !Stream {
        return open(server, name, .record, dev, stream_name, ss, map, attr);
    }

    /// Create a new playback connection to the server.
    pub fn openPlayback(server: ?[*]const u8, name: [*]const u8, dev: ?[*]const u8, stream_name: [*]const u8, ss: *const SampleSpecification, map: ?*const ChannelMap, attr: ?*const BufferAttributes) !Stream {
        return open(server, name, .playback, dev, stream_name, ss, map, attr);
    }

    /// Create a new connection to the server.
    fn open(server: ?[*]const u8, name: [*]const u8, dir: StreamDirection, dev: ?[*]const u8, stream_name: [*]const u8, ss: *const SampleSpecification, map: ?*const ChannelMap, attr: ?*const BufferAttributes) !Stream {
        var err: c_int = undefined;
        var stream = pa_simple_new(server, name, dir, dev, stream_name, ss, map, attr, &err) orelse return pulseErrorToZigError(err);
        return Stream{
            .handle = stream,
        };
    }

    /// Close and free the connection to the server.
    pub fn close(stream: Stream) void {
        pa_simple_free(stream.handle);
    }

    /// Write some data to the server.
    pub fn write(stream: Stream, data: []const u8) !void {
        var err: c_int = undefined;
        if (pa_simple_write(stream.handle, data.ptr, data.len, &err) != 0)
            return pulseErrorToZigError(err);
    }

    /// Read some data from the server.
    /// This function blocks until bytes amount of data has been received from the server, or until an error occurs.
    pub fn read(stream: Stream, data: []u8) !void {
        var err: c_int = undefined;
        if (pa_simple_read(stream.handle, data.ptr, data.len, &err) != 0)
            return pulseErrorToZigError(err);
    }

    /// Wait until all data already written is played by the daemon.
    pub fn drain(stream: Stream) !void {
        var err: c_int = undefined;
        if (pa_simple_drain(stream.handle, &err) != 0)
            return pulseErrorToZigError(err);
    }

    /// Flush the playback or record buffer. This discards any audio in the buffer.
    pub fn flush(stream: Stream) !void {
        var err: c_int = undefined;
        if (pa_simple_flush(stream.handle, &err) != 0)
            return pulseErrorToZigError(err);
    }

    /// Return the playback or record latency.
    pub fn getLatencyInMicroSeconds(stream: Stream) !u64 {
        var err: c_int = 0;
        const result = pa_simple_get_latency(stream.handle, &err);
        if (err != 0)
            return pulseErrorToZigError(err);
        return result;
    }
};

const PulseError = error{UnknownError};

fn pulseErrorToZigError(errc: c_int) PulseError {
    return error.UnknownError;
}

const pa_simple = @OpaqueType();

extern fn pa_simple_new(server: ?[*]const u8, name: [*]const u8, dir: StreamDirection, dev: [*c]const u8, stream_name: [*c]const u8, ss: [*c]const SampleSpecification, map: [*c]const ChannelMap, attr: [*c]const BufferAttributes, @"error": ?*c_int) ?*pa_simple;
extern fn pa_simple_free(s: *pa_simple) void;
extern fn pa_simple_write(s: *pa_simple, data: ?*const c_void, bytes: usize, @"error": ?*c_int) c_int;
extern fn pa_simple_drain(s: *pa_simple, @"error": [*]c_int) c_int;
extern fn pa_simple_read(s: *pa_simple, data: ?*c_void, bytes: usize, @"error": ?*c_int) c_int;
extern fn pa_simple_get_latency(s: *pa_simple, @"error": ?*c_int) u64;
extern fn pa_simple_flush(s: *pa_simple, @"error": ?*c_int) c_int;

pub const StreamDirection = extern enum {
    noDirection,
    playback,
    record,
    upload,
};

pub const SampleSpecification = extern struct {
    format: SampleFormat,
    rate: u32,
    channels: u8,
};

pub const SampleFormat = extern enum {
    u8 = 0,
    alaw = 1,
    ulaw = 2,
    s16le = 3,
    s16be = 4,
    float32le = 5,
    float32be = 6,
    s32le = 7,
    s32be = 8,
    s24le = 9,
    s24be = 10,
    s24_32le = 11,
    s24_32be = 12,
    invalid = -1,
};

pub const ChannelMap = extern struct {
    channels: u8,
    map: [32]ChannelPosition,
};

pub const ChannelPosition = extern enum {
    invalid = -1,
    mono = 0,
    frontLeft = 1,
    frontRight = 2,
    frontCenter = 3,
    // left = 1,
    // right = 2,
    // center = 3,
    rearCenter = 4,
    rearLeft = 5,
    rearRight = 6,
    // lfe = 7,
    subwoofer = 7,
    frontLeftOfCenter = 8,
    frontRightOfCenter = 9,
    sideLeft = 10,
    sideRight = 11,
    aux0 = 12,
    aux1 = 13,
    aux2 = 14,
    aux3 = 15,
    aux4 = 16,
    aux5 = 17,
    aux6 = 18,
    aux7 = 19,
    aux8 = 20,
    aux9 = 21,
    aux10 = 22,
    aux11 = 23,
    aux12 = 24,
    aux13 = 25,
    aux14 = 26,
    aux15 = 27,
    aux16 = 28,
    aux17 = 29,
    aux18 = 30,
    aux19 = 31,
    aux20 = 32,
    aux21 = 33,
    aux22 = 34,
    aux23 = 35,
    aux24 = 36,
    aux25 = 37,
    aux26 = 38,
    aux27 = 39,
    aux28 = 40,
    aux29 = 41,
    aux30 = 42,
    aux31 = 43,
    topCenter = 44,
    topFrontLeft = 45,
    topFrontRight = 46,
    topFrontCenter = 47,
    topRearLeft = 48,
    topRearRight = 49,
    topRearCenter = 50,
};

pub const BufferAttributes = extern struct {
    maxlength: u32,
    tlength: u32,
    prebuf: u32,
    minreq: u32,
    fragsize: u32,
};
