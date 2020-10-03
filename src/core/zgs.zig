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
};

/// Initialize a new game system.
/// Note that the system keeps the pointer to `game`  until the system is closed. Don't free game
/// before the system is deinitialized.
/// The system is allocated by allocator to ensure the returned value is a pinned pointer as
/// System stores internal references.
pub fn init(allocator: *std.mem.Allocator, game: *const Game) !*System {
    var system = try allocator.create(System);
    errdefer allocator.destroy(system);

    system.* = System{
        .allocator = allocator,
        .game = game,
        .pool = undefined,
        .environment = undefined,
        .vm = undefined,
    };

    system.pool = ObjectPool.init(allocator);
    errdefer system.pool.deinit();

    system.environment = try lola.runtime.Environment.init(allocator, &game.code, system.pool.interface());
    errdefer system.environment.deinit();

    try lola.libs.std.install(&system.environment, allocator);

    system.vm = try lola.runtime.VM.init(allocator, &system.environment);
    errdefer system.vm.deinit();

    return system;
}

pub const System = struct {
    const Self = @This();

    allocator: *std.mem.Allocator,

    game: *const Game,

    virtual_screen: Screen = Screen{},

    pool: ObjectPool,
    environment: lola.runtime.Environment,
    vm: lola.runtime.VM,

    is_finished: bool = false,

    pub fn update(self: *Self) !void {
        const result = try self.vm.execute(10_000);
        switch (result) {
            .completed => self.is_finished = true,
            else => {},
        }
    }

    pub fn deinit(self: *Self) void {
        self.vm.deinit();
        self.environment.deinit();
        self.pool.deinit();
        self.allocator.destroy(self);
    }
};

pub const Game = struct {
    name: []const u8,
    icon: [24][24]u8,
    code: lola.CompileUnit,
    data: std.StringHashMap([]const u8),
};
