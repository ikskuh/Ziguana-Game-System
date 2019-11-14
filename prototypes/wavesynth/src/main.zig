const std = @import("std");

const PA = @import("pa-simple.zig");
//     7  3 4 2
//     N  I V E
const song_text_form =
    \\C-3 1
    \\ = 
    \\ = 
    \\ = 
    \\ = 
    \\ = 
    \\ = 
    \\ = 
    \\ = 
    \\ = 
    \\ = 
    \\
    \\
    \\
    \\
    \\
    \\
    \\D-3 0 C 0
    \\E-3 0 C
    \\F-3 0
    \\G-3     0
    \\A-3   C 0
    \\ = 
    \\A-3 0   0
    \\ = 
    \\B-3
    \\B-3
    \\B-3
    \\B-3
    \\A-3
    \\ = 
    \\
    \\
    \\G-3
    \\G-3
    \\G-3
    \\G-3
    \\F-3
    \\ = 
    \\F-3
    \\ = 
    \\A-3
    \\A-3
    \\A-3
    \\A-3
    \\D-3
    \\
;

pub fn loadChannelFromText(allocator: *std.mem.Allocator, source: []const u8) ![]Event {
    var list = std.ArrayList(Event).init(allocator);
    var iterator = std.mem.separate(source, "\n");

    var lastInstr: u3 = 0;
    var lastVolume: u4 = 0xC;

    while (iterator.next()) |line| {
        std.debug.warn("'{}'\n", line);
        switch (line.len) {
            0, 3, 5, 7, 9 => {},
            else => return error.InvalidFormat,
        }

        if (line.len == 0) {
            // note-off event
            try list.append(Event.off);
            continue;
        }

        var event = Event{
            .note = if (std.mem.eql(u8, line[0..3], " = ")) Note.repeated else try Note.parse(line[0..3]),
            .instr = if (line.len >= 5 and line[4] != ' ') try std.fmt.parseInt(u3, line[4..5], 16) else lastInstr,
            .volume = if (line.len >= 7 and line[6] != ' ') try std.fmt.parseInt(u4, line[6..7], 16) else lastVolume,
            .effect = if (line.len >= 9) try std.fmt.parseInt(u2, line[8..9], 16) else 0,
        };

        lastVolume = event.volume;
        lastInstr = event.instr;

        try list.append(event);
    }
    return list.toOwnedSlice();
}

const Event = struct {
    note: Note,
    instr: u3,
    volume: u4 = 0xF,
    effect: u2 = 0x0,

    pub const off = @This(){ .note = Note{ .index = 0 }, .instr = 0, .volume = 0 };
};

/// A note on the piano keyboard.
/// Indexed "left to right", starting at C0
const Note = struct {
    index: u7,

    pub const repeated = @This(){ .index = 127 };

    /// converts english note notation (A#1) to key index (14).
    /// Lowest note is C0 (16.3516 Hz), highest note is C8 (4186,01 Hz).
    pub fn parse(spec: []const u8) !Note {
        if (spec.len < 2 or spec.len > 3)
            return error.InvalidFormat;

        var modifier: enum {
            none,
            sharp,
        } = .none;

        var noteName = spec[0];
        if (spec.len == 3) {
            modifier = switch (spec[1]) {
                '#' => @typeOf(modifier).sharp,
                '-' => .none,
                else => return error.InvalidFormat,
            };
        }

        // 0 ...
        var index = try std.fmt.parseInt(u7, spec[spec.len - 1 ..], 10);

        const allowsModifier = switch (noteName) {
            'A', 'C', 'D', 'F', 'G' => true,
            else => false,
        };
        if (!allowsModifier and modifier != .none)
            return error.InvalidNote;

        var note = 12 * index + switch (noteName) {
            'C' => @as(u7, 0),
            'D' => 2,
            'E' => 4,
            'F' => 5,
            'G' => 7,
            'A' => 9,
            'B' => 11,
            else => return error.InvalidNote,
        };
        note += switch (modifier) {
            .sharp => @as(u7, 1),
            .none => 0,
        };

        return Note{
            .index = note,
        };
    }

    // converts key index on keyboard (14) to frequency (58,2705 Hz)
    pub fn toFreq(note: Note) f32 {
        // freq(i)=440 hertz * (2^(1/12))^(i - 49)
        // see: https://en.wikipedia.org/wiki/Piano_key_frequencies
        return 440.0 * std.math.pow(f32, std.math.pow(f32, 2, 1.0 / 12.0), @intToFloat(f32, note.index) - 49.0 - 8.0); // 8.0 is the adjustment for "offset" index
    }

    pub fn format(value: Note, comptime fmt: []const u8, options: std.fmt.FormatOptions, context: var, comptime Errors: type, output: fn (@typeOf(context), []const u8) Errors!void) Errors!void {
        const name = value.index % 12;
        const offset = value.index / 12;
        try std.fmt.format(context, Errors, output, "{}{}", switch (name) {
            0 => "C",
            1 => "C#",
            2 => "D",
            3 => "D#",
            4 => "E",
            5 => "F",
            6 => "F#",
            7 => "G",
            8 => "G#",
            9 => "A",
            10 => "A#",
            11 => "B",
            else => unreachable,
        }, offset);
    }
};

test "Note.parse" {
    std.debug.assert((try Note.parse("C0")).index == 0);
    std.debug.assert((try Note.parse("C1")).index == 12);
    std.debug.assert((try Note.parse("G5")).index == 67);
    std.debug.assert((try Note.parse("A4")).index == 57);
    std.debug.assert((try Note.parse("C-1")).index == 12);
    std.debug.assert((try Note.parse("G-5")).index == 67);
    std.debug.assert((try Note.parse("A-4")).index == 57);
    std.debug.assert((try Note.parse("D#4")).index == 51);
    std.debug.assert((try Note.parse("A#6")).index == 82);
}

test "Note.toFreq" {
    const floatEq = struct {
        fn floatEq(value: f32, comptime expected: f32) bool {
            // maximum offset is 1‰
            return std.math.fabs(value - expected) < std.math.fabs(expected) / 1000.0;
        }
    }.floatEq;

    std.debug.assert(floatEq((Note{ .index = 57 }).toFreq(), 440.0)); // A4
    std.debug.assert(floatEq((Note{ .index = 48 }).toFreq(), 261.626)); // C4
    std.debug.assert(floatEq((Note{ .index = 30 }).toFreq(), 92.4986)); // F#2
    std.debug.assert(floatEq((Note{ .index = 18 }).toFreq(), 46.2493)); // F#1
    std.debug.assert(floatEq((Note{ .index = 9 }).toFreq(), 27.5)); // A0
}

test "Note.format" {
    var buffer = " " ** 64;

    std.debug.assert(std.mem.eql(u8, "A4", try std.fmt.bufPrint(buffer[0..], "{}", Note{ .index = 57 })));
    std.debug.assert(std.mem.eql(u8, "C4", try std.fmt.bufPrint(buffer[0..], "{}", Note{ .index = 48 })));
    std.debug.assert(std.mem.eql(u8, "F#2", try std.fmt.bufPrint(buffer[0..], "{}", Note{ .index = 30 })));
    std.debug.assert(std.mem.eql(u8, "F#1", try std.fmt.bufPrint(buffer[0..], "{}", Note{ .index = 18 })));
    std.debug.assert(std.mem.eql(u8, "A0", try std.fmt.bufPrint(buffer[0..], "{}", Note{ .index = 9 })));
}

pub fn bpmToSecondsPerBeat(bpm: f32) f32 {
    return (60.0 / bpm);
}

const Instrument = struct {
    const This = @This();

    envelope: Envelope,
    waveform: Waveform,

    pub fn synthesize(this: Instrument, time: f32, note: Note, on_time: f32, off_time: ?f32) f32 {
        const env = this.envelope.getAmplitude(time, on_time, off_time);

        return env * (oscillate(time, note.toFreq(), this.waveform));
    }
};

const Channel = struct {
    const This = @This();

    events: []const Event,
    instruments: []const Instrument,

    const CurrentNote = struct {
        note: Note,
        on_time: f32,
        off_time: ?f32,
        instrument: u3,
    };

    currentNote: ?CurrentNote = null,
    currentVolume: f32 = 1.0,

    pub fn synthesize(this: *This, time: f32, tempo: f32) f32 {
        if (time < 0)
            return 0.0;
        const time_per_beat = bpmToSecondsPerBeat(tempo);
        const trackIndex = @floatToInt(usize, std.math.floor(time / time_per_beat));
        if (trackIndex >= this.events.len)
            return 0.0;

        const start_of_note = time_per_beat * @intToFloat(f32, trackIndex);

        const event = this.events[trackIndex];

        const is_on = (event.volume > 0);
        if (is_on) {
            if (event.note.index != Note.repeated.index) {
                this.currentNote = CurrentNote{
                    .note = event.note,
                    .on_time = start_of_note,
                    .off_time = null,
                    .instrument = event.instr,
                };
            }
            this.currentVolume = @intToFloat(f32, event.volume) / @intToFloat(f32, std.math.maxInt(@typeOf(event.volume)));
        } else if (this.currentNote) |*cn| {
            if (cn.off_time == null) {
                std.debug.assert(start_of_note > cn.on_time);
                cn.off_time = start_of_note;
                std.debug.warn("turn off @ {}: {}\n", time, this.currentNote);
            }
        }

        if (this.currentNote) |cn| {
            const instrument = this.instruments[cn.instrument];
            return this.currentVolume * instrument.synthesize(time, cn.note, cn.on_time, cn.off_time);
        } else {
            return 0.0;
        }
    }
};

pub fn main() anyerror!void {
    const sampleSpec = PA.SampleSpecification{
        .format = .float32le,
        .channels = 2,
        .rate = 44100,
    };
    var stream = try PA.Stream.openPlayback(null, // Use the default server.
        c"Ziguana Game System", // Our application's name.
        null, // Use the default device.
        c"Wave Synth", // Description of our stream.
        &sampleSpec, // Our sample format.
        null, // Use default channel map
        null // Use default buffering attributes.
    );
    defer stream.close();

    std.debug.warn("Starting playback...\n");

    const instruments = [_]Instrument{
        // "Piano"
        Instrument{
            .waveform = .triangle,
            .envelope = Envelope{
                .attackTime = 0.1,
                .decayTime = 0.5,
                .releaseTime = 0.1,
                .sustainLevel = 0.2,
            },
        },
        // "Pad"
        Instrument{
            .waveform = .triangle,
            .envelope = Envelope{
                .attackTime = 0.8,
                .decayTime = 0.3,
                .releaseTime = 0.9,
                .sustainLevel = 0.8,
            },
        },
    };

    // render ADSR
    if (false) {
        var t: f32 = 0.0;
        const in = instruments[1]; // PAD
        const spaces = " " ** 64;
        var prevT: f32 = -1.0;
        while (t <= 10.0) : (t += 0.1) {
            var amp = in.envelope.getAmplitude(t, 1.0, 8.0);

            if (std.math.floor(prevT) < std.math.floor(t)) {
                std.debug.warn("{}", @floatToInt(usize, std.math.floor(t)));
            }

            std.debug.warn("\t|{}⏺\n", spaces[0..@floatToInt(usize, std.math.floor(48.0 * amp + 0.5))]);

            prevT = t;
        }
    }

    var channel0 = Channel{
        .instruments = instruments,
        .events = try loadChannelFromText(std.heap.direct_allocator, song_text_form),
    };

    // Plays "Alle meine Entchen" at 120 BPM
    // One Event is 1 eighth (1/8)

    const tempo = 120.0; // 120 BPM

    var buffer = [_]f32{0} ** 256;
    var time: f32 = -2.0; // start in negative space, so "play two seconds of silence"

    while (true) {
        for (buffer) |*sample, i| {
            const t = (time + @intToFloat(f32, i) / @as(f32, sampleSpec.rate));

            if (t >= 0) {
                sample.* = channel0.synthesize(t, tempo);
            } else {
                sample.* = 0.0;
            }
        }
        time += @as(f32, buffer.len) / @as(f32, sampleSpec.rate);

        try stream.write(@sliceToBytes(buffer[0..]));

        if (time >= @intToFloat(f32, channel0.events.len) * bpmToSecondsPerBeat(tempo))
            break;
    }
}

fn lerp(a: var, b: @typeOf(a), f: @typeOf(a)) @typeOf(a) {
    return a * (1.0 - f) + b * f;
}

pub fn freqToAngleVelocity(freq: f32) f32 {
    return freq * 2 * std.math.pi;
}

pub const Waveform = enum {
    sine,
    square,
    sawtooth,
    triangle,
    noise,
};

var noiseRng = std.rand.DefaultPrng.init(1);

pub fn oscillate(time: f32, freq: f32, kind: Waveform) f32 {
    const av = freqToAngleVelocity(freq);

    return switch (kind) {
        .sine => std.math.sin(av * time),
        .square => if (std.math.sin(av * time) > 0.0) @as(f32, 1.0) else @as(f32, -1.0),
        .triangle => (2.0 / std.math.pi) * std.math.asin(std.math.sin(av * time)),
        .sawtooth => 2.0 * std.math.modf(freq * time).fpart - 1.0,
        .noise => 2.0 * noiseRng.random.float(f32) - 1.0,
    };
}

pub const Envelope = struct {
    attackTime: f32,
    decayTime: f32,
    releaseTime: f32,
    attackLevel: f32 = 1.0,
    sustainLevel: f32,

    pub fn getAmplitude(self: Envelope, time: f32, onTime: f32, offTime: ?f32) f32 {
        const dt = time - onTime;
        if (dt < 0.0) {
            return 0.0;
        } else if (dt < self.attackTime) {
            return self.attackLevel * (dt / self.attackTime);
        } else if (offTime) |off| {
            if (time >= off) {
                const offdt = time - off;
                if (offdt < self.releaseTime) {
                    return lerp(self.sustainLevel, 0.0, offdt / self.releaseTime);
                } else {
                    return 0;
                }
            }
        }
        if (dt < self.attackTime + self.decayTime) {
            return lerp(self.attackLevel, self.sustainLevel, ((dt - self.attackTime) / self.decayTime));
        } else {
            return self.sustainLevel;
        }
    }
};
