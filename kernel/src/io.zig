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

pub fn inb(port: u16) u8 {
    return asm volatile ("inb  %[port], %[ret]"
        : [ret] "={al}" (-> u8)
        : [port] "{dx}" (port)
    );
}

pub fn inw(port: u16) u16 {
    return asm volatile ("inb  %[port], %[ret]"
        : [ret] "={ax}" (-> u16)
        : [port] "{dx}" (port)
    );
}
