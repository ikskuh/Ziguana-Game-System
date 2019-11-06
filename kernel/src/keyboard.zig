const io = @import("io.zig");
const Interrupts = @import("interrupts.zig");
const Terminal = @import("text-terminal.zig");

fn sendCommand(cmd: u8) void {

    // Warten bis die Tastatur bereit ist, und der Befehlspuffer leer ist
    while ((io.inb(0x64) & 0x2) != 0) {}
    io.outb(0x60, cmd);
}

pub fn init() void {
    // IRQ-Handler fuer Tastatur-IRQ(1) registrieren
    Interrupts.setIRQHandler(1, kbdIrqHandler);
    // Interrupts.setkbdIrqHandler(12, mouseIrqHandler);

    // Tastaturpuffer leeren
    while ((io.inb(0x64) & 0x1) != 0) {
        _ = io.inb(0x60);
    }

    // Tastatur aktivieren
    sendCommand(0xF4);
}

pub const KeyEvent = struct {
    set: ScancodeSet,
    scancode: u16,
};

var foo = u32(0);
var lastKeyPress: ?KeyEvent = null;

pub fn getKey() ?KeyEvent {
    _ = @atomicLoad(u32, &foo, .SeqCst);
    var copy = lastKeyPress;
    lastKeyPress = null;
    return copy;
}

const ScancodeSet = enum {
    default,
    extended0,
    extended1,
};

fn pushScancode(set: ScancodeSet, scancode: u16, isRelease: bool) void {
    if (!isRelease) {
        lastKeyPress = KeyEvent{
            .set = set,
            .scancode = scancode,
        };
    }

    // Zum Testen sollte folgendes verwendet werden:
    Terminal.println("[kbd:{}/{}/{}]", set, scancode, if (isRelease) "R" else "P");
}

const IrqState = enum {
    default,
    receiveE0,
    receiveE1_Byte0,
    receiveE1_Byte1,
};

var irqState: IrqState = .default;
var e1Byte0: u8 = undefined;

fn kbdIrqHandler(cpu: *Interrupts.CpuState) *Interrupts.CpuState {
    const inputData = io.inb(0x60);
    irqState = switch (irqState) {
        .default => switch (inputData) {
            0xE0 => IrqState.receiveE0,
            0xE1 => IrqState.receiveE1_Byte0,
            else => blk: {
                pushScancode(.default, inputData & 0x7F, (inputData & 0x80 != 0));

                break :blk IrqState.default;
            },
        },
        .receiveE0 => switch (inputData) {
            // these are "fake shifts"
            0x2A, 0x36 => IrqState.default,
            else => blk: {
                pushScancode(.extended0, inputData & 0x7F, (inputData & 0x80 != 0));

                break :blk IrqState.default;
            },
        },
        .receiveE1_Byte0 => blk: {
            e1Byte0 = inputData;
            break :blk .receiveE1_Byte1;
        },
        .receiveE1_Byte1 => blk: {
            const scancode = (u16(inputData) << 8) | e1Byte0;

            pushScancode(.extended1, scancode, (inputData & 0x80) != 0);

            break :blk .default;
        },
    };

    return cpu;
}

fn mouseIrqHandler(cpu: *Interrupts.CpuState) *Interrupts.CpuState {
    @panic("EEK, A MOUSE!");
}
