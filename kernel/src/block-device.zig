
/// An interface for block devices. use @fieldParentPtr for accessing the implementation.
pub const BlockDevice = struct {
    pub const Error = error{};

    read: fn (device: *BlockDevice, startingBlock: usize, data: []u8) Error!void,
    write: fn write(device: *BlockDevice, startingBlock: usize, data: []const u8) Error!void,
};
