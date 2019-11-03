const std = @import("std");

const Operand = union(enum) {
    direct: Direct,
    indirect: Indirect,

    const Direct = union(enum) {
        register: u4,
        label: []const u8,
        immediate: u32,
    };

    const Indirect = struct {
        source: Direct,
        offset: ?i32,
    };
};

const Instruction = struct {
    mnemonic: []const u8,
    operands: [3]Operand,
    operandCount: usize,

    fn new(mn: []const u8) Instruction {
        return Instruction{
            .mnemonic = mn,
            .operandCount = 0,
            .operands = undefined,
        };
    }

    fn addOperand(this: *Instruction, oper: Operand) !void {
        if (this.operandCount >= this.operands.len)
            return error.TooManyOperands;
        this.operands[this.operandCount] = oper;
        this.operandCount += 1;
    }
};

const Element = union(enum) {
    instruction: Instruction,
    label: []const u8,
    data8: u8,
    data16: u16,
    data32: u32,
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
        directiveOrLabel, // .foo
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
        //     const token = this.readTokenNoDebug();
        //     std.debug.warn("token: {}\n", token);
        //     return token;
        // }

        // fn readTokenNoDebug(this: *Parser) !?Token {
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

                // don't eat the delimiting newline, otherwise trailing comments will fail
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

            // is either .label or .directiveOrLabel
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
                        .type = .directiveOrLabel,
                        .value = this.source[start + 1 .. end],
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
                    const text = this.source[start..end];

                    comptime var i = 0;
                    inline while (i < 16) : (i += 1) {
                        comptime var registerName: [3]u8 = "r??";
                        comptime var len = std.fmt.formatIntBuf(registerName[1..], i, 10, false, std.fmt.FormatOptions{});
                        // @compileLog(i, registerName[0 .. 1 + len]);
                        if (std.mem.eql(u8, text, registerName[0 .. 1 + len])) {
                            return Token{
                                .type = .registerName,
                                .value = text,
                            };
                        }
                    }

                    return Token{
                        .type = .identifier,
                        .value = text,
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

    fn readExpectedToken(this: *Parser, comptime _type: TokenType) ![]const u8 {
        const token = (try this.readToken()) orelse return error.UnexpectedEndOfText;
        if (token.type != _type)
            return error.UnexpectedToken;
        return token.value;
    }

    fn readAnyExpectedToken(this: *Parser, allowedTypes: []const TokenType) !Token {
        const token = (try this.readToken()) orelse return error.UnexpectedEndOfText;
        for (allowedTypes) |val| {
            if (token.type == val)
                return token;
        }
        return error.UnexpectedToken;
    }

    state: State = .default,

    fn convertTokenToNumber(token: Token) !u32 {
        return switch (token.type) {
            .hexnum => try std.fmt.parseInt(u32, token.value[2..], 16),
            .decnum => try std.fmt.parseInt(u32, token.value, 10),
            else => return error.UnexpectedToken,
        };
    }

    fn convertTokenToDirectOperand(token: Token) !Operand.Direct {
        return switch (token.type) {
            .registerName => Operand.Direct{
                .register = try std.fmt.parseInt(u4, token.value[1..], 10),
            },
            .identifier, .directiveOrLabel => Operand.Direct{
                .label = token.value,
            },
            .hexnum, .decnum => Operand.Direct{
                .immediate = try convertTokenToNumber(token),
            },
            else => return error.UnexpectedToken,
        };
    }

    fn readNumberToken(this: *Parser) !u32 {
        return try convertTokenToNumber(try this.readAnyExpectedToken(([_]TokenType{ .decnum, .hexnum })[0..]));
    }

    fn readNext(this: *Parser) !?Element {
        // loop until we return
        while (true) {
            var token = (try this.readToken()) orelse return null;

            if (token.type == .lineBreak) {
                // line breaks will stop any special processing from directives
                this.state = .default;
                continue;
            }

            switch (this.state) {
                .default => {
                    switch (token.type) {
                        .directiveOrLabel => {
                            if (std.mem.eql(u8, token.value, "def")) {
                                const name = try this.readExpectedToken(.identifier);
                                _ = try this.readExpectedToken(.comma);
                                const value = try this.readNumberToken();

                                // TODO: Handle .def
                            } else if (std.mem.eql(u8, token.value, "undef")) {
                                const name = try this.readExpectedToken(.identifier);
                            } else if (std.mem.eql(u8, token.value, "d8")) {
                                this.state = .readsD8;
                            } else if (std.mem.eql(u8, token.value, "d16")) {
                                this.state = .readsD16;
                            } else if (std.mem.eql(u8, token.value, "d32") or std.mem.eql(u8, token.value, "dw")) {
                                this.state = .readsD32;
                            } else if (std.mem.eql(u8, token.value, "align")) {
                                const al = try this.readNumberToken();
                                return Element{
                                    .alignment = al,
                                };
                            } else {
                                return error.UnknownDirective;
                            }
                        },
                        .label => {
                            return Element{
                                .label = token.value,
                            };
                        },

                        // is a mnemonic/instruction
                        .identifier => {
                            var instruction = Instruction.new(token.value);

                            // read operands
                            var readDelimiterNext = false;
                            var isFirst = true;
                            while (true) {
                                const subtok = (try this.readToken()) orelse return error.UnexpectedEndOfText;

                                if (isFirst and subtok.type == .lineBreak)
                                    break;
                                isFirst = false;

                                if (readDelimiterNext) {
                                    // is either comma for another operand or lineBreak for "end of operands"
                                    switch (subtok.type) {
                                        .lineBreak => break,
                                        .comma => {},
                                        else => return error.UnexpectedToken,
                                    }
                                    readDelimiterNext = false;
                                } else {
                                    // is an operand value
                                    switch (subtok.type) {
                                        .identifier, .hexnum, .decnum, .directiveOrLabel, .registerName => {
                                            try instruction.addOperand(Operand{
                                                .direct = try convertTokenToDirectOperand(subtok),
                                            });
                                        },
                                        .beginIndirection => {
                                            const directOperand = try convertTokenToDirectOperand((try this.readToken()) orelse return error.UnexpectedEndOfText);

                                            const something = try this.readAnyExpectedToken(([_]TokenType{ .endIndirection, .positiveOffset, .negativeOffset })[0..]);
                                            const result = switch (something.type) {
                                                .endIndirection => Operand.Indirect{
                                                    .source = directOperand,
                                                    .offset = null,
                                                },
                                                .positiveOffset => blk: {
                                                    const num = try this.readNumberToken();
                                                    _ = try this.readExpectedToken(.endIndirection);
                                                    break :blk Operand.Indirect{
                                                        .source = directOperand,
                                                        .offset = @intCast(i32, num),
                                                    };
                                                },
                                                .negativeOffset => blk: {
                                                    const num = try this.readNumberToken();
                                                    _ = try this.readExpectedToken(.endIndirection);
                                                    break :blk Operand.Indirect{
                                                        .source = directOperand,
                                                        .offset = -@intCast(i32, num),
                                                    };
                                                },
                                                else => return error.UnexpectedToken,
                                            };

                                            try instruction.addOperand(Operand{
                                                .indirect = result,
                                            });
                                        },
                                        else => return error.UnexpectedToken,
                                    }
                                    readDelimiterNext = true;
                                }
                            }
                            return Element{ .instruction = instruction };
                        },

                        else => return error.UnexpectedToken,
                    }
                },
                .readsD8, .readsD16, .readsD32 => {
                    switch (token.type) {
                        .decnum, .hexnum => {
                            const num = try convertTokenToNumber(token);
                            return switch (this.state) {
                                .readsD8 => Element{
                                    .data8 = @intCast(u8, num),
                                },
                                .readsD16 => Element{
                                    .data16 = @intCast(u16, num),
                                },
                                .readsD32 => Element{
                                    .data32 = num,
                                },

                                else => unreachable,
                            };
                        },
                        .identifier => {
                            // TODO: Support definitions and labels here
                            return error.NotImplementedYet;
                        },
                        .comma => {},
                        else => return error.UnexpectedToken,
                    }
                },
            }
        }
    }

    const State = enum {
        default,
        readsD8,
        readsD16,
        readsD32,
    };
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
        std.debug.warn("semantic element: {}\n", label_or_instruction);
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
                try writer.write(u8(0xAA));
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
            .alignment => |al| {
                std.debug.assert((al & (al - 1)) == 0);
                writer.offset = (writer.offset + al - 1) & ~(al - 1);
            },
        }
    }

    // debug output:
    var iter = globalLabels.iterator();
    while (iter.next()) |lbl| {
        std.debug.warn("label: {}\n", lbl);
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
                std.mem.copy(u8, this.target[this.offset .. this.offset + @sizeOf(T)], std.mem.asBytes(&value));
                this.offset += @sizeOf(T);
            },
            else => @compileError(@typeName(@typeOf(value)) ++ " is not supported by writer!"),
        }
    }
};
