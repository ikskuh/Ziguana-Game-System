const std = @import("std");
const builtin = @import("builtin");

const Terminal = @import("text-terminal.zig");
const Multiboot = @import("multiboot.zig");
const VGA = @import("vga.zig");
const GDT = @import("gdt.zig");
const Interrupts = @import("interrupts.zig");
const Keyboard = @import("keyboard.zig");

const Assembler = @import("assembler.zig");

const EnumArray = @import("enum-array.zig").EnumArray;

export var multibootHeader align(4) linksection(".multiboot") = Multiboot.Header.init();

var systemTicks: u32 = 0;

// right now roughly 100ms
fn handleTimerIRQ(cpu: *Interrupts.CpuState) *Interrupts.CpuState {
    _ = @atomicRmw(u32, &systemTicks, .Add, 1, .Release);
    return cpu;
}

export var usercode: [4096]u8 align(16) = undefined;
var usercodeValid: bool = false;

// 1 MB Fixed buffer for debug purposes
var fixedBufferForAllocation: [1 * 1024 * 1024]u8 align(16) = undefined;

var registers: [16]u32 = [_]u32{0} ** 16;

pub const enable_assembler_tracing = false;

pub fn getRegisterAddress(register: u4) u32 {
    return @ptrToInt(&registers[register]);
}

var enable_live_tracing = false;

pub const assembler_api = struct {
    pub extern fn flushpix() void {
        switch (vgaApi) {
            .buffered => VGA.swapBuffers(),
            else => {},
        }
    }

    pub extern fn trace(value: u32) void {
        switch (value) {
            0, 1 => {
                enable_live_tracing = (value != 0);
            },
            2 => vgaApi = .immediate,
            3 => vgaApi = .buffered,
            else => {
                Terminal.println("trace({})", value);
            },
        }
    }

    pub extern fn setpix(x: u32, y: u32, col: u32) void {
        // Terminal.println("setpix({},{},{})", x, y, col);
        if (vgaApi == .immediate) {
            VGA.setPixelDirect(x, y, @truncate(u4, col));
        }
        VGA.setPixel(x, y, @truncate(u4, col));
    }
    pub extern fn getpix(x: u32, y: u32) u32 {
        // Terminal.println("getpix({},{})", x, y);
        return VGA.getPixel(x, y);
    }

    pub extern fn gettime() u32 {
        // systemTicks is in 0.1 sec steps, but we want ms
        const time = 100 * @atomicLoad(u32, &systemTicks, .Acquire);
        // Terminal.println("gettime() = {}", time);
        return time;
    }

    pub extern fn getkey() u32 {
        const keycode = if (Keyboard.getKey()) |key|
            key.scancode | switch (key.set) {
                .default => u32(0),
                .extended0 => u32(0x10000),
                .extended1 => u32(0x20000),
            }
        else
            u32(0);

        // Terminal.println("getkey() = 0x{X:0>5}", keycode);
        return keycode;
    }
};

const VgaApi = enum {
    buffered,
    immediate,
};
var vgaApi: VgaApi = .immediate;

pub fn debugCall(cpu: *Interrupts.CpuState) void {
    if (!enable_live_tracing)
        return;
    Terminal.println("-----------------------------");
    Terminal.println("Line: {}", @intToPtr(*u32, cpu.eip).*);
    Terminal.println("CPU:\r\n{}", cpu);
    Terminal.println("Registers:");
    for (registers) |reg, i| {
        Terminal.println("r{} = {}", i, reg);
    }
    // skip 4 bytes after interrupt. this is the assembler line number!
    cpu.eip += 4;
}

const developSource = @embedFile("../../gasm/concept.asm");

const Task = struct {
    entryPoint: extern fn () noreturn = undefined,
};

const TaskId = enum {
    shell,
    codeEditor,
    spriteEditor,
    tilemapEditor,
    codeRunner,
};

extern fn editorNotImplementedYet() noreturn {
    @panic("This editor is not implemented yet!");
}

extern fn executeUsercode() noreturn {
    // start the user-compiled script
    if (usercodeValid) {
        asm volatile ("jmp usercode");
        unreachable;
    } else {
        startTask(.shell);
    }
}

extern fn executeTilemapEditor() noreturn {
    var time: usize = 0;
    var color: u4 = 1;
    while (true) : (time += 1) {
        if (Keyboard.getKey()) |key| {
            if (key.set == .default and key.scancode == 57) {
                // space
                if (@addWithOverflow(u4, color, 1, &color)) {
                    color = 1;
                }
            }
        }

        var y: usize = 0;
        while (y < 480) : (y += 1) {
            var x: usize = 0;
            while (x < 640) : (x += 1) {
                // c = @truncate(u4, (x + offset_x + dx) / 32 + (y + offset_y + dy) / 32);
                const c = if (y > (systemTicks % 480)) color else 0;
                VGA.setPixel(x, y, c);
            }
        }

        VGA.swapBuffers();
    }
}

const TaskList = EnumArray(TaskId, Task);
const taskList = TaskList.initMap(([_]TaskList.KV{
    TaskList.KV{
        .key = .shell,
        .value = Task{
            .entryPoint = editorNotImplementedYet,
        },
    },
    TaskList.KV{
        .key = .codeEditor,
        .value = Task{
            .entryPoint = editorNotImplementedYet,
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

fn startTask(task: TaskId) noreturn {
    taskList.at(task).entryPoint();
}

pub fn main() anyerror!void {
    Terminal.clear();
    {
        Terminal.print("[ ] Initialize gdt...\r");
        GDT.init();
        Terminal.println("[X");
    }
    {
        Terminal.print("[ ] Initialize idt...\r");
        Interrupts.init();
        Terminal.println("[X");

        // Terminal.print("[ ] Fire Test Interrupt\r");
        // Interrupts.trigger_isr(45);
        // Terminal.println("[X");

        Interrupts.setIRQHandler(0, handleTimerIRQ);

        Terminal.print("[ ] Enable IRQs...\r");
        Interrupts.enableExternalInterrupts();
        Interrupts.enableAllIRQs();
        Terminal.println("[X");
    }
    {
        Terminal.print("[ ] Enable Keyboard...\r");
        Keyboard.init();
        Terminal.println("[X");
    }

    const flags = @ptrCast(*Multiboot.Structure.Flags, &multiboot.flags).*;

    Terminal.print("Multiboot Structure: {*}\r\n", multiboot);
    inline for (@typeInfo(Multiboot.Structure).Struct.fields) |fld| {
        if (comptime !std.mem.eql(u8, comptime fld.name, "flags")) {
            if (@field(flags, fld.name)) {
                Terminal.print("\t{}\t= {}\r\n", fld.name, @field(multiboot, fld.name));
            }
        }
    }

    Terminal.print("VGA init...\r\n");

    // prevent the terminal to write data into the video memory
    Terminal.enable_video = false;

    VGA.init();

    Terminal.println("Assembler Source:\r\n{}", developSource);

    {
        var y: usize = 0;
        while (y < 480) : (y += 1) {
            var x: usize = 0;
            while (x < 640) : (x += 1) {
                VGA.setPixel(x, y, 0xF);
            }
        }
    }

    VGA.swapBuffers();
    Terminal.println("Start assembling code...");

    var fba = std.heap.FixedBufferAllocator.init(fixedBufferForAllocation[0..]);

    // foo
    usercodeValid = false;
    try Assembler.assemble(&fba.allocator, developSource, usercode[0..], null);
    usercodeValid = true;

    Terminal.println("Assembled code successfully!");
    Terminal.println("Memory required: {} bytes!", fba.end_index);

    startTask(.codeRunner);
}

fn kmain() noreturn {
    if (multibootMagic != 0x2BADB002) {
        @panic("System was not bootet with multiboot!");
    }

    main() catch |err| {
        Terminal.setColors(.white, .red);
        Terminal.print("\r\n\r\nmain() returned {}!", err);
    };

    Terminal.println("system haltet, shut down now!");
    while (true) {
        Interrupts.disableExternalInterrupts();
        asm volatile ("hlt");
    }
}

var kernelStack: [1 << 16]u8 align(16) = undefined;

var multiboot: *Multiboot.Structure = undefined;
var multibootMagic: u32 = undefined;

export nakedcc fn _start() noreturn {
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

    @newStackCall(kernelStack[0..], kmain);
}

pub fn panic(msg: []const u8, error_return_trace: ?*builtin.StackTrace) noreturn {
    @setCold(true);
    Interrupts.disableExternalInterrupts();
    Terminal.setColors(.white, .red);
    Terminal.println("\r\n\r\nKERNEL PANIC: {}\r\n", msg);

    Terminal.println("Registers:");
    for (registers) |reg, i| {
        Terminal.println("r{} = {}", i, reg);
    }

    Terminal.println("Stack Trace: 0x{X}", @returnAddress());
    Terminal.println("{}", error_return_trace);

    while (true) {
        Interrupts.disableExternalInterrupts();
        asm volatile ("hlt");
    }
}
