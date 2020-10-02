# htmlentities.zig

![Build status](https://github.com/kivikakk/htmlentities.zig/workflows/Zig/badge.svg)

The bundled [`entities.json`](/entities.json) is sourced from <https://www.w3.org/TR/html5/entities.json>.

Modelled on [Philip Jackson's `entities` crate](https://github.com/p-jackson/entities) for Rust.

## Overview

The core datatypes are:

```zig
pub const Entity = struct {
    entity: []u8,
    codepoints: Codepoints,
    characters: []u8,
};

pub const Codepoints = union(enum) {
    Single: u32,
    Double: [2]u32,
};
```

The list of entities is directly exposed, as well as a binary search function:

```zig
pub const ENTITIES: [_]Entity
pub fn lookup(entity: []const u8) ?Entity
```

## Usage

build.zig:

```zig
    exe.addPackagePath("htmlentities", "vendor/htmlentities.zig/src/main.zig");
```

main.zig:

```zig
const std = @import("std");
const htmlentities = @import("htmlentities");

pub fn main() !void {
    var eacute = htmlentities.lookup("&eacute;").?;
    std.debug.print("eacute: {}\n", .{eacute});
}
```

Output:

```
eacute: Entity{ .entity = &eacute;, .codepoints = Codepoints{ .Single = 233 }, .characters = é }
```

## Help wanted

Ideally we'd do the JSON parsing and struct creation at comptime.  The std JSON
tokeniser uses ~80GB of RAM and millions of backtracks to handle the whole
`entities.json` at comptime, so it's not gonna happen yet.  Maybe once we get a
comptime allocator we can use the regular parser.

As it is, we do codegen.  Ideally we'd piece together an AST and render that
instead of just writing Zig directly -- I did try it with a 'template' input
string (see some broken wip at
[`63b9393`](https://github.com/kivikakk/htmlentities.zig/commit/63b9393)), but
it's hard to do since `std.zig.render` expects all tokens, including string
literal, to be available in the originally parsed source.  At the moment we
parse our generated source and format it so we can at least validate it
syntactically in the build step.
