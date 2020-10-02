const std = @import("std");
const assert = std.debug.assert;
const zig = std.zig;

pub fn build(b: *std.build.Builder) !void {
    try generateEntities();

    const mode = b.standardReleaseOptions();
    const lib = b.addStaticLibrary("htmlentities.zig", "src/main.zig");
    lib.setBuildMode(mode);
    lib.install();

    var main_tests = b.addTest("src/main.zig");
    main_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);
}

const embedded_json = @embedFile("entities.json");

fn generateEntities() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var json_parser = std.json.Parser.init(&arena.allocator, false);
    var tree = try json_parser.parse(embedded_json);

    var buffer = std.ArrayList(u8).init(&arena.allocator);
    var writer = buffer.writer();

    try writer.writeAll("pub const ENTITIES = [_]@import(\"main.zig\").Entity{\n");

    var entries = tree.root.Object.items();
    var maybe_prev: ?[]const u8 = null;
    for (entries) |entry, i| {
        if (maybe_prev) |prev| {
            // We rely on lexicographical sort for binary search.
            assert(std.mem.lessThan(u8, prev, entry.key));
        }
        maybe_prev = entry.key;
        try writer.writeAll(".{ .entity = ");
        try zig.renderStringLiteral(entry.key, writer);
        try writer.writeAll(", .codepoints = ");

        var codepoints_array = entry.value.Object.get("codepoints").?.Array;
        if (codepoints_array.items.len == 1) {
            try std.fmt.format(writer, ".{{ .Single = {} }}, ", .{codepoints_array.items[0].Integer});
        } else {
            try std.fmt.format(writer, ".{{ .Double = [2]u32{{ {}, {} }} }}, ", .{ codepoints_array.items[0].Integer, codepoints_array.items[1].Integer });
        }

        try writer.writeAll(".characters = ");
        try zig.renderStringLiteral(entry.value.Object.get("characters").?.String, writer);
        try writer.writeAll(" },\n");
    }

    try writer.writeAll("};\n");

    var zig_tree = try zig.parse(&arena.allocator, buffer.items);

    var out_file = try std.fs.cwd().createFile("src/entities.zig", .{});
    _ = try zig.render(&arena.allocator, out_file.writer(), zig_tree);
    out_file.close();
}
