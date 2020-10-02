const std = @import("std");
const tables = @import("tables.zig");
const unicode = @import("zunicode.zig");

const testing = std.testing;

const test_failed = error.TestFailed;
const notletterTest = [_]i32{
    0x20,
    0x35,
    0x375,
    0x619,
    0x700,
    0x1885,
    0xfffe,
    0x1ffff,
    0x10ffff,
};
const upper_test = [_]i32{
    0x41,
    0xc0,
    0xd8,
    0x100,
    0x139,
    0x14a,
    0x178,
    0x181,
    0x376,
    0x3cf,
    0x13bd,
    0x1f2a,
    0x2102,
    0x2c00,
    0x2c10,
    0x2c20,
    0xa650,
    0xa722,
    0xff3a,
    0x10400,
    0x1d400,
    0x1d7ca,
};
const notupperTest = [_]i32{
    0x40,
    0x5b,
    0x61,
    0x185,
    0x1b0,
    0x377,
    0x387,
    0x2150,
    0xab7d,
    0xffff,
    0x10000,
};

test "isUpper" {
    for (upper_test) |r, i| {
        testing.expect(unicode.isUpper(r));
    }
    for (notupperTest) |r, i| {
        testing.expect(!unicode.isUpper(r));
    }
    for (notletterTest) |r, i| {
        testing.expect(!unicode.isUpper(r));
    }
}

const caseT = struct {
    case: tables.Case,
    in: i32,
    out: i32,
    fn init(case: tables.Case, in: i32, out: i32) caseT {
        return caseT{ .case = case, .in = in, .out = out };
    }
};

const case_test = [_]caseT{

    // ASCII (special-cased so test carefully)
    caseT.init(tables.Case.Upper, '\n', '\n'),
    caseT.init(tables.Case.Upper, 'a', 'A'),
    caseT.init(tables.Case.Upper, 'A', 'A'),
    caseT.init(tables.Case.Upper, '7', '7'),
    caseT.init(tables.Case.Lower, '\n', '\n'),
    caseT.init(tables.Case.Lower, 'a', 'a'),
    caseT.init(tables.Case.Lower, 'A', 'a'),
    caseT.init(tables.Case.Lower, '7', '7'),
    caseT.init(tables.Case.Title, '\n', '\n'),
    caseT.init(tables.Case.Title, 'a', 'A'),
    caseT.init(tables.Case.Title, 'A', 'A'),
    caseT.init(tables.Case.Title, '7', '7'),
    // Latin-1: easy to read the tests!
    caseT.init(tables.Case.Upper, 0x80, 0x80),
    // caseT.init(tables.Case.Upper, 'Å', 'Å'),
    // caseT.init(tables.Case.Upper, 'å', 'Å'),
    caseT.init(tables.Case.Lower, 0x80, 0x80),
    // caseT.init(tables.Case.Lower, 'Å', 'å'),
    // caseT.init(tables.Case.Lower, 'å', 'å'),
    caseT.init(tables.Case.Title, 0x80, 0x80),
    // caseT.init(tables.Case.Title, 'Å', 'Å'),
    // caseT.init(tables.Case.Title, 'å', 'Å'),

    // 0131;LATIN SMALL LETTER DOTLESS I;Ll;0;L;;;;;N;;;0049;;0049
    caseT.init(tables.Case.Upper, 0x0131, 'I'),
    caseT.init(tables.Case.Lower, 0x0131, 0x0131),
    caseT.init(tables.Case.Title, 0x0131, 'I'),

    // 0133;LATIN SMALL LIGATURE IJ;Ll;0;L;<compat> 0069 006A;;;;N;LATIN SMALL LETTER I J;;0132;;0132
    caseT.init(tables.Case.Upper, 0x0133, 0x0132),
    caseT.init(tables.Case.Lower, 0x0133, 0x0133),
    caseT.init(tables.Case.Title, 0x0133, 0x0132),

    // 212A;KELVIN SIGN;Lu;0;L;004B;;;;N;DEGREES KELVIN;;;006B;
    caseT.init(tables.Case.Upper, 0x212A, 0x212A),
    caseT.init(tables.Case.Lower, 0x212A, 'k'),
    caseT.init(tables.Case.Title, 0x212A, 0x212A),

    // From an UpperLower sequence
    // A640;CYRILLIC CAPITAL LETTER ZEMLYA;Lu;0;L;;;;;N;;;;A641;
    caseT.init(tables.Case.Upper, 0xA640, 0xA640),
    caseT.init(tables.Case.Lower, 0xA640, 0xA641),
    caseT.init(tables.Case.Title, 0xA640, 0xA640),
    // A641;CYRILLIC SMALL LETTER ZEMLYA;Ll;0;L;;;;;N;;;A640;;A640
    caseT.init(tables.Case.Upper, 0xA641, 0xA640),
    caseT.init(tables.Case.Lower, 0xA641, 0xA641),
    caseT.init(tables.Case.Title, 0xA641, 0xA640),
    // A64E;CYRILLIC CAPITAL LETTER NEUTRAL YER;Lu;0;L;;;;;N;;;;A64F;
    caseT.init(tables.Case.Upper, 0xA64E, 0xA64E),
    caseT.init(tables.Case.Lower, 0xA64E, 0xA64F),
    caseT.init(tables.Case.Title, 0xA64E, 0xA64E),
    // A65F;CYRILLIC SMALL LETTER YN;Ll;0;L;;;;;N;;;A65E;;A65E
    caseT.init(tables.Case.Upper, 0xA65F, 0xA65E),
    caseT.init(tables.Case.Lower, 0xA65F, 0xA65F),
    caseT.init(tables.Case.Title, 0xA65F, 0xA65E),

    // From another UpperLower sequence
    // 0139;LATIN CAPITAL LETTER L WITH ACUTE;Lu;0;L;004C 0301;;;;N;LATIN CAPITAL LETTER L ACUTE;;;013A;
    caseT.init(tables.Case.Upper, 0x0139, 0x0139),
    caseT.init(tables.Case.Lower, 0x0139, 0x013A),
    caseT.init(tables.Case.Title, 0x0139, 0x0139),
    // 013F;LATIN CAPITAL LETTER L WITH MIDDLE DOT;Lu;0;L;<compat> 004C 00B7;;;;N;;;;0140;
    caseT.init(tables.Case.Upper, 0x013f, 0x013f),
    caseT.init(tables.Case.Lower, 0x013f, 0x0140),
    caseT.init(tables.Case.Title, 0x013f, 0x013f),
    // 0148;LATIN SMALL LETTER N WITH CARON;Ll;0;L;006E 030C;;;;N;LATIN SMALL LETTER N HACEK;;0147;;0147
    caseT.init(tables.Case.Upper, 0x0148, 0x0147),
    caseT.init(tables.Case.Lower, 0x0148, 0x0148),
    caseT.init(tables.Case.Title, 0x0148, 0x0147),

    // tables.Case.Lower lower than tables.Case.Upper.
    // AB78;CHEROKEE SMALL LETTER GE;Ll;0;L;;;;;N;;;13A8;;13A8
    caseT.init(tables.Case.Upper, 0xab78, 0x13a8),
    caseT.init(tables.Case.Lower, 0xab78, 0xab78),
    caseT.init(tables.Case.Title, 0xab78, 0x13a8),
    caseT.init(tables.Case.Upper, 0x13a8, 0x13a8),
    caseT.init(tables.Case.Lower, 0x13a8, 0xab78),
    caseT.init(tables.Case.Title, 0x13a8, 0x13a8),

    // Last block in the 5.1.0 table
    // 10400;DESERET CAPITAL LETTER LONG I;Lu;0;L;;;;;N;;;;10428;
    caseT.init(tables.Case.Upper, 0x10400, 0x10400),
    caseT.init(tables.Case.Lower, 0x10400, 0x10428),
    caseT.init(tables.Case.Title, 0x10400, 0x10400),
    // 10427;DESERET CAPITAL LETTER EW;Lu;0;L;;;;;N;;;;1044F;
    caseT.init(tables.Case.Upper, 0x10427, 0x10427),
    caseT.init(tables.Case.Lower, 0x10427, 0x1044F),
    caseT.init(tables.Case.Title, 0x10427, 0x10427),
    // 10428;DESERET SMALL LETTER LONG I;Ll;0;L;;;;;N;;;10400;;10400
    caseT.init(tables.Case.Upper, 0x10428, 0x10400),
    caseT.init(tables.Case.Lower, 0x10428, 0x10428),
    caseT.init(tables.Case.Title, 0x10428, 0x10400),
    // 1044F;DESERET SMALL LETTER EW;Ll;0;L;;;;;N;;;10427;;10427
    caseT.init(tables.Case.Upper, 0x1044F, 0x10427),
    caseT.init(tables.Case.Lower, 0x1044F, 0x1044F),
    caseT.init(tables.Case.Title, 0x1044F, 0x10427),

    // First one not in the 5.1.0 table
    // 10450;SHAVIAN LETTER PEEP;Lo;0;L;;;;;N;;;;;
    caseT.init(tables.Case.Upper, 0x10450, 0x10450),
    caseT.init(tables.Case.Lower, 0x10450, 0x10450),
    caseT.init(tables.Case.Title, 0x10450, 0x10450),

    // Non-letters with case.
    caseT.init(tables.Case.Lower, 0x2161, 0x2171),
    caseT.init(tables.Case.Upper, 0x0345, 0x0399),
};

test "toUpper" {
    for (case_test) |c, idx| {
        switch (c.case) {
            tables.Case.Upper => {
                const r = unicode.toUpper(c.in);
                testing.expectEqual(c.out, r);
            },
            else => {},
        }
    }
}

test "toLower" {
    for (case_test) |c, idx| {
        switch (c.case) {
            tables.Case.Lower => {
                const r = unicode.toLower(c.in);
                testing.expectEqual(c.out, r);
            },
            else => {},
        }
    }
}

test "toLower" {
    for (case_test) |c, idx| {
        switch (c.case) {
            tables.Case.Title => {
                const r = unicode.toTitle(c.in);
                testing.expectEqual(c.out, r);
            },
            else => {},
        }
    }
}

test "to" {
    for (case_test) |c| {
        const r = unicode.to(c.case, c.in);
        testing.expectEqual(c.out, r);
    }
}

test "isControlLatin1" {
    var i: i32 = 0;
    while (i <= tables.max_latin1) : (i += 1) {
        const got = unicode.isControl(i);
        var want: bool = false;
        if (0x00 <= i and i <= 0x1F) {
            want = true;
        } else if (0x7F <= i and i <= 0x9F) {
            want = true;
        }
        testing.expectEqual(want, got);
    }
}

test "isLetterLatin1" {
    var i: i32 = 0;
    while (i <= tables.max_latin1) : (i += 1) {
        const got = unicode.isLetter(i);
        const want = unicode.is(tables.Letter, i);
        testing.expectEqual(want, got);
    }
}

test "isUpperLatin1" {
    var i: i32 = 0;
    while (i <= tables.max_latin1) : (i += 1) {
        const got = unicode.isUpper(i);
        const want = unicode.is(tables.Upper, i);
        testing.expectEqual(want, got);
    }
}

test "isLowerLatin1" {
    var i: i32 = 0;
    while (i <= tables.max_latin1) : (i += 1) {
        const got = unicode.isLower(i);
        const want = unicode.is(tables.Lower, i);
        testing.expectEqual(want, got);
    }
}

test "isNumberLatin1" {
    var i: i32 = 0;
    while (i <= tables.max_latin1) : (i += 1) {
        const got = unicode.isNumber(i);
        const want = unicode.is(tables.Number, i);
        testing.expectEqual(want, got);
    }
}

test "isPrintLatin1" {
    var i: i32 = 0;
    while (i <= tables.max_latin1) : (i += 1) {
        const got = unicode.isPrint(i);
        var want = unicode.in(i, unicode.print_ranges[0..]);
        if (i == ' ') {
            want = true;
        }
        testing.expectEqual(want, got);
    }
}

test "isGraphicLatin1" {
    var i: i32 = 0;
    while (i <= tables.max_latin1) : (i += 1) {
        const got = unicode.isGraphic(i);
        var want = unicode.in(i, unicode.graphic_ranges[0..]);
        testing.expectEqual(want, got);
    }
}

test "isPunctLatin1" {
    var i: i32 = 0;
    while (i <= tables.max_latin1) : (i += 1) {
        const got = unicode.isPunct(i);
        const want = unicode.is(tables.Punct, i);
        testing.expectEqual(want, got);
    }
}

test "isSpaceLatin1" {
    var i: i32 = 0;
    while (i <= tables.max_latin1) : (i += 1) {
        const got = unicode.isSpace(i);
        const want = unicode.is(tables.White_Space, i);
        testing.expectEqual(want, got);
    }
}

test "isSymbolLatin1" {
    var i: i32 = 0;
    while (i <= tables.max_latin1) : (i += 1) {
        const got = unicode.isSymbol(i);
        const want = unicode.is(tables.Symbol, i);
        testing.expectEqual(want, got);
    }
}

const test_digit = [_]i32{
    0x0030,
    0x0039,
    0x0661,
    0x06F1,
    0x07C9,
    0x0966,
    0x09EF,
    0x0A66,
    0x0AEF,
    0x0B66,
    0x0B6F,
    0x0BE6,
    0x0BEF,
    0x0C66,
    0x0CEF,
    0x0D66,
    0x0D6F,
    0x0E50,
    0x0E59,
    0x0ED0,
    0x0ED9,
    0x0F20,
    0x0F29,
    0x1040,
    0x1049,
    0x1090,
    0x1091,
    0x1099,
    0x17E0,
    0x17E9,
    0x1810,
    0x1819,
    0x1946,
    0x194F,
    0x19D0,
    0x19D9,
    0x1B50,
    0x1B59,
    0x1BB0,
    0x1BB9,
    0x1C40,
    0x1C49,
    0x1C50,
    0x1C59,
    0xA620,
    0xA629,
    0xA8D0,
    0xA8D9,
    0xA900,
    0xA909,
    0xAA50,
    0xAA59,
    0xFF10,
    0xFF19,
    0x104A1,
    0x1D7CE,
};

const test_letter = [_]i32{
    0x0041,
    0x0061,
    0x00AA,
    0x00BA,
    0x00C8,
    0x00DB,
    0x00F9,
    0x02EC,
    0x0535,
    0x06E6,
    0x093D,
    0x0A15,
    0x0B99,
    0x0DC0,
    0x0EDD,
    0x1000,
    0x1200,
    0x1312,
    0x1401,
    0x1885,
    0x2C00,
    0xA800,
    0xF900,
    0xFA30,
    0xFFDA,
    0xFFDC,
    0x10000,
    0x10300,
    0x10400,
    0x20000,
    0x2F800,
    0x2FA1D,
};

test "isDigit" {
    for (test_digit) |r| {
        testing.expect(unicode.isDigit(r));
    }

    for (test_letter) |r| {
        testing.expect(!unicode.isDigit(r));
    }
}

test "DigitOptimization" {
    var i: i32 = 0;
    while (i <= tables.max_latin1) : (i += 1) {
        const got = unicode.isDigit(i);
        const want = unicode.is(tables.Digit, i);
        testing.expectEqual(want, got);
    }
}
