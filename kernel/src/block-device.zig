/// An interface for block devices. use @fieldParentPtr for accessing the implementation.
pub const BlockDevice = struct {
    pub const Error = error{
        DeviceNotPresent,
        DataIsNotAligned,
        AddressNotOnDevice,
        Timeout,
        DeviceError,
        BlockSizeMustBePowerOfTwo,
        BufferLengthMustBeMultipleOfBlockSize,
    };
    pub const Icon = enum {
        generic,
        floppy,
        hdd,
    };

    /// The icon that will be displayed in the UI.
    icon: Icon,

    /// The number of blocks available on this device.
    blockCount: usize,

    /// Function to read a stream of blocks from the device.
    read: fn (device: *BlockDevice, startingBlock: usize, data: []u8) Error!void,

    /// Function to write a stream of blocks to the device.
    write: fn write(device: *BlockDevice, startingBlock: usize, data: []const u8) Error!void,
};
