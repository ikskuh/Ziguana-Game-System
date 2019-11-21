const IO = @import("io.zig");

pub const Error = error{
    AlreadyInProgress,
    InvalidAddress,
    EmptyData,
    DataTooLarge,
    InvalidChannel,
    DataCrosses64kBoundary,
};

const TransferMode = packed struct {
    /// which channel to configure
    channel: u2,

    direction: TransferDirection,
    autoInit: bool,

    count: AddressOperation,
    mode: Mode,

    const TransferDirection = enum(u2) {
        verify = 0b00,

        /// this means "RAM to device" (so: CPU *writes* data)
        /// this bitfield is usually described as *read*, as the device reads from
        /// RAM, but i find this more confusing then helping, so i flipped those.
        /// We implement code for a CPU here, not a for the FDC!
        write = 0b10,

        /// this means "device to RAM" (so: CPU *reads* data)
        read = 0b01,
    };

    const AddressOperation = enum(u1) {
        // increment address
        increment = 0,

        // decrement address
        decrement = 1,
    };

    const Mode = enum(u2) {
        demand = 0b00,
        single = 0b01,
        block = 0b10,
        cascade = 0b11,
    };
};

const DmaStatus = struct {
    transferComplete: [4]bool,
    transferRequested: [4]bool,
};

const DmaController = struct {
    start: [4]u16,
    counter: [4]u16,
    currentAddress: [4]u16,
    currentCounter: [4]u16,
    page: [4]u16,

    // Liefert Statusinformationen zum DMA-Controller (siehe dazu unten).
    status: u16,
    // Befehle, die der Controller ausführen soll, werden hierein geschrieben (für eine Liste der Befehle siehe unten).
    command: u16,

    // Durch Schreiben in dieses Register wird ein Reset des entsprechenden Controllers durchgeführt.
    resetPort: u16,

    // Dieses Register ist nötig, um mit 8-Bit-Zugriffen, die 16-Bit-Register zu verwenden.
    // Vor dem Zugriff auf ein 16-Bit-Register sollte eine Null an dieses Register gesendet werden.
    // Dadurch wird der Flip-Flop des Controllers zurückgesetzt und es wird beim anschließenden
    // Zugriff auf ein 16-Bit-Register das Low-Byte adressiert.
    // Der Controller wird das Flip-Flop-Register danach selbstständig auf Eins setzen, wodurch der
    // nächste Zugriff das High-Byte adressiert. Dies ist sowohl beim Lesen als auch beim Schreiben
    // aus bzw. in 16-Bit-Register nötig.
    flipflop: u16,

    // Über dieses Register kann der Übertragungsmodus für einen Channel und einige weitere ergänzende Details zum Befehl,
    // der an das Befehlsregister gesendet wird, festgelegt werden (Für eine genaue Beschreibung siehe unten).
    transferMode: u16,

    // Hierüber kann ein einzelner Channel maskiert, also deaktiviert, werden.
    // Dies sollte immer(!) getan werden, wenn der Controller auf einen Transfer
    // vorbereitet wird, um gleichzeitige Zugriffe von mehreren Programmen zu
    // unterbinden. Die Bits 0 und 1 enthalten dabei die Nummer des Channels,
    // dessen Status geändert werden soll. In Bit 2 wird angegeben, ob der
    // gewählte Channel aktiviert (0) oder deaktiviert (1) werden soll.
    channelMask: u16,

    // Dieses Register hat die gleiche Funktion wie das Maskierungsregister oben, aber mit dem
    // Unterschied, dass mit Hilfe dieses Registers der Zustand meherer Channel gleichzeitig
    // geändert werden kann. Bit 0 bis 3 geben dabei an, ob der entsprechende Channel (0 … 3)
    // aktiviert (0) oder deaktiviert (1) werden soll. Hierbei ist zu beachten, dass nicht aus
    // Versehen ein Channel irrtümlicherweise (de)aktiviert wird, dessen Status eigentlich unverändert bleiben soll.
    multiMask: u16,

    // Dieses Register ermöglicht es, einen Transfer mittels Software auszulösen. Für den Aufbau des zu sendenen Bytes siehe unten.
    request: u16,

    pub fn setTransferMode(dma: DmaController, transferMode: TransferMode) void {
        IO.out(u8, dma.transferMode, @bitCast(u8, transferMode));
    }

    pub fn enable(dma: DmaController, enabled: bool) void {
        IO.out(u8, dma.command, if (enabled) @as(u8, 0b00000100) else 0);
    }

    pub fn maskChannel(dma: DmaController, channel: u2, masked: bool) void {
        IO.out(u8, dma.channelMask, @as(u8, channel) | if (masked) @as(u8, 0b100) else 0);
    }

    pub fn reset(dma: DmaController) void {
        IO.out(u8, dma.resetPort, 0xFF);
    }

    fn resetFlipFlop(dma: DmaController) void {
        IO.out(u8, dma.flipflop, 0xFF);
    }

    pub fn setStartAddress(dma: DmaController, channel: u2, address: u16) void {
        dma.resetFlipFlop();
        IO.out(u8, dma.start[channel], @truncate(u8, address));
        IO.out(u8, dma.start[channel], @truncate(u8, address >> 8));
    }

    pub fn setCounter(dma: DmaController, channel: u2, count: u16) void {
        dma.resetFlipFlop();
        IO.out(u8, dma.counter[channel], @truncate(u8, count));
        IO.out(u8, dma.counter[channel], @truncate(u8, count >> 8));
    }

    pub fn getCurrentAddress(dma: DmaController, channel: u2) u16 {
        dma.resetFlipFlop();

        var value: u16 = 0;
        value |= @as(u16, IO.in(u8, dma.currentAddress[channel]));
        value |= @as(u16, IO.in(u8, dma.currentAddress[channel])) << 16;
        return value;
    }

    pub fn getCurrentCounter(dma: DmaController, channel: u2) u16 {
        dma.resetFlipFlop();

        var value: u16 = 0;
        value |= @as(u16, IO.in(u8, dma.currentCounter[channel]));
        value |= @as(u16, IO.in(u8, dma.currentCounter[channel])) << 16;
        return value;
    }

    pub fn setPage(dma: DmaController, channel: u2, page: u8) void {
        return IO.out(u8, dma.page[channel], page);
    }

    pub fn getPage(dma: DmaController, channel: u2) u8 {
        return IO.in(u8, dma.page[channel]);
    }

    /// Reading this register will clear the TC bits!!!!
    pub fn getStatus(dma: DmaController) DmaStatus {
        const word = IO.in(u8, dma.status);
        return DmaStatus{
            .transferComplete = [4]bool{
                (word & 0b00000001) != 0,
                (word & 0b00000010) != 0,
                (word & 0b00000100) != 0,
                (word & 0b00001000) != 0,
            },
            .transferRequested = [4]bool{
                (word & 0b00010000) != 0,
                (word & 0b00100000) != 0,
                (word & 0b01000000) != 0,
                (word & 0b10000000) != 0,
            },
        };
    }
};

const dmaMaster = DmaController{
    .start = [_]u16{ 0x00, 0x02, 0x04, 0x06 },
    .counter = [_]u16{ 0x01, 0x03, 0x05, 0x07 },
    .currentAddress = [_]u16{ 0x00, 0x02, 0x04, 0x06 },
    .currentCounter = [_]u16{ 0x01, 0x03, 0x05, 0x07 },
    .page = [_]u16{ 0x87, 0x83, 0x81, 0x82 },
    .status = 0x08,
    .command = 0x08,
    .resetPort = 0x0D,
    .flipflop = 0x0C,
    .transferMode = 0x0B,
    .channelMask = 0x0A,
    .multiMask = 0x0F,
    .request = 0x09,
};

const dmaSlave = DmaController{
    .start = [_]u16{ 0xC0, 0xC2, 0xC4, 0xC6 },
    .counter = [_]u16{ 0xC1, 0xC3, 0xC5, 0xC7 },
    .currentAddress = [_]u16{ 0xC0, 0xC2, 0xC4, 0xC6 },
    .currentCounter = [_]u16{ 0xC1, 0xC3, 0xC5, 0xC7 },
    .page = [_]u16{ 0x8F, 0x8B, 0x89, 0x8A },
    .status = 0xD0,
    .command = 0xD0,
    .resetPort = 0xDA,
    .flipflop = 0xD8,
    .transferMode = 0xD6,
    .channelMask = 0xD4,
    .multiMask = 0xDE,
    .request = 0xD2,
};

const Handle = struct {
    dma: *const DmaController,
    channel: u2,

    pub fn isComplete(handle: Handle) bool {
        return handle.dma.getStatus().transferComplete[handle.channel];
    }

    pub fn close(handle: Handle) void {}
};

/// starts a new DMA transfer
fn begin(channel: u3, source_ptr: usize, source_len: usize, mode: TransferMode.Mode, dir: TransferMode.TransferDirection) Error!Handle {
    const handle = Handle{
        .dma = if ((channel & 0b100) != 0) &dmaSlave else &dmaMaster,
        .channel = @truncate(u2, channel),
    };

    if (channel == 0 or channel == 4)
        return error.InvalidChannel;

    if (source_ptr >= 0x1000000)
        return error.InvalidAddress;
    if (source_len == 0)
        return error.EmptyData;
    if (source_len >= 0x10000)
        return error.DataTooLarge;

    if ((source_ptr & 0xFF0000) != ((source_ptr + source_len - 1) & 0xFF0000))
        return error.DataCrosses64kBoundary;

    // We modify the channel, make sure it doesn't do DMA stuff in time
    handle.dma.maskChannel(handle.channel, true);

    handle.dma.setStartAddress(handle.channel, @truncate(u16, source_ptr));
    handle.dma.setCounter(handle.channel, @truncate(u16, source_len - 1));
    handle.dma.setPage(handle.channel, @truncate(u8, source_ptr >> 16));

    handle.dma.setTransferMode(TransferMode{
        .channel = handle.channel,
        .direction = dir,
        .autoInit = false,
        .count = .increment,
        .mode = mode,
    });

    // We have configured our channel, let's go!
    handle.dma.maskChannel(handle.channel, false);
    return handle;
}

/// starts a new DMA transfer
pub fn beginRead(channel: u3, buffer: []u8, mode: TransferMode.Mode) Error!Handle {
    const source_ptr = @ptrToInt(buffer.ptr);
    const source_len = buffer.len;

    return begin(channel, source_ptr, source_len, mode, .read);
}

/// starts a new DMA transfer
pub fn beginWrite(channel: u3, buffer: []const u8, mode: TransferMode.Mode) Error!Handle {
    const source_ptr = @ptrToInt(buffer.ptr);
    const source_len = buffer.len;

    return begin(channel, source_ptr, source_len, mode, .write);
}
