const std = @import("std");
const lola = @import("lola");
const painterz = @import("painterz");

pub const ObjectPool = lola.runtime.ObjectPool(.{});

fn parsePixelValue(value: ?u8) ?u4 {
    if (value == null)
        return null;
    return switch (value.?) {
        0...15 => @truncate(u4, value.?),
        '0'...'9' => @truncate(u4, value.? - '0'),
        'a'...'f' => @truncate(u4, value.? - 'a' + 10),
        'A'...'F' => @truncate(u4, value.? - 'A' + 10),
        else => null,
    };
}

pub const Color = struct {
    const black = 0x0;
    const dark_purple = 0x1;
    const dark_blue = 0x2;
    const dark_gray = 0x3;
    const brown = 0x4;
    const dark_green = 0x5;
    const red = 0x6;
    const gray = 0x7;
    const blue = 0x8;
    const orange = 0x9;
    const light_gray = 0xA;
    const green = 0xB;
    const skin = 0xC;
    const dim_cyan = 0xD;
    const yellow = 0xE;
    const white = 0xF;
};

comptime {
    if (Screen.width % TextTerminal.width != 0)
        @compileError("TextTerminal.width is not a integer divisor of Screen.width!");
    if (Screen.height % TextTerminal.height != 0)
        @compileError("TextTerminal.height is not a integer divisor of Screen.height!");

    if ((Screen.width / TextTerminal.width) != (Screen.height / TextTerminal.height))
        @compileError("TextTerminal does not have square tiles!");
}

pub const TextTerminal = struct {
    const Self = @This();

    const raw_font = @as([tile_size * 256]u8, @embedFile("res/font.dat").*);

    const CursorPosition = struct {
        x: usize,
        y: usize,
    };

    const Char = struct {
        data: u8,
        color: ?u4,

        const empty = @This(){
            .data = ' ',
            .color = null,
        };
    };

    pub const width = 20;
    pub const height = 15;
    pub const tile_size = Screen.width / width;

    comptime {
        if (tile_size < 1 or tile_size > 8) {
            @compileError("TextTerminal.tile_size must be less or equal than 8 pixel large!");
        }
    }

    const empty_row = [1]Char{Char.empty} ** width;
    const empty_screen = [1][20]Char{empty_row} ** height;

    content: [height][width]Char = empty_screen,
    cursor_visible: bool = true,
    cursor_position: CursorPosition = CursorPosition{ .x = 0, .y = 0 },

    bg_color: ?u4 = 0,
    fg_color: ?u4 = 15,

    const Glyph = struct {
        bits: [tile_size]u8,

        inline fn get(self: @This(), x: u3, y: u3) bool {
            return (self.bits[y] & (@as(u8, 1) << x)) != 0;
        }
    };

    pub fn getGlyph(char: u8) Glyph {
        return Glyph{ .bits = raw_font[tile_size * @as(usize, char) ..][0..tile_size].* };
    }

    pub fn render(self: Self, screen: *Screen, cursor_blink_active: bool) void {
        for (self.content) |line, row| {
            for (line) |char, column| {
                const glyph = getGlyph(char.data);
                var y: usize = 0;
                while (y < tile_size) : (y += 1) {
                    // unroll 6 pixel-set operations
                    comptime var x = 0;
                    inline while (x < tile_size) : (x += 1) {
                        screen.pixels[tile_size * row + y][tile_size * column + x] = if ((glyph.get(x, @truncate(u3, y))))
                            char.color orelse @as(u8, 0xFF)
                        else
                            self.bg_color orelse @as(u8, 0xFF);
                    }
                }
            }
        }

        if (self.cursor_visible and cursor_blink_active) {
            var y: usize = 0;
            while (y < tile_size) : (y += 1) {
                var x: usize = 0;
                while (x < tile_size) : (x += 1) {
                    screen.pixels[tile_size * self.cursor_position.y + y][tile_size * self.cursor_position.x + x] = self.fg_color orelse 0xFF;
                }
            }
        }
    }

    pub fn clear(self: *Self) void {
        self.content = empty_screen;
        self.cursor_position = CursorPosition{
            .x = 0,
            .y = 0,
        };
    }

    pub fn scroll(self: *Self, amount: u32) void {
        if (amount > self.content.len) {
            self.content = empty_screen;
        } else {
            var r: usize = 1;
            while (r < self.content.len) : (r += 1) {
                self.content[r - 1] = self.content[r];
            }
            self.content[self.content.len - 1] = empty_row;
        }
    }

    pub fn put(self: *Self, char: u8) void {
        switch (char) {
            '\r' => self.cursor_position.x = 0,
            '\n' => self.cursor_position.y += 1,
            else => {
                self.content[self.cursor_position.y][self.cursor_position.x] = Char{
                    .data = char,
                    .color = self.fg_color,
                };
                self.cursor_position.x += 1;
            },
        }
        if (self.cursor_position.x >= self.content[0].len) {
            self.cursor_position.x = 0;
            self.cursor_position.y += 1;
        }
        if (self.cursor_position.y >= self.content.len) {
            self.scroll(1);
            self.cursor_position.y -= 1;
        }
    }

    pub fn write(self: *Self, string: []const u8) void {
        for (string) |c| {
            self.put(c);
        }
    }

    const Writer = std.io.Writer(*Self, error{}, struct {
        fn write(self: *Self, buffer: []const u8) error{}!usize {
            self.write(buffer);
            return buffer.len;
        }
    }.write);
    pub fn writer(self: *Self) Writer {
        return Writer{ .context = self };
    }
};

pub const Screen = struct {
    const Self = @This();

    pub const RGBA = extern struct {
        r: u8,
        g: u8,
        b: u8,
        a: u8 = 0xFF,
    };

    pub const border_size = 16;
    pub const width = 160;
    pub const height = 120;

    pub const total_width = 2 * border_size + width;
    pub const total_height = 2 * border_size + height;

    border_color: u8 = 2, // dim blue
    pixels: [height][width]u8 = [1][width]u8{[1]u8{0} ** width} ** height,
    pixel_rng: std.rand.DefaultPrng = std.rand.DefaultPrng.init(1337), // can always be the same sequence, shouldn't matter
    palette: [16]RGBA = [16]RGBA{
        // Using the Dawnbringer 16 palette by default.
        // https://lospec.com/palette-list/dawnbringer-16
        RGBA{ .r = 0x14, .g = 0x0c, .b = 0x1c }, // 0 #140c1c black
        RGBA{ .r = 0x44, .g = 0x24, .b = 0x34 }, // 1 #442434 dark purple
        RGBA{ .r = 0x30, .g = 0x34, .b = 0x6d }, // 2 #30346d dark blue
        RGBA{ .r = 0x4e, .g = 0x4a, .b = 0x4e }, // 3 #4e4a4e dark gray
        RGBA{ .r = 0x85, .g = 0x4c, .b = 0x30 }, // 4 #854c30 brown
        RGBA{ .r = 0x34, .g = 0x65, .b = 0x24 }, // 5 #346524 dark green
        RGBA{ .r = 0xd0, .g = 0x46, .b = 0x48 }, // 6 #d04648 red
        RGBA{ .r = 0x75, .g = 0x71, .b = 0x61 }, // 7 #757161 gray
        RGBA{ .r = 0x59, .g = 0x7d, .b = 0xce }, // 8 #597dce blue
        RGBA{ .r = 0xd2, .g = 0x7d, .b = 0x2c }, // 9 #d27d2c orange
        RGBA{ .r = 0x85, .g = 0x95, .b = 0xa1 }, // A #8595a1 light gray
        RGBA{ .r = 0x6d, .g = 0xaa, .b = 0x2c }, // B #6daa2c green
        RGBA{ .r = 0xd2, .g = 0xaa, .b = 0x99 }, // C #d2aa99 skin
        RGBA{ .r = 0x6d, .g = 0xc2, .b = 0xca }, // D #6dc2ca dim cyan
        RGBA{ .r = 0xda, .g = 0xd4, .b = 0x5e }, // E #dad45e yellow
        RGBA{ .r = 0xde, .g = 0xee, .b = 0xd6 }, // F #deeed6 white
    },

    fn translateColor(self: *Self, color: u8) RGBA {
        const index = std.math.cast(u4, color) catch self.pixel_rng.random.int(u4);
        return self.palette[index];
    }

    pub fn set(self: *Self, x: isize, y: isize, color: u8) void {
        const px = std.math.cast(usize, x) catch return;
        const py = std.math.cast(usize, y) catch return;
        if (px >= width) return;
        if (py >= height) return;
        self.pixels[py][px] = color;
    }

    pub fn get(self: Self, x: isize, y: isize) u8 {
        const px = std.math.cast(usize, x) catch return 0xFF;
        const py = std.math.cast(usize, y) catch return 0xFF;
        if (px >= width) return 0xFF;
        if (py >= height) return 0xFF;
        return self.pixels[py][px];
    }

    pub fn render(self: *Self) [total_height][total_width]RGBA {
        var buffer: [total_height][total_width]RGBA = undefined;

        for (buffer) |*row| {
            for (row) |*color| {
                color.* = self.translateColor(self.border_color);
            }
        }

        for (self.pixels) |row, y| {
            for (row) |color, x| {
                buffer[border_size + y][border_size + x] = self.translateColor(color);
            }
        }

        return buffer;
    }

    fn clear(self: *Self, color: u8) void {
        for (self.pixels) |*row| {
            for (row) |*pixel| {
                pixel.* = color;
            }
        }
    }

    fn scroll(self: *Self, src_dx: i32, src_dy: i32) void {
        const srcbuf = self.pixels;

        const dx: u32 = @intCast(u32, @mod(-src_dx, Screen.width));
        const dy: u32 = @intCast(u32, @mod(-src_dy, Screen.height));

        if (dx == 0 and dy == 0)
            return;

        const H = struct {
            fn wrapAdd(a: usize, b: u32, comptime limit: comptime_int) u32 {
                return (@intCast(u32, a) + b) % limit;
            }
        };

        for (self.pixels) |*row, y| {
            for (row) |*pixel, x| {
                pixel.* = srcbuf[H.wrapAdd(y, dy, Screen.height)][H.wrapAdd(x, dx, Screen.width)];
            }
        }
    }

    fn blitBuffer(self: *Self, dst_x: i32, dst_y: i32, buffer_width: u31, pixel_buffer: []const u8) void {
        if (buffer_width == 0)
            return;
        var index: usize = 0;

        var dy: u31 = 0;
        while (true) : (dy += 1) {
            var dx: u31 = 0;
            while (dx < buffer_width) : (dx += 1) {
                const pixel = pixel_buffer[index];
                if (parsePixelValue(pixel)) |color| {
                    self.set(
                        dst_x + @as(i32, dx),
                        dst_y + @as(i32, dy),
                        color,
                    );
                }
                index += 1;
                if (index >= pixel_buffer.len)
                    return;
            }
        }
    }

    fn drawText(self: *Self, x: i32, y: i32, color: ?u8, text: []const u8) void {
        var dx = x;
        var dy = y;

        for (text) |char| {
            const glyph = TextTerminal.getGlyph(char);

            var iy: u4 = 0;
            while (iy < TextTerminal.tile_size) : (iy += 1) {
                comptime var ix: u4 = 0;
                inline while (ix < TextTerminal.tile_size) : (ix += 1) {
                    if (glyph.get(@truncate(u3, ix), @truncate(u3, iy))) {
                        self.set(
                            dx + @as(i32, ix),
                            dy + @as(i32, iy),
                            color orelse 0xFF,
                        );
                    }
                }
            }

            dx += TextTerminal.tile_size;
        }
    }
};

pub const JoystickButton = struct {
    const Self = @This();

    is_pressed: bool = false,
    press_state: bool = false,
    release_state: bool = false,

    pub fn wasHit(self: *Self) bool {
        defer self.press_state = self.is_pressed;
        return if (self.is_pressed)
            !self.press_state
        else
            false;
    }

    pub fn wasReleased(self: *Self) bool {
        defer self.release_state = self.is_pressed;
        return if (!self.is_pressed)
            self.release_state
        else
            false;
    }

    /// Syncs the event states so no cached event might be happening
    fn resetEvent(self: *Self) void {
        self.press_state = self.is_pressed;
        self.release_state = self.is_pressed;
    }
};

pub const JoystickState = struct {
    x: f64,
    y: f64,

    a: bool,
    b: bool,
    go: bool,
    menu: bool,
};

const Joystick = struct {
    const Self = @This();

    x: f64 = 0,
    y: f64 = 0,

    up: JoystickButton = JoystickButton{},
    down: JoystickButton = JoystickButton{},
    left: JoystickButton = JoystickButton{},
    right: JoystickButton = JoystickButton{},

    a: JoystickButton = JoystickButton{},
    b: JoystickButton = JoystickButton{},
    go: JoystickButton = JoystickButton{},
    menu: JoystickButton = JoystickButton{},

    fn update(self: *Self, state: JoystickState) void {
        self.x = state.x;
        self.y = state.y;

        self.up.is_pressed = self.y < -0.1;
        self.down.is_pressed = self.y > 0.1;
        self.left.is_pressed = self.x < -0.1;
        self.right.is_pressed = self.x > 0.1;

        self.a.is_pressed = state.a;
        self.b.is_pressed = state.b;
        self.go.is_pressed = state.go;
        self.menu.is_pressed = state.menu;
    }

    fn resetEvents(self: *Self) void {
        self.a.resetEvent();
        self.b.resetEvent();
        self.go.resetEvent();
        self.menu.resetEvent();
    }
};

/// Initialize a new game system.
/// The system is allocated by allocator to ensure the returned value is a pinned pointer as
/// System stores internal references.
pub fn init(allocator: *std.mem.Allocator) !*System {
    var system = try allocator.create(System);
    errdefer allocator.destroy(system);

    system.* = System{
        .allocator = allocator,
        .game = null,
    };

    return system;
}

pub const System = struct {
    const Self = @This();

    const Event = union(enum) {
        /// The game system is done, shut down the emulator
        quit,

        /// Flush System.virtual_screen to the actual screen.
        render,

        /// The system is stale and requires either more events to be pushed
        /// or enough time has passed and control should return to the caller
        /// again (required for WASM and other systems)
        yield,
    };

    const State = union(enum) {
        // Either running the game (if any) or show a broken screen
        default,

        shutdown,

        save_dialog: *SaveGameCall,

        load_dialog: *LoadGameCall,

        pause_dialog: *PauseGameCall,
    };

    const GraphicsMode = enum { text, graphics };

    allocator: *std.mem.Allocator,

    virtual_screen: Screen = Screen{},
    virtual_terminal: TextTerminal = TextTerminal{},

    state: State = .default,
    game: ?Game = null,
    is_finished: bool = false,

    graphics_mode: GraphicsMode = .text,
    gpu_auto_flush: bool = true,
    gpu_flush: bool = false,

    is_joystick_normalized: bool = false,
    joystick: Joystick = Joystick{},

    /// Loads the given game, unloading any currently loaded game.
    /// Note that the system keeps the pointer to `game`  until the system is closed. Don't free game
    /// before the system is deinitialized.
    pub fn loadGame(self: *Self, rom: *const GameROM) !void {
        self.unloadGame();

        self.game = @as(Game, undefined); // makes self.game non-null
        try Game.init(&self.game.?, self, rom);
        errdefer game = null;
    }

    /// Unloads the current game and resumes the home position.
    pub fn unloadGame(self: *Self) void {
        // switch (self.state) {
        //     .default => {},
        // }
        if (self.game) |*game| {
            game.deinit();
        }
        self.game = null;
        self.state = .default;
        self.resetScreen();
    }

    pub fn update(self: *Self) !Event {
        defer self.gpu_flush = false;
        const loop_event: Event = switch (self.state) {
            .shutdown => return .quit,

            .default => blk: {
                if (self.game) |*game| {
                    const result = game.vm.execute(10_000) catch |err| {
                        if (err == error.PoweroffSignal) {
                            self.state = .shutdown;
                            break :blk .yield;
                        } else {
                            // TODO: Print stack trace here
                            std.debug.print("failed with {}\n", .{@errorName(err)});

                            try game.vm.printStackTrace(std.io.getStdOut().writer());
                        }
                        self.unloadGame();

                        break :blk Event.render;
                    };
                    switch (result) {
                        .completed => {
                            self.unloadGame();
                            break :blk Event.yield;
                        },
                        .exhausted, .paused => break :blk if (self.gpu_auto_flush or self.gpu_flush)
                            Event.render
                        else
                            Event.yield,
                    }
                } else {
                    self.virtual_screen.clear(0xFF);
                    // what to do here?
                    break :blk Event.render;
                }
            },

            .save_dialog => |call| {
                std.debug.assert(self.game != null);

                if (self.joystick.menu.wasHit()) {
                    call.result = false;
                    return self.closeDialog(&call.dialog);
                }

                if (self.joystick.b.wasHit()) {
                    call.result = true;
                    return self.closeDialog(&call.dialog);
                }

                if (self.joystick.up.wasHit() and call.selected_slot > 0) {
                    call.selected_slot -= 1;
                }

                if (self.joystick.down.wasHit() and call.selected_slot < 2) {
                    call.selected_slot += 1;
                }

                self.virtual_screen.clear(Color.light_gray);
                self.virtual_screen.drawText(28, 2, Color.dark_purple, "<<SAVE GAME>>");
                self.virtual_screen.drawText(0, 12, Color.white, "Chose your game file");

                self.virtual_screen.drawText(0, 24, Color.white, "[ ] <empty>");
                self.virtual_screen.drawText(0, 32, Color.white, "[ ] <empty>");
                self.virtual_screen.drawText(0, 40, Color.white, "[ ] <empty>");

                self.virtual_screen.drawText(8, 24 + 8 * call.selected_slot, Color.red, "X");

                return .render;
            },

            .load_dialog => |call| {
                std.debug.assert(self.game != null);

                if (self.joystick.menu.wasHit()) {
                    call.data = null;
                    return self.closeDialog(&call.dialog);
                }

                if (self.joystick.b.wasHit()) {
                    call.data = switch (call.selected_slot) {
                        0 => try self.allocator.dupe(u8, "1"),
                        1 => try self.allocator.dupe(u8, "2"),
                        2 => try self.allocator.dupe(u8, "3"),
                        else => unreachable,
                    };
                    return self.closeDialog(&call.dialog);
                }

                if (self.joystick.up.wasHit() and call.selected_slot > 0) {
                    call.selected_slot -= 1;
                }

                if (self.joystick.down.wasHit() and call.selected_slot < 2) {
                    call.selected_slot += 1;
                }

                self.virtual_screen.clear(Color.light_gray);
                self.virtual_screen.drawText(28, 2, Color.dark_purple, "<<LOAD GAME>>");
                self.virtual_screen.drawText(0, 12, Color.white, "Chose your game file");

                self.virtual_screen.drawText(0, 24, Color.white, "[ ] <empty>");
                self.virtual_screen.drawText(0, 32, Color.white, "[ ] <empty>");
                self.virtual_screen.drawText(0, 40, Color.white, "[ ] <empty>");

                self.virtual_screen.drawText(8, 24 + 8 * call.selected_slot, Color.red, "X");

                return .render;
            },

            .pause_dialog => |call| {
                std.debug.assert(self.game != null);

                if (self.joystick.menu.wasHit()) {
                    return self.closeDialog(&call.dialog);
                }

                self.virtual_screen.clear(Color.light_gray);
                self.virtual_screen.drawText(6, 6, Color.white, "The game is paused");

                self.virtual_screen.blitBuffer(48, 33, 24, std.mem.asBytes(&self.game.?.rom.icon));

                return .render;
            },
        };

        if (self.graphics_mode == .text and (loop_event == .render or loop_event == .yield)) {
            self.virtual_terminal.render(
                &self.virtual_screen,
                @mod(std.time.milliTimestamp(), 1000) >= 500,
            );
            return .render;
        }
        return loop_event;
    }

    fn closeDialog(self: *Self, dialog: *Dialog) Event {
        dialog.completed = true;
        self.state = .default;
        self.virtual_screen.pixels = dialog.screen_backup;
        return .render;
    }

    pub fn deinit(self: *Self) void {
        self.unloadGame();
        self.allocator.destroy(self);
    }

    pub fn setJoystick(self: *Self, joy: JoystickState) void {
        if (self.is_joystick_normalized) {
            var joybuf = joy;
            const len2 = joy.x * joy.x + joy.y * joy.y;
            if (len2 > 1.0) {
                const len = std.math.sqrt(len2);
                joybuf.x /= len;
                joybuf.y /= len;
            }
            self.joystick.update(joybuf);
        } else {
            self.joystick.update(joy);
        }
    }

    fn resetScreen(self: *Self) void {
        self.virtual_screen = Screen{};
    }

    const Canvas = painterz.Canvas(*Screen, u8, Screen.set);
    fn canvas(self: *Self) Canvas {
        return Canvas.init(&self.virtual_screen);
    }
};

pub const GameROM = struct {
    id: []const u8,
    name: []const u8,
    icon: [24][24]u8,
    code: lola.CompileUnit,
    data: std.StringHashMap([]const u8),
};

const Game = struct {
    const Self = @This();

    system: *System,
    rom: *const GameROM,

    pool: ObjectPool,
    environment: lola.runtime.Environment,
    vm: lola.runtime.VM,

    fn init(game: *Self, system: *System, rom: *const GameROM) !void {
        game.* = Self{
            .system = system,
            .rom = rom,

            .pool = undefined,
            .environment = undefined,
            .vm = undefined,
        };

        game.pool = ObjectPool.init(system.allocator);
        errdefer game.pool.deinit();

        game.environment = try lola.runtime.Environment.init(system.allocator, &rom.code, game.pool.interface());
        errdefer game.environment.deinit();

        try lola.libs.std.install(&game.environment, system.allocator);

        inline for (std.meta.declarations(api)) |decl| {
            const function = @field(api, decl.name);

            const Type = @TypeOf(function);

            const lola_fn = if (Type == lola.runtime.UserFunctionCall)
                lola.runtime.Function{
                    .syncUser = .{
                        .context = lola.runtime.Context.init(Game, game),
                        .call = function,
                        .destructor = null,
                    },
                }
            else if (Type == lola.runtime.AsyncUserFunctionCall)
                lola.runtime.Function{
                    .asyncUser = .{
                        .context = lola.runtime.Context.init(Game, game),
                        .call = function,
                        .destructor = null,
                    },
                }
            else
                lola.runtime.Function.wrapWithContext(
                    function,
                    game,
                );

            try game.environment.installFunction(decl.name, lola_fn);
        }

        game.vm = try lola.runtime.VM.init(system.allocator, &game.environment);
        errdefer game.vm.deinit();
    }

    pub fn deinit(self: *Self) void {
        self.vm.deinit();
        self.environment.deinit();
        self.pool.deinit();
        self.* = undefined;
    }

    fn initDialog(self: *Self) Dialog {
        self.system.joystick.resetEvents();
        return Dialog{
            .game = self,
            .screen_backup = self.system.virtual_screen.pixels,
            .completed = false,
        };
    }

    const api = struct {
        // System Control
        fn Poweroff(game: *Game) error{PoweroffSignal} {
            std.debug.assert(game.system.state == .default);
            game.system.state = .shutdown;
            return error.PoweroffSignal;
        }

        fn SaveGame(
            environment: *lola.runtime.Environment,
            call_context: lola.runtime.Context,
            args: []const lola.runtime.Value,
        ) anyerror!lola.runtime.AsyncFunctionCall {
            const game = call_context.get(Game);

            if (args.len != 1)
                return error.InvalidArgs;

            const original_data = try args[0].toString();
            const data = try game.system.allocator.dupe(u8, original_data);
            errdefer game.system.allocator.free(data);

            const call = try game.system.allocator.create(SaveGameCall);
            errdefer game.system.allocator.destroy(call);

            call.* = SaveGameCall{
                .data = data,
                .dialog = game.initDialog(),
            };

            game.system.state = System.State{
                .save_dialog = call,
            };

            return lola.runtime.AsyncFunctionCall{
                .context = lola.runtime.Context.init(SaveGameCall, call),
                .execute = SaveGameCall.execute,
                .destructor = SaveGameCall.destroy,
            };
        }

        fn LoadGame(
            environment: *lola.runtime.Environment,
            call_context: lola.runtime.Context,
            args: []const lola.runtime.Value,
        ) anyerror!lola.runtime.AsyncFunctionCall {
            const game = call_context.get(Game);

            if (args.len != 0)
                return error.InvalidArgs;

            const call = try game.system.allocator.create(LoadGameCall);
            errdefer game.system.allocator.destroy(call);

            call.* = LoadGameCall{
                .dialog = game.initDialog(),
            };

            game.system.state = System.State{
                .load_dialog = call,
            };

            return lola.runtime.AsyncFunctionCall{
                .context = lola.runtime.Context.init(LoadGameCall, call),
                .execute = LoadGameCall.execute,
                .destructor = LoadGameCall.destroy,
            };
        }

        fn Pause(
            environment: *lola.runtime.Environment,
            call_context: lola.runtime.Context,
            args: []const lola.runtime.Value,
        ) anyerror!lola.runtime.AsyncFunctionCall {
            const game = call_context.get(Game);

            if (args.len != 0)
                return error.InvalidArgs;

            const call = try game.system.allocator.create(PauseGameCall);
            errdefer game.system.allocator.destroy(call);

            call.* = PauseGameCall{
                .dialog = game.initDialog(),
            };

            game.system.state = System.State{
                .pause_dialog = call,
            };

            return lola.runtime.AsyncFunctionCall{
                .context = lola.runtime.Context.init(PauseGameCall, call),
                .execute = PauseGameCall.execute,
                .destructor = PauseGameCall.destroy,
            };
        }

        // Resource Management

        fn LoadData(game: *Game, path: []const u8) !?lola.runtime.String {
            if (game.rom.data.get(path)) |data| {
                return try lola.runtime.String.init(game.system.allocator, data);
            } else {
                return null;
            }
        }

        // Text Mode

        fn Print(
            environment: *lola.runtime.Environment,
            context: lola.runtime.Context,
            args: []const lola.runtime.Value,
        ) anyerror!lola.runtime.Value {
            const game = context.get(Game);

            const output = game.system.virtual_terminal.writer();
            for (args) |arg| {
                if (arg == .string) {
                    try output.print("{s}", .{arg.toString() catch unreachable});
                } else {
                    try output.print("{}", .{arg});
                }
            }
            try output.writeAll("\r\n");

            return .void;
        }

        fn Input(game: *Game, prompt: ?[]const u8) ?lola.runtime.String {
            // TODO: Implement Input
            return null;
        }

        fn TxtClear(game: *Game) void {
            game.system.virtual_terminal.clear();
        }

        fn TxtSetBackground(game: *Game, color: ?u8) void {
            game.system.virtual_terminal.bg_color = parsePixelValue(color);
        }

        fn TxtSetForeground(game: *Game, color: ?u8) void {
            game.system.virtual_terminal.fg_color = parsePixelValue(color);
        }

        fn TxtWrite(
            environment: *lola.runtime.Environment,
            context: lola.runtime.Context,
            args: []const lola.runtime.Value,
        ) anyerror!lola.runtime.Value {
            const game = context.get(Game);

            const output = game.system.virtual_terminal.writer();
            for (args) |arg| {
                if (arg == .string) {
                    try output.print("{s}", .{arg.toString() catch unreachable});
                } else {
                    try output.print("{}", .{arg});
                }
            }

            // TODO: Return number of chars written
            return .void;
        }

        fn TxtRead(game: *Game) !lola.runtime.String {
            @panic("TODO: Implement TxtRead!");
        }

        fn TxtReadLine(game: *Game) !?lola.runtime.String {
            @panic("TODO: Implement TxtReadLine!");
        }

        fn TxtEnableCursor(game: *Game, enabled: bool) void {
            game.system.virtual_terminal.cursor_visible = enabled;
        }

        fn TxtSetCursor(game: *Game, x: i32, y: i32) void {
            if (x < 0 or x >= TextTerminal.width)
                return;
            if (y < 0 or y >= TextTerminal.height)
                return;
            game.system.virtual_terminal.cursor_position.x = @intCast(u5, x);
            game.system.virtual_terminal.cursor_position.y = @intCast(u5, y);
        }

        fn TxtScroll(game: *Game, lines: u32) void {
            game.system.virtual_terminal.scroll(lines);
        }

        // Graphics Mode

        fn SetGraphicsMode(game: *Game, enabled: bool) void {
            game.system.graphics_mode = if (enabled) .graphics else .text;
        }

        fn GpuSetPixel(game: *Game, x: i32, y: i32, color: ?u8) !void {
            game.system.virtual_screen.set(x, y, color orelse 0xFF);
        }

        fn GpuGetPixel(game: *Game, x: i32, y: i32) !?u8 {
            const color = game.system.virtual_screen.get(x, y);
            if (color >= 16)
                return null;
            return color;
        }

        fn GpuGetFramebuffer(game: *Game) !lola.runtime.String {
            return try lola.runtime.String.init(
                game.system.allocator,
                std.mem.sliceAsBytes(&game.system.virtual_screen.pixels),
            );
        }

        fn GpuSetFramebuffer(game: *Game, buffer: []const u8) void {
            var pixels = std.mem.sliceAsBytes(&game.system.virtual_screen.pixels);

            std.mem.copy(
                u8,
                pixels[0..std.math.min(pixels.len, buffer.len)],
                buffer[0..std.math.min(pixels.len, buffer.len)],
            );
        }

        fn GpuBlitBuffer(game: *Game, dst_x: i32, dst_y: i32, width: u31, pixel_buffer: []const u8) void {
            game.system.virtual_screen.blitBuffer(dst_x, dst_y, width, pixel_buffer);
        }

        fn GpuDrawLine(game: *Game, x0: i32, y0: i32, x1: i32, y1: i32, color: ?u8) void {
            game.system.canvas().drawLine(x0, y0, x1, y1, color orelse 0xFF);
        }

        fn GpuDrawRect(game: *Game, x: i32, y: i32, w: u32, h: u32, color: ?u8) void {
            game.system.canvas().drawRectangle(x, y, w, h, color orelse 0xFF);
        }

        fn GpuFillRect(game: *Game, x: i32, y: i32, w: u31, h: u31, color: ?u8) void {
            game.system.canvas().fillRectangle(x, y, w, h, color orelse 0xFF);
        }

        fn GpuDrawText(game: *Game, x: i32, y: i32, color: ?u8, text: []const u8) void {
            game.system.virtual_screen.drawText(x, y, color, text);
        }

        fn GpuScroll(game: *Game, dx: i32, dy: i32) void {
            game.system.virtual_screen.scroll(dx, dy);
        }

        fn GpuSetBorder(game: *Game, color: ?u8) void {
            game.system.virtual_screen.border_color = color orelse 0xFF;
        }

        fn GpuFlush(
            environment: *lola.runtime.Environment,
            call_context: lola.runtime.Context,
            args: []const lola.runtime.Value,
        ) anyerror!lola.runtime.AsyncFunctionCall {
            if (args.len != 0)
                return error.TypeMismatch;

            const Impl = struct {
                fn execute(context: lola.runtime.Context) !?lola.runtime.Value {
                    const game = context.get(Game);
                    game.system.gpu_flush = true;
                    return .void;
                }
            };

            return lola.runtime.AsyncFunctionCall{
                .context = call_context,
                .execute = Impl.execute,
                .destructor = null,
            };
        }

        fn GpuEnableAutoFlush(game: *Game, enabled: bool) void {
            game.system.gpu_auto_flush = enabled;
        }

        // Keyboard
        fn KbdIsDown(game: *Game, key: []const u8) bool {
            @panic("implement");
        }

        fn KbdIsUp(game: *Game, key: []const u8) bool {
            @panic("implement");
        }

        // Joystick

        fn JoyEnableNormalization(game: *Game, enabled: bool) void {
            game.system.is_joystick_normalized = enabled;
        }

        fn JoyGetX(game: *Game) f64 {
            return game.system.joystick.x;
        }

        fn JoyGetY(game: *Game) f64 {
            return game.system.joystick.y;
        }

        fn JoyGetA(game: *Game) bool {
            return game.system.joystick.a.is_pressed;
        }

        fn JoyGetB(game: *Game) bool {
            return game.system.joystick.b.is_pressed;
        }

        fn JoyGetGo(game: *Game) bool {
            return game.system.joystick.go.is_pressed;
        }

        fn JoyGetMenu(game: *Game) bool {
            return game.system.joystick.menu.is_pressed;
        }

        fn JoyHitA(game: *Game) bool {
            return game.system.joystick.a.wasHit();
        }

        fn JoyHitB(game: *Game) bool {
            return game.system.joystick.b.wasHit();
        }

        fn JoyHitGo(game: *Game) bool {
            return game.system.joystick.go.wasHit();
        }

        fn JoyHitMenu(game: *Game) bool {
            return game.system.joystick.menu.wasHit();
        }

        fn JoyReleaseA(game: *Game) bool {
            return game.system.joystick.a.wasReleased();
        }

        fn JoyReleaseB(game: *Game) bool {
            return game.system.joystick.b.wasReleased();
        }

        fn JoyReleaseGo(game: *Game) bool {
            return game.system.joystick.go.wasReleased();
        }

        fn JoyReleaseMenu(game: *Game) bool {
            return game.system.joystick.menu.wasReleased();
        }
    };
};

const Dialog = struct {
    game: *Game,
    screen_backup: [Screen.height][Screen.width]u8,
    completed: bool,
};

const SaveGameCall = struct {
    const Self = @This();

    dialog: Dialog,
    data: []const u8,
    result: ?bool = null,
    selected_slot: u8 = 0,

    fn execute(context: lola.runtime.Context) !?lola.runtime.Value {
        const self = context.get(Self);
        if (self.dialog.completed)
            return lola.runtime.Value.initBoolean(self.result orelse @panic("call.result wasn't set before calling closeDialog!"));
        return null;
    }

    fn destroy(context: lola.runtime.Context) void {
        const self = context.get(Self);

        self.dialog.game.system.allocator.free(self.data);
        self.dialog.game.system.allocator.destroy(self);
    }
};

const LoadGameCall = struct {
    const Self = @This();

    dialog: Dialog,
    data: ?[]const u8 = null,
    selected_slot: u8 = 0,

    fn execute(context: lola.runtime.Context) !?lola.runtime.Value {
        const self = context.get(Self);
        if (self.dialog.completed) {
            if (self.data) |data| {
                return try lola.runtime.Value.initString(self.dialog.game.system.allocator, data);
            }
            return .void;
        }
        return null;
    }

    fn destroy(context: lola.runtime.Context) void {
        const self = context.get(Self);

        if (self.data) |data|
            self.dialog.game.system.allocator.free(data);
        self.dialog.game.system.allocator.destroy(self);
    }
};

const PauseGameCall = struct {
    const Self = @This();

    dialog: Dialog,

    fn execute(context: lola.runtime.Context) !?lola.runtime.Value {
        const self = context.get(Self);
        if (self.dialog.completed) {
            return .void;
        } else {
            return null;
        }
    }

    fn destroy(context: lola.runtime.Context) void {
        const self = context.get(Self);

        self.dialog.game.system.allocator.destroy(self);
    }
};
