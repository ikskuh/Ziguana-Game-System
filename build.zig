const std = @import("std");

const is_windows_host = (std.builtin.os.tag == .windows);

const pkgs = struct {
    const painterz = std.build.Pkg{
        .name = "painterz",
        .path = "extern/painterz/painterz.zig",
    };

    const interface = std.build.Pkg{
        .name = "interface",
        .path = "extern/interface/interface.zig",
    };

    const args = std.build.Pkg{
        .name = "args",
        .path = "extern/args/args.zig",
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
    pc_exe.addPackage(pkgs.args);

    pc_exe.install();

    const run_step = pc_exe.run();
    run_step.addArg("--directory");
    run_step.addArg("examples/bouncy");

    b.step("run", "Starts the game system").dependOn(&run_step.step);

    const resources_step = b.step("resources", "Regenerates the resource files");

    {
        const compile_mkbitmap = b.addSystemCommand(&[_][]const u8{
            if (is_windows_host) "C:\\Windows\\Microsoft.NET\\Framework\\v.4.0.30319\\csc" else "mcs",
            "src/tools/mkbitmap.cs",
            "/r:System.Drawing.dll",
            "/out:zig-cache/bin/mkbitmap.exe",
        });

        const build_font = b.addSystemCommand(if (is_windows_host)
            &[_][]const u8{
                "zig-cache\\bin\\mkbitmap.exe",
                "res/dos_8x8_font_white.png",
                "src/core/res/font.dat",
            }
        else
            &[_][]const u8{
                "mono",
                "zig-cache\\bin\\mkbitmap.exe",
                "res/dos_8x8_font_white.png",
                "src/core/res/font.dat",
            });
        build_font.step.dependOn(&compile_mkbitmap.step);

        resources_step.dependOn(&build_font.step);
    }
}
