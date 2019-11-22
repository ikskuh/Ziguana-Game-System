const std = @import("std");

const IO = @import("io.zig");
const TextTerminal = @import("text-terminal.zig");
const Interrupts = @import("interrupts.zig");
const Timer = @import("timer.zig");
const CHS = @import("chs.zig");

const BlockIterator = @import("block-iterator.zig").BlockIterator;

usingnamespace @import("block-device.zig");

fn wait400NS(port: u16) void {
    _ = IO.in(u8, port);
    _ = IO.in(u8, port);
    _ = IO.in(u8, port);
    _ = IO.in(u8, port);
}

const Device = struct {
    const This = @This();

    device: BlockDevice,
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
        DeviceError,
        Timeout,
    };

    fn waitForErrOrReady(device: Device, timeout: usize) Error!void {
        const end = Timer.ticks + timeout;
        while (Timer.ticks < end) {
            const stat = device.status();
            if (stat.hasError)
                return error.DeviceError;
            if (stat.ready)
                return;
        }
        return error.Timeout;
    }

    fn setupParameters(device: Device, lba: u24, blockCount: u8) void {
        if (device.isMaster) {
            IO.out(u8, device.ports.devSelect, 0xE0);
        } else {
            IO.out(u8, device.ports.devSelect, 0xF0);
        }
        IO.out(u8, device.ports.sectors, blockCount);
        IO.out(u8, device.ports.lbaLow, @truncate(u8, lba));
        IO.out(u8, device.ports.lbaMid, @truncate(u8, lba >> 8));
        IO.out(u8, device.ports.lbaHigh, @truncate(u8, lba >> 16));
    }
};

var devs: [8]Device = undefined;

var blockdevs: [8]*BlockDevice = undefined;

pub fn init() error{}![]*BlockDevice {
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
        .{ .port = 0x168, .isMaster = true },
        .{ .port = 0x168, .isMaster = false },
    };

    var deviceCount: usize = 0;

    for (baseports) |cfg, i| {
        devs[i] = Device{
            .device = BlockDevice{
                .icon = .hdd,
                .read = read,
                .write = write,
            },
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
            blockdevs[deviceCount] = &devs[i].device;
            deviceCount += 1;
        }
    }

    return blockdevs[0..deviceCount];
}

pub fn read(dev: *BlockDevice, lba: usize, buffer: []u8) BlockDevice.Error!void {
    const parent = @fieldParentPtr(Device, "device", dev);
    return readBlocks(parent.*, @intCast(u24, lba), buffer);
}

fn readBlocks(device: Device, lba: u24, buffer: []u8) BlockDevice.Error!void {
    if (!device.present)
        return error.DeviceNotPresent;

    if (!std.mem.isAligned(buffer.len, device.blockSize))
        return error.DataIsNotAligned;

    const ports = device.ports;

    const blockCount = @intCast(u8, buffer.len / device.blockSize);

    if (lba + blockCount > device.sectorCount)
        return error.AddressNotOnDevice;

    device.setupParameters(lba, blockCount);
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

pub fn write(dev: *BlockDevice, lba: usize, buffer: []const u8) BlockDevice.Error!void {
    const parent = @fieldParentPtr(Device, "device", dev);
    return writeBlocks(parent.*, @intCast(u24, lba), buffer);
}

fn writeBlocks(device: Device, lba: u24, buffer: []const u8) BlockDevice.Error!void {
    if (!device.present)
        return error.DeviceNotPresent;

    if (!std.mem.isAligned(buffer.len, device.blockSize))
        return error.DataIsNotAligned;

    const ports = device.ports;

    const blockCount = @intCast(u8, buffer.len / device.blockSize);

    if (lba + blockCount > device.sectorCount)
        return error.AddressNotOnDevice;

    device.setupParameters(lba, blockCount);
    IO.out(u8, ports.cmd, 0x30);

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
