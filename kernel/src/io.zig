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
