const std = @import("std");
const builtin = @import("builtin");
const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    const exe = b.addExecutable("kernel", "src/main.zig");
    b.verbose = true;
    exe.setBuildMode(mode);
    exe.setLinkerScriptPath("src/linker.ld");
    exe.setTheTarget(std.build.Target{
        .Cross = std.build.CrossTarget{
            .arch = builtin.Arch.i386,
            .os = builtin.Os.freestanding,
            .abi = builtin.Abi.eabi,
        },
    });
    exe.install();
}
