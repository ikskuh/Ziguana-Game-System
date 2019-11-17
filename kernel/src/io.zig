pub fn outb(port: u16, data: u8) void {
    asm volatile ("outb %[data], %[port]"
        :
        : [port] "{dx}" (port),
          [data] "{al}" (data)
    );
}

pub fn outw(port: u16, data: u16) void {
    asm volatile ("outw %[data], %[port]"
        :
        : [port] "{dx}" (port),
          [data] "{ax}" (data)
    );
}

pub fn outl(port: u16, data: u32) void {
    asm volatile ("outl %[data], %[port]"
        :
        : [port] "{dx}" (port),
          [data] "{eax}" (data)
    );
}

pub fn inb(port: u16) u8 {
    return asm volatile ("inb  %[port], %[ret]"
        : [ret] "={al}" (-> u8)
        : [port] "{dx}" (port)
    );
}

pub fn inw(port: u16) u16 {
    return asm volatile ("inw  %[port], %[ret]"
        : [ret] "={ax}" (-> u16)
        : [port] "{dx}" (port)
    );
}

pub fn inl(port: u16) u32 {
    return asm volatile ("inl  %[port], %[ret]"
        : [ret] "={eax}" (-> u32)
        : [port] "{dx}" (port)
    );
}

pub fn out(comptime T: type, port: u16, value: T) void {
    switch (T) {
        u8 => return outb(port, value),
        u16 => return outw(port, value),
        u32 => return outl(port, value),
        else => @compileError("Only u8, u16 or u32 are allowed for port I/O!"),
    }
}

pub fn in(comptime T: type, port: u16) T {
    switch (T) {
        u8 => return inb(port),
        u16 => return inw(port),
        u32 => return inl(port),
        else => @compileError("Only u8, u16 or u32 are allowed for port I/O!"),
    }
}
