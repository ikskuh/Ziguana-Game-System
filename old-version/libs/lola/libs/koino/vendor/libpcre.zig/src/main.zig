const std = @import("std");
const assert = std.debug.assert;
const testing = std.testing;

const c = @cImport({
    @cInclude("pcre.h");
});

pub const Options = struct {
    Anchored: bool = false,
    AutoCallout: bool = false,
    BsrAnycrlf: bool = false,
    BsrUnicode: bool = false,
    Caseless: bool = false,
    DollarEndonly: bool = false,
    Dotall: bool = false,
    Dupnames: bool = false,
    Extended: bool = false,
    Extra: bool = false,
    Firstline: bool = false,
    JavascriptCompat: bool = false,
    Multiline: bool = false,
    NeverUtf: bool = false,
    NewlineAny: bool = false,
    NewlineAnycrlf: bool = false,
    NewlineCr: bool = false,
    NewlineCrlf: bool = false,
    NewlineLf: bool = false,
    NoAutoCapture: bool = false,
    NoAutoPossess: bool = false,
    NoStartOptimize: bool = false,
    NoUtf16Check: bool = false,
    NoUtf32Check: bool = false,
    NoUtf8Check: bool = false,
    Ucp: bool = false,
    Ungreedy: bool = false,
    Utf16: bool = false,
    Utf32: bool = false,
    Utf8: bool = false,

    fn compile(options: Options) c_int {
        var r: c_int = 0;
        if (options.Anchored) r |= c.PCRE_ANCHORED;
        if (options.AutoCallout) r |= c.PCRE_AUTO_CALLOUT;
        if (options.BsrAnycrlf) r |= c.PCRE_BSR_ANYCRLF;
        if (options.BsrUnicode) r |= c.PCRE_BSR_UNICODE;
        if (options.Caseless) r |= c.PCRE_CASELESS;
        if (options.DollarEndonly) r |= c.PCRE_DOLLAR_ENDONLY;
        if (options.Dotall) r |= c.PCRE_DOTALL;
        if (options.Dupnames) r |= c.PCRE_DUPNAMES;
        if (options.Extended) r |= c.PCRE_EXTENDED;
        if (options.Extra) r |= c.PCRE_EXTRA;
        if (options.Firstline) r |= c.PCRE_FIRSTLINE;
        if (options.JavascriptCompat) r |= c.PCRE_JAVASCRIPT_COMPAT;
        if (options.Multiline) r |= c.PCRE_MULTILINE;
        if (options.NeverUtf) r |= c.PCRE_NEVER_UTF;
        if (options.NewlineAny) r |= c.PCRE_NEWLINE_ANY;
        if (options.NewlineAnycrlf) r |= c.PCRE_NEWLINE_ANYCRLF;
        if (options.NewlineCr) r |= c.PCRE_NEWLINE_CR;
        if (options.NewlineCrlf) r |= c.PCRE_NEWLINE_CRLF;
        if (options.NewlineLf) r |= c.PCRE_NEWLINE_LF;
        if (options.NoAutoCapture) r |= c.PCRE_NO_AUTO_CAPTURE;
        if (options.NoAutoPossess) r |= c.PCRE_NO_AUTO_POSSESS;
        if (options.NoStartOptimize) r |= c.PCRE_NO_START_OPTIMIZE;
        if (options.NoUtf16Check) r |= c.PCRE_NO_UTF16_CHECK;
        if (options.NoUtf32Check) r |= c.PCRE_NO_UTF32_CHECK;
        if (options.NoUtf8Check) r |= c.PCRE_NO_UTF8_CHECK;
        if (options.Ucp) r |= c.PCRE_UCP;
        if (options.Ungreedy) r |= c.PCRE_UNGREEDY;
        if (options.Utf16) r |= c.PCRE_UTF16;
        if (options.Utf32) r |= c.PCRE_UTF32;
        if (options.Utf8) r |= c.PCRE_UTF8;
        return r;
    }
};

// pub const Compile2Error = enum(c_int) {};

pub const Regex = struct {
    pcre: *c.pcre,
    pcre_extra: ?*c.pcre_extra,
    capture_count: usize,

    pub const CompileError = error{CompileError} || std.mem.Allocator.Error;
    pub const ExecError = error{ExecError} || std.mem.Allocator.Error;

    pub fn compile(
        pattern: [:0]const u8,
        options: Options,
    ) CompileError!Regex {
        var err: [*c]const u8 = undefined;
        var err_offset: c_int = undefined;

        const pcre = c.pcre_compile(pattern, options.compile(), &err, &err_offset, 0) orelse {
            std.debug.warn("pcre_compile (at {}): {}\n", .{ err_offset, @ptrCast([*:0]const u8, err) });
            return error.CompileError;
        };
        errdefer c.pcre_free.?(pcre);

        const pcre_extra = c.pcre_study(pcre, 0, &err);
        if (err != 0) {
            std.debug.warn("pcre_study: {}\n", .{@ptrCast([*:0]const u8, err)});
            return error.CompileError;
        }
        errdefer c.pcre_free_study(pcre_extra);

        var capture_count: c_int = undefined;
        var fullinfo_rc = c.pcre_fullinfo(pcre, pcre_extra, c.PCRE_INFO_CAPTURECOUNT, &capture_count);
        if (fullinfo_rc != 0) @panic("could not request PCRE_INFO_CAPTURECOUNT");

        return Regex{
            .pcre = pcre,
            .pcre_extra = pcre_extra,
            .capture_count = @intCast(usize, capture_count),
        };
    }

    pub fn deinit(self: Regex) void {
        c.pcre_free_study(self.pcre_extra);
        c.pcre_free.?(self.pcre);
    }

    /// Returns the start and end index of the match if any, otherwise null.
    pub fn matches(self: Regex, s: []const u8, options: Options) ExecError!?Capture {
        var ovector: [3]c_int = undefined;
        var result = c.pcre_exec(self.pcre, self.pcre_extra, s.ptr, @intCast(c_int, s.len), 0, options.compile(), &ovector, 3);
        switch (result) {
            c.PCRE_ERROR_NOMATCH => return null,
            c.PCRE_ERROR_NOMEMORY => return error.OutOfMemory,
            else => {},
        }
        // result == 0 implies there were capture groups that didn't fit into ovector.
        // We don't care.
        if (result < 0) {
            std.debug.print("pcre_exec: {}\n", .{result});
            return error.ExecError; // TODO: should clarify
        }
        return Capture{ .start = @intCast(usize, ovector[0]), .end = @intCast(usize, ovector[1]) };
    }

    /// Searches for capture groups in s. The 0th Capture of the result is the entire match.
    pub fn captures(self: Regex, allocator: *std.mem.Allocator, s: []const u8, options: Options) (ExecError || std.mem.Allocator.Error)!?[]?Capture {
        var ovecsize = (self.capture_count + 1) * 3;
        var ovector: []c_int = try allocator.alloc(c_int, ovecsize);
        defer allocator.free(ovector);

        var result = c.pcre_exec(self.pcre, self.pcre_extra, s.ptr, @intCast(c_int, s.len), 0, options.compile(), &ovector[0], @intCast(c_int, ovecsize));

        switch (result) {
            c.PCRE_ERROR_NOMATCH => return null,
            c.PCRE_ERROR_NOMEMORY => return error.OutOfMemory,
            else => {},
        }
        // 0 implies we didn't allocate enough ovector, and should never happen.
        std.debug.assert(result != 0);
        if (result < 0) {
            std.debug.print("pcre_exec: {}\n", .{result});
            return error.ExecError; // TODO: should clarify
        }

        var caps: []?Capture = try allocator.alloc(?Capture, @intCast(usize, self.capture_count + 1));
        errdefer allocator.free(caps);
        for (caps) |*cap, i| {
            if (i >= result) {
                cap.* = null;
            } else if (ovector[i * 2] == -1) {
                assert(ovector[i * 2 + 1] == -1);
                cap.* = null;
            } else {
                cap.* = .{
                    .start = @intCast(usize, ovector[i * 2]),
                    .end = @intCast(usize, ovector[i * 2 + 1]),
                };
            }
        }
        return caps;
    }
};

pub const Capture = struct {
    start: usize,
    end: usize,
};

test "compiles" {
    const regex = Regex.compile("(", .{});
    testing.expectError(error.CompileError, regex);
}

test "matches" {
    const regex = try Regex.compile("hello", .{});
    defer regex.deinit();
    testing.expect((try regex.matches("hello", .{})) != null);
    testing.expect((try regex.matches("yes hello", .{})) != null);
    testing.expect((try regex.matches("yes hello", .{ .Anchored = true })) == null);
}

test "captures" {
    const regex = try Regex.compile("(a+)b(c+)", .{});
    defer regex.deinit();
    testing.expect((try regex.captures(std.testing.allocator, "a", .{})) == null);
    const captures = (try regex.captures(std.testing.allocator, "aaaaabcc", .{})).?;
    defer std.testing.allocator.free(captures);
    testing.expectEqualSlices(?Capture, &[_]?Capture{
        .{
            .start = 0,
            .end = 8,
        },
        .{
            .start = 0,
            .end = 5,
        },
        .{
            .start = 6,
            .end = 8,
        },
    }, captures);
}

test "missing capture group" {
    const regex = try Regex.compile("abc(def)(ghi)?(jkl)", .{});
    defer regex.deinit();
    const captures = (try regex.captures(std.testing.allocator, "abcdefjkl", .{})).?;
    defer std.testing.allocator.free(captures);
    testing.expectEqualSlices(?Capture, &[_]?Capture{
        .{
            .start = 0,
            .end = 9,
        },
        .{
            .start = 3,
            .end = 6,
        },
        null,
        .{
            .start = 6,
            .end = 9,
        },
    }, captures);
}

test "missing capture group at end of capture list" {
    const regex = try Regex.compile("abc(def)(ghi)?jkl", .{});
    defer regex.deinit();
    const captures = (try regex.captures(std.testing.allocator, "abcdefjkl", .{})).?;
    defer std.testing.allocator.free(captures);
    testing.expectEqualSlices(?Capture, &[_]?Capture{
        .{
            .start = 0,
            .end = 9,
        },
        .{
            .start = 3,
            .end = 6,
        },
        null,
    }, captures);
}
