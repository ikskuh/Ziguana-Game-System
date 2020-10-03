const std = @import("std");
const lola = @import("lola");
const painterz = @import("painterz");

pub const ObjectPool = lola.runtime.ObjectPool(.{});

fn parsePixelValue(value: u8) ?u4 {
    return switch (value) {
        0...15 => @truncate(u4, value),
        '0'...'9' => @truncate(u4, value - '0'),
        'a'...'f' => @truncate(u4, value - 'a' + 10),
        'A'...'F' => @truncate(u4, value - 'F' + 10),
        else => null,
    };
}

pub const Screen = struct {
    const Self = @This();

    pub const RGBA = extern struct {
        r: u8,
        g: u8,
        b: u8,
        a: u8 = 0xFF,
    };

    pub const border_size = 12;
    pub const width = 120;
    pub const height = 90;

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
};

pub const JoystickState = struct {
    x: f64,
    y: f64,
    a: bool,
    b: bool,
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
    };

    const GraphicsMode = enum { text, graphics };

    allocator: *std.mem.Allocator,

    virtual_screen: Screen = Screen{},

    state: State = .default,
    game: ?Game = null,
    is_finished: bool = false,

    graphics_mode: GraphicsMode = .text,
    gpu_auto_flush: bool = true,
    gpu_flush: bool = false,

    is_joystick_normalized: bool = false,
    joystick: JoystickState = JoystickState{
        .x = 0,
        .y = 0,
        .a = false,
        .b = false,
    },

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
        switch (self.state) {
            .default => {},
        }
        if (self.game) |*game| {
            game.deinit();
        }
        self.game = null;
        self.resetScreen();
    }

    pub fn update(self: *Self) !Event {
        defer self.gpu_flush = false;
        switch (self.state) {
            .default => {
                if (self.game) |*game| {
                    const result = game.vm.execute(10_000) catch |err| {
                        // TODO: Print stack trace here
                        std.debug.print("failed with {}\n", .{@errorName(err)});

                        try game.vm.printStackTrace(std.io.getStdOut().writer());

                        self.unloadGame();

                        return .render;
                    };
                    switch (result) {
                        .completed => {
                            self.unloadGame();
                            return .yield;
                        },
                        .exhausted => {
                            // we exhausted, which means there's no possibility we have a gpu_flush
                            std.debug.assert(!self.gpu_flush);
                            return if (self.gpu_auto_flush)
                                .render
                            else
                                .yield;
                        },
                        .paused => return if (self.gpu_auto_flush or self.gpu_flush)
                            .render
                        else
                            .yield,
                    }
                } else {
                    self.virtual_screen.clear(0xFF);
                    // what to do here?
                    return .render;
                }
            },
        }
        unreachable;
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
            self.joystick = joybuf;
        } else {
            self.joystick = joy;
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

    const api = struct {
        // System Control
        fn Poweroff(game: *Game) void {
            @panic("implement");
        }

        fn SaveGame(game: *Game) void {
            @panic("is asynchronous");
        }

        fn LoadGame(game: *Game) void {
            @panic("is asynchronous");
        }

        fn Pause(game: *Game) void {
            @panic("is asynchronous");
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
            const stderr = std.io.getStdErr().writer();
            for (args) |arg| {
                try stderr.print("{}", .{arg});
            }
            try stderr.writeAll("\n");

            return .void;
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
            var index: usize = 0;

            var dy: u31 = 0;
            while (true) : (dy += 1) {
                var dx: u31 = 0;
                while (dx < width) : (dx += 1) {
                    const pixel = pixel_buffer[index];
                    if (parsePixelValue(pixel)) |color| {
                        game.system.virtual_screen.set(
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

        fn GpuDrawLine(game: *Game, x0: i32, y0: i32, x1: i32, y1: i32, color: u8) void {
            game.system.canvas().drawLine(x0, y0, x1, y1, color);
        }

        fn GpuDrawRect(game: *Game, x: i32, y: i32, w: u32, h: u32, color: u8) void {
            game.system.canvas().drawRectangle(x, y, w, h, color);
        }

        fn GpuFillRect(game: *Game, x: i32, y: i32, w: u31, h: u31, color: u8) void {
            game.system.canvas().fillRectangle(x, y, w, h, color);
        }

        fn GpuDrawText(game: *Game, x: i32, y: i32, text: []const u8) void {
            @panic("todo");
        }

        fn GpuScroll(game: *Game, src_dx: i32, src_dy: i32) void {
            const srcbuf = game.system.virtual_screen.pixels;

            const dx: u32 = @intCast(u32, @mod(-src_dx, Screen.width));
            const dy: u32 = @intCast(u32, @mod(-src_dy, Screen.height));

            if (dx == 0 and dy == 0)
                return;

            const H = struct {
                fn wrapAdd(a: usize, b: u32, comptime limit: comptime_int) u32 {
                    return (@intCast(u32, a) + b) % limit;
                }
            };

            for (game.system.virtual_screen.pixels) |*row, y| {
                for (row) |*pixel, x| {
                    pixel.* = srcbuf[H.wrapAdd(y, dy, Screen.height)][H.wrapAdd(x, dx, Screen.width)];
                }
            }
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
            return game.system.joystick.a;
        }

        fn JoyGetB(game: *Game) bool {
            return game.system.joystick.b;
        }
    };
};
