const std = @import("std");
const lola = @import("lola");

pub const ObjectPool = lola.runtime.ObjectPool(.{});

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
        RGBA{ .r = 0x14, .g = 0x0c, .b = 0x1c },
        RGBA{ .r = 0x44, .g = 0x24, .b = 0x34 },
        RGBA{ .r = 0x30, .g = 0x34, .b = 0x6d },
        RGBA{ .r = 0x4e, .g = 0x4a, .b = 0x4e },
        RGBA{ .r = 0x85, .g = 0x4c, .b = 0x30 },
        RGBA{ .r = 0x34, .g = 0x65, .b = 0x24 },
        RGBA{ .r = 0xd0, .g = 0x46, .b = 0x48 },
        RGBA{ .r = 0x75, .g = 0x71, .b = 0x61 },
        RGBA{ .r = 0x59, .g = 0x7d, .b = 0xce },
        RGBA{ .r = 0xd2, .g = 0x7d, .b = 0x2c },
        RGBA{ .r = 0x85, .g = 0x95, .b = 0xa1 },
        RGBA{ .r = 0x6d, .g = 0xaa, .b = 0x2c },
        RGBA{ .r = 0xd2, .g = 0xaa, .b = 0x99 },
        RGBA{ .r = 0x6d, .g = 0xc2, .b = 0xca },
        RGBA{ .r = 0xda, .g = 0xd4, .b = 0x5e },
        RGBA{ .r = 0xde, .g = 0xee, .b = 0xd6 },
    },

    fn translateColor(self: *Self, color: u8) RGBA {
        const index = std.math.cast(u4, color) catch self.pixel_rng.random.int(u4);
        return self.palette[index];
    }

    pub fn set(self: *Self, x: i32, y: i32, color: u8) void {
        const px = std.math.cast(usize, x) catch return;
        const py = std.math.cast(usize, y) catch return;
        if (px >= width) return;
        if (py >= height) return;
        self.pixels[py][px] = color;
    }

    pub fn get(self: Self, x: i32, y: i32) u8 {
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

    const State = union(enum) {
        // Either running the game (if any) or show a broken screen
        default,
    };

    allocator: *std.mem.Allocator,

    virtual_screen: Screen = Screen{},

    state: State = .default,
    game: ?Game = null,
    is_finished: bool = false,

    /// Loads the given game, unloading any currently loaded game.
    /// Note that the system keeps the pointer to `game`  until the system is closed. Don't free game
    /// before the system is deinitialized.
    pub fn loadGame(self: *Self, rom: *const GameROM) !void {
        self.unloadGame();

        self.game = @as(Game, undefined); // makes self.game non-null
        try Game.init(&self.game.?, self, rom);
        errdefer game = null;
    }

    pub fn unloadGame(self: *Self) void {
        switch (self.state) {
            .default => {},
        }
        if (self.game) |*game| {
            game.deinit();
        }
        self.game = null;
    }

    pub fn update(self: *Self) !void {
        switch (self.state) {
            .default => {
                if (self.game) |*game| blk: {
                    const result = game.vm.execute(10_000) catch |err| {
                        // TODO: Print stack trace here
                        std.debug.print("failed with {}\n", .{@errorName(err)});

                        self.unloadGame();

                        break :blk;
                    };
                    switch (result) {
                        .completed => self.unloadGame(),
                        else => {},
                    }
                } else {
                    self.virtual_screen.clear(0xFF);
                    // what to do here?
                }
            },
        }
    }

    pub fn deinit(self: *Self) void {
        self.unloadGame();
        self.allocator.destroy(self);
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
    rom: *const GameROM,

    pool: ObjectPool,
    environment: lola.runtime.Environment,
    vm: lola.runtime.VM,

    fn init(game: *Self, system: *System, rom: *const GameROM) !void {
        game.* = Self{
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

        game.vm = try lola.runtime.VM.init(system.allocator, &game.environment);
        errdefer game.vm.deinit();
    }

    pub fn deinit(self: *Self) void {
        self.vm.deinit();
        self.environment.deinit();
        self.pool.deinit();
        self.* = undefined;
    }
};
