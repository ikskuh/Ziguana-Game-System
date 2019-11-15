const std = @import("std");
const IO = @import("io.zig");
const Terminal = @import("text-terminal.zig");

const PCI_CONFIG_DATA = 0x0CFC;
const PCI_CONFIG_ADDRESS = 0x0CF8;

fn pci_read(bus: u8, device: u5, function: u3, register: u8) u32 {
    const address = 0x80000000 | (@as(u32, bus) << 16) | (@as(u32, device) << 11) | (@as(u32, function) << 8) | (register & 0xFC);
    IO.outl(PCI_CONFIG_ADDRESS, address);
    return IO.inl(PCI_CONFIG_DATA);
}

fn pci_write(bus: u8, device: u5, function: u3, register: u8, value: u32) void {
    const address = 0x80000000 | (@as(u32, bus) << 16) | (@as(u32, device) << 11) | (@as(u32, function) << 8) | (register & 0xFC);
    IO.outl(PCI_CONFIG_ADDRESS, address);
    IO.outl(PCI_CONFIG_DATA, value);
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

                Terminal.println("{}:{}:{} = {X:0>4}:{X:0>4}", bus, device, function, vendorId, deviceId);

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

                // Terminal.println("\t{}", header);

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
