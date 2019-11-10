const Interrupts = @import("interrupts.zig");
const IO = @import("io.zig");

pub const freq = 1000; // 1 kHz
pub var ticks: usize = 0;

// right now roughly 100ms
fn handleTimerIRQ(cpu: *Interrupts.CpuState) *Interrupts.CpuState {
    _ = @atomicRmw(usize, &ticks, .Add, 1, .Release);
    return cpu;
}

pub fn wait(cnt: usize) void {
    const dst = @atomicLoad(usize, &ticks, .Acquire) + cnt;
    while (@atomicLoad(usize, &ticks, .Acquire) < dst) {
        asm volatile ("hlt");
    }
}

pub fn init() void {
    const timer_limit = 1193182 / freq;

    ticks = 0;

    IO.outb(0x43, 0x34); // Binary, Mode 2, LSB first, Channel 0
    IO.outb(0x40, @truncate(u8, timer_limit & 0xFF));
    IO.outb(0x40, @truncate(u8, timer_limit >> 8));

    Interrupts.setIRQHandler(0, handleTimerIRQ);
    Interrupts.enableIRQ(0);
}
