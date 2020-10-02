const assert = @import("std").debug.assert;

pub const rune_error: i32 = 0xfffd;
pub const max_rune: i32 = 0x10ffff;
pub const rune_self: i32 = 0x80;
pub const utf_max: usize = 4;

const surrogate_min: i32 = 0xD800;
const surrogate_max: i32 = 0xDFFF;

const t1: i32 = 0x00; // 0000 0000
const tx: i32 = 0x80; // 1000 0000
const t2: i32 = 0xC0; // 1100 0000
const t3: i32 = 0xE0; // 1110 0000
const t4: i32 = 0xF0; // 1111 0000
const t5: i32 = 0xF8; // 1111 1000

const maskx: i32 = 0x3F; // 0011 1111
const mask2: i32 = 0x1F; // 0001 1111
const mask3: i32 = 0x0F; // 0000 1111
const mask4: i32 = 0x07; // 0000 0111

const rune1Max = (1 << 7) - 1;
const rune2Max = (1 << 11) - 1;
const rune3Max = (1 << 16) - 1;

// The default lowest and highest continuation byte.
const locb: u8 = 0x80; // 1000 0000
const hicb: u8 = 0xBF; // 1011 1111

// These names of these constants are chosen to give nice alignment in the
// table below. The first nibble is an index into acceptRanges or F for
// special one-byte cases. The second nibble is the Rune length or the
// Status for the special one-byte case.
const xx: u8 = 0xF1; // invalid: size 1
const as: u8 = 0xF0; // ASCII: size 1
const s1: u8 = 0x02; // accept 0, size 2
const s2: u8 = 0x13; // accept 1, size 3
const s3: u8 = 0x03; // accept 0, size 3
const s4: u8 = 0x23; // accept 2, size 3
const s5: u8 = 0x34; // accept 3, size 4
const s6: u8 = 0x04; // accept 0, size 4
const s7: u8 = 0x44; // accept 4, size 4

// first is information about the first byte in a UTF-8 sequence.
const first = [_]u8{
    //   1   2   3   4   5   6   7   8   9   A   B   C   D   E   F
    as, as, as, as, as, as, as, as, as, as, as, as, as, as, as, as, // 0x00-0x0F
    as, as, as, as, as, as, as, as, as, as, as, as, as, as, as, as, // 0x10-0x1F
    as, as, as, as, as, as, as, as, as, as, as, as, as, as, as, as, // 0x20-0x2F
    as, as, as, as, as, as, as, as, as, as, as, as, as, as, as, as, // 0x30-0x3F
    as, as, as, as, as, as, as, as, as, as, as, as, as, as, as, as, // 0x40-0x4F
    as, as, as, as, as, as, as, as, as, as, as, as, as, as, as, as, // 0x50-0x5F
    as, as, as, as, as, as, as, as, as, as, as, as, as, as, as, as, // 0x60-0x6F
    as, as, as, as, as, as, as, as, as, as, as, as, as, as, as, as, // 0x70-0x7F
    //   1   2   3   4   5   6   7   8   9   A   B   C   D   E   F
    xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, // 0x80-0x8F
    xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, // 0x90-0x9F
    xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, // 0xA0-0xAF
    xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, // 0xB0-0xBF
    xx, xx, s1, s1, s1, s1, s1, s1, s1, s1, s1, s1, s1, s1, s1, s1, // 0xC0-0xCF
    s1, s1, s1, s1, s1, s1, s1, s1, s1, s1, s1, s1, s1, s1, s1, s1, // 0xD0-0xDF
    s2, s3, s3, s3, s3, s3, s3, s3, s3, s3, s3, s3, s3, s4, s3, s3, // 0xE0-0xEF
    s5, s6, s6, s6, s7, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, xx, // 0xF0-0xFF
};

const acceptRange = struct {
    lo: u8,
    hi: u8,

    fn init(lo: u8, hi: u8) acceptRange {
        return acceptRange{ .lo = lo, .hi = hi };
    }
};

const accept_ranges = [_]acceptRange{
    acceptRange.init(locb, hicb),
    acceptRange.init(0xA0, hicb),
    acceptRange.init(locb, 0x9F),
    acceptRange.init(0x90, hicb),
    acceptRange.init(locb, 0x8F),
};

pub fn fullRune(p: []const u8) bool {
    const n = p.len;
    if (n == 0) {
        return false;
    }
    const x = first[p[0]];
    if (n >= @intCast(usize, x & 7)) {
        return true; // ASCII, invalid or valid.
    }
    // Must be short or invalid
    const accept = accept_ranges[@intCast(usize, x >> 4)];
    if (n > 1 and (p[1] < accept.lo or accept.hi < p[1])) {
        return true;
    } else if (n > 2 and (p[0] < locb or hicb < p[2])) {
        return true;
    }
    return false;
}

pub const Rune = struct {
    value: i32,
    size: usize,
};

/// decodeRune unpacks the first UTF-8 encoding in p and returns the rune and
/// its width in bytes. If p is empty it returns RuneError. Otherwise, if
/// the encoding is invalid, it returns RuneError. Both are impossible
/// results for correct, non-empty UTF-8.
///
/// An encoding is invalid if it is incorrect UTF-8, encodes a rune that is
/// out of range, or is not the shortest possible UTF-8 encoding for the
/// value. No other validation is performed.
pub fn decodeRune(p: []const u8) !Rune {
    const n = p.len;
    if (n < 1) {
        return error.RuneError;
    }
    const p0 = p[0];
    const x = first[p[0]];
    if (x >= as) {
        // The following code simulates an additional check for x == xx and
        // handling the ASCII and invalid cases accordingly. This mask-and-or
        // approach prevents an additional branch.
        const mask = @intCast(i32, x) << 31 >> 31;
        return Rune{
            .value = (@intCast(i32, p[0]) & ~mask) | (rune_error & mask),
            .size = 1,
        };
    }
    const sz = x & 7;
    const accept = accept_ranges[@intCast(usize, x >> 4)];
    if (n < @intCast(usize, sz)) {
        return error.RuneError;
    }
    const b1 = p[1];
    if (b1 < accept.lo or accept.hi < b1) {
        return error.RuneError;
    }
    if (sz == 2) {
        return Rune{
            .value = @intCast(i32, p0 & @intCast(u8, mask2)) << 6 | @intCast(i32, b1 & @intCast(u8, maskx)),
            .size = 2,
        };
    }
    const b2 = p[2];
    if (b2 < locb or hicb < b2) {
        return error.RuneError;
    }
    if (sz == 3) {
        return Rune{
            .value = @intCast(i32, p0 & @intCast(u8, mask3)) << 12 | @intCast(i32, b1 & @intCast(u8, maskx)) << 6 | @intCast(i32, b2 & @intCast(u8, maskx)),
            .size = 3,
        };
    }
    const b3 = p[3];
    if (b3 < locb or hicb < b3) {
        return error.RuneError;
    }
    return Rune{
        .value = @intCast(i32, p0 & @intCast(u8, mask4)) << 18 | @intCast(i32, b1 & @intCast(u8, maskx)) << 12 | @intCast(i32, b2 & @intCast(u8, maskx)) << 6 | @intCast(i32, b3 & @intCast(u8, maskx)),
        .size = 4,
    };
}

pub fn runeLen(r: i32) !usize {
    if (r <= rune1Max) {
        return 1;
    } else if (r <= rune2Max) {
        return 2;
    } else if (surrogate_min <= r and r <= surrogate_min) {
        return error.RuneError;
    } else if (r <= rune3Max) {
        return 3;
    } else if (r <= max_rune) {
        return 4;
    }
    return error.RuneError;
}

/// runeStart reports whether the byte could be the first byte of an encoded,
/// possibly invalid rune. Second and subsequent bytes always have the top two
/// bits set to 10.
pub fn runeStart(b: u8) bool {
    return b & 0xC0 != 0x80;
}

// decodeLastRune unpacks the last UTF-8 encoding in p and returns the rune and
// its width in bytes. If p is empty it returns RuneError. Otherwise, if
// the encoding is invalid, it returns RuneError Both are impossible
// results for correct, non-empty UTF-8.
//
// An encoding is invalid if it is incorrect UTF-8, encodes a rune that is
// out of range, or is not the shortest possible UTF-8 encoding for the
// value. No other validation is performed.
pub fn decodeLastRune(p: []const u8) !Rune {
    const end = p.len;
    if (end < 1) {
        return error.RuneError;
    }
    var start = end - 1;
    const r = @intCast(i32, p[start]);
    if (r < rune_self) {
        return Rune{
            .value = r,
            .size = 1,
        };
    }
    // guard against O(n^2) behavior when traversing
    // backwards through strings with long sequences of
    // invalid UTF-8.
    var lim = end - utf_max;
    if (lim < 0) {
        lim = 0;
    }
    while (start >= lim) {
        if (runeStart(p[start])) {
            break;
        }
        start -= 1;
    }
    if (start < 0) {
        start = 0;
    }
    var rune = try decodeRune(p[start..end]);
    if (start + rune.size != end) {
        return error.RuneError;
    }
    return rune;
}

pub fn encodeRune(p: []u8, r: i32) !usize {
    const i = r;
    if (i <= rune1Max) {
        p[0] = @intCast(u8, r);
        return 1;
    } else if (i <= rune2Max) {
        _ = p[1];
        p[0] = @intCast(u8, t2 | (r >> 6));
        p[1] = @intCast(u8, tx | (r & maskx));
        return 2;
    } else if (i > max_rune or surrogate_min <= i and i <= surrogate_min) {
        return error.RuneError;
    } else if (i <= rune3Max) {
        _ = p[2];
        p[0] = @intCast(u8, t3 | (r >> 12));
        p[1] = @intCast(u8, tx | ((r >> 6) & maskx));
        p[2] = @intCast(u8, tx | (r & maskx));
        return 3;
    } else {
        _ = p[3];
        p[0] = @intCast(u8, t4 | (r >> 18));
        p[1] = @intCast(u8, tx | ((r >> 12) & maskx));
        p[2] = @intCast(u8, tx | ((r >> 6) & maskx));
        p[3] = @intCast(u8, tx | (r & maskx));
        return 4;
    }
    return error.RuneError;
}

pub const Iterator = struct {
    src: []const u8,
    pos: usize,

    pub fn init(src: []const u8) Iterator {
        return Iterator{
            .src = src,
            .pos = 0,
        };
    }

    // resets the cursor position to index
    pub fn reset(self: *Iterator, index: usize) void {
        assert(index < self.src.len);
        self.pos = index;
    }

    pub fn next(self: *Iterator) !?Rune {
        if (self.pos >= self.src.len) {
            return null;
        }
        const rune = try decodeRune(self.src[self.pos..]);
        self.pos += rune.size;
        return rune;
    }

    // this is an alias for peek_nth(1)
    pub fn peek(self: *Iterator) !?Rune {
        return self.peek_nth(1);
    }

    // peek_nth reads nth rune without advancing the cursor.
    pub fn peek_nth(self: *Iterator, n: usize) !?Rune {
        var pos = self.pos;
        var i: usize = 0;
        var last_read: ?Rune = undefined;
        while (i < n) : (i += 1) {
            if (pos >= self.src.len) {
                return null;
            }
            const rune = try decodeRune(self.src[pos..]);
            pos += rune.size;
            last_read = rune;
        }
        return last_read;
    }
};

// runeCount returns the number of runes in p. Erroneous and short
// encodings are treated as single runes of width 1 byte.

pub fn runeCount(p: []const u8) usize {
    const np = p.len;
    var n: usize = 0;
    var i: usize = 0;
    while (i < np) {
        n += 1;
        const c = p[i];
        if (@intCast(u32, c) < rune_self) {
            i += 1;
            continue;
        }
        const x = first[c];
        if (c == xx) {
            i += 1;
            continue;
        }
        var size = @intCast(usize, x & 7);
        if (i + size > np) {
            i += 1; // Short or invalid.
            continue;
        }
        const accept = accept_ranges[x >> 4];

        if (p[i + 1] < accept.lo or accept.hi < p[i + 1]) {
            size = 1;
        } else if (size == 2) {} else if (p[i + 2] < locb or hicb < p[i + 2]) {
            size = 1;
        } else if (size == 3) {} else if (p[i + 3] < locb or hicb < p[i + 3]) {
            size = 1;
        }
        i += size;
    }
    return n;
}

pub fn valid(p: []const u8) bool {
    const n = p.len;
    var i: usize = 0;
    while (i < n) {
        const pi = p[i];
        if (@intCast(u32, c) < rune_self) {
            i += 1;
            continue;
        }
        const x = first[pi];
        if (x == xx) {
            return false; // Illegal starter byte.
        }
        const size = @intCast(usize, x & 7);
        if (i + size > n) {
            return false; // Short or invalid.
        }
        const accept = accept_ranges[x >> 4];
        if (p[i + 1] < accept.lo or accept.hi < p[i + 1]) {
            return false;
        } else if (size == 2) {} else if (p[i + 2] < locb or hicb < p[i + 2]) {
            return false;
        } else if (size == 3) {} else if (p[i + 3] < locb or hicb < p[i + 3]) {
            return false;
        }
        i += size;
    }
    return true;
}

// ValidRune reports whether r can be legally encoded as UTF-8.
// Code points that are out of range or a surrogate half are illegal.
pub fn validRune(r: u32) bool {
    if (0 <= r and r < surrogate_min) {
        return true;
    } else if (surrogate_min < r and r <= max_rune) {
        return true;
    }
    return false;
}
