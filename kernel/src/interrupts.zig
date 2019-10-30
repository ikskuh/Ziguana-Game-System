const std = @import("std");
const Terminal = @import("text-terminal.zig");

const CpuState = packed struct {
    // Von Hand gesicherte Register
    eax: u32,
    ebx: u32,
    ecx: u32,
    edx: u32,
    esi: u32,
    edi: u32,
    ebp: u32,

    intr: u32,
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


export extern fn handle_interrupt(cpu: *CpuState) void {
    Terminal.setColor(.white, .magenta);
    Terminal.println("CPU State:");
    Terminal.println("{}", cpu);
}



export var idt: [256]Descriptor align(16) = undefined;

pub fn init() void {
    comptime var i: usize = 0;
    inline while (i < idt.len) : (i += 1) {
        idt[i] = Descriptor.init(getInterruptStub(i), 0x08, .interruptGate, .bits32, 0, true);
    }

    asm volatile ("lidt idtp");
}

pub fn trigger_isr0() void {
    asm volatile ("int $0x0");
}

pub fn enableIRQ() void {
    asm volatile ("sti");
}

pub fn disableIRQ() void {
    asm volatile ("cli");
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
        \\ add $4, %%esp
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