const std = @import("std");

pub fn build(b: *std.build.Builder) !void {
    const mode = b.standardReleaseOptions();
    const lib = b.addStaticLibrary("libpcre.zig", "src/main.zig");
    lib.setBuildMode(mode);
    try linkPcre(lib);
    lib.install();

    var main_tests = b.addTest("src/main.zig");
    try linkPcre(main_tests);
    main_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);
}

pub fn linkPcre(exe: *std.build.LibExeObjStep) !void {
    exe.linkLibC();
    if (std.builtin.os.tag == .windows) {
        try exe.addVcpkgPaths(.Static);
        exe.linkSystemLibrary("pcre");
    } else {
        exe.linkSystemLibrary("libpcre");
    }
}
