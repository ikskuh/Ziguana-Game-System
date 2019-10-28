const std = @import("std");
const serial = @import("serial-port.zig");

pub const Color = enum(u4) {
    black = 0,
    blue = 1,
    green = 2,
    cyan = 3,
    red = 4,
    nagenta = 5,
    brown = 6,
    lightGray = 7,
    gray = 8,
    lightBlue = 9,
    lightGreen = 10,
    lightCyan = 11,
    lightRed = 12,
    lightMagenta = 13,
    yellow = 14,
    white = 15,
};

pub const Char = packed struct {
    char: u8,
    foreground: Color,
    background: Color,
};

pub const WIDTH = 80;
pub const HEIGHT = 25;

var videoBuffer = @intToPtr(*volatile [HEIGHT][WIDTH]Char, 0xB8000);

var currentForeground: Color = .lightGray;
var currentBackground: Color = .black;

var cursorX: u16 = 0;
var cursorY: u16 = 0;

pub var enable_serial = true;
pub var enable_video = true;

pub fn clear() void {
    cursorX = 0;
    cursorY = 0;
    for (videoBuffer) |*line| {
        for (line) |*char| {
            char.* = Char{
                .char = ' ',
                .foreground = currentForeground,
                .background = currentBackground,
            };
        }
    }
}
pub fn resetColors() void {
    currentForeground = .lightGray;
    currentBackground = .black;
}

pub fn setForegroundColor(color: Color) void {
    currentForeground = color;
}

pub fn setBackgroundColor(color: Color) void {
    currentBackground = color;
}

pub fn setColor(foreground: Color, background: Color) void {
    currentBackground = background;
    currentForeground = foreground;
}

pub fn scroll(lineCount: usize) void {
    var i: usize = 0;
    while (i < lineCount) : (i += 1) {
        var y: usize = 0;
        while (y < HEIGHT - 1) : (y += 1) {
            videoBuffer.*[y] = videoBuffer.*[y + 1];
        }
        videoBuffer.*[HEIGHT - 1] = [1]Char{Char{
            .background = .black,
            .foreground = .black,
            .char = ' ',
        }} ** WIDTH;
    }
    cursorY -= 1;
}

fn newline() void {
    cursorY += 1;
    if (cursorY >= HEIGHT) {
        scroll(1);
    }
}

fn put_raw(c: u8) void {
    if (!enable_video) return;
    videoBuffer[cursorY][cursorX] = Char{
        .char = c,
        .foreground = currentForeground,
        .background = currentBackground,
    };
    cursorX += 1;
    if (cursorX >= WIDTH) {
        cursorX = 0;
        newline();
    }
}

pub fn put(c: u8) void {
    if (enable_serial)
        serial.put(c);
    switch (c) {
        '\r' => cursorX = 0,
        '\n' => newline(),
        '\t' => {
            cursorX = (cursorX & ~u16(3)) + u16(4);
            if (cursorX >= WIDTH)
                newline();
        },
        else => put_raw(c),
    }
}

fn write_raw(raw: []const u8) void {
    for (raw) |c| {
        put_raw(c);
    }
}

pub fn write(text: []const u8) void {
    for (text) |c| {
        put(c);
    }
}

fn putFormat(x: void, data: []const u8) error{NeverHappens}!void {
    write(data);
}

pub fn print(comptime fmt: []const u8, params: ...) void {
    std.fmt.format(void{}, error{NeverHappens}, putFormat, fmt, params) catch |err| switch (err) {
        error.NeverHappens => unreachable,
    };
}

pub fn println(comptime fmt: []const u8, params: ...) void {
    print(fmt, params);
    write("\r\n");
}
