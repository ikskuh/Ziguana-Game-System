const std = @import("std");

const Operand = union(enum) {
    direct: Direct,
    indirect: Indirect,

    const Direct = union(enum) {
        register: u4,
        label: []const u8,
        immediate: u32,
    };

    const Indirect = union(enum) {
        source: Direct,
        offset: ?i32,
    };
};

const Instruction = struct {
    mnemonic: []const u8,
    operands: [3]Operand,
    operandCount: usize,
};

const Element = union(enum) {
    instruction: Instruction,
    label: []const u8,
    data8: u8,
    data16: u16,
    data32: u32,
    data64: u64,
    alignment: u32,
};

const Parser = struct {
    allocator: *std.mem.Allocator,
    source: []const u8,
    offset: usize,

    constants: std.StringHashMap(u32),

    fn init(allocator: *std.mem.Allocator, source: []const u8) Parser {
        return Parser{
            .allocator = allocator,
            .source = source,
            .offset = 0,
            .constants = std.StringHashMap(u32).init(allocator),
        };
    }

    fn deinit(this: *Parser) void {
        this.constants.deinit();
    }

    const TokenType = enum {
        hexnum, // 0x10
        decnum, // 10
        registerName, // r0 … r15
        label, // either 'bla:' or '.bla:'
        comma, // ,
        beginIndirection, // [
        endIndirection, // ]
        identifier, // [A-Za-z][A-Za-z0-9]+
        directive, // .foo
        lineBreak, // '\n'
        positiveOffset, // '+'
        negativeOffset, // '-'
        endOfText,
    };

    const Token = struct {
        type: TokenType,
        value: []const u8,
    };

    fn isWordCharacter(c: u8) bool {
        return switch (c) {
            '0'...'9' => true,
            'a'...'z' => true,
            'A'...'Z' => true,
            '_' => true,
            else => false,
        };
    }

    fn isDigit(c: u8) bool {
        return switch (c) {
            '0'...'9' => true,
            else => false,
        };
    }

    fn isHexDigit(c: u8) bool {
        return switch (c) {
            '0'...'9' => true,
            'a'...'f' => true,
            'A'...'F' => true,
            else => false,
        };
    }

    fn readToken(this: *Parser) !?Token {
        if (this.offset >= this.source.len)
            return null;

        // skip to next start of "meaningful"
        while (true) {
            const c = this.source[this.offset];
            if (c == '#') { // read line comment
                this.offset += 1;
                if (this.offset >= this.source.len)
                    return null;
                while (this.source[this.offset] != '\n') {
                    this.offset += 1;
                    if (this.offset >= this.source.len)
                        return null;
                }
                this.offset += 1;
            } else if (c == ' ' or c == '\t') {
                this.offset += 1;
            } else {
                break;
            }
        }

        switch (this.source[this.offset]) {
            // is single-char item
            '\n', ',', '[', ']', '-', '+' => {
                this.offset += 1;
                return Token{
                    .type = switch (this.source[this.offset - 1]) {
                        '\n' => .lineBreak,
                        ',' => .comma,
                        '[' => .beginIndirection,
                        ']' => .endIndirection,
                        '-' => .negativeOffset,
                        '+' => .positiveOffset,
                        else => unreachable,
                    },
                    .value = this.source[this.offset - 1 .. this.offset],
                };
            },

            // is either .label or .directive
            '.' => {
                const start = this.offset;
                var end = start + 1;
                if (end >= this.source.len)
                    return error.UnexpectedEndOfText;
                while (isWordCharacter(this.source[end])) {
                    end += 1;
                    if (end >= this.source.len)
                        return error.UnexpectedEndOfText;
                }
                this.offset = end;
                if (this.source[end] == ':') {
                    this.offset += 1;
                    return Token{
                        .type = .label,
                        .value = this.source[start..end],
                    };
                } else {
                    return Token{
                        .type = .directive,
                        .value = this.source[start..end],
                    };
                }
            },

            // identifier:
            'A'...'Z', 'a'...'z', '_' => {
                const start = this.offset;
                var end = start + 1;
                if (end >= this.source.len)
                    return error.UnexpectedEndOfText;
                while (isWordCharacter(this.source[end])) {
                    end += 1;
                    if (end >= this.source.len)
                        return error.UnexpectedEndOfText;
                }
                this.offset = end;

                if (this.source[end] == ':') {
                    this.offset += 1;
                    return Token{
                        .type = .label,
                        .value = this.source[start..end],
                    };
                } else {
                    return Token{
                        .type = .identifier,
                        .value = this.source[start..end],
                    };
                }
            },

            // numbers:
            '0'...'9' => {
                const start = this.offset;
                var end = start + 1;
                if (end >= this.source.len)
                    return error.UnexpectedEndOfText;
                while (isHexDigit(this.source[end]) or this.source[end] == 'x') {
                    end += 1;
                    if (end >= this.source.len)
                        return error.UnexpectedEndOfText;
                }
                this.offset = end;

                const text = this.source[start..end];

                if (text.len >= 2 and text[0] == '0' and text[1] == 'x') {
                    if (text.len == 2)
                        return error.InvalidHexLiteral;

                    return Token{
                        .type = .hexnum,
                        .value = this.source[start..end],
                    };
                }
                return Token{
                    .type = .decnum,
                    .value = this.source[start..end],
                };
            },
            else => return error.UnexpectedCharacter,
        }

        return null;
    }

    fn readNext(this: *Parser) !?Element {
        while (try this.readToken()) |token| {
            std.debug.warn("token: {}\n", token);
        }
        return null;
    }
};

pub fn assemble(allocator: *std.mem.Allocator, source: []const u8, target: []u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var parser = Parser.init(&arena.allocator, source);
    defer parser.deinit();

    var globalLabels = std.StringHashMap(u32).init(&arena.allocator);
    defer globalLabels.deinit();

    var localLabels = std.StringHashMap(u32).init(&arena.allocator);
    defer localLabels.deinit();

    var writer = Writer.init(target);

    const Patch = struct {
        offset: u32,
        value: u32,
    };

    var patchlist = std.ArrayList(Patch).init(&arena.allocator);
    defer patchlist.deinit();

    while (try parser.readNext()) |label_or_instruction| {
        switch (label_or_instruction) {
            .label => |lbl| {
                if (lbl[0] == '.') {
                    // is local
                    _ = try localLabels.put(lbl, writer.offset);
                } else {
                    // erase all local labels as soon as we encounter a global label
                    localLabels.clear();
                    _ = try globalLabels.put(lbl, writer.offset);
                }
            },
            .instruction => |instr| {
                // TODO:
            },
            .data8 => |data| {
                try writer.write(data);
            },
            .data16 => |data| {
                try writer.write(data);
            },
            .data32 => |data| {
                try writer.write(data);
            },
            .data64 => |data| {
                try writer.write(data);
            },
            .alignment => |al| {
                std.debug.assert((al & (al - 1)) == 0);
                writer.offset = (writer.offset + al - 1) & (al - 1);
            },
        }
    }
}

/// simple wrapper around a slice that allows
/// sequential writing to that slice
const Writer = struct {
    target: []u8,
    offset: u32,

    fn init(target: []u8) Writer {
        return Writer{
            .target = target,
            .offset = 0,
        };
    }

    fn ensureSpace(this: *Writer, size: usize) !void {
        if (this.offset + size > this.target.len)
            return error.NotEnoughSpace;
    }

    fn write(this: *Writer, value: var) !void {
        const T = @typeOf(value);
        try this.ensureSpace(@sizeOf(T));
        switch (T) {
            u8, u16, u32, u64 => {
                std.mem.copy(u8, this.target[this.offset .. this.offset + @sizeOf(T)], @sliceToBytes(@ptrCast([*]const T, &value)[0..@sizeOf(T)]));
                this.offset += @sizeOf(T);
            },
            else => @compileError(@typeName(@typeOf(value)) ++ " is not supported by writer!"),
        }
    }
};
