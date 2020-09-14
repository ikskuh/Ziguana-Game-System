const std = @import("std");
const builtin = @import("builtin");
const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    const kernel = b.addExecutable("kernel", "kernel/src/main.zig");
    kernel.setBuildMode(mode);
    kernel.setLinkerScriptPath("kernel/src/linker.ld");
    kernel.setTarget(std.zig.CrossTarget{
        .cpu_arch = .i386,
        .cpu_model = .{
            .explicit = &std.Target.x86.cpu._i386,
        },

        // workaround for LLVM bugs :(
        // without cmov, the code won't compile
        .cpu_features_add = blk: {
            var features = std.Target.Cpu.Feature.Set.empty;
            features.addFeature(@enumToInt(std.Target.x86.Feature.cmov));
            break :blk features;
        },

        .os_tag = .freestanding,
        .abi = .eabi,
    });
    kernel.install();

    const verbose_debug = b.option(bool, "verbose-qemu", "Enable verbose debug output for QEMU") orelse false;
    const qemu_debug_mode: []const u8 = if (verbose_debug)
        "guest_errors,int,cpu_reset"
    else
        "guest_errors,cpu_reset";

    const run_qemu = b.addSystemCommand(&[_][]const u8{
        "qemu-system-i386",
        "-no-shutdown", // don't shutdown the VM on halt
        "-no-reboot", // don't reset the machine on errors
        "-serial",
        "stdio", // using the stdout as our serial console
        "-device",
        "sb16", // add soundblaster 16
        "-device",
        "ac97", // add ac97
        "-device",
        "intel-hda",
        "-device",
        "hda-duplex", // add intel HD audio
        "-m",
        "64M", // 64 MB RAM
        "-d",
        qemu_debug_mode, // debug output will yield all interrupts and resets
        // "-drive",
        // "format=raw,if=ide,file=kernel/boot.img",
        // "-drive",
        // "format=raw,if=floppy,file=kernel/cartridge.img", // attach floppy cartridge
    });

    { // don't use the system image, boot the kernel directly
        run_qemu.addArg("-kernel");
        run_qemu.addArtifactArg(kernel);
    }

    const run_step = b.step("run", "Runs qemu with emulation");
    run_step.dependOn(&run_qemu.step);
}
