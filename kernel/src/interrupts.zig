const std = @import("std");
const io = @import("io.zig");
const Terminal = @import("text-terminal.zig");

pub const InterruptHandler = fn (*CpuState) *CpuState;

var irqHandlers = [_]?InterruptHandler{null} ** 32;

pub fn setIRQHandler(irq: u4, handler: ?InterruptHandler) void {
    irqHandlers[irq] = handler;
}

export fn handle_interrupt(_cpu: *CpuState) *CpuState {
    var cpu = _cpu;
    switch (cpu.interrupt) {
        0x00...0x1F => {
            // Exception
            Terminal.setColors(.white, .magenta);
            Terminal.println("Unhandled exception:\r\n{}", cpu);
            Terminal.resetColors();

            while (true) {
                asm volatile (
                    \\ cli
                    \\ hlt
                );
            }
        },
        0x20...0x2F => {
            // IRQ
            if (irqHandlers[cpu.interrupt - 0x20]) |handler| {
                cpu = handler(cpu);
            } else {
                Terminal.println("Unhandled IRQ{}:\r\n{}", cpu.interrupt - 0x20, cpu);
            }

            if (cpu.interrupt >= 0x28) {
                io.outb(0xa0, 0x20); // ACK slave PIC
            }
            io.outb(0x20, 0x20); // ACK master PIC
        },
        else => {
            Terminal.println("Unhandled interrupt:\r\n{}", cpu);
        },
    }

    return cpu;
}

export var idt: [256]Descriptor align(16) = undefined;

pub fn init() void {
    comptime var i: usize = 0;
    inline while (i < idt.len) : (i += 1) {
        idt[i] = Descriptor.init(getInterruptStub(i), 0x08, .interruptGate, .bits32, 0, true);
    }

    asm volatile ("lidt idtp");

    // Master-PIC initialisieren
    io.outb(0x20, 0x11); // Initialisierungsbefehl fuer den PIC
    io.outb(0x21, 0x20); // Interruptnummer fuer IRQ 0
    io.outb(0x21, 0x04); // An IRQ 2 haengt der Slave
    io.outb(0x21, 0x01); // ICW 4

    // Slave-PIC initialisieren
    io.outb(0xa0, 0x11); // Initialisierungsbefehl fuer den PIC
    io.outb(0xa1, 0x28); // Interruptnummer fuer IRQ 8
    io.outb(0xa1, 0x02); // An IRQ 2 haengt der Slave
    io.outb(0xa1, 0x01); // ICW 4
}

pub fn fireInterrupt(comptime intr: u32) void {
    asm volatile ("int %[i]"
        :
        : [i] "n" (intr)
    );
}

pub fn enableIRQ(irqNum: u4) void {
    switch (irqNum) {
        0...7 => {
            io.outb(0x21, io.inb(0x21) & ~(u8(1) << @intCast(u3, irqNum)));
        },
        8...15 => {
            io.outb(0x21, io.inb(0x21) & ~(u8(1) << @intCast(u3, irqNum - 8)));
        },
    }
}

pub fn disableIRQ(irqNum: u4) void {
    switch (irqNum) {
        0...7 => {
            io.outb(0x21, io.inb(0x21) | (u8(1) << @intCast(u3, irqNum)));
        },
        8...15 => {
            io.outb(0x21, io.inb(0x21) | (u8(1) << @intCast(u3, irqNum - 8)));
        },
    }
}

pub fn enableAllIRQs() void {
    // Alle IRQs aktivieren (demaskieren)
    io.outb(0x21, 0x0);
    io.outb(0xa1, 0x0);
}

pub fn disableAllIRQs() void {
    // Alle IRQs aktivieren (demaskieren)
    io.outb(0x21, 0xFF);
    io.outb(0xa1, 0xFF);
}

pub fn enableExternalInterrupts() void {
    asm volatile ("sti");
}

pub fn disableExternalInterrupts() void {
    asm volatile ("cli");
}

pub const CpuState = packed struct {
    // Von Hand gesicherte Register
    eax: u32,
    ebx: u32,
    ecx: u32,
    edx: u32,
    esi: u32,
    edi: u32,
    ebp: u32,

    interrupt: u32,
    errorcode: u32,

    // Von der CPU gesichert
    eip: u32,
    cs: u32,
    eflags: u32,
    esp: u32,
    ss: u32,
};

const InterruptType = enum(u3) {
    interruptGate = 0b110,
    trapGate = 0b111,
    taskGate = 0b101,
};

const InterruptBits = enum(u1) {
    bits32 = 1,
    bits16 = 0,
};

const Descriptor = packed struct {
    offset0: u16, // 0-15 Offset 0-15 Gibt das Offset des ISR innerhalb des Segments an. Wenn der entsprechende Interrupt auftritt, wird eip auf diesen Wert gesetzt.
    selector: u16, // 16-31 Selector Gibt den Selector des Codesegments an, in das beim Auftreten des Interrupts gewechselt werden soll. Im Allgemeinen ist dies das Kernel-Codesegment (Ring 0).
    ist: u3 = 0, // 32-34 000 / IST Gibt im LM den Index in die IST an, ansonsten 0!
    _0: u5 = 0, // 35-39 Reserviert Wird ignoriert
    type: InterruptType, // 40-42 Typ Gibt die Art des Interrupts an
    bits: InterruptBits, // 43 D Gibt an, ob es sich um ein 32bit- (1) oder um ein 16bit-Segment (0) handelt.
    // Im LM: Für 64-Bit LDT 0, ansonsten 1
    _1: u1 = 0, // 44 0
    privilege: u2, // 45-46 DPL Gibt das Descriptor Privilege Level an, das man braucht um diesen Interrupt aufrufen zu dürfen.
    enabled: bool, // 47 P Gibt an, ob dieser Eintrag benutzt wird.
    offset1: u16, // 48-63 Offset 16-31

    pub fn init(offset: ?nakedcc fn () void, selector: u16, _type: InterruptType, bits: InterruptBits, privilege: u2, enabled: bool) Descriptor {
        const offset_val = @ptrToInt(offset);
        return Descriptor{
            .offset0 = @truncate(u16, offset_val & 0xFFFF),
            .offset1 = @truncate(u16, (offset_val >> 16) & 0xFFFF),
            .selector = selector,
            .type = _type,
            .bits = bits,
            .privilege = privilege,
            .enabled = enabled,
        };
    }
};

comptime {
    std.debug.assert(@sizeOf(Descriptor) == 8);
}

const InterruptTable = packed struct {
    limit: u16,
    table: [*]Descriptor,
};

export const idtp = InterruptTable{
    .table = &idt,
    .limit = @sizeOf(@typeOf(idt)) - 1,
};

export nakedcc fn common_isr_handler() void {
    asm volatile (
        \\ push %%ebp
        \\ push %%edi
        \\ push %%esi
        \\ push %%edx
        \\ push %%ecx
        \\ push %%ebx
        \\ push %%eax
        \\ 
        \\ // Handler aufrufen
        \\ push %%esp
        \\ call handle_interrupt
        \\ mov %%eax, %%esp
        \\ 
        \\ // CPU-Zustand wiederherstellen
        \\ pop %%eax
        \\ pop %%ebx
        \\ pop %%ecx
        \\ pop %%edx
        \\ pop %%esi
        \\ pop %%edi
        \\ pop %%ebp
        \\ 
        \\ // Fehlercode und Interruptnummer vom Stack nehmen
        \\ add $8, %%esp
        \\ 
        \\ // Ruecksprung zum unterbrochenen Code
        \\ iret
    );
}

fn getInterruptStub(comptime i: u32) nakedcc fn () void {
    const Wrapper = struct {
        nakedcc fn stub_with_zero() void {
            asm volatile (
                \\ pushl $0
                \\ pushl %[nr]
                \\ jmp common_isr_handler
                :
                : [nr] "n" (i)
            );
        }
        nakedcc fn stub_with_errorcode() void {
            asm volatile (
                \\ pushl %[nr]
                \\ jmp common_isr_handler
                :
                : [nr] "n" (i)
            );
        }
    };
    return switch (i) {
        8, 10...14, 17 => Wrapper.stub_with_errorcode,
        else => Wrapper.stub_with_zero,
    };
}
