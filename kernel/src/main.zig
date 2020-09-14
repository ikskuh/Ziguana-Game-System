const std = @import("std");
const builtin = @import("builtin");

const Terminal = @import("text-terminal.zig");
const Multiboot = @import("multiboot.zig");
const VGA = @import("vga.zig");
const GDT = @import("gdt.zig");
const Interrupts = @import("interrupts.zig");
const Keyboard = @import("keyboard.zig");
const SerialPort = @import("serial-port.zig");
const CodeEditor = @import("code-editor.zig");
const Timer = @import("timer.zig");
const SplashScreen = @import("splashscreen.zig");
const Assembler = @import("assembler.zig");

const EnumArray = @import("enum-array.zig").EnumArray;

const PCI = @import("pci.zig");
const CMOS = @import("cmos.zig");
const FDC = @import("floppy-disk-controller.zig");

const Heap = @import("heap.zig");

const PMM = @import("pmm.zig");
const VMM = @import("vmm.zig");

const ATA = @import("ata.zig");

const ZGSFS = @import("zgs-fs.zig");

usingnamespace @import("block-device.zig");

export var multibootHeader align(4) linksection(".multiboot") = Multiboot.Header.init();

var usercodeValid: bool = false;

var registers: [16]u32 = [_]u32{0} ** 16;

pub fn getRegisterAddress(register: u4) u32 {
    return @ptrToInt(&registers[register]);
}

var enable_live_tracing = false;

pub const assembler_api = struct {
    pub fn flushpix() callconv(.C) void {
        switch (vgaApi) {
            .buffered => VGA.swapBuffers(),
            else => {},
        }
    }

    pub fn trace(value: u32) callconv(.C) void {
        switch (value) {
            0, 1 => {
                enable_live_tracing = (value != 0);
            },
            2 => vgaApi = .immediate,
            3 => vgaApi = .buffered,
            else => {
                Terminal.println("trace({})", .{value});
            },
        }
    }

    pub fn setpix(x: u32, y: u32, col: u32) callconv(.C) void {
        // Terminal.println("setpix({},{},{})", x, y, col);
        if (vgaApi == .immediate) {
            VGA.setPixelDirect(x, y, @truncate(u4, col));
        }
        VGA.setPixel(x, y, @truncate(u4, col));
    }

    pub fn getpix(x: u32, y: u32) callconv(.C) u32 {
        // Terminal.println("getpix({},{})", x, y);
        return VGA.getPixel(x, y);
    }

    pub fn gettime() callconv(.C) u32 {
        // systemTicks is in 0.1 sec steps, but we want ms
        const time = Timer.ticks;
        // Terminal.println("gettime() = {}", time);
        return time;
    }

    pub fn getkey() callconv(.C) u32 {
        const keycode = if (Keyboard.getKey()) |key|
            key.scancode | switch (key.set) {
                .default => @as(u32, 0),
                .extended0 => @as(u32, 0x10000),
                .extended1 => @as(u32, 0x20000),
            }
        else
            @as(u32, 0);

        // Terminal.println("getkey() = 0x{X:0>5}", keycode);
        return keycode;
    }

    pub fn exit() callconv(.C) noreturn {
        Terminal.println("User code finished!", .{});
        haltForever();
    }
};

const VgaApi = enum {
    buffered,
    immediate,
};
var vgaApi: VgaApi = .immediate;

pub const enable_assembler_tracing = false;

pub var currentAssemblerLine: ?usize = null;

pub fn debugCall(cpu: *Interrupts.CpuState) void {
    if (!enable_live_tracing)
        return;

    currentAssemblerLine = @intToPtr(*u32, cpu.eip).*;

    // Terminal.println("-----------------------------");
    // Terminal.println("Line: {}", currentAssemblerLine);
    // Terminal.println("CPU:\r\n{}", cpu);
    // Terminal.println("Registers:");
    // for (registers) |reg, i| {
    //     Terminal.println("r{} = {}", i, reg);
    // }

    // skip 4 bytes after interrupt. this is the assembler line number!
    cpu.eip += 4;
}

// const developSource = @embedFile("../../gasm/concept.asm");

const Task = struct {
    entryPoint: fn () callconv(.C) noreturn = undefined,
};

pub const TaskId = enum {
    splash,
    shell,
    codeEditor,
    spriteEditor,
    tilemapEditor,
    codeRunner,
};

fn editorNotImplementedYet() callconv(.C) noreturn {
    Terminal.println("This editor is not implemented yet!", .{});
    while (true) {
        // wait for interrupt
        asm volatile ("hlt");
    }
}

fn executeUsercode() callconv(.C) noreturn {
    Terminal.println("Start assembling code...", .{});

    var arena = std.heap.ArenaAllocator.init(Heap.allocator);

    var buffer = std.ArrayList(u8).init(&arena.allocator);

    CodeEditor.saveTo(buffer.writer()) catch |err| {
        arena.deinit();
        Terminal.println("Failed to save user code: {}", .{err});
        while (true) {
            // wait for interrupt
            asm volatile ("hlt");
        }
    };

    if (Assembler.assemble(&arena.allocator, buffer.items, VMM.getUserSpace(), null)) {
        arena.deinit();

        Terminal.println("Assembled code successfully!", .{});
        // Terminal.println("Memory required: {} bytes!", fba.end_index);

        Terminal.println("Setup graphics...", .{});

        // Load dawnbringers 16 color palette
        // see: https://lospec.com/palette-list/dawnbringer-16
        VGA.loadPalette(&comptime [_]VGA.RGB{
            VGA.RGB.parse("#140c1c") catch unreachable, //  0 = black
            VGA.RGB.parse("#442434") catch unreachable, //  1 = dark purple-brown
            VGA.RGB.parse("#30346d") catch unreachable, //  2 = blue
            VGA.RGB.parse("#4e4a4e") catch unreachable, //  3 = gray
            VGA.RGB.parse("#854c30") catch unreachable, //  4 = brown
            VGA.RGB.parse("#346524") catch unreachable, //  5 = green
            VGA.RGB.parse("#d04648") catch unreachable, //  6 = salmon
            VGA.RGB.parse("#757161") catch unreachable, //  7 = khaki
            VGA.RGB.parse("#597dce") catch unreachable, //  8 = baby blue
            VGA.RGB.parse("#d27d2c") catch unreachable, //  9 = orange
            VGA.RGB.parse("#8595a1") catch unreachable, // 10 = light gray
            VGA.RGB.parse("#6daa2c") catch unreachable, // 11 = grass green
            VGA.RGB.parse("#d2aa99") catch unreachable, // 12 = skin
            VGA.RGB.parse("#6dc2ca") catch unreachable, // 13 = bright blue
            VGA.RGB.parse("#dad45e") catch unreachable, // 14 = yellow
            VGA.RGB.parse("#deeed6") catch unreachable, // 15 = white
        });

        Terminal.println("Start user code...", .{});

        asm volatile ("jmp 0x40000000");
        unreachable;
    } else |err| {
        arena.deinit();
        buffer.deinit();
        Terminal.println("Failed to assemble user code: {}", .{err});
        while (true) {
            // wait for interrupt
            asm volatile ("hlt");
        }
    }
}

fn executeTilemapEditor() callconv(.C) noreturn {
    var time: usize = 0;
    var color: VGA.Color = 1;
    while (true) : (time += 1) {
        if (Keyboard.getKey()) |key| {
            if (key.set == .default and key.scancode == 57) {
                // space
                if (@addWithOverflow(VGA.Color, color, 1, &color)) {
                    color = 1;
                }
            }
        }

        var y: usize = 0;
        while (y < VGA.height) : (y += 1) {
            var x: usize = 0;
            while (x < VGA.width) : (x += 1) {
                // c = @truncate(u4, (x + offset_x + dx) / 32 + (y + offset_y + dy) / 32);
                const c = if (y > ((Timer.ticks / 10) % 200)) color else 0;
                VGA.setPixel(x, y, c);
            }
        }

        VGA.swapBuffers();
    }
}

const TaskList = EnumArray(TaskId, Task);
const taskList = TaskList.initMap(&([_]TaskList.KV{
    TaskList.KV{
        .key = .splash,
        .value = Task{
            .entryPoint = SplashScreen.run,
        },
    },
    TaskList.KV{
        .key = .shell,
        .value = Task{
            .entryPoint = editorNotImplementedYet,
        },
    },
    TaskList.KV{
        .key = .codeEditor,
        .value = Task{
            .entryPoint = CodeEditor.run,
        },
    },
    TaskList.KV{
        .key = .spriteEditor,
        .value = Task{
            .entryPoint = editorNotImplementedYet,
        },
    },
    TaskList.KV{
        .key = .tilemapEditor,
        .value = Task{
            .entryPoint = executeTilemapEditor,
        },
    },
    TaskList.KV{
        .key = .codeRunner,
        .value = Task{
            .entryPoint = executeUsercode,
        },
    },
}));

var userStack: [8192]u8 align(16) = undefined;

pub fn handleFKey(cpu: *Interrupts.CpuState, key: Keyboard.FKey) *Interrupts.CpuState {
    return switch (key) {
        .F1 => switchTask(.shell),
        .F2 => switchTask(.codeEditor),
        .F3 => switchTask(.spriteEditor),
        .F4 => switchTask(.tilemapEditor),
        .F5 => switchTask(.codeRunner),
        .F12 => blk: {
            if (Terminal.enable_serial) {
                Terminal.println("Disable serial... Press F12 to enable serial again!", .{});
                Terminal.enable_serial = false;
            } else {
                Terminal.enable_serial = true;
                Terminal.println("Serial output enabled!", .{});
            }
            break :blk cpu;
        },
        else => cpu,
    };
}

pub fn switchTask(task: TaskId) *Interrupts.CpuState {
    const Helper = struct {
        fn createTask(stack: []u8, id: TaskId) *Interrupts.CpuState {
            var newCpu = @ptrCast(*Interrupts.CpuState, stack.ptr + stack.len - @sizeOf(Interrupts.CpuState));
            newCpu.* = Interrupts.CpuState{
                .eax = 0,
                .ebx = 0,
                .ecx = 0,
                .edx = 0,
                .esi = 0,
                .edi = 0,
                .ebp = 0,

                .eip = @ptrToInt(taskList.at(id).entryPoint),
                .cs = 0x08,
                .eflags = 0x202,

                .interrupt = 0,
                .errorcode = 0,
                .esp = 0,
                .ss = 0,
            };
            return newCpu;
        }
    };

    var stack = userStack[0..];
    return Helper.createTask(stack, task);
}

extern const __start: u8;
extern const __end: u8;

pub fn main() anyerror!void {
    // HACK: this fixes some weird behaviour with "code running into userStack"
    _ = userStack;

    SerialPort.init(SerialPort.COM1, 9600, .none, .eight);

    Terminal.clear();

    Terminal.println("Kernel Range: {X:0>8} - {X:0>8}", .{ @ptrToInt(&__start), @ptrToInt(&__end) });
    Terminal.println("Stack Size:   {}", .{@as(u32, @sizeOf(@TypeOf(kernelStack)))});
    // Terminal.println("User Stack:   {X:0>8}", @ptrToInt(&userStack));
    Terminal.println("Kernel Stack: {X:0>8}", .{@ptrToInt(&kernelStack)});

    const flags = @ptrCast(*Multiboot.Structure.Flags, &multiboot.flags).*;
    //const flags = @bitCast(Multiboot.Structure.Flags, multiboot.flags);

    Terminal.print("Multiboot Structure: {*}\r\n", .{multiboot});
    inline for (@typeInfo(Multiboot.Structure).Struct.fields) |fld| {
        if (comptime !std.mem.eql(u8, comptime fld.name, "flags")) {
            if (@field(flags, fld.name)) {
                Terminal.print("\t{}\t= {}\r\n", .{ fld.name, @field(multiboot, fld.name) });
            }
        }
    }

    // Init PMM

    // mark everything in the "memmap" as free
    if (multiboot.flags != 0) {
        var iter = multiboot.mmap.iterator();
        while (iter.next()) |entry| {
            if (entry.baseAddress + entry.length > 0xFFFFFFFF)
                continue; // out of range

            Terminal.println("mmap = {}", .{entry});

            var start = std.mem.alignForward(@intCast(usize, entry.baseAddress), 4096); // only allocate full pages
            var length = entry.length - (start - entry.baseAddress); // remove padded bytes
            while (start < entry.baseAddress + length) : (start += 4096) {
                PMM.mark(@intCast(usize, start), switch (entry.type) {
                    .available => PMM.Marker.free,
                    else => PMM.Marker.allocated,
                });
            }
        }
    }

    Terminal.println("total memory: {} pages, {Bi}", .{ PMM.getFreePageCount(), PMM.getFreeMemory() });

    // mark "ourself" used
    {
        var pos = @ptrToInt(&__start);
        std.debug.assert(std.mem.isAligned(pos, 4096));
        while (pos < @ptrToInt(&__end)) : (pos += 4096) {
            PMM.mark(pos, .allocated);
        }
    }

    // Mark MMIO area as allocated
    {
        var i: usize = 0x0000;
        while (i < 0x10000) : (i += 0x1000) {
            PMM.mark(i, .allocated);
        }
    }

    {
        Terminal.print("[ ] Initialize gdt...\r", .{});
        GDT.init();
        Terminal.println("[X", .{});
    }

    var pageDirectory = try VMM.init();

    // map ourself into memory
    {
        var pos = @ptrToInt(&__start);
        std.debug.assert(std.mem.isAligned(pos, 0x1000));
        while (pos < @ptrToInt(&__end)) : (pos += 0x1000) {
            try pageDirectory.mapPage(pos, pos, .readOnly);
        }
    }

    // map VGA memory
    {
        var i: usize = 0xA0000;
        while (i < 0xC0000) : (i += 0x1000) {
            try pageDirectory.mapPage(i, i, .readWrite);
        }
    }

    Terminal.print("[ ] Map user space memory...\r", .{});
    try VMM.createUserspace(pageDirectory);
    Terminal.println("[X", .{});

    Terminal.print("[ ] Map heap memory...\r", .{});
    try VMM.createHeap(pageDirectory);
    Terminal.println("[X", .{});

    Terminal.println("free memory: {} pages, {Bi}", .{ PMM.getFreePageCount(), PMM.getFreeMemory() });

    Terminal.print("[ ] Enable paging...\r", .{});
    VMM.enablePaging();
    Terminal.println("[X", .{});

    Terminal.print("[ ] Initialize heap memory...\r", .{});
    Heap.init();
    Terminal.println("[X", .{});

    {
        Terminal.print("[ ] Initialize idt...\r", .{});
        Interrupts.init();
        Terminal.println("[X", .{});

        Terminal.print("[ ] Enable IRQs...\r", .{});
        Interrupts.disableAllIRQs();
        Interrupts.enableExternalInterrupts();
        Terminal.println("[X", .{});
    }

    Terminal.print("[ ] Enable Keyboard...\r", .{});
    Keyboard.init();
    Terminal.println("[X", .{});

    Terminal.print("[ ] Enable Timer...\r", .{});
    Timer.init();
    Terminal.println("[X", .{});

    Terminal.print("[ ] Initialize CMOS...\r", .{});
    CMOS.init();
    Terminal.println("[X", .{});

    CMOS.printInfo();

    var drives = std.ArrayList(*BlockDevice).init(Heap.allocator);

    Terminal.print("[ ] Initialize FDC...\r", .{});
    for (try FDC.init()) |drive| {
        try drives.append(drive);
    }
    Terminal.println("[X", .{});

    Terminal.print("[ ] Initialize ATA...\r", .{});
    for (try ATA.init()) |drive| {
        try drives.append(drive);
    }
    Terminal.println("[X", .{});

    Terminal.print("[ ] Scan drives...\n", .{});
    {
        const MBR = @import("mbr.zig");
        var i: usize = 0;
        for (drives.items) |drive| {
            // if(drive.blockSize != 512)
            //     continue; // currently unsupported
            var buf: [512]u8 = undefined;
            try drive.read(drive, 0, buf[0..]);

            // Check if the first block marks a "ZGS Partition"
            const fsHeader = @ptrCast(*const ZGSFS.FSHeader, &buf);
            if (fsHeader.isValid()) {
                // yay! \o/
                Terminal.println("found ZGSFS: {}", .{drive});
                continue;
            }

            // Check if the first block contains a partition table
            const mbrHeader = @ptrCast(*const MBR.BootSector, &buf);
            if (mbrHeader.isValid()) {
                // yay! \o/
                Terminal.println("found MBR header: {}", .{drive});

                var index: usize = 0;
                while (index < 4) : (index += 1) {
                    const part = mbrHeader.getPartition(@truncate(u2, index));
                    if (part.id != 0) {
                        Terminal.println("Partition[{}] = {}", .{ index, part });
                    }
                }

                continue;
            }

            // Block device is useless to us :(
        }
    }
    // Terminal.println("[X");

    drives.deinit();

    // Terminal.print("[ ] Initialize PCI...\r", .{});
    // PCI.init();
    // Terminal.println("[X", .{});

    Terminal.print("Initialize text editor...\r\n", .{});
    CodeEditor.init();

    try CodeEditor.load("// Get ready to code!");

    // Terminal.print("Press 'space' to start system...\r\n");
    // while (true) {
    //     if (Keyboard.getKey()) |key| {
    //         if (key.char) |c|
    //             if (c == ' ')
    //                 break;
    //     }
    // }

    Terminal.print("[ ] Initialize VGA...\r", .{});
    // prevent the terminal to write data into the video memory
    Terminal.enable_video = false;
    VGA.init();
    Terminal.println("[X", .{});

    Terminal.println("[x] Disable serial debugging for better performance...", .{});
    Terminal.println("    Press F12 to re-enable serial debugging!", .{});
    // Terminal.enable_serial = false;

    asm volatile ("int $0x45");
    unreachable;
}

fn kmain() noreturn {
    if (multibootMagic != 0x2BADB002) {
        @panic("System was not bootet with multiboot!");
    }

    main() catch |err| {
        Terminal.enable_serial = true;
        Terminal.setColors(.white, .red);
        Terminal.println("\r\n\r\nmain() returned {}!", .{err});
        if (@errorReturnTrace()) |trace| {
            for (trace.instruction_addresses) |addr, i| {
                if (i >= trace.index)
                    break;
                Terminal.println("Stack: {x: >8}", .{addr});
            }
        }
    };

    Terminal.enable_serial = true;
    Terminal.println("system haltet, shut down now!", .{});
    while (true) {
        Interrupts.disableExternalInterrupts();
        asm volatile ("hlt");
    }
}

var kernelStack: [4096]u8 align(16) = undefined;

var multiboot: *Multiboot.Structure = undefined;
var multibootMagic: u32 = undefined;

export fn _start() callconv(.Naked) noreturn {
    // DO NOT INSERT CODE BEFORE HERE
    // WE MUST NOT MODIFY THE REGISTER CONTENTS
    // BEFORE SAVING THEM TO MEMORY
    multiboot = asm volatile (""
        : [_] "={ebx}" (-> *Multiboot.Structure)
    );
    multibootMagic = asm volatile (""
        : [_] "={eax}" (-> u32)
    );
    // FROM HERE ON WE ARE SAVE

    const eos = @ptrToInt(&kernelStack) + @sizeOf(u8) * kernelStack.len;
    asm volatile (""
        :
        : [stack] "{esp}" (eos)
    );

    kmain();
}

pub fn panic(msg: []const u8, error_return_trace: ?*builtin.StackTrace) noreturn {
    @setCold(true);
    Terminal.enable_serial = true;
    Interrupts.disableExternalInterrupts();
    Terminal.setColors(.white, .red);
    Terminal.println("\r\n\r\nKERNEL PANIC: {}\r\n", .{msg});

    // Terminal.println("Registers:");
    // for (registers) |reg, i| {
    //     Terminal.println("r{} = {}", i, reg);
    // }

    const first_trace_addr = @returnAddress();

    // const dwarf_info: ?*std.debug.DwarfInfo = getSelfDebugInfo() catch |err| blk: {
    //     Terminal.println("unable to get debug info: {}\n", @errorName(err));
    //     break :blk null;
    // };
    var it = std.debug.StackIterator.init(first_trace_addr, null);
    while (it.next()) |return_address| {
        Terminal.println("Stack: {x}", .{return_address});
        // if (dwarf_info) |di| {
        //     std.debug.printSourceAtAddressDwarf(
        //         di,
        //         serial_out_stream,
        //         return_address,
        //         true, // tty color on
        //         printLineFromFile,
        //     ) catch |err| {
        //         Terminal.println("missed a stack frame: {}\n", @errorName(err));
        //         continue;
        //     };
        // }
    }

    haltForever();
}

fn haltForever() noreturn {
    while (true) {
        Interrupts.disableExternalInterrupts();
        asm volatile ("hlt");
    }
}
