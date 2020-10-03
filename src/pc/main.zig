const std = @import("std");
const zgs = @import("zgs");
const lola = @import("lola");
const sdl = @import("sdl2");
const args_parser = @import("args");

var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = &gpa_state.allocator;

const CliArgs = struct {
    directory: ?[]const u8 = null,
    game: ?[]const u8 = null,
};

pub fn main() !u8 {
    defer _ = gpa_state.deinit();

    var cli_args = try args_parser.parseForCurrentProcess(CliArgs, gpa);
    defer cli_args.deinit();

    if (cli_args.options.directory != null and cli_args.options.game != null) {
        @panic("print usage message and error");
        // return 1;
    }

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

    var game_system = try zgs.init(gpa);
    defer game_system.deinit();

    var game: ?zgs.GameROM = null;

    if (cli_args.options.directory) |directory_path| {
        var dir = try std.fs.cwd().openDir(directory_path, .{});
        defer dir.close();

        game = try createROMFromDirectory(dir);
    }

    defer if (game) |*g| deinitROM(g);
    if (game) |*g|
        try game_system.loadGame(g);

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

    return 0;
}

fn createROMFromDirectory(dir: std.fs.Dir) !zgs.GameROM {
    var game = zgs.GameROM{
        .name = undefined,
        .icon = undefined,
        .code = undefined,
        .data = undefined,
    };

    game.name = blk: {
        var file = try dir.openFile("game.name", .{});
        defer file.close();

        break :blk try file.readToEndAlloc(gpa, 64);
    };
    errdefer gpa.free(game.name);

    blk: {
        var file = dir.openFile("game.ico", .{}) catch |err| switch (err) {
            // when file not there, just leave the default icon
            error.FileNotFound => break :blk,
            else => |e| return e,
        };
        defer file.close();

        try file.reader().readNoEof(std.mem.asBytes(&game.icon));
    }

    game.code = if (dir.openFile("game.lola", .{})) |file| blk: {
        defer file.close();

        const source = try file.readToEndAlloc(gpa, 1 << 10); // 1 MB of source is a lot
        defer gpa.free(source);

        var diagnostics = lola.compiler.Diagnostics.init(gpa);
        defer diagnostics.deinit();

        var module_or_null = try lola.compiler.compile(
            gpa,
            &diagnostics,
            "game.lola",
            source,
        );

        for (diagnostics.messages.items) |msg| {
            std.debug.print("{}\n", .{msg});
        }

        break :blk module_or_null orelse return error.InvalidSource;
    } else |err| blk: {
        if (err != error.FileNotFound)
            return err;

        var file = try dir.openFile("game.lola.lm", .{});
        defer file.close();

        break :blk try lola.CompileUnit.loadFromStream(gpa, file.reader());
    };

    errdefer game.code.deinit();

    game.data = std.StringHashMap([]const u8).init(gpa);
    errdefer game.data.deinit();

    var data_directory = dir.openDir("data", .{
        .iterate = true,
        .no_follow = true,
    }) catch |err| switch (err) {
        // No data directory, we are done
        error.FileNotFound => return game,
        else => |e| return e,
    };
    defer data_directory.close();

    // TODO: Iterate recursively through all subfolders
    var iterator = data_directory.iterate();
    while (try iterator.next()) |entry| {
        switch (entry.kind) {
            .File => {
                var file = try data_directory.openFile(entry.name, .{});
                defer file.close();

                const name = try gpa.dupe(u8, entry.name);
                errdefer gpa.free(name);

                const contents = try file.readToEndAlloc(gpa, 16 << 20); // 16 MB
                errdefer gpa.free(contents);

                try game.data.put(name, contents);
            },
            .Directory => @panic("TODO: Directory recursion not implemented yet!"),
            else => {},
        }
    }

    return game;
}

fn deinitROM(rom: *zgs.GameROM) void {
    var iter = rom.data.iterator();
    while (iter.next()) |kv| {
        gpa.free(kv.key);
        gpa.free(kv.value);
    }
    gpa.free(rom.name);
    rom.code.deinit();
    rom.data.deinit();
    rom.* = undefined;
}
