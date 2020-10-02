const std = @import("std");
const unicode = @import("zunicode.zig");
const utf8 = @import("utf8.zig");

const t = std.testing;

test "init" {
    t.expectEqual(utf8.max_rune, unicode.tables.max_rune);
    t.expectEqual(utf8.rune_error, unicode.tables.replacement_char);
}

const Utf8Map = struct {
    r: i32,
    str: []const u8,

    fn init(r: i32, str: []const u8) Utf8Map {
        return Utf8Map{ .r = r, .str = str };
    }
};

const utf8_map = [_]Utf8Map{
    Utf8Map.init(0x0000, "\x00"),
    Utf8Map.init(0x0001, "\x01"),
    Utf8Map.init(0x007e, "\x7e"),
    Utf8Map.init(0x007f, "\x7f"),
    Utf8Map.init(0x0080, "\xc2\x80"),
    Utf8Map.init(0x0081, "\xc2\x81"),
    Utf8Map.init(0x00bf, "\xc2\xbf"),
    Utf8Map.init(0x00c0, "\xc3\x80"),
    Utf8Map.init(0x00c1, "\xc3\x81"),
    Utf8Map.init(0x00c8, "\xc3\x88"),
    Utf8Map.init(0x00d0, "\xc3\x90"),
    Utf8Map.init(0x00e0, "\xc3\xa0"),
    Utf8Map.init(0x00f0, "\xc3\xb0"),
    Utf8Map.init(0x00f8, "\xc3\xb8"),
    Utf8Map.init(0x00ff, "\xc3\xbf"),
    Utf8Map.init(0x0100, "\xc4\x80"),
    Utf8Map.init(0x07ff, "\xdf\xbf"),
    Utf8Map.init(0x0400, "\xd0\x80"),
    Utf8Map.init(0x0800, "\xe0\xa0\x80"),
    Utf8Map.init(0x0801, "\xe0\xa0\x81"),
    Utf8Map.init(0x1000, "\xe1\x80\x80"),
    Utf8Map.init(0xd000, "\xed\x80\x80"),
    Utf8Map.init(0xd7ff, "\xed\x9f\xbf"), // last code point before surrogate half.
    Utf8Map.init(0xe000, "\xee\x80\x80"), // first code point after surrogate half.
    Utf8Map.init(0xfffe, "\xef\xbf\xbe"),
    Utf8Map.init(0xffff, "\xef\xbf\xbf"),
    Utf8Map.init(0x10000, "\xf0\x90\x80\x80"),
    Utf8Map.init(0x10001, "\xf0\x90\x80\x81"),
    Utf8Map.init(0x40000, "\xf1\x80\x80\x80"),
    Utf8Map.init(0x10fffe, "\xf4\x8f\xbf\xbe"),
    Utf8Map.init(0x10ffff, "\xf4\x8f\xbf\xbf"),
    Utf8Map.init(0xFFFD, "\xef\xbf\xbd"),
};

const surrogete_map = [_]Utf8Map{
    Utf8Map.init(0xd800, "\xed\xa0\x80"),
    Utf8Map.init(0xdfff, "\xed\xbf\xbf"),
};

const test_strings = [][]const u8{
    "",
    "abcd",
    "☺☻☹",
    "日a本b語ç日ð本Ê語þ日¥本¼語i日©",
    "日a本b語ç日ð本Ê語þ日¥本¼語i日©日a本b語ç日ð本Ê語þ日¥本¼語i日©日a本b語ç日ð本Ê語þ日¥本¼語i日©",
    "\x80\x80\x80\x80",
};

test "fullRune" {
    for (utf8_map) |m| {
        t.expectEqual(true, utf8.fullRune(m.str));
    }
    const sample = [_][]const u8{ "\xc0", "\xc1" };
    for (sample) |m| {
        t.expectEqual(true, utf8.fullRune(m));
    }
}

test "encodeRune" {
    for (utf8_map) |m, idx| {
        var buf = [_]u8{0} ** 10;
        const n = try utf8.encodeRune(buf[0..], m.r);
        const ok = std.mem.eql(u8, buf[0..n], m.str);
        t.expectEqualSlices(u8, m.str, buf[0..n]);
    }
}

test "decodeRune" {
    for (utf8_map) |m| {
        const r = try utf8.decodeRune(m.str);
        t.expectEqual(m.r, r.value);
        t.expectEqual(m.str.len, r.size);
    }
}

test "surrogateRune" {
    for (surrogete_map) |m| {
        t.expectError(error.RuneError, utf8.decodeRune(m.str));
    }
}

test "Iterator" {
    const source = "a,b,c";
    var iter = utf8.Iterator.init(source);
    var a = try iter.next();
    t.expect(a != null);
    t.expect('a' == a.?.value);
    _ = try iter.next();

    a = try iter.next();
    t.expect(a != null);

    t.expect(a != null);
    t.expect('b' == a.?.value);
    _ = try iter.next();
    _ = try iter.next();
    a = try iter.next();
    t.expect(a == null);

    iter.reset(0);
    a = try iter.peek();
    t.expect(a != null);

    const b = try iter.next();
    t.expect(b != null);
    t.expectEqual(a.?.value, b.?.value);
}
