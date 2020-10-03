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

    var game = zgs.GameROM{
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

    try game.data.put(
        "ball.ico",
        "" ++
            "...ff..." ++
            "..fddf.." ++
            ".fd99df." ++
            "fd9999df" ++
            "fd9999df" ++
            ".fd99df." ++
            "..fddf.." ++
            "...ff...",
    );

    var game_system = try zgs.init(gpa);
    defer game_system.deinit();

    try game_system.loadGame(&game);

    var system_timer = try std.time.Timer.start();

    main_loop: while (true) {
        while (sdl.pollEvent()) |event| {
            switch (event) {
                .quit => break :main_loop,
                .key_down => |key| {
                    switch (key.keysym.scancode) {
                        else => {},
                    }
                },
                .key_up => |key| {
                    switch (key.keysym.scancode) {
                        else => {},
                    }
                },
                else => {},
            }
        }

        var keyboard = sdl.getKeyboardState();
        {
            var joystick_state = zgs.JoystickState{
                .x = 0,
                .y = 0,
                .a = false,
                .b = false,
            };
            if (keyboard.isPressed(.SDL_SCANCODE_LEFT))
                joystick_state.x -= 1;
            if (keyboard.isPressed(.SDL_SCANCODE_RIGHT))
                joystick_state.x += 1;
            if (keyboard.isPressed(.SDL_SCANCODE_UP))
                joystick_state.y -= 1;
            if (keyboard.isPressed(.SDL_SCANCODE_DOWN))
                joystick_state.y += 1;
            joystick_state.a = keyboard.isPressed(.SDL_SCANCODE_SPACE);
            joystick_state.b = keyboard.isPressed(.SDL_SCANCODE_ESCAPE);

            game_system.setJoystick(joystick_state);
        }

        switch (try game_system.update()) {
            .yield => {},
            .quit => break :main_loop,
            .render => {
                const screen_content = game_system.virtual_screen.render();

                try screen_buffer.update(std.mem.sliceAsBytes(&screen_content), @sizeOf(zgs.Screen.RGBA) * screen_content[0].len, null);

                try renderer.copy(screen_buffer, null, null);

                renderer.present();
            },
        }
    }
}
