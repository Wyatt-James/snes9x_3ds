/*
 * This wacky linker script has the specific goal of putting .gsu_segment at a memory address
 * where its address + 28 can be accessed as an ARM32 immediate value (an 8-bit value, rotated
 * right any even number of bits)
 * 
 * This is used to simplify the TESTR14 operation in fxinst_asm.s, as it can be reduced from 
 * 2 instructions to 1 (or, from 1 register + 1 instruction to only 1 instruction)
 * 
 * This is currently disabled because it's madness to design around. Maybe later!
 * This also balloons the file when enabled. Not sure how to fix it.
 */


SECTIONS
{
  .gsu_segment 0x004FFFE4  : {KEEP(*(.bss))}
}

