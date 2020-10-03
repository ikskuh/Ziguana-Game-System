const std = @import("std");

const pkgs = struct {
    const painterz = std.build.Pkg{
        .name = "painterz",
        .path = "extern/painterz/painterz.zig",
    };

    const interface = std.build.Pkg{
        .name = "interface",
        .path = "extern/interface/interface.zig",
    };

    const lola = std.build.Pkg{
        .name = "lola",
        .path = "extern/lola/src/library/main.zig",
        .dependencies = &[_]std.build.Pkg{
            interface,
        },
    };

    const sdl2 = std.build.Pkg{
        .name = "sdl2",
        .path = "extern/sdl2/src/lib.zig",
    };

    const zgs = std.build.Pkg{
        .name = "zgs",
        .path = "src/core/zgs.zig",
        .dependencies = &[_]std.build.Pkg{
            lola, painterz,
        },
    };
};

pub fn build(b: *std.build.Builder) void {
    const pc_exe = b.addExecutable("zgs.pc", "src/pc/main.zig");

    pc_exe.linkLibC();
    pc_exe.linkSystemLibrary("sdl2");
    pc_exe.addPackage(pkgs.sdl2);
    pc_exe.addPackage(pkgs.zgs);
    pc_exe.addPackage(pkgs.lola);

    pc_exe.install();

    const run_step = pc_exe.run();

    run_step.addArg("examples/bouncy");

    b.step("run", "Starts the game system").dependOn(&run_step.step);
}
