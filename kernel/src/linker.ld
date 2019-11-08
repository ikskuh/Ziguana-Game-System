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

        /*
        __debug_info_start = .;
        KEEP(*(.debug_info))
        __debug_info_end = .;

        __debug_abbrev_start = .;
        KEEP(*(.debug_abbrev))
        __debug_abbrev_end = .;

        __debug_str_start = .;
        KEEP(*(.debug_str)) 
        __debug_str_end = .;

        __debug_line_start = .;
        KEEP(*(.debug_line)) 
        __debug_line_end = .;

        __debug_ranges_start = .;
        KEEP(*(.debug_ranges))
        __debug_ranges_end = .;
        */

        __debug_info_start = .;
        __debug_info_end = .;
        
        __debug_abbrev_start = .;
        __debug_abbrev_end = .;
        
        __debug_str_start = .;
        __debug_str_end = .;

        __debug_line_start = .;
        __debug_line_end = .;

        __debug_ranges_start = .;
        __debug_ranges_end = .;
    }
    .bss ALIGN(4096) : {
        *(.bss)
    }

    . = ALIGN(4096);
    __end = .;
}
