ENTRY(_start)
SECTIONS
{
    . = 1M; /* Load to 1 MB */

    __start = .;

    /* Multiboot-Header into first 8 kB */
    .text : {
        KEEP(*(.multiboot));
        *(.text)
    }
    .data ALIGN(4096) : {
        *(.data)
    }
    .rodata ALIGN(4096) : {
        *(.rodata)
    }
    .bss ALIGN(4096) : {
        *(.bss)
    }

    . = ALIGN(4096);
    __end = .;
}
