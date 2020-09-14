const std = @import("std");
const IO = @import("io.zig");
const Terminal = @import("text-terminal.zig");

const PCI_CONFIG_DATA = 0x0CFC;
const PCI_CONFIG_ADDRESS = 0x0CF8;

fn pci_read(bus: u8, device: u5, function: u3, register: u8) u32 {
    const address = 0x80000000 | (@as(u32, bus) << 16) | (@as(u32, device) << 11) | (@as(u32, function) << 8) | (register & 0xFC);
    IO.out(u32, PCI_CONFIG_ADDRESS, address);
    return IO.in(u32, PCI_CONFIG_DATA);
}

fn pci_write(bus: u8, device: u5, function: u3, register: u8, value: u32) void {
    const address = 0x80000000 | (@as(u32, bus) << 16) | (@as(u32, device) << 11) | (@as(u32, function) << 8) | (register & 0xFC);
    IO.out(u32, PCI_CONFIG_ADDRESS, address);
    IO.out(u32, PCI_CONFIG_DATA, value);
}

pub fn init() void {
    var bus: u8 = 0;
    while (bus < 10) {
        var device: u5 = 0;
        while (true) {
            var function: u3 = 0;
            while (true) {
                const vendorId_deviceId = pci_read(bus, device, function, 0x00);

                const vendorId = @truncate(u16, vendorId_deviceId & 0xFFFF);
                const deviceId = @truncate(u16, vendorId_deviceId >> 16);

                // skip when 0, 1 or FFFF
                switch (vendorId) {
                    0x0000, 0x0001, 0xFFFF => {
                        if (@addWithOverflow(u3, function, 1, &function))
                            break;
                        continue;
                    },
                    else => {},
                }

                Terminal.print("{:0>2}:{:0>2}.{:0>2}: {X:0>4}:{X:0>4}", .{ bus, device, function, vendorId, deviceId });

                const HeaderInfo = packed struct {
                    command: u16,
                    status: u16,
                    revision: u8,
                    classcode: u24,
                    cacheLineSize: u8,
                    latencyTimer: u8,
                    headerType: u7,
                    isMultifunction: bool,
                    bist: u8,
                };

                var infopack = [_]u32{
                    pci_read(bus, device, function, 0x04),
                    pci_read(bus, device, function, 0x08),
                    pci_read(bus, device, function, 0x0C),
                };

                const header = @bitCast(HeaderInfo, infopack);

                Terminal.print("  [{X:0>6}]", .{header.classcode});

                const cc = ClassCodeDescription.lookUp(header.classcode);
                if (cc.class != null) {
                    Terminal.print("  {}", .{cc.programmingInterface orelse cc.subclass orelse cc.class});
                }
                Terminal.println("", .{});
                const desc = DeviceDescription.lookUp(vendorId, deviceId);
                if (desc.vendor != null) {
                    Terminal.println("  {}", .{desc.device orelse desc.vendor});
                }
                if (!header.isMultifunction)
                    break;
                if (@addWithOverflow(u3, function, 1, &function))
                    break;
            }
            if (@addWithOverflow(u5, device, 1, &device))
                break;
        }

        if (@addWithOverflow(u8, bus, 1, &bus))
            break;
    }
}

const pci_device_database = @embedFile("../../data/devices.dat");
const pci_classcode_database = @embedFile("../../data/classes.dat");

const DeviceDescription = struct {
    vendor: ?[]const u8,
    device: ?[]const u8,

    pub fn lookUp(vendorId: u16, deviceId: u16) DeviceDescription {
        var iterator = std.mem.tokenize(pci_device_database, "\n");

        var desc = DeviceDescription{
            .vendor = null,
            .device = null,
        };

        var vendorIdStrBuf = "    ".*;
        const vendorIdStr = std.fmt.bufPrint(vendorIdStrBuf[0..], "{x:0>4}", .{vendorId}) catch unreachable;

        var deviceIdStrBuf = "    ".*;
        const deviceIdStr = std.fmt.bufPrint(deviceIdStrBuf[0..], "{x:0>4}", .{deviceId}) catch unreachable;

        while (iterator.next()) |line| {
            if (desc.vendor != null) {
                // search device
                if (line[0] != '\t') // found another vendor, don't have a matching device!
                    return desc;

                if (std.mem.startsWith(u8, line[1..], deviceIdStr)) {
                    desc.device = line[7..];
                    return desc;
                }
            } else {
                // search vendor
                if (std.mem.startsWith(u8, line, vendorIdStr)) {
                    desc.vendor = line[6..];
                }
            }
        }

        return desc;
    }
};

const ClassCodeDescription = struct {
    class: ?[]const u8,
    subclass: ?[]const u8,
    programmingInterface: ?[]const u8,

    pub fn lookUp(classcode: u24) ClassCodeDescription {
        var iterator = std.mem.tokenize(pci_classcode_database, "\n");

        var desc = ClassCodeDescription{
            .class = null,
            .subclass = null,
            .programmingInterface = null,
        };

        var classCodeStrBuf = "      ".*;
        const classCodeStr = std.fmt.bufPrint(classCodeStrBuf[0..], "{x:0>6}", .{classcode}) catch unreachable;

        while (iterator.next()) |line| {
            if (desc.subclass != null) {
                // search programmingInterface
                if (line[0] != '\t') // found another class, don't have a matching classcode!
                    return desc;
                if (line[1] != '\t') // found another subclass, don't have a matching classcode!
                    return desc;

                if (std.mem.startsWith(u8, line[1..], classCodeStr[4..6])) {
                    desc.programmingInterface = line[5..];
                    return desc;
                }
            } else if (desc.class != null) {
                // search subclass
                if (line[0] != '\t') // found another class, don't have a matching classcode!
                    return desc;

                if (std.mem.startsWith(u8, line[1..], classCodeStr[2..4])) {
                    desc.subclass = line[5..];
                }
            } else {
                // search class
                if (std.mem.startsWith(u8, line, classCodeStr[0..2])) {
                    desc.class = line[4..];
                }
            }
        }

        return desc;
    }
};
