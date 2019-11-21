const std = @import("std");

const IO = @import("io.zig");
const TextTerminal = @import("text-terminal.zig");
const Interrupts = @import("interrupts.zig");
const Timer = @import("timer.zig");
const CHS = @import("chs.zig");

const BlockIterator = @import("block-iterator.zig").BlockIterator;

fn wait400NS(port: u16) void {
    _ = IO.in(u8, port);
    _ = IO.in(u8, port);
    _ = IO.in(u8, port);
    _ = IO.in(u8, port);
}

// struct cpu *ata_isr(struct cpu *cpu)
// {
//     // hal_debug("ATA isr!\n");
//     return cpu;
// }

// static int devcnt = 0;

const Device = struct {
    const This = @This();

    blockSize: usize,
    sectorCount: usize,
    isMaster: bool,
    baseport: u16,
    ports: Ports,
    present: bool,

    const Ports = struct {
        data: u16,
        @"error": u16,
        sectors: u16,
        lbaLow: u16,
        lbaMid: u16,
        lbaHigh: u16,
        devSelect: u16,
        status: u16,
        cmd: u16,
        control: u16,
    };

    const Status = packed struct {
        /// Indicates an error occurred. Send a new command to clear it (or nuke it with a Software Reset).
        hasError: bool,

        /// Index. Always set to zero.
        index: u1 = 0,

        /// Corrected data. Always set to zero.
        correctedData: bool = 0,

        /// Set when the drive has PIO data to transfer, or is ready to accept PIO data.
        dataRequest: bool,

        /// Overlapped Mode Service Request.
        serviceRequest: bool,

        /// Drive Fault Error (does not set ERR).
        driveFault: bool,

        /// Bit is clear when drive is spun down, or after an error. Set otherwise.
        ready: bool,

        /// Indicates the drive is preparing to send/receive data (wait for it to clear). In case of 'hang' (it never clears), do a software reset.
        busy: bool,
    };

    comptime {
        std.debug.assert(@sizeOf(Status) == 1);
    }

    fn status(device: This) Status {
        wait400NS(device.ports.status);
        return @bitCast(Status, IO.in(u8, device.ports.status));
    }

    fn isFloating(device: This) bool {
        return IO.in(u8, device.ports.status) == 0xFF;
    }

    fn initialize(device: *This) bool {
        if (device.isFloating())
            return false;

        const ports = device.ports;

        // To use the IDENTIFY command, select a target drive by sending
        // 0xA0 for the master drive, or
        // 0xB0 for the slave, to the "drive select" IO port.
        if (device.isMaster) {
            IO.out(u8, ports.devSelect, 0xA0); // Select Master
        } else {
            IO.out(u8, ports.devSelect, 0xB0); // Select Slave
        }

        // Then set the Sectorcount, LBAlo, LBAmid, and LBAhi IO ports to 0
        IO.out(u8, ports.sectors, 0);
        IO.out(u8, ports.lbaLow, 0);
        IO.out(u8, ports.lbaMid, 0);
        IO.out(u8, ports.lbaHigh, 0);

        // Then send the IDENTIFY command (0xEC) to the Command IO port.
        IO.out(u8, ports.cmd, 0xEC);

        // Then read the Status port again. If the value read is 0, the drive does not
        // exist.
        const statusByte = IO.in(u8, device.ports.status);
        if (statusByte == 0x00) {
            // hal_debug("IDENTIFY failed with STATUS = 0.\n");
            return false;
        }

        // For any other value: poll the Status port (0x1F7) until bit 7 (BSY, value = 0x80)
        // clears. Because of some ATAPI drives that do not follow spec, at this point you
        // need to check the LBAmid and LBAhi ports (0x1F4 and 0x1F5) to see if they are
        // non-zero. If so, the drive is not ATA, and you should stop polling. Otherwise,
        // continue polling one of the Status ports until bit 3 (DRQ, value = 8) sets,
        // or until bit 0 (ERR, value = 1) sets.
        while (device.status().busy) {
            // hal_debug("devbusy\n");
        }

        if ((IO.in(u8, ports.lbaMid) != 0) or (IO.in(u8, ports.lbaHigh) != 0)) {
            // hal_debug("%d, %d\n", IO.in(u8, ports.lbaMid), IO.in(u8, ports.lbaHigh));
            // hal_debug("IDENTIFY failed with INVALID ATA DEVICE.\n");
            return false;
        }

        device.waitForErrOrReady(150) catch return false;

        // At that point, if ERR is clear, the data is ready to read from the Data port
        // (0x1F0).
        // Read 256 16-bit values, and store them.

        var ataData: [256]u16 = undefined;
        for (ataData) |*w| {
            w.* = IO.in(u16, ports.data);
        }

        device.sectorCount = ((@as(u32, ataData[61]) << 16) | ataData[60]);

        return true;
    }

    const Error = error{
        AtaError,
        Timeout,
    };

    fn waitForErrOrReady(device: Device, timeout: usize) Error!void {
        const end = Timer.ticks + timeout;
        while (Timer.ticks < end) {
            const stat = device.status();
            if (stat.hasError)
                return error.AtaError;
            if (stat.ready)
                return;
        }
        return error.Timeout;
    }
};

var devs: [8]Device = undefined;

pub fn init() error{}!void {
    const PortConfig = struct {
        port: u16,
        isMaster: bool,
    };
    const baseports = [_]PortConfig{
        .{ .port = 0x1F0, .isMaster = true },
        .{ .port = 0x1F0, .isMaster = false },
        .{ .port = 0x170, .isMaster = true },
        .{ .port = 0x170, .isMaster = false },
        .{ .port = 0x1E8, .isMaster = true },
        .{ .port = 0x1E8, .isMaster = false },
        .{ .port = 0x168, .isMaster = false },
    };

    for (baseports) |cfg, i| {
        devs[i] = Device{
            .blockSize = 512,
            .baseport = cfg.port,
            .isMaster = cfg.isMaster,
            .ports = Device.Ports{
                .data = devs[i].baseport + 0,
                .@"error" = devs[i].baseport + 1,
                .sectors = devs[i].baseport + 2,
                .lbaLow = devs[i].baseport + 3,
                .lbaMid = devs[i].baseport + 4,
                .lbaHigh = devs[i].baseport + 5,
                .devSelect = devs[i].baseport + 6,
                .status = devs[i].baseport + 7,
                .cmd = devs[i].baseport + 7,
                .control = devs[i].baseport + 518,
            },
            .sectorCount = undefined,
            .present = false,
        };

        devs[i].present = devs[i].initialize();

        if (devs[i].present) {
            TextTerminal.println("ATA{} = {}", i, devs[i]);
        }
    }
}

pub fn read(index: u3, lba: usize, buffer: []u8) !void {
    return readBlocks(devs[index], lba, buffer);
}

fn readBlocks(device: Device, lba: usize, buffer: []u8) !void {
    if (!device.present)
        return error.DeviceNotPresent;

    if (!std.mem.isAligned(buffer.len, device.blockSize))
        return error.DataIsNotAligned;

    const ports = device.ports;

    if (device.sectorCount <= 0)
        return error.NoSectors;

    const blockCount = @intCast(u8, buffer.len / device.blockSize);

    if (device.isMaster) {
        IO.out(u8, ports.devSelect, 0xE0);
    } else {
        IO.out(u8, ports.devSelect, 0xF0);
    }
    IO.out(u8, ports.sectors, blockCount);
    IO.out(u8, ports.lbaLow, @truncate(u8, lba));
    IO.out(u8, ports.lbaMid, @truncate(u8, lba >> 8));
    IO.out(u8, ports.lbaHigh, @truncate(u8, lba >> 16));
    IO.out(u8, ports.cmd, 0x20);

    var block: usize = 0;
    while (block < blockCount) : (block += 1) {
        try device.waitForErrOrReady(150);

        var words: [256]u16 = undefined;

        for (words) |*w| {
            w.* = IO.in(u16, ports.data);

            // WHY?!
            asm volatile ("nop");
            asm volatile ("nop");
            asm volatile ("nop");
            asm volatile ("nop");
        }

        @memcpy(buffer.ptr + device.blockSize * block, @ptrCast([*]const u8, &words), device.blockSize);
    }
}

pub fn write(index: u3, lba: usize, buffer: []const u8) !void {
    return writeBlocks(devs[index], lba, buffer);
}

fn writeBlocks(device: Device, lba: usize, buffer: []const u8) !void {
    if (!device.present)
        return error.DeviceNotPresent;

    if (!std.mem.isAligned(buffer.len, device.blockSize))
        return error.DataIsNotAligned;

    const ports = device.ports;

    if (device.sectorCount <= 0)
        return error.NoSectors;

    const blockCount = @intCast(u8, buffer.len / device.blockSize);

    if (device.isMaster) {
        IO.out(u8, ports.devSelect, 0xE0);
    } else {
        IO.out(u8, ports.devSelect, 0xF0);
    }
    IO.out(u8, ports.sectors, blockCount);
    IO.out(u8, ports.lbaLow, @truncate(u8, lba));
    IO.out(u8, ports.lbaMid, @truncate(u8, lba >> 8));
    IO.out(u8, ports.lbaHigh, @truncate(u8, lba >> 16));
    IO.out(u8, ports.cmd, 0x30);

    // hal_debug("HAL|Write %d\n", lba);

    var block: usize = 0;
    while (block < blockCount) : (block += 1) {
        try device.waitForErrOrReady(150);

        var words: [256]u16 = undefined;

        @memcpy(@ptrCast([*]u8, &words), buffer.ptr + device.blockSize * block, device.blockSize);

        for (words) |w| {
            IO.out(u16, ports.data, w);

            // WHY?!
            asm volatile ("nop");
            asm volatile ("nop");
            asm volatile ("nop");
            asm volatile ("nop");
        }

        IO.out(u8, ports.cmd, 0xE7); // Flush
        try device.waitForErrOrReady(150);
    }
}
