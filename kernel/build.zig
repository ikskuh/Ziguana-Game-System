const std = @import("std");
const builtin = @import("builtin");
const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    const kernel = b.addExecutable("kernel", "src/main.zig");
    kernel.setBuildMode(mode);
    kernel.setLinkerScriptPath("src/linker.ld");
    kernel.setTheTarget(std.build.Target{
        .Cross = std.build.CrossTarget{
            .arch = builtin.Arch.i386,
            .os = builtin.Os.freestanding,
            .abi = builtin.Abi.eabi,
        },
    });
    kernel.install();

    const exe = b.addExecutable("assembler", "src/standalone-assembler.zig");
    exe.setBuildMode(mode);
    exe.install();
}
