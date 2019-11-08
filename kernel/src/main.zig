const std = @import("std");
const builtin = @import("builtin");

const Terminal = @import("text-terminal.zig");
const Multiboot = @import("multiboot.zig");
const VGA = @import("vga.zig");
const GDT = @import("gdt.zig");
const Interrupts = @import("interrupts.zig");
const Keyboard = @import("keyboard.zig");
const SerialPort = @import("serial-port.zig");

const Assembler = @import("assembler.zig");

const EnumArray = @import("enum-array.zig").EnumArray;
const BitmapAllocator = @import("bitmap-allocator.zig").BitmapAllocator;

export var multibootHeader align(4) linksection(".multiboot") = Multiboot.Header.init();

var systemTicks: u32 = 0;

// right now roughly 100ms
fn handleTimerIRQ(cpu: *Interrupts.CpuState) *Interrupts.CpuState {
    _ = @atomicRmw(u32, &systemTicks, .Add, 1, .Release);
    return cpu;
}

var usercodeValid: bool = false;

// 1 MB Fixed buffer for debug purposes
var fixedBufferForAllocation: [1 * 1024 * 1024]u8 align(16) = undefined;

var registers: [16]u32 = [_]u32{0} ** 16;

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
        // jump into user space
        asm volatile ("jmp 0x40000000");
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

extern const __start: u8;
extern const __end: u8;

fn dumpPMM(msg: []const u8) void {
    Terminal.println("{}:", msg);
    for (pmm_allocator.bitmap) |bits, i| {
        if (i < 20) {
            comptime var j = 0;
            inline while (j < 32) : (j += 1) {
                Terminal.print("{}", (bits >> j) & 1);
            }
            if (i % 4 == 3) {
                Terminal.println("");
            }
        }
    }
}

pub fn main() anyerror!void {
    SerialPort.init(SerialPort.COM1, 9600, .none, .eight);

    Terminal.clear();

    // const flags = @ptrCast(*Multiboot.Structure.Flags, &multiboot.flags).*;
    const flags = @bitCast(Multiboot.Structure.Flags, multiboot.flags);

    Terminal.print("Multiboot Structure: {*}\r\n", multiboot);
    inline for (@typeInfo(Multiboot.Structure).Struct.fields) |fld| {
        if (comptime !std.mem.eql(u8, comptime fld.name, "flags")) {
            if (@field(flags, fld.name)) {
                Terminal.print("\t{}\t= {}\r\n", fld.name, @field(multiboot, fld.name));
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

            Terminal.println("mmap = {}", entry);

            var start = std.mem.alignForward(@intCast(usize, entry.baseAddress), 4096); // only allocate full pages
            var length = entry.length - (start - entry.baseAddress); // remove padded bytes
            while (start < entry.baseAddress + length) : (start += 4096) {
                pmm_allocator.markPage(@intCast(usize, start), switch (entry.type) {
                    .available => @typeOf(pmm_allocator).Marker.free,
                    else => @typeOf(pmm_allocator).Marker.allocated,
                });
            }
        }
    }

    // mark "ourself" used
    {
        var pos = @ptrToInt(&__start);
        std.debug.assert(std.mem.isAligned(pos, 4096));
        while (pos < @ptrToInt(&__end)) : (pos += 4096) {
            pmm_allocator.markPage(pos, .allocated);
        }
    }

    // Mark MMIO area as allocated
    {
        var i: usize = 0x0000;
        while (i < 0x10000) : (i += 0x1000) {
            pmm_allocator.markPage(i, .allocated);
        }
    }
    Terminal.println("free memory: {} pages", pmm_allocator.getFreePageCount());

    {
        Terminal.print("[ ] Initialize gdt...\r");
        GDT.init();
        Terminal.println("[X");
    }

    var pageDirectory = try vmm_mapper.init();

    // map ourself into memory
    {
        var pos = @ptrToInt(&__start);
        std.debug.assert(std.mem.isAligned(pos, 4096));
        while (pos < @ptrToInt(&__end)) : (pos += 4096) {
            try pageDirectory.mapPage(pos, pos, .readWrite);
        }
    }

    // map VGA memory
    {
        var i: usize = 0xA0000;
        while (i < 0xC0000) : (i += 0x1000) {
            try pageDirectory.mapPage(i, i, .readWrite);
        }
    }

    try vmm_mapper.create_userspace(pageDirectory);

    Terminal.println("[x] Fill userspace: {Bi}", vmm_mapper.sizeOfUserspace);

    Terminal.print("[ ] Enable paging...\r");
    vmm_mapper.enable_paging();
    Terminal.println("[X");

    {
        Terminal.print("[ ] Initialize idt...\r");
        Interrupts.init();
        Terminal.println("[X");

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

    Terminal.print("VGA init...\r\n");

    // prevent the terminal to write data into the video memory
    Terminal.enable_video = false;

    VGA.init();

    // Terminal.println("Assembler Source:\r\n{}", developSource);

    {
        var y: usize = 0;
        while (y < VGA.height) : (y += 1) {
            var x: usize = 0;
            while (x < VGA.width) : (x += 1) {
                VGA.setPixel(x, y, @truncate(u4, x + y));
            }
        }
    }

    VGA.swapBuffers();
    Terminal.println("Start assembling code...");

    var fba = std.heap.FixedBufferAllocator.init(fixedBufferForAllocation[0..]);

    // foo
    usercodeValid = false;
    try Assembler.assemble(&fba.allocator, developSource, vmm_mapper.getUserSpace(), null);
    usercodeValid = true;

    Terminal.println("Assembled code successfully!");
    Terminal.println("Memory required: {} bytes!", fba.end_index);

    Terminal.println("Start user code...");
    startTask(.codeRunner);

    // var time: usize = 0;
    // while (true) {
    //     var y: usize = 0;
    //     while (y < VGA.height) : (y += 1) {
    //         var x: usize = 0;
    //         while (x < VGA.width) : (x += 1) {
    //             VGA.setPixel(x, y, @truncate(u4, x + y + time));
    //         }
    //     }
    //     VGA.swapBuffers();

    //     time += 1;
    // }
}

fn kmain() noreturn {
    if (multibootMagic != 0x2BADB002) {
        @panic("System was not bootet with multiboot!");
    }

    main() catch |err| {
        Terminal.setColors(.white, .red);
        Terminal.println("\r\n\r\nmain() returned {}!", err);
        if (@errorReturnTrace()) |trace| {
            for (trace.instruction_addresses) |addr, i| {
                if (i >= trace.index)
                    break;
                Terminal.println("{X: >8}", addr);
            }
        }
    };

    Terminal.println("system haltet, shut down now!");
    while (true) {
        Interrupts.disableExternalInterrupts();
        asm volatile ("hlt");
    }
}

var kernelStack: [4096]u8 align(16) = undefined;

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

const SerialOutStream = struct {
    const This = @This();
    fn print(_: This, comptime fmt: []const u8, args: ...) error{Never}!void {
        Terminal.print(fmt, args);
    }

    fn write(_: This, text: []const u8) error{Never}!void {
        Terminal.print("{}", text);
    }

    fn writeByte(_: This, byte: u8) error{Never}!void {
        Terminal.print("{c}", byte);
    }
};

const serial_out_stream = SerialOutStream{};

fn printLineFromFile(out_stream: var, line_info: std.debug.LineInfo) anyerror!void {
    Terminal.println("TODO print line from the file\n");
}

pub fn panic(msg: []const u8, error_return_trace: ?*builtin.StackTrace) noreturn {
    @setCold(true);
    Interrupts.disableExternalInterrupts();
    Terminal.setColors(.white, .red);
    Terminal.println("\r\n\r\nKERNEL PANIC: {}\r\n", msg);

    // Terminal.println("Registers:");
    // for (registers) |reg, i| {
    //     Terminal.println("r{} = {}", i, reg);
    // }

    const first_trace_addr = @returnAddress();

    const dwarf_info: ?*std.debug.DwarfInfo = getSelfDebugInfo() catch |err| blk: {
        Terminal.println("unable to get debug info: {}\n", @errorName(err));
        break :blk null;
    };
    var it = std.debug.StackIterator.init(first_trace_addr);
    while (it.next()) |return_address| {
        Terminal.println("Stack: {x}", return_address);
        if (dwarf_info) |di| {
            std.debug.printSourceAtAddressDwarf(
                di,
                serial_out_stream,
                return_address,
                true, // tty color on
                printLineFromFile,
            ) catch |err| {
                Terminal.println("missed a stack frame: {}\n", @errorName(err));
                continue;
            };
        }
    }

    haltForever();
}

fn haltForever() noreturn {
    while (true) {
        Interrupts.disableExternalInterrupts();
        asm volatile ("hlt");
    }
}

// 1 MBit for 4 GB @ 4096 pages
var pmm_allocator = BitmapAllocator(1 * 1024 * 1024).init();

const vmm_mapper = struct {
    // WARNING: Change assembler jmp according to this!
    const startOfUserspace = 0x40000000; // 1 GB into virtual memory
    var sizeOfUserspace: usize = 0; // not initialized

    fn getUserSpace() []u8 {
        if (sizeOfUserspace == 0)
            @panic("Userspace is not initialized!");
        return @intToPtr([*]u8, startOfUserspace)[0..sizeOfUserspace];
    }

    fn init() !*PageDirectory {
        var directory = @intToPtr(*PageDirectory, pmm_allocator.allocPage() orelse return error.OutOfMemory);
        @memset(@ptrCast([*]u8, directory), 0, 4096);

        asm volatile ("mov %[ptr], %%cr3"
            :
            : [ptr] "r" (directory)
        );

        return directory;
    }

    fn create_userspace(directory: *PageDirectory) !void {
        var pointer = u32(startOfUserspace);
        while (pmm_allocator.allocPage()) |pmm_address| : (pointer += 4096) {
            // Terminal.println("Map {X} to {X}", pmm_address, pointer);
            try directory.mapPage(pointer, pmm_address, .readWrite);
            sizeOfUserspace += 0x1000;
        }
    }

    fn enable_paging() void {
        var cr0 = asm volatile ("mov %%cr0, %[cr]"
            : [cr] "=r" (-> u32)
        );
        cr0 |= (1 << 31);
        asm volatile ("mov %[cr], %%cr0"
            :
            : [cr] "r" (cr0)
        );
    }

    const PageDirectory = extern struct {
        entries: [1024]Entry,

        fn mapPage(directory: *PageDirectory, virtualAddress: usize, physicalAddress: usize, access: WriteProtection) error{
            AlreadyMapped,
            OutOfMemory,
        }!void {
            const loc = addrToLocation(virtualAddress);

            var dirEntry = &directory.entries[loc.directoryIndex];
            if (!dirEntry.isMapped) {
                var tbl = @intToPtr(*allowzero PageTable, pmm_allocator.allocPage() orelse return error.OutOfMemory);
                @memset(@ptrCast([*]u8, tbl), 0, 4096);

                dirEntry.* = Entry{
                    .isMapped = true,
                    .writeProtection = .readWrite,
                    .access = .ring0,
                    .enableWriteThroughCaching = false,
                    .disableCaching = false,
                    .wasAccessed = false,
                    .wasWritten = false,
                    .size = .fourKilo,
                    .dontRefreshTLB = false,
                    .userBits = 0,
                    // Hack to workaround #2627
                    .pointer0 = @truncate(u4, (@ptrToInt(tbl) >> 12)),
                    .pointer1 = @intCast(u16, (@ptrToInt(tbl) >> 16)),
                };

                std.debug.assert(@ptrToInt(tbl) == (@bitCast(usize, dirEntry.*) & 0xFFFFF000));
            }

            var table = @intToPtr(*allowzero PageTable, ((usize(dirEntry.pointer1) << 4) | usize(dirEntry.pointer0)) << 12);

            var tblEntry = &table.entries[loc.tableIndex];

            if (tblEntry.isMapped) {
                Terminal.println("Mapping is at {} is {X}: {}", loc, @bitCast(u32, tblEntry.*), tblEntry);
                return error.AlreadyMapped;
            }

            tblEntry.* = Entry{
                .isMapped = true,
                .writeProtection = access,
                .access = .ring0,
                .enableWriteThroughCaching = false,
                .disableCaching = false,
                .wasAccessed = false,
                .wasWritten = false,
                .size = .fourKilo,
                .dontRefreshTLB = false,
                .userBits = 0,
                // Hack to workaround #2627
                .pointer0 = @truncate(u4, (physicalAddress >> 12)),
                .pointer1 = @intCast(u16, (physicalAddress >> 16)),
            };

            std.debug.assert(physicalAddress == (@bitCast(usize, tblEntry.*) & 0xFFFFF000));

            asm volatile ("invlpg %[ptr]"
                :
                : [ptr] "m" (virtualAddress)
            );
        }
    };

    const PageTable = extern struct {
        entries: [1024]Entry,
    };

    const PageLocation = struct {
        directoryIndex: u10,
        tableIndex: u10,
    };

    fn addrToLocation(addr: usize) PageLocation {
        const idx = addr / 4096;
        return PageLocation{
            .directoryIndex = @truncate(u10, idx / 1024),
            .tableIndex = @truncate(u10, idx & 0x3FF),
        };
    }

    const WriteProtection = enum(u1) {
        readOnly = 0,
        readWrite = 1,
    };

    const PageAccess = enum(u1) {
        ring0 = 0,
        all = 1,
    };

    const PageSize = enum(u1) {
        fourKilo = 0,
        fourMegas = 1,
    };

    const Entry = packed struct {
        isMapped: bool,
        writeProtection: WriteProtection,
        access: PageAccess,
        enableWriteThroughCaching: bool,
        disableCaching: bool,
        wasAccessed: bool,
        wasWritten: bool,
        size: PageSize,
        dontRefreshTLB: bool,
        userBits: u3 = 0,

        // magic bug fix for #2627
        pointer0: u4,
        pointer1: u16,
    };

    comptime {
        std.debug.assert(@sizeOf(Entry) == 4);
        std.debug.assert(@sizeOf(PageDirectory) == 4096);
        std.debug.assert(@sizeOf(PageTable) == 4096);
    }
};

var kernel_panic_allocator_bytes: [4 * 1024 * 1024]u8 = undefined;
var kernel_panic_allocator_state = std.heap.FixedBufferAllocator.init(kernel_panic_allocator_bytes[0..]);
const kernel_panic_allocator = &kernel_panic_allocator_state.allocator;

extern var __debug_info_start: u8;
extern var __debug_info_end: u8;
extern var __debug_abbrev_start: u8;
extern var __debug_abbrev_end: u8;
extern var __debug_str_start: u8;
extern var __debug_str_end: u8;
extern var __debug_line_start: u8;
extern var __debug_line_end: u8;
extern var __debug_ranges_start: u8;
extern var __debug_ranges_end: u8;

fn dwarfSectionFromSymbolAbs(start: *u8, end: *u8) std.debug.DwarfInfo.Section {
    return std.debug.DwarfInfo.Section{
        .offset = 0,
        .size = @ptrToInt(end) - @ptrToInt(start),
    };
}

fn dwarfSectionFromSymbol(start: *u8, end: *u8) std.debug.DwarfInfo.Section {
    return std.debug.DwarfInfo.Section{
        .offset = @ptrToInt(start),
        .size = @ptrToInt(end) - @ptrToInt(start),
    };
}

fn getSelfDebugInfo() !*std.debug.DwarfInfo {
    const S = struct {
        var have_self_debug_info = false;
        var self_debug_info: std.debug.DwarfInfo = undefined;

        var in_stream_state = std.io.InStream(anyerror){ .readFn = readFn };
        var in_stream_pos: usize = 0;
        const in_stream = &in_stream_state;

        fn readFn(self: *std.io.InStream(anyerror), buffer: []u8) anyerror!usize {
            const ptr = @intToPtr([*]const u8, in_stream_pos);
            @memcpy(buffer.ptr, ptr, buffer.len);
            in_stream_pos += buffer.len;
            return buffer.len;
        }

        const SeekableStream = std.io.SeekableStream(anyerror, anyerror);
        var seekable_stream_state = SeekableStream{
            .seekToFn = seekToFn,
            .seekByFn = seekForwardFn,

            .getPosFn = getPosFn,
            .getEndPosFn = getEndPosFn,
        };
        const seekable_stream = &seekable_stream_state;

        fn seekToFn(self: *SeekableStream, pos: u64) anyerror!void {
            in_stream_pos = @intCast(usize, pos);
        }
        fn seekForwardFn(self: *SeekableStream, pos: i64) anyerror!void {
            in_stream_pos = @bitCast(usize, @bitCast(isize, in_stream_pos) +% @intCast(isize, pos));
        }
        fn getPosFn(self: *SeekableStream) anyerror!u64 {
            return in_stream_pos;
        }
        fn getEndPosFn(self: *SeekableStream) anyerror!u64 {
            return @ptrToInt(&__debug_ranges_end);
        }
    };
    if (S.have_self_debug_info)
        return &S.self_debug_info;

    S.self_debug_info = std.debug.DwarfInfo{
        .dwarf_seekable_stream = S.seekable_stream,
        .dwarf_in_stream = S.in_stream,
        .endian = builtin.Endian.Little,
        .debug_info = dwarfSectionFromSymbol(&__debug_info_start, &__debug_info_end),
        .debug_abbrev = dwarfSectionFromSymbolAbs(&__debug_abbrev_start, &__debug_abbrev_end),
        .debug_str = dwarfSectionFromSymbolAbs(&__debug_str_start, &__debug_str_end),
        .debug_line = dwarfSectionFromSymbol(&__debug_line_start, &__debug_line_end),
        .debug_ranges = dwarfSectionFromSymbolAbs(&__debug_ranges_start, &__debug_ranges_end),
        .abbrev_table_list = undefined,
        .compile_unit_list = undefined,
        .func_list = undefined,
    };
    try std.debug.openDwarfDebugInfo(&S.self_debug_info, kernel_panic_allocator);
    return &S.self_debug_info;
}
