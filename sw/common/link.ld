OUTPUT_ARCH(riscv)

MEMORY
{
  ram   (rwx) : ORIGIN = 0x80000000, LENGTH = 0xF8000
  stack (rw)  : ORIGIN = 0x800F8000, LENGTH = 0x08000
}

_min_stack   = 0x1000;
_stack_len   = LENGTH(stack);
_stack_start = ORIGIN(stack) + LENGTH(stack);
_stack_end   = ORIGIN(stack);

_ram_start = ORIGIN(ram);
_ram_end   = ORIGIN(ram) + LENGTH(ram);
_ram_size  = LENGTH(ram);

_entry_point = _vectors_start + 0x80;
ENTRY(_entry_point)

SECTIONS
{
  .text : {
    . = ALIGN(4);
    _vectors_start = .;
    KEEP(*(.vectors))
    _vectors_end = .;
    KEEP(*(.init))
    *(.text)
    *(.text.*)
    . = ALIGN(4);
  } > ram

  .rodata : {
    . = ALIGN(4);
    *(.srodata)
    *(.srodata.*)
    *(.rodata)
    *(.rodata.*)
    . = ALIGN(4);
  } > ram

  .data : {
    . = ALIGN(4);
    _sdata = .;
    *(.sdata)
    *(.sdata.*)
    *(.data)
    *(.data.*)
    . = ALIGN(4);
    _edata = .;
  } > ram

  .bss (NOLOAD) : {
    . = ALIGN(4);
    _bss_start = .;
    *(.sbss)
    *(.sbss.*)
    *(.bss)
    *(.bss.*)
    *(COMMON)
    _bss_end = .;
    . = ALIGN(4);
  } > ram

  .stack (NOLOAD) : {
    . = ALIGN(4);
    . = . + _min_stack;
    . = ALIGN(4);
    _stack = .;
  } > stack
}

uart0_base = 0x10000000;
sim_ctrl   = 0x10002000;
