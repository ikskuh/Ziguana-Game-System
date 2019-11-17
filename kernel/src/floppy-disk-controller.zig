const std = @import("std");

const IO = @import("io.zig");
const TextTerminal = @import("text-terminal.zig");
const CMOS = @import("cmos.zig");
const ISA_DMA = @import("isa-dma.zig");
const Interrupts = @import("interrupts.zig");
const Timer = @import("timer.zig");
const CHS = @import("chs.zig");

const BlockIterator = @import("block-iterator.zig").BlockIterator;

pub const microHDFloppyLayout = CHS.DriveLayout{
    .headCount = 2,
    .cylinderCount = 80,
    .sectorCount = 18,
};

// this file follows roughly the following links:
// https://wiki.osdev.org/FDC
// https://www.lowlevel.eu/wiki/Floppy_Disk_Controller

pub const DriveName = enum(u2) {
    A = 0,
    B = 1,
    C = 2,
    D = 3,
};

const IoMode = enum {
    portIO,
    dma,
};

const Drive = struct {
    available: bool,
    id: u2,
    ioMode: IoMode,
};

var allDrives: [4]Drive = undefined;

var currentDrive: ?*Drive = null;

fn getCurrentDrive() !*Drive {
    const drive = currentDrive orelse return error.NoDriveSelected;
    if (!drive.available)
        return error.DriveNotAvailable;
    return drive;
}

/// discovers and initializes all floppy drives
pub fn init() !void {
    Interrupts.setIRQHandler(6, handleIRQ6);
    Interrupts.enableIRQ(6);

    const drives = CMOS.getFloppyDrives();

    for (allDrives) |*drive, i| {
        drive.* = Drive{
            .available = switch (i) {
                0 => if (drives.A) |d| d == .microHD else false,
                1 => if (drives.B) |d| d == .microHD else false,
                2 => false,
                3 => false,
                else => unreachable,
            },
            .id = @intCast(u2, i),
            .ioMode = .dma,
        };
    }

    // The bottom 2 bits specify the data transfer rate to/from the drive.
    // You want both bits set to zero for a 1.44MB or 1.2MB floppy drive.
    // So generally, you want to set CCR to zero just once, after bootup
    // (because the BIOS may not have done it, unless it booted a floppy disk).
    writeRegister(.datarateSelectRegister, 0x00);

    if ((try execVersion()) != 0x90) {
        // controller isn't a 82077AA
        return error.ControllerNotSupported;
    }

    // Reset the controller
    try resetController();

    // Implied seek, fifo enabled, polling disabled, 8 byte threshold, manufacturer precompensation
    try execConfigure(true, false, true, 8, 0);

    // Lock down configuration over controller resets
    try execLock(true);

    for (allDrives) |*drive| {
        if (!drive.available)
            continue;

        try selectDrive(drive);

        try setMotorPower(.on);

        // wait for the motor to spin up
        Timer.wait(200);

        try execRecalibrate();

        try setMotorPower(.off);
    }
}

/// reads
pub fn read(name: DriveName, startingBlock: usize, data: []u8) !void {
    try selectDrive(&allDrives[@enumToInt(name)]);

    var drive = try getCurrentDrive();

    try setMotorPower(.on);

    // turn motor off after successful or failed operation
    defer setMotorPower(.off) catch unreachable; // error is only when getCurrentDrive() fails and we called that already :)

    Timer.wait(200); // Let motor spin up a bit

    var iterator = try BlockIterator(.mutable).init(startingBlock, data, 512);
    while (iterator.next()) |block| {
        var retries: usize = 5;
        var lastError: anyerror = undefined;
        while (retries > 0) : (retries -= 1) {
            // readBlock(block.block, block.slice) catch |err| {
            //     lastError = err;
            //     continue;
            // };
            try readBlock(block.block, block.slice);
            break;
        }
        if (retries == 0)
            return lastError;
    }
}

fn readBlock(block: u32, buffer: []u8) !void {
    const chs = try CHS.lba2chs(microHDFloppyLayout, block);

    execSeek(@intCast(u8, chs.cylinder), @intCast(u8, chs.head), 1000) catch {
        try execRecalibrate();
        try execSeek(@intCast(u8, chs.cylinder), @intCast(u8, chs.head), 1000);
    };

    try execRead(chs, buffer);
}

fn resetController() !void {
    var dor = @bitCast(DigitalOutputRegister, readRegister(.digitalOutputRegister));

    dor.disableReset = false;
    dor.irqEnabled = true;

    resetIrqCounter();
    writeRegister(.digitalOutputRegister, 0x00);

    dor.disableReset = true;
    writeRegister(.digitalOutputRegister, @bitCast(u8, dor));

    try waitForInterrupt(250);
}

const MotorPower = enum(u1) {
    off = 0,
    on = 1,
};

fn setMotorPower(power: MotorPower) !void {
    var drive = try getCurrentDrive();

    var dor = @bitCast(DigitalOutputRegister, readRegister(.digitalOutputRegister));
    switch (drive.id) {
        0 => dor.motorA = (power == .on),
        1 => dor.motorB = (power == .on),
        2 => dor.motorC = (power == .on),
        3 => dor.motorD = (power == .on),
    }
    writeRegister(.digitalOutputRegister, @bitCast(u8, dor));
}

fn selectDrive(drive: *Drive) !void {
    if (!drive.available)
        return error.DriveNotAvailable;

    var dor = @bitCast(DigitalOutputRegister, readRegister(.digitalOutputRegister));
    dor.driveSelect = drive.id;
    writeRegister(.digitalOutputRegister, @bitCast(u8, dor));

    currentDrive = drive;

    // set 500kbit/s
    writeRegister(.datarateSelectRegister, 0x00);

    // SRT = "Step Rate Time" = time the controller should wait for the head assembly
    // to move between successive cylinders. A reasonable amount of time
    // to allow for this is 3ms for modern 3.5 inch floppy drives. A very safe amount would be 6 to 8ms.
    // To calculate the value for the SRT setting from the given time, use
    // "SRT_value = 16 - (milliseconds * data_rate / 500000)".
    // For a 1.44 MB floppy and 8ms delay this gives "SRT_value = 16 - (8 * 500000 / 500000)" or a parameter value of 8.

    // HLT = "Head Load Time" = time the controller should wait between activating a head and actually performing a read/write.
    // A reasonable value for this is around 10ms. A very safe amount would be 30ms.
    // To calculate the value for the HLT setting from the given time, use
    // "HLT_value = milliseconds * data_rate / 1000000".
    // For a 1.44 MB floppy and a 10ms delay this gives "HLT_value = 10 * 500000 / 1000000" or 5.

    // HUT = "Head Unload Time" = time the controller should wait before deactivating the head.
    // To calculate the value for the HUT setting from a given time, use
    // "HUT_value = milliseconds * data_rate / 8000000".
    // For a 1.44 MB floppy and a 240 mS delay this gives "HUT_value = 24 * 500000 / 8000000" or 15.
    // However, it seems likely that the smartest thing to do is just to set the value to 0 (which is the maximum in any mode).

    try execSpecify(drive.ioMode == .dma, 8, 5, 0);

    // Bugfix: Somehow specify deletes the DMA enabled bit!
    dor = @bitCast(DigitalOutputRegister, readRegister(.digitalOutputRegister));
    dor.irqEnabled = true;
    writeRegister(.digitalOutputRegister, @bitCast(u8, dor));
}

fn execSeek(cylinder: u8, head: u8, timeout: usize) !void {
    var drive = try getCurrentDrive();

    try startCommand(.seek, false, false, false);

    try writeFifo(head << 2 | drive.id);
    try writeFifo(cylinder);

    try waitForInterrupt(5000); // wait a long time for the seek to happen

    try execSenseInterrupt(false);

    const end = Timer.ticks + timeout;
    while (Timer.ticks < end) {
        const msr = @bitCast(MainStatusRegister, readRegister(.mainStatusRegister));

        const isSeeking = switch (drive.id) {
            0 => msr.driveAseeking,
            1 => msr.driveBseeking,
            2 => msr.driveCseeking,
            3 => msr.driveDseeking,
        };
        if (!isSeeking and !msr.commandBusy)
            return; // yay, we're done!
    }
    return error.Timeout;
}

fn execRead(address: CHS.CHS, buffer: []u8) !void {
    const drive = try getCurrentDrive();

    var handle = if (drive.ioMode == .dma) try ISA_DMA.beginRead(2, buffer, .single) else undefined;
    defer if (drive.ioMode == .dma) handle.close();

    // if (drive.ioMode == .portIO) {
    //     var dor = @bitCast(DigitalOutputRegister, readRegister(.digitalOutputRegister));
    //     dor.irqEnabled = false;
    //     writeRegister(.digitalOutputRegister, @bitCast(u8, dor));
    // }
    // defer if (drive.ioMode == .portIO) {
    //     var dor = @bitCast(DigitalOutputRegister, readRegister(.digitalOutputRegister));
    //     dor.irqEnabled = true;
    //     writeRegister(.digitalOutputRegister, @bitCast(u8, dor));
    // };

    TextTerminal.print("start read|");

    try startCommand(.readData, false, true, false);

    try writeFifo(@intCast(u8, (address.head << 2) | drive.id));
    try writeFifo(@intCast(u8, address.cylinder));
    try writeFifo(@intCast(u8, address.head));
    try writeFifo(@intCast(u8, address.sector));
    try writeFifo(0x02); // (all floppy drives use 512bytes per sector))
    try writeFifo(microHDFloppyLayout.sectorCount); // END OF TRACK (end of track, the last sector number on the track)
    try writeFifo(0x1B); // GAP 1
    try writeFifo(0xFF); // (all floppy drives use 512bytes per sector)

    // If !DMA, then
    // read via PIO here!

    if (drive.ioMode == .portIO) {
        for (buffer) |*b, i| {
            const msr = @bitCast(MainStatusRegister, readRegister(.mainStatusRegister));
            std.debug.assert(msr.nonDma);

            b.* = try readFifo();
        }
        Timer.wait(200); // let the FIFO overrun m(
        try waitForInterrupt(100);
    } else {
        TextTerminal.println("wait for dma...");
        while (handle.isComplete() == false) {
            Timer.wait(100);
        }
        TextTerminal.println("dma done...");
        try waitForInterrupt(100);
    }

    TextTerminal.println("read data:");
    for (buffer) |b, i| {
        TextTerminal.print("{X:0>2} ", b);

        if ((i % 16) == 15) {
            TextTerminal.println("");
        }
    }

    // {
    //     const msr = @bitCast(MainStatusRegister, readRegister(.mainStatusRegister));
    //     std.debug.assert(!msr.nonDma);
    // }

    const st0 = try readFifo(); // First result byte = st0 status register
    const st1 = try readFifo(); // Second result byte = st1 status register
    const st2 = try readFifo(); // Third result byte = st2 status register
    const cylinder = try readFifo(); // Fourth result byte = cylinder number
    const endHead = try readFifo(); // Fifth result byte = ending head number
    const endSector = try readFifo(); // Sixth result byte = ending sector number
    const mb2 = try readFifo(); // Seventh result byte = 2

    TextTerminal.println("result: {} / {X} {X} {X} {} {} {} {}", buffer.len, st0, st1, st2, cylinder, endHead, endSector, mb2);

    if (mb2 != 2)
        return error.ExpectedValueWasNotTwo; // this is ... cryptic.
}

fn execRecalibrate() !void {
    var drive = try getCurrentDrive();

    try startCommand(.recalibrate, false, false, false);

    try writeFifo(drive.id);

    try waitForInterrupt(5000);

    try execSenseInterrupt(false);
}

fn execSenseInterrupt(postResetCondition: bool) !void {
    var drive = try getCurrentDrive();

    try startCommand(.senseInterrupt, false, false, false);

    const st0 = try readFifo();
    const cyl = try readFifo(); // this is probably wrong

    // TextTerminal.println("sense returned: st0={X}, cyl={}", st0, cyl);

    // The correct value of st0 after a reset should be 0xC0 | drive number (drive number = 0 to 3).
    // After a Recalibrate/Seek it should be 0x20 | drive number.
    if (postResetCondition) {
        if ((st0 & 0xE0) != 0xC0 | @as(u8, drive.id))
            return error.SenseInterruptFailure;
    } else {
        if ((st0 & 0xE0) != 0x20 | @as(u8, drive.id))
            return error.SenseInterruptFailure;
    }
}

fn execSpecify(enableDMA: bool, stepRateTime: u4, headLoadTime: u7, headUnloadTime: u4) !void {
    try startCommand(.specify, false, false, false);

    try writeFifo((@as(u8, stepRateTime) << 4) | headUnloadTime);
    try writeFifo((@as(u8, headLoadTime) << 1) | (if (enableDMA) @as(u8, 0) else 1));
}

/// Returns one byte. If the value is 0x90, the floppy controller is a 82077AA.
fn execVersion() !u8 {
    try startCommand(.version, false, false, false);
    return try readFifo();
}

fn execConfigure(impliedSeek: bool, disableFifo: bool, disablePolling: bool, fifoIrqThreshold: u5, precompensation: u8) !void {
    if (fifoIrqThreshold < 1 or fifoIrqThreshold > 16)
        return error.ThresholdOutOfRange;
    var data = @as(u8, @intCast(u4, fifoIrqThreshold - 1));
    if (impliedSeek)
        data |= (1 << 6);
    if (disableFifo)
        data |= (1 << 5);
    if (!disablePolling)
        data |= (1 << 4);

    try startCommand(.configure, false, false, false);
    try writeFifo(0x00);
    try writeFifo(data);
    try writeFifo(precompensation);
}

fn execLock(enableLock: bool) !void {
    try startCommand(.lock, enableLock, false, false);

    const result = try readFifo();
    if (result != if (enableLock) @as(u8, 0x10) else 0x00)
        return error.LockFailed;
}

fn startCommand(cmd: FloppyCommand, multiTrack: bool, mfmMode: bool, skipMode: bool) !void {
    var msr = @bitCast(MainStatusRegister, readRegister(.mainStatusRegister));
    if (msr.commandBusy)
        return error.ControllerIsBusy;

    var data = @as(u8, @enumToInt(cmd));
    if (multiTrack)
        data |= 0x80;
    if (mfmMode)
        data |= 0x40;
    if (skipMode)
        data |= 0x20;

    TextTerminal.println("startCommand({}, {}, {}, {})", cmd, multiTrack, mfmMode, skipMode);
    try writeFifo(data);
}

const FifoDirection = enum {
    fdcToHost,
    hostToFdc,
};

fn waitForFifoReady() error{Timeout}!FifoDirection {
    var count: usize = 0;
    while (true) {
        var msr = @bitCast(MainStatusRegister, readRegister(.mainStatusRegister));
        if (msr.fifoReady)
            return if (msr.fifoExpectsRead) return FifoDirection.fdcToHost else FifoDirection.hostToFdc;
        Timer.wait(10);
        count += 1;
        if (count >= 10)
            return error.Timeout;
    }
}

fn writeFifo(value: u8) !void {
    if ((try waitForFifoReady()) != .hostToFdc)
        return error.InvalidFifoOperation;
    writeRegister(.dataFifo, value);
}

fn readFifo() !u8 {
    if ((try waitForFifoReady()) != .fdcToHost)
        return error.InvalidFifoOperation;
    return readRegister(.dataFifo);
}

fn writeRegister(reg: FloppyOutputRegisters, value: u8) void {
    TextTerminal.println("writeRegister({}, 0x{X})", reg, value);
    IO.out(u8, @enumToInt(reg), value);
}

fn readRegister(reg: FloppyInputRegisters) u8 {
    const value = IO.in(u8, @enumToInt(reg));
    // TextTerminal.println("readRegister({}) = 0x{X}", reg, value);
    return value;
}

var irqCounter: u32 = 0;

fn resetIrqCounter() void {
    @atomicStore(u32, &irqCounter, 0, .Release);
}

fn handleIRQ6(cpu: *Interrupts.CpuState) *Interrupts.CpuState {
    TextTerminal.print(".");
    _ = @atomicRmw(u32, &irqCounter, .Add, 1, .SeqCst);
    return cpu;
}

/// waits `timeout` ms for IRQ6
fn waitForInterrupt(timeout: usize) error{Timeout}!void {
    var end = Timer.ticks + timeout;
    while (Timer.ticks < end) {
        if (@atomicRmw(u32, &irqCounter, .Xchg, 0, .SeqCst) > 0) {
            return;
        }
        asm volatile ("hlt");
    }
    return error.Timeout;
}

const FloppyCommand = enum(u5) {
    readTrack = 2, // generates irq6
    specify = 3, // * set drive parameters
    senseDriveStatus = 4,
    writeData = 5, // * write to the disk
    readData = 6, // * read from the disk
    recalibrate = 7, // * seek to cylinder 0
    senseInterrupt = 8, // * ack irq6, get status of last command
    writeDeletedData = 9,
    readId = 10, // generates irq6
    readDeletedData = 12,
    formatTrack = 13, // *
    dumpRegisters = 14,
    seek = 15, // * seek both heads to cylinder x
    version = 16, // * used during initialization, once
    scanEqual = 17,
    perpendicularMode = 18, // * used during initialization, once, maybe
    configure = 19, // * set controller parameters
    lock = 20, // * protect controller params from a reset
    verify = 22,
    scanLowOrEqual = 25,
    scanHighOrEqual = 29,
};

const FloppyOutputRegisters = enum(u16) {
    digitalOutputRegister = 0x3f2,
    tapeDriveRegister = 0x3f3,
    datarateSelectRegister = 0x3f4,
    dataFifo = 0x3f5,
    configurationControlRegister = 0x3f7,
};

const FloppyInputRegisters = enum(u16) {
    statusRegisterA = 0x3f0,
    statusRegisterB = 0x3f1,
    digitalOutputRegister = 0x3f2,
    tapeDriveRegister = 0x3f3,
    mainStatusRegister = 0x3f4,
    dataFifo = 0x3f5,
    digitalInputRegister = 0x3F7,
};

const DigitalOutputRegister = packed struct {
    driveSelect: u2,
    disableReset: bool,
    irqEnabled: bool,
    motorA: bool,
    motorB: bool,
    motorC: bool,
    motorD: bool,
};

const MainStatusRegister = packed struct {
    driveDseeking: bool,
    driveCseeking: bool,
    driveBseeking: bool,
    driveAseeking: bool,
    commandBusy: bool,
    nonDma: bool,
    fifoExpectsRead: bool,
    fifoReady: bool,
};

comptime {
    std.debug.assert(@sizeOf(DigitalOutputRegister) == 1);
    std.debug.assert(@sizeOf(MainStatusRegister) == 1);
}
