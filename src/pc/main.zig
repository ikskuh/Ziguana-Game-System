const std = @import("std");
const zgs = @import("zgs");
const lola = @import("lola");
const sdl = @import("sdl2");

var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = &gpa_state.allocator;

pub fn main() !void {
    defer _ = gpa_state.deinit();

    try sdl.init(.{
        .video = true,
        .audio = true,
        .events = true,
    });
    defer sdl.quit();

    const scale = 6;

    var window = try sdl.createWindow(
        "Ziguana Game System",
        .centered,
        .centered,
        scale * zgs.Screen.total_width,
        scale * zgs.Screen.total_height,
        .{},
    );
    defer window.destroy();

    var renderer = try sdl.createRenderer(
        window,
        null,
        .{
            .accelerated = true,
            .present_vsync = true,
        },
    );
    defer renderer.destroy();

    var screen_buffer = try sdl.createTexture(
        renderer,
        .abgr8888,
        .streaming,
        zgs.Screen.total_width,
        zgs.Screen.total_height,
    );
    defer screen_buffer.destroy();

    var game = zgs.Game{
        .name = "Example",
        .icon = undefined,
        .code = undefined,
        .data = undefined,
    };

    game.code = blk: {
        var file = try std.fs.cwd().openFile("examples/bouncy/game.lola.lm", .{});
        defer file.close();

        break :blk try lola.CompileUnit.loadFromStream(gpa, file.reader());
    };
    defer game.code.deinit();

    game.data = std.StringHashMap([]const u8).init(gpa);
    defer game.data.deinit();

    var game_system = try zgs.init(gpa, &game);
    defer game_system.deinit();

    var system_timer = try std.time.Timer.start();

    main_loop: while (true) {
        while (sdl.pollEvent()) |event| {
            switch (event) {
                .quit => break :main_loop,
                else => {},
            }
        }

        try game_system.update();

        const screen_content = game_system.virtual_screen.render();

        try screen_buffer.update(std.mem.sliceAsBytes(&screen_content), @sizeOf(zgs.Screen.RGBA) * screen_content[0].len, null);

        try renderer.copy(screen_buffer, null, null);

        renderer.present();
    }
}
