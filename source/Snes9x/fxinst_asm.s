#define vLow   r0
#define rR15   r3
#define rGSU   r4
#define rVCNT  r5
#define rSTAT  r6
#define rARM   r7
#define rPIPE  r8
#define rSREG  r9
#define rDREG  r10
#define rGOTO  fp

@ R0 contains vLow
@ R1 contains GSU.pvPrgBank, for fetching PIPE
@ R2 contains pipe after interpreter
@ R3 contains GSU R15 after interpreter
@ R4 contains the pointer to GSU
@ R5 contains vCounter, the instruction counter
@ R6 contains the GSU STAT register
@ R7 contains the ARM flag register, NZCV flags synchronized with GSU
@ R8 contains the GSU PIPE register
@ R9 contains a pointer to the GSU SREG
@ R10 contains a pointer to the GSU DREG
@ FP contains a pointer to the instruction dispatch table
@ IP contains PIPE after interpreter
@ LR is reserved and must be preserved

@ WYATT_TODO various optimizations:
@ - Optimize TESTR14. See below
@ - Fix doubled loads and stores caused by aliasing
@ - Fix regalloc occasionally reloading R15
@     If CLRFLAGS is called, we can use rSREG as scratch to save a reg
@ - Put the GSU struct in its own over-aligned segment. This would allow us to do certain comparisons, notably the one in TESTR14, in one fewer instruction.
@ - Make a special version of INC and DEC for R15 to save 1 cycle for all other INCs. Might be viable for other instructions too.
@ - Look into the possibility of avoiding the UXTH instructions in IBT/IWT. Shift to top of reg and load with register lsr 16?
@ - Move dispatch's pipe duplication to individual instructions
@ - Remove stack usage. Only plot and rpix use stack due to register pressure, but we could use flag registers or something. Just be careful of early returns.
@ - Store some constants in the stack or GSU struct to make reloading them faster? For instance, R0 pointers for SREG and DREG. Cycle timings might work out. Ensure 64-bit alignment and single-cycle issues if so.

@ Optimize TESTR14. Most TESTR14s are interleaved with CLRFLAGS; only the DREG = 0 part needs to be.
@ Current:
@   Most of the handler
@   Load pointer to R14
@   Check if DREG == that pointer
@   DREG = 0
@   4x conditional loads/stores
@   RET

@ Ideally:
@   Most of the handler
@   Load pointer to R14
@   Check if DREG == that pointer
@   BEQ shared_testr14 (branch forward for statically predicted)
@   DREG = 0
@   RET
@
@  shared_testr14:
@   DREG = 0
@   4x loads/stores
@   RET

@ The handler can be trivially shared to reduce code size with zero impact on cached cycle timings.
@ Cycle timings:
@   Correctly predicted not taken (static, dynamic): 2 cycles branch (folded), ret folded
@   Correctly predicted taken: 2 cycles branch (folded) + 4 cycles handler, ret folded
@   Incorrectly predicted, not taken: pipe flush
@   Incorrectly predicted, taken: pipe flush

    .section .text.fx_run_asm,"ax",%progbits
    .align    2
    .global fx_run_asm
    .syntax unified
    .arm
    .type fx_run_asm, %function
    .cfi_startproc
fx_run_asm:
        push    {rGSU, rVCNT, rSTAT, rARM, rPIPE, rSREG, rDREG, rGOTO, lr}
        sub     sp, sp, #12                              @ Allocate 8 bytes on stack, plus 4 padding
        ldr     rGSU, .L242                              @ Load GSU pointer
        sub     rVCNT, vLow, #1                          @ Decrement vCounter by 1, move to correct variable
        ldr     rR15, [rGSU, #120]                       @ Load GSU.vMode
        ldr     rGOTO, .L242+4                           @ Load GOTO table
      @ cmp     rR15, #3                                 @ If vMode > 3, vMode = 0.  Unreachable.
      @ movhi   r3, #0                                   @  |
        ldr     r2, .L242+8                              @ Load plot/rpix table
        add     r1, r2, rR15, lsl #3                     @ Compute target address
        ldr     r2, [r2, rR15, lsl #3]                   @ Load plot from the table 
        ldr     rR15, [r1, #4]                           @ Load rpix from the table
        ldrh    r1, [rGSU, #28]                          @ READR14: Load R14
      @ cmp     vLow, #0                                 @ If nInstructions == 0, end. Unreachable.
        ldr     vLow, [rGSU, #408]                       @ READR14: Load ROM base pointer
        ldrb    r1, [vLow, r1]                           @ READR14: Load ROM(R14)
        ldrb    rSREG, [rGSU, #61]                       @ Load reserved regs
        ldrb    rDREG, [rGSU, #60]                       @  |
        ldrh    rSTAT, [rGSU, #64]                       @  |
        ldr     rARM, [rGSU, #68]                        @  |
        ldrb    rPIPE, [rGSU, #62]                       @  |
        add     rSREG, rGSU, rSREG, lsl #1               @  |
        add     rDREG, rGSU, rDREG, lsl #1               @  V
        strb    r1, [rGSU, #38]                          @ READR14: Store to ROMBUFFER
        str     r2, [rGOTO, #2352]                       @ Populate GOTO table
        str     r2, [rGOTO, #304]                        @  |
        str     rR15, [rGOTO, #3376]                     @  |
        str     rR15, [rGOTO, #1328]                     @  V
      @ beq     loop_end                                 @ End if nInstructions == 0. Unreachable.
        ldr     r1, [rGSU, #412]                         @ FETCHPIPE: Load GSU.pvPrgBank. Taken from loop_dispatch to save a cycle.
loop_dispatch:
        ldrh    rR15, [rGSU, #30]                        @ FETCHPIPE: Load R15
        ldrb    ip, [r1, rR15]                           @ FETCHPIPE
        and     r2, rSTAT, #768                          @ Get opcode mode bits
        orr     r2, rPIPE, r2                            @ Compute opcode
        and     vLow, rPIPE, #15                         @ Compute vLow
        mov     rPIPE, ip                                @ Duplicate PIPE. WYATT_TODO Probably better to move this to the individual instructions.
        ldr     pc, [rGOTO, r2, lsl #2]                  @ Branch to handler

@ GETBS: get sign extended byte from ROM at address R14
handle_fx_getbs:
        add     rR15, rR15, #1                           @ R15++
        strh    rR15, [rGSU, #30]                        @ Store R15
        ldrsb   rR15, [rGSU, #38]                        @ R15 = SEX8(ROMBUFFER)
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = R0
        strh    rR15, [rDREG]                            @ Store value to DREG
        add     rR15, rGSU, #28                          @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        ldrheq  rR15, [rGSU, #28]                        @  |
        ldreq   r2, [rGSU, #408]                         @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: clear STAT
        ldrbeq  rR15, [r2, rR15]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = R0
        strbeq  rR15, [rGSU, #38]                        @  |
        @ Fallthrough to loop head. WYATT_TODO the most common handler should go here.

loop_head:
        subs    rVCNT, rVCNT, #1                         @ Decrement vCounter and exit if it underflows
        ldr     r1, [rGSU, #412]                         @ FETCHPIPE: Load GSU.pvPrgBank. Taken from loop_dispatch to save a cycle.
        bcs     loop_dispatch                            @ 
loop_end:
        sub     rR15, rSREG, rGSU                        @ Save reserved registers
        asr     rR15, rR15, #1                           @  |
        strb    rR15, [rGSU, #61]                        @  |
        sub     rR15, rDREG, rGSU                        @  |
        asr     rR15, rR15, #1                           @  |
        strh    rSTAT, [rGSU, #64]                       @  |
        str     rARM, [rGSU, #68]                        @  |
        strb    rPIPE, [rGSU, #62]                       @  |
        strb    rR15, [rGSU, #60]                        @  V
        add     sp, sp, #12                              @ Free space on stack
        pop     {rGSU, rVCNT, rSTAT, rARM, rPIPE, rSREG, rDREG, rGOTO, pc} @ Return

@ STOP: stop GSU execution
handle_fx_stop:
        add     rR15, rR15, #1                           @ R15++
        strh    rR15, [rGSU, #30]                        @ Store R15
        mov     rR15, #0                                 @ plotOptionReg = 0
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        ldr     r2, [rGSU, #100]                         @ R2 = GSU.pvRegisters[GSU_CFGR]
        bic     rSTAT, rSTAT, #32                        @ CF(G)
        ldrsb   r2, [r2, #55]                            @ R2 = GSU_CFGR
        mov     rPIPE, #1                                @ PIPE = 1
        cmp     r2, #0                                   @ If GSU_CFGR == 0, Raise IRQ
        orrge   rSTAT, rSTAT, #32768                     @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @  |
        strb    rR15, [rGSU, #36]                        @ Store plotOptionReg
        b       loop_end                                 @ 

@ PLOT 2BIT: Draws a pixel at R1,R2 (X,Y), using GSU.vColorReg as the source
handle_fx_plot_2bit:
        add     rR15, rR15, #1                           @ R15++
        ldrh    r1, [rGSU, #2]                           @ Load X
        ldr     r2, [rGSU, #388]                         @ Load screen height
        strh    rR15, [rGSU, #30]                        @ Store R15
        ldrb    rR15, [rGSU, #4]                         @ Load Y
        cmp     rR15, r2                                 @ Test Y > screen height
        add     r2, r1, #1                               @ X++
        strh    r2, [rGSU, #2]                           @  |
        bcs     handle_fx_plot_4bit.return               @ If Y > screen height, return
        ldrb    vLow, [rGSU, #36]                        @ Load vPlotOptionReg
        ldrb    r2, [rGSU, #37]                          @ Load vColorReg
        tst     vLow, #2                                 @ Test vPlotOptionReg & 0x02
        uxtb    r1, r1                                   @ Truncate X to 8-bit
        bne     handle_fx_plot_2bit.L237                 @ If vPlotOptionReg & 0x02, potentially use upper nibble of color

        @ vLow is vPlotOptionReg
        @ R1 is X
        @ R2 is color
        @ rR15 is Y
        @ IP is free
.L15:
        and     vLow, vLow, #1                           @ If (4-bit color) | (vPlotOptionReg & 1) is 0, return
        orrs    vLow, vLow, r2, lsl #28                  @  |
        beq     handle_fx_plot_4bit.return               @  |
        lsr     vLow, r1, #3                             @ vLow = GSU.x[X >> 3]
        add     vLow, rGSU, vLow, lsl #2                 @  |
        ldr     vLow, [vLow, #260]                       @  |
        mov     ip, #128                                 @ IP = BIT(7) >> (X & 7)
        and     r1, r1, #7                               @  |
        lsr     ip, ip, r1                               @  |
        lsr     r1, rR15, #3                             @ R1 = GSU.apvScreen[Y >> 3]
        add     r1, rGSU, r1, lsl #2                     @  |
        ldr     r1, [r1, #132]                           @  |
        lsl     rR15, rR15, #29                          @ R15 = pixel 0 pointer
        add     rR15, vLow, rR15, lsr #28                @  |  Shifted math is equivalent to vLow + ((y & 7) << 1)
        add     rR15, rR15, r1                           @  |

        @ vLow is free
        @ R1 is free
        @ R2 is color
        @ rR15 is pixel 0 Pointer
        @ IP is the pixel mask

        @ The pointer seems to always be 2-byte aligned, so this is a free speedup
        ldrh    vLow, [rR15, #0]                         @ Load pixel pair 1
        tst     r2, #1                                   @ Pixel conditional
        orrne   vLow, vLow, ip                           @  |
        biceq   vLow, vLow, ip                           @  |
        tst     r2, #2                                   @ Pixel conditional
        orrne   vLow, vLow, ip, lsl #8                   @  |
        biceq   vLow, vLow, ip, lsl #8                   @  |
        strh    vLow, [rR15, #0]                         @ Store pixel pair
        b       handle_fx_plot_4bit.return               @ 

@ RPIX 2BIT: Reads the color of pixel R1,R2 (X, Y) and stores to DREG.
handle_fx_rpix_2bit:
        add     rR15, rR15, #1                           @ R15++
        ldr     r1, [rGSU, #388]                         @ R1 = screen height
        strh    rR15, [rGSU, #30]                        @ Store R15
        ldrb    rR15, [rGSU, #4]                         @ R15 = Y
        cmp     rR15, r1                                 @ Test Y > screen height
        ldrb    r1, [rGSU, #2]                           @ R1 = X
        bcs     handle_fx_rpix_8bit.return               @ If Y > screen height, return
        
        @ R1 is X, rR15 is Y
        lsr     vLow, r1, #3                             @ vLow = GSU.x[X >> 3]
        add     vLow, rGSU, vLow, lsl #2                 @  |
        ldr     vLow, [vLow, #260]                       @  |
        mov     ip, #128                                 @ IP = BIT(7) >> (X & 7)
        and     r1, r1, #7                               @  |
        lsr     ip, ip, r1                               @  |
        lsr     r1, rR15, #3                             @ R1 = GSU.apvScreen[Y >> 3]
        add     r1, rGSU, r1, lsl #2                     @  |
        ldr     r1, [r1, #132]                           @  |
        lsl     rR15, rR15, #29                          @ R15 = pixel 0 pointer
        add     rR15, vLow, rR15, lsr #28                @  |  Shifted math is equivalent to vLow + ((y & 7) << 1)
        add     rR15, rR15, r1                           @  |

        @ rR15 is pixel 0 Pointer, IP is the pixel mask
        mov vLow, #0                                     @ Initial result

        ldrb r1, [rR15, #0]                              @ Pixel 0
        tst ip, r1                                       @  |
        orrne vLow, vLow, #1                             @  |

        ldrb r1, [rR15, #1]                              @ Pixel 1
        tst ip, r1                                       @  |
        orrne vLow, vLow, #2                             @  |

        strh vLow, [rDREG]                               @ Store result
        b handle_fx_rpix_8bit.return

@ PLOT 4BIT: Draws a pixel at R1,R2 (X,Y), using GSU.vColorReg as the source
handle_fx_plot_4bit:
        add     rR15, rR15, #1                           @ R15++
        ldrh    r1, [rGSU, #2]                           @ Load X
        ldr     r2, [rGSU, #388]                         @ Load screen height
        strh    rR15, [rGSU, #30]                        @ Store R15
        ldrb    rR15, [rGSU, #4]                         @ Load Y
        cmp     rR15, r2                                 @ Test Y > screen height
        add     r2, r1, #1                               @ X++
        strh    r2, [rGSU, #2]                           @  |
        bcs     handle_fx_plot_4bit.return               @ If Y > screen height, return
        ldrb    vLow, [rGSU, #36]                        @ Load vPlotOptionReg
        ldrb    r2, [rGSU, #37]                          @ Load vColorReg
        tst     vLow, #2                                 @ Test vPlotOptionReg & 0x02
        uxtb    r1, r1                                   @ Truncate X to 8-bit
        bne     handle_fx_plot_4bit.L238                 @ If vPlotOptionReg & 0x02, potentially use upper nibble of color

        @ vLow is vPlotOptionReg
        @ R1 is X
        @ R2 is color
        @ rR15 is Y
        @ IP is free
.L25:
        and     vLow, vLow, #1                           @ If (4-bit color) | (vPlotOptionReg & 1) is 0, return
        orrs    vLow, vLow, r2, lsl #28                  @  |
        beq     handle_fx_plot_4bit.return               @  |
        lsr     vLow, r1, #3                             @ vLow = GSU.x[X >> 3]
        add     vLow, rGSU, vLow, lsl #2                 @  |
        ldr     vLow, [vLow, #260]                       @  |
        mov     ip, #128                                 @ IP = BIT(7) >> (X & 7)
        and     r1, r1, #7                               @  |
        lsr     ip, ip, r1                               @  |
        lsr     r1, rR15, #3                             @ R1 = GSU.apvScreen[Y >> 3]
        add     r1, rGSU, r1, lsl #2                     @  |
        ldr     r1, [r1, #132]                           @  |
        lsl     rR15, rR15, #29                          @ R15 = pixel 0 pointer
        add     rR15, vLow, rR15, lsr #28                @  |  Shifted math is equivalent to vLow + ((y & 7) << 1)
        add     rR15, rR15, r1                           @  |

        @ vLow is free
        @ R1 is free
        @ R2 is color
        @ rR15 is pixel 0 Pointer
        @ IP is the pixel mask

        @ The pointer seems to always be 2-byte aligned, so this is a free speedup
        ldrh    vLow, [rR15, #0]                         @ Load pixel pair 1
        tst     r2, #1                                   @ Pixel conditional
        orrne   vLow, vLow, ip                           @  |
        biceq   vLow, vLow, ip                           @  |
        tst     r2, #2                                   @ Pixel conditional
        orrne   vLow, vLow, ip, lsl #8                   @  |
        biceq   vLow, vLow, ip, lsl #8                   @  |
        strh    vLow, [rR15, #0]                         @ Store pixel pair

        ldrh    vLow, [rR15, #16]                        @ Load pixel pair 2
        tst     r2, #4                                   @ Pixel conditional
        orrne   vLow, vLow, ip                           @  |
        biceq   vLow, vLow, ip                           @  |
        tst     r2, #8                                   @ Pixel conditional
        orrne   vLow, vLow, ip, lsl #8                   @  |
        biceq   vLow, vLow, ip, lsl #8                   @  |
        strh    vLow, [rR15, #16]                        @ Store pixel pair

@ WYATT_TODO could tail-merge this with 2bit for free
handle_fx_plot_4bit.return:
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0. WYATT_TODO move this to the return statement and branch there instead of to loop_head. This solves the UNLIKELY cases and allows us to use these two regs as scratch.
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       loop_head                                @ 

@ RPIX 4BIT: Reads the color of pixel R1,R2 (X, Y) and stores to DREG.
handle_fx_rpix_4bit:
        add     rR15, rR15, #1                           @ R15++
        ldr     r1, [rGSU, #388]                         @ R1 = screen height
        strh    rR15, [rGSU, #30]                        @ Store R15
        ldrb    rR15, [rGSU, #4]                         @ R15 = Y
        cmp     rR15, r1                                 @ Test Y > screen height
        ldrb    r1, [rGSU, #2]                           @ R1 = X
        bcs     handle_fx_rpix_8bit.return               @ If Y > screen height, return
        
        @ R1 is X, rR15 is Y
        lsr     vLow, r1, #3                             @ vLow = GSU.x[X >> 3]
        add     vLow, rGSU, vLow, lsl #2                 @  |
        ldr     vLow, [vLow, #260]                       @  |
        mov     ip, #128                                 @ IP = BIT(7) >> (X & 7)
        and     r1, r1, #7                               @  |
        lsr     ip, ip, r1                               @  |
        lsr     r1, rR15, #3                             @ R1 = GSU.apvScreen[Y >> 3]
        add     r1, rGSU, r1, lsl #2                     @  |
        ldr     r1, [r1, #132]                           @  |
        lsl     rR15, rR15, #29                          @ R15 = pixel 0 pointer
        add     rR15, vLow, rR15, lsr #28                @  |  Shifted math is equivalent to vLow + ((y & 7) << 1)
        add     rR15, rR15, r1                           @  |

        @ rR15 is pixel 0 Pointer, IP is the pixel mask
        mov vLow, #0                                     @ Initial result, sets Z flag

        ldrb r1, [rR15, #0]                              @ Pixel 0
        tst ip, r1                                       @  |
        orrne vLow, vLow, #1                             @  |
        ldrb r2, [rR15, #1]                              @ Pixel 1
        tst ip, r2                                       @  |
        orrne vLow, vLow, #2                             @  |
        ldrb r1, [rR15, #16]                             @ Pixel 2
        tst ip, r1                                       @  |
        orrne vLow, vLow, #4                             @  |
        ldrb r2, [rR15, #17]                             @ Pixel 3
        tst ip, r2                                       @  |
        orrne vLow, vLow, #8                             @  |

        strh vLow, [rDREG]                               @ Store result
        b handle_fx_rpix_8bit.return

@ PLOT 8BIT: Draws a pixel at R1,R2 (X,Y), using GSU.vColorReg as the source
handle_fx_plot_8bit:
        add     rR15, rR15, #1                           @ 
        ldrh    r2, [rGSU, #2]                           @ 
        ldr     r1, [rGSU, #388]                         @ 
        strh    rR15, [rGSU, #30]                        @ 
        ldrb    rR15, [rGSU, #4]                         @ 
        add     rSREG, rGSU, #0                          @ 
        cmp     rR15, r1                                 @ 
        add     r1, r2, #1                               @ 
        mov     rDREG, rSREG                             @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        strh    r1, [rGSU, #2]                           @ 
        bcs     loop_head                                @ 
        ldrb    r1, [rGSU, #36]                          @ 
        tst     r1, #16                                  @ 
        and     vLow, r1, #1                             @ 
        ldrb    r1, [rGSU, #37]                          @ 
        beq     handle_fx_plot_8bit.L239                 @ 
        orrs    vLow, r1, vLow                           @ 
        beq     loop_head                                @ 
.L40:
        mov     vLow, #128                               @ 
        uxtb    r2, r2                                   @ 
        lsr     ip, r2, #3                               @ 
        and     r2, r2, #7                               @ 
        add     ip, rGSU, ip, lsl #2                     @ 
        asr     r2, vLow, r2                             @ 
        lsr     vLow, rR15, #3                           @ 
        ldr     ip, [ip, #260]                           @ 
        add     vLow, rGSU, vLow, lsl #2                 @ 
        lsl     rR15, rR15, #1                           @ 
        ldr     vLow, [vLow, #132]                       @ 
        and     rR15, rR15, #14                          @ 
        add     ip, rR15, ip                             @ 
        uxtb    r2, r2                                   @ 
        ldrb    rR15, [vLow, ip]                         @ 
        str     r2, [sp]                                 @ 
        mov     r2, vLow                                 @ 
        str     vLow, [sp, #4]                           @ 
        mov     vLow, rR15                               @ 
        add     rR15, r2, ip                             @ 
        ldr     r2, [sp]                                 @ 
        tst     r1, #1                                   @ 
        orrne   vLow, vLow, r2                           @ 
        biceq   vLow, vLow, r2                           @ 
        ldr     r2, [sp, #4]                             @ 
        tst     r1, #2                                   @ 
        strb    vLow, [r2, ip]                           @ 
        ldrb    vLow, [rR15, #1]                         @ 
        ldr     r2, [sp]                                 @ 
        orrne   vLow, r2, vLow                           @ 
        biceq   vLow, vLow, r2                           @ 
        strb    vLow, [rR15, #1]                         @ 
        ldr     r2, [sp]                                 @ 
        ldrb    vLow, [rR15, #16]                        @ 
        tst     r1, #4                                   @ 
        orrne   vLow, r2, vLow                           @ 
        biceq   vLow, vLow, r2                           @ 
        strb    vLow, [rR15, #16]                        @ 
        ldr     r2, [sp]                                 @ 
        ldrb    vLow, [rR15, #17]                        @ 
        tst     r1, #8                                   @ 
        orrne   vLow, r2, vLow                           @ 
        biceq   vLow, vLow, r2                           @ 
        strb    vLow, [rR15, #17]                        @ 
        ldr     r2, [sp]                                 @ 
        ldrb    vLow, [rR15, #32]                        @ 
        tst     r1, #16                                  @ 
        orrne   vLow, r2, vLow                           @ 
        biceq   vLow, vLow, r2                           @ 
        strb    vLow, [rR15, #32]                        @ 
        ldr     r2, [sp]                                 @ 
        ldrb    vLow, [rR15, #33]                        @ 
        tst     r1, #32                                  @ 
        orrne   vLow, r2, vLow                           @ 
        biceq   vLow, vLow, r2                           @ 
        strb    vLow, [rR15, #33]                        @ 
        ldr     r2, [sp]                                 @ 
        ldrb    vLow, [rR15, #48]                        @ 
        tst     r1, #64                                  @ 
        orrne   vLow, r2, vLow                           @ 
        biceq   vLow, vLow, r2                           @ 
        ldr     r2, [sp]                                 @ 
        tst     r1, #128                                 @ 
        ldrb    r1, [rR15, #49]                          @ 
        strb    vLow, [rR15, #48]                        @ 
        orrne   r2, r2, r1                               @ 
        biceq   r2, r1, r2                               @ 
        strb    r2, [rR15, #49]                          @ 
        b       loop_head                                @ 

@ RPIX 8BIT: Reads the color of pixel R1,R2 (X, Y) and stores to DREG.
handle_fx_rpix_8bit:
        add     rR15, rR15, #1                           @ R15++
        ldr     r1, [rGSU, #388]                         @ R1 = screen height
        strh    rR15, [rGSU, #30]                        @ Store R15
        ldrb    rR15, [rGSU, #4]                         @ R15 = Y
        cmp     rR15, r1                                 @ Test Y > screen height
        ldrb    r1, [rGSU, #2]                           @ R1 = X
        bcs     handle_fx_rpix_8bit.return               @ If Y > screen height, return
        
        @ R1 is X, rR15 is Y
        lsr     vLow, r1, #3                             @ vLow = GSU.x[X >> 3]
        add     vLow, rGSU, vLow, lsl #2                 @  |
        ldr     vLow, [vLow, #260]                       @  |
        mov     ip, #128                                 @ IP = BIT(7) >> (X & 7)
        and     r1, r1, #7                               @  |
        lsr     ip, ip, r1                               @  |
        lsr     r1, rR15, #3                             @ R1 = GSU.apvScreen[Y >> 3]
        add     r1, rGSU, r1, lsl #2                     @  |
        ldr     r1, [r1, #132]                           @  |
        lsl     rR15, rR15, #29                          @ R15 = pixel 0 pointer
        add     rR15, vLow, rR15, lsr #28                @  |  Shifted math is equivalent to vLow + ((y & 7) << 1)
        add     rR15, rR15, r1                           @  |

        @ rR15 is pixel 0 Pointer, IP is the pixel mask
        mov vLow, #0                                     @ Initial result

        ldrb r1, [rR15, #0]                              @ Pixel 0
        tst ip, r1                                       @  |
        orrne vLow, vLow, #1                             @  |
        ldrb r2, [rR15, #1]                              @ Pixel 1
        tst ip, r2                                       @  |
        orrne vLow, vLow, #2                             @  |
        ldrb r1, [rR15, #16]                             @ Pixel 2
        tst ip, r1                                       @  |
        orrne vLow, vLow, #4                             @  |
        ldrb r2, [rR15, #17]                             @ Pixel 3
        tst ip, r2                                       @  |
        orrne vLow, vLow, #8                             @  |
        ldrb r1, [rR15, #32]                             @ Pixel 4
        tst ip, r1                                       @  |
        orrne vLow, vLow, #16                            @  |
        ldrb r2, [rR15, #33]                             @ Pixel 5
        tst ip, r2                                       @  |
        orrne vLow, vLow, #32                            @  |
        ldrb r1, [rR15, #48]                             @ Pixel 6
        tst ip, r1                                       @  |
        orrne vLow, vLow, #64                            @  |
        ldrb r2, [rR15, #49]                             @ Pixel 7
        tst ip, r2                                       @  |
        orrne vLow, vLow, #128                           @  |

        strh vLow, [rDREG]                               @ Store result
        cmp vLow, #0                                     @ Update ARM Z flag
        bic rARM, rARM, #1073741824                      @  |
        orreq rARM, rARM, #1073741824                    @  |
        
handle_fx_rpix_8bit.return:        
        add     rR15, rGSU, #28                          @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        ldrheq  rR15, [rGSU, #28]                        @  |
        ldreq   r2, [rGSU, #408]                         @  |
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strbeq  rR15, [rGSU, #38]                        @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       loop_head                                @ 

@ NOP: Clears flags and advances R15 
handle_fx_nop:
        add     rR15, rR15, #1                           @ R15++
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        strh    rR15, [rGSU, #30]                        @ Store R15
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       loop_head                                @ 

@ CACHE: reintialize GSU cache
handle_fx_cache:
        ldrh    r1, [rGSU, #32]                          @ r1 = GSU.vCacheBaseReg
        bic     r2, rR15, #15                            @ r2 = R15 & 0xfff0
        cmp     r1, r2                                   @ If address range is not equal, cache needs a reload
        beq     .cache_test_active                       @ If address range is equal, check if cache is active
@ Reload cache
.reload_cache:
        strh    r2, [rGSU, #32]                          @ GSU.vCacheBaseReg = R15 & 0xfff0
        mov     r2, #0                                   @ 
        str     r2, [rGSU, #72]                          @ GSU.vCacheFlags = 0
        mov     r2, #1                                   @ 
        strb    r2, [rGSU, #1456]                        @ GSU.bCacheActive = TRUE
.skip_cache_reload:
        add     rR15, rR15, #1                           @ R15++
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        strh    rR15, [rGSU, #30]                        @ Store R15
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       loop_head                                @ 

@ LSR: logical shift right
handle_fx_lsr:
        ldrh    r2, [rGSU, #30]                          @ Load R15 into R2 WYATT_TODO this is inefficient! Does inline ASM break regalloc?
        ldrh    rR15, [rSREG]                            @ Load SREG
        add     r2, r2, #1                               @ R15++
        strh    r2, [rGSU, #30]                          @ Store R15
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        lsrs    rR15, rR15, #1                           @ Do the rightshift
        mrs     rARM, cpsr                               @ Read flags from CPSR
        strh    rR15, [rDREG]                            @ Store result into DREG
        add     rR15, rGSU, #28                          @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        ldrheq  rR15, [rGSU, #28]                        @  |
        ldreq   r2, [rGSU, #408]                         @  |
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strbeq  rR15, [rGSU, #38]                        @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       loop_head                                @ 

@ ROL: rotate left
handle_fx_rol:
        ldrh    r2, [rGSU, #30]                          @ Load R15 into R2 WYATT_TODO this is inefficient! Does inline ASM break regalloc?
        ldrh    rR15, [rSREG]                            @ Load SREG
        add     r2, r2, #1                               @ R15++
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        lsl     rR15, rR15, #16                          @ Shift value into upper half of reg
        orrcs   rR15, rR15, #32768                       @ If carry is set, set bit 15
        lsls    rR15, rR15, #1                           @ Shift left 1 to set carry
        mrs     rARM, cpsr                               @ Read flags from CPSR
        lsr     rR15, rR15, #16                          @ Shift down from top half of register
        strh    r2, [rGSU, #30]                          @ Store R15
        strh    rR15, [rDREG]                            @ Store result
        add     rR15, rGSU, #28                          @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        ldrheq  rR15, [rGSU, #28]                        @  |
        ldreq   r2, [rGSU, #408]                         @  |
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strbeq  rR15, [rGSU, #38]                        @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       loop_head                                @ 

@ BRA: unconditional branch
handle_fx_bra:
        add     rR15, rR15, #1                           @ R15++
        uxth    rR15, rR15                               @ Wrap R15 at 16 bits
        sxtb    r2, ip                                   @ Sign-extend saved PIPE
        add     r2, rR15, r2                             @ Add PIPE to R15
        ldrb    rPIPE, [r1, rR15]                        @ FETCHPIPE
        strh    r2, [rGSU, #30]                          @ Store destination to R15
        b       loop_head                                @ 

@ BGE: branch if greater or equal
handle_fx_bge:
        add     rR15, rR15, #1                           @ R15++
        uxth    r2, rR15                                 @ Wrap R15 at 16 bits
        ldrb    rPIPE, [r1, r2]                          @ FETCHPIPE
        sxtb    ip, ip                                   @ Sign-extend saved PIPE
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        addge   rR15, rR15, ip                           @ Handle branch
        addlt   rR15, rR15, #1                           @ 
        strh    rR15, [rGSU, #30]                        @ Store destination to R15
        b       loop_head                                @ 

@ BLT: branch if less than
handle_fx_blt:
        add     rR15, rR15, #1                           @  R15++
        uxth    r2, rR15                                 @  Wrap R15 at 16 bits
        ldrb    rPIPE, [r1, r2]                          @  FETCHPIPE
        sxtb    ip, ip                                   @  Sign-extend saved PIPE
        msr     cpsr_f, rARM                             @  Load flags into CPSR
        addlt   rR15, rR15, ip                           @  Handle branch
        addge   rR15, rR15, #1                           @  
        strh    rR15, [rGSU, #30]                        @  Store destination to R15
        b       loop_head                                @ 

@ BNE: branch if not equal
handle_fx_bne:
        add     rR15, rR15, #1                           @  R15++
        uxth    r2, rR15                                 @  Wrap R15 at 16 bits
        ldrb    rPIPE, [r1, r2]                          @  FETCHPIPE
        sxtb    ip, ip                                   @  Sign-extend saved PIPE
        msr     cpsr_f, rARM                             @  Load flags into CPSR
        addne   rR15, rR15, ip                           @  Handle branch
        addeq   rR15, rR15, #1                           @  
        strh    rR15, [rGSU, #30]                        @  Store destination to R15
        b       loop_head                                @ 

@ BEQ: branch if equal
handle_fx_beq:
        add     rR15, rR15, #1                           @  R15++
        uxth    r2, rR15                                 @  Wrap R15 at 16 bits
        ldrb    rPIPE, [r1, r2]                          @  FETCHPIPE
        sxtb    ip, ip                                   @  Sign-extend saved PIPE
        msr     cpsr_f, rARM                             @  Load flags into CPSR
        addeq   rR15, rR15, ip                           @  Handle branch
        addne   rR15, rR15, #1                           @  
        strh    rR15, [rGSU, #30]                        @  Store destination to R15
        b       loop_head                                @ 

@ BPL: branch if positive or zero
handle_fx_bpl:
        add     rR15, rR15, #1                           @  R15++
        uxth    r2, rR15                                 @  Wrap R15 at 16 bits
        ldrb    rPIPE, [r1, r2]                          @  FETCHPIPE
        sxtb    ip, ip                                   @  Sign-extend saved PIPE
        msr     cpsr_f, rARM                             @  Load flags into CPSR
        addpl   rR15, rR15, ip                           @  Handle branch
        addmi   rR15, rR15, #1                           @  
        strh    rR15, [rGSU, #30]                        @  Store destination to R15
        b       loop_head                                @ 

@ BMI: branch if negative
handle_fx_bmi:
        add     rR15, rR15, #1                           @  R15++
        uxth    r2, rR15                                 @  Wrap R15 at 16 bits
        ldrb    rPIPE, [r1, r2]                          @  FETCHPIPE
        sxtb    ip, ip                                   @  Sign-extend saved PIPE
        msr     cpsr_f, rARM                             @  Load flags into CPSR
        addmi   rR15, rR15, ip                           @  Handle branch
        addpl   rR15, rR15, #1                           @  
        strh    rR15, [rGSU, #30]                        @  Store destination to R15
        b       loop_head                                @ 

@ BCC: branch if lower (unsigned <)
handle_fx_bcc:
        add     rR15, rR15, #1                           @  R15++
        uxth    r2, rR15                                 @  Wrap R15 at 16 bits
        ldrb    rPIPE, [r1, r2]                          @  FETCHPIPE
        sxtb    ip, ip                                   @  Sign-extend saved PIPE
        msr     cpsr_f, rARM                             @  Load flags into CPSR
        addcc   rR15, rR15, ip                           @  Handle branch
        addcs   rR15, rR15, #1                           @  
        strh    rR15, [rGSU, #30]                        @  Store destination to R15
        b       loop_head                                @ 

@ BCS: branch if higher or same (unsigned >=)
handle_fx_bcs:
        add     rR15, rR15, #1                           @  R15++
        uxth    r2, rR15                                 @  Wrap R15 at 16 bits
        ldrb    rPIPE, [r1, r2]                          @  FETCHPIPE
        sxtb    ip, ip                                   @  Sign-extend saved PIPE
        msr     cpsr_f, rARM                             @  Load flags into CPSR
        addcs   rR15, rR15, ip                           @  Handle branch
        addcc   rR15, rR15, #1                           @  
        strh    rR15, [rGSU, #30]                        @  Store destination to R15
        b       loop_head                                @ 

@ BVC: branch if no overflow
handle_fx_bvc:
        add     rR15, rR15, #1                           @  R15++
        uxth    r2, rR15                                 @  Wrap R15 at 16 bits
        ldrb    rPIPE, [r1, r2]                          @  FETCHPIPE
        sxtb    ip, ip                                   @  Sign-extend saved PIPE
        msr     cpsr_f, rARM                             @  Load flags into CPSR
        addvc   rR15, rR15, ip                           @  Handle branch
        addvs   rR15, rR15, #1                           @  
        strh    rR15, [rGSU, #30]                        @  Store destination to R15
        b       loop_head                                @ 

@ BVS: branch if overflow
handle_fx_bvs:
        add     rR15, rR15, #1                           @  R15++
        uxth    r2, rR15                                 @  Wrap R15 at 16 bits
        ldrb    rPIPE, [r1, r2]                          @  FETCHPIPE
        sxtb    ip, ip                                   @  Sign-extend saved PIPE
        msr     cpsr_f, rARM                             @  Load flags into CPSR
        addvs   rR15, rR15, ip                           @  Handle branch
        addvc   rR15, rR15, #1                           @  
        strh    rR15, [rGSU, #30]                        @  Store destination to R15
        b       loop_head                                @ 

@ TO: set register n as destination register
@ move one register to another (if B flag is set)
handle_fx_to_r:
        tst     rSTAT, #4096                             @ Test B
        addeq   vLow, rGSU, vLow, lsl #1                 @ Compute register pointer for DREG
        beq     .L81                                     @ If B is set, only set DREG
        ldrh    r2, [rSREG]                              @ Load SREG
        lsl     vLow, vLow, #1                           @ Compute register offset
        strh    r2, [rGSU, vLow]                         @ Store to vLow
        add     vLow, rGSU, #0                           @ CLRFLAGS: vLow = 0
        mov     rSREG, vLow                              @ CLRFLAGS: SREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
.L81:
        add     rR15, rR15, #1                           @ R15++
        mov     rDREG, vLow                              @ CLRFLAGS: DREG = vLow. May be 0 or a reg depending on branch.
        strh    rR15, [rGSU, #30]                        @ Store R15
        b       loop_head                                @ 


@ TO_R14: set register 14 as destination register
@ If B flag is set, move SREG to R14, CLRFLAGS, and READR14 instead
handle_fx_to_r14:
        tst     rSTAT, #4096                             @ Test B
        bne     handle_fx_to_r14.b_is_set                @ If B is set, branch
        add     rDREG, rGSU, #28                         @ Else, DREG = R14
.L84:
        add     rR15, rR15, #1                           @ R15++
        strh    rR15, [rGSU, #30]                        @ Store R15
        b       loop_head                                @ 

@ TO_R15: Set DREG to R15 and increment R15
@ If B flag is set, move SREG to R15 instead
handle_fx_to_r15:
        tst     rSTAT, #4096                             @ Test B
        beq     handle_fx_to_r15.b_is_not_set            @ If B is not set, branch (no return)
        ldrh    rR15, [rSREG]                            @ Load SREG into rR15
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        strh    rR15, [rGSU, #30]                        @ Store R15
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        b       loop_head                                @ 

@ WITH: set register n as source and destination register
handle_fx_with:
        add     rDREG, rGSU, vLow, lsl #1                @ Calculate register
        add     rR15, rR15, #1                           @ R15++
        mov     rSREG, rDREG                             @ Copy register to SREG
        strh    rR15, [rGSU, #30]                        @ Store R15
        orr     rSTAT, rSTAT, #4096                      @ Set flag B
        b       loop_head                                @ 

@ STW: store word (16 bits)
handle_fx_stw_r:
        lsl     vLow, vLow, #1                           @ Double vLow for 16-bit offset
        ldrh    rR15, [rGSU, vLow]                       @ Load offset into rR15. WYATT_TODO can probably just load into vLow.
        ldr     r1, [rGSU, #404]                         @ Load RAM base pointer
        strh    rR15, [rGSU, #34]                        @ Store offset to GSU.vLastRamAdr
        ldrh    r2, [rSREG]                              @ Load source data
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        strb    r2, [r1, rR15]                           @ Store bottom byte
        eor     rR15, rR15, #1                           @ Flip bottom bit of offset
        lsr     r2, r2, #8                               @ Prep top byte
        strb    r2, [r1, rR15]                           @ Store top byte
        ldrh    rR15, [rGSU, #30]                        @ Load R15. WYATT_TODO unnecessary.
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        add     rR15, rR15, #1                           @ R15++
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strh    rR15, [rGSU, #30]                        @ Store R15
        b       loop_head                                @ 

@ LOOP: decrement loop counter R12 and branch to R13 on not zero
handle_fx_loop:
        ldrh    rR15, [rGSU, #24]                        @ Load counter
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        sub     rR15, rR15, #1                           @ Decrement counter
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        lsl     rARM, rR15, #16                          @ Shift counter to top half of register and test flags
        movs    rARM, rARM                               @ 
        mrs     rARM, cpsr                               @ Read flags from CPSR
        cmp     rR15, #0                                 @ Test counter
        strh    rR15, [rGSU, #24]                        @ Store counter
        ldrheq  rR15, [rGSU, #30]                        @ If counter is 0, load R15. WYATT_TODO can probably use move instead of load
        ldrhne  rR15, [rGSU, #26]                        @ If counter is nonzero, load R13
        addeq   rR15, rR15, #1                           @ If counter is 0, increment R15
        uxtheq  rR15, rR15                               @ Wrap R15 at 16 bits. WYATT_TODO unnecessary
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strh    rR15, [rGSU, #30]                        @ Store R15
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       loop_head                                @ 

@ ALT1: set ALT mode 1
handle_fx_alt1:
        add     rR15, rR15, #1                           @ R15++
        bic     rSTAT, rSTAT, #4096                      @ Clear B flag
        strh    rR15, [rGSU, #30]                        @ Store R15
        orr     rSTAT, rSTAT, #256                       @ Set ALT1 flag
        b       loop_head                                @ 

@ ALT2: set ALT mode 2
handle_fx_alt2:
        add     rR15, rR15, #1                           @ R15++
        bic     rSTAT, rSTAT, #4096                      @ Clear B flag
        strh    rR15, [rGSU, #30]                        @ Store R15
        orr     rSTAT, rSTAT, #512                       @ Set ALT2 flag
        b       loop_head                                @ 
        
@ ALT3: set ALT mode 3
handle_fx_alt3:
        add     rR15, rR15, #1                           @ R15++
        bic     rSTAT, rSTAT, #4096                      @ Clear B flag
        strh    rR15, [rGSU, #30]                        @ Store R15
        orr     rSTAT, rSTAT, #768                       @ Set ALT1 + ALT2 flags
        b       loop_head                                @ 

@ LDW: load word
handle_fx_ldw_r:
        lsl     vLow, vLow, #1                           @ Double vLow for 16-bit offset
        ldrh    r2, [rGSU, vLow]                         @ Load offset into r2. WYATT_TODO can probably just load into vLow. 
        ldr     r1, [rGSU, #404]                         @ Load RAM base pointer
        strh    r2, [rGSU, #34]                          @ Store offset to GSU.vLastRamAdr
        eor     ip, r2, #1                               @ Flip bottom bit of offset, stored in a separate register
        add     vLow, rR15, #1                           @ R15++
        ldrb    rR15, [r1, r2]                           @ Load bottom byte
        ldrb    r2, [r1, ip]                             @ Load top byte
        strh    vLow, [rGSU, #30]                        @ Store R15
        orr     rR15, rR15, r2, lsl #8                   @ Combine bytes into word
        strh    rR15, [rDREG]                            @ Store word into DREG
        add     rR15, rGSU, #28                          @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        ldrheq  rR15, [rGSU, #28]                        @  |
        ldreq   r2, [rGSU, #408]                         @  |
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strbeq  rR15, [rGSU, #38]                        @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       loop_head                                @ 

@ SWAP: swap low and high bytes of SREG, store in DREG
handle_fx_swap:
        add     r2, rR15, #1                             @ R15++
        ldrh    rR15, [rSREG]                            @ Load value from SREG
        strh    r2, [rGSU, #30]                          @ Store R15
        rev16   rR15, rR15                               @ Byteswap value
        add     r2, rGSU, #28                            @ TESTR14: Pointer to R14
        strh    rR15, [rDREG]                            @ Store value into DREG
        orr     r1, rR15, rR15, lsl #16                  @ Duplicate value into both halves of a register for flags. WYATT_TODO could technically just shift here.
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        movs    rARM, r1                                 @ Set flags
        mrs     rARM, cpsr                               @ Read flags from CPSR
        cmp     rDREG, r2                                @ TESTR14: If DREG == 14, load rombuffer
        ldrheq  rR15, [rGSU, #28]                        @  |
        ldreq   r2, [rGSU, #408]                         @  |
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strbeq  rR15, [rGSU, #38]                        @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       loop_head                                @ 

@ COLOR: copy SREG to color register
handle_fx_color:
        ldrb    r1, [rGSU, #36]                          @ Load plotOptionReg
        ldrb    r2, [rSREG]                              @ Load color from SREG
        tst     r1, #4                                   @ If plotOptionReg & 0x04, duplicate the high nibble of color to the low nibble
        andne   vLow, r2, #240                           @  |
        orrne   r2, vLow, r2, lsr #4                     @  V
        tst     r1, #8                                   @ If plotOptionReg & 0x08, only update the bottom nibble
        ldrbne  r1, [rGSU, #37]                          @  |
        andne   r2, r2, #15                              @  |
        bicne   r1, r1, #15                              @  |
        orrne   r2, r1, r2                               @  V
        add     rR15, rR15, #1                           @ R15++
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        strb    r2, [rGSU, #37]                          @ Store result to GSU.vColorReg
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strh    rR15, [rGSU, #30]                        @ Store R15
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       loop_head                                @ 

@ NOT: bitwise NOT of SREG, store in DREG
handle_fx_not:
        ldrh    r2, [rGSU, #30]                          @ Load R15. WYATT_TODO unnecessary
        ldrh    rR15, [rSREG]                            @ Load value from SREG
        add     r2, r2, #1                               @ R15++
        strh    r2, [rGSU, #30]                          @ Store R15
        add     rR15, rR15, rR15, lsl #16                @ Duplicate value into both halves of a register
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        mvns    rR15, rR15                               @ Negate value and set flags
        mrs     rARM, cpsr                               @ Read flags from CPSR
        strh    rR15, [rDREG]                            @ Store value
        add     rR15, rGSU, #28                          @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        ldrheq  rR15, [rGSU, #28]                        @  |
        ldreq   r2, [rGSU, #408]                         @  |
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strbeq  rR15, [rGSU, #38]                        @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       loop_head                                @ 

@ ADD: SREG + register n, store in DREG
handle_fx_add_r:
        ldrh    rR15, [rSREG]                            @ Load value 1 from SREG
        ldrh    r2, [rGSU, #30]                          @ Load R15. WYATT_TODO unnecessary
        lsl     vLow, vLow, #1                           @ Shift vLow for 2-byte offset
        ldrh    rARM, [rGSU, vLow]                       @ Load value 2 from register N
        add     r2, r2, #1                               @ R15++
        lsl     rR15, rR15, #16                          @ Duplicate value 1 into both halves of a register
        adds    rR15, rR15, rARM, lsl #16                @ Add both values. Overwrites all flags.
        mrs     rARM, cpsr                               @ Read flags from CPSR
        lsr     rR15, rR15, #16                          @ Shift result down from top half of register
        strh    r2, [rGSU, #30]                          @ Store R15
        strh    rR15, [rDREG]                            @ Store result to DREG
        add     rR15, rGSU, #28                          @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        ldrheq  rR15, [rGSU, #28]                        @  |
        ldreq   r2, [rGSU, #408]                         @  |
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strbeq  rR15, [rGSU, #38]                        @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       loop_head                                @ 

@ SUB: SREG - register n, store in DREG
handle_fx_sub_r:
        ldrh    rR15, [rSREG]                            @ Load value 1 from SREG
        ldrh    r2, [rGSU, #30]                          @ Load R15. WYATT_TODO unnecessary
        lsl     vLow, vLow, #1                           @ Shift vLow for 2-byte offset
        ldrh    rARM, [rGSU, vLow]                       @ Load value 2 from register N
        add     r2, r2, #1                               @ R15++
        lsl     rR15, rR15, #16                          @ Duplicate value 1 into both halves of a register
        subs    rR15, rR15, rARM, lsl #16                @ Subtract value 2 from value 1. Overwrites all flags.
        mrs     rARM, cpsr                               @ Read flags from CPSR
        lsr     rR15, rR15, #16                          @ Shift result down from top half of register
        strh    r2, [rGSU, #30]                          @ Store R15
        strh    rR15, [rDREG]                            @ Store result to DREG
        add     rR15, rGSU, #28                          @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        ldrheq  rR15, [rGSU, #28]                        @  |
        ldreq   r2, [rGSU, #408]                         @  |
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strbeq  rR15, [rGSU, #38]                        @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       loop_head                                @ 

@ MERGE: Top halves of R7 and R8 as upper and lower bytes respectively, store in DREG
handle_fx_merge:
        ldrh    r1, [rGSU, #14]                          @ Load R7
        ldrh    r2, [rGSU, #16]                          @ Load R8
        bic     r1, r1, #255                             @ Clear bottom half of R7
        orr     r2, r1, r2, lsr #8                       @ Shift top half of R8 down and OR to create final value
        add     rR15, rR15, #1                           @ R15++
        strh    rR15, [rGSU, #30]                        @ Store R15
        lsr     rR15, r2, #4                             @ Calculate merge flag LUT index
        orr     rR15, rR15, r1, lsr #12                  @  |
        and     rR15, rR15, #15                          @  V
        add     rR15, rGSU, rR15                         @ Calculate flag LUT offset
        ldrb    rARM, [rR15, #42]                        @ Load flags from LUT
        strh    r2, [rDREG]                              @ Store result to DREG
        add     rR15, rGSU, #28                          @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        ldrheq  rR15, [rGSU, #28]                        @  |
        ldreq   r2, [rGSU, #408]                         @  |
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        lsl     rARM, rARM, #28                          @ Shift resultant flags into position. WYATT_TODO could use u32s, but would be more DCACHE.
        strbeq  rR15, [rGSU, #38]                        @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       loop_head                                @ 

@ AND: bitwise AND of SREG and register n, store in DREG
handle_fx_and_r:
        lsl     vLow, vLow, #1                           @ Shift vLow for 2-byte offset
        ldrh    rR15, [rSREG]                            @ Load value 1 from SREG
        ldrh    r2, [rGSU, vLow]                         @ Load value 2 from register N
        add     rR15, rR15, rR15, lsl #16                @ Duplicate values into both halves of their registers
        add     r2, r2, r2, lsl #16                      @  |
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        ands    rR15, rR15, r2                           @ AND the two values together
        mrs     rARM, cpsr                               @ Read flags from CPSR
        ldrh    r2, [rGSU, #30]                          @ Load R15. WYATT_TODO unnecessary
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        add     r2, r2, #1                               @ R15++
        strh    r2, [rGSU, #30]                          @ Store R15
        strh    rR15, [rDREG]                            @ Store result
        add     rR15, rGSU, #28                          @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        ldrheq  rR15, [rGSU, #28]                        @  |
        ldreq   r2, [rGSU, #408]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        strbeq  rR15, [rGSU, #38]                        @  |
        b       loop_head                                @ 

@ MULT: multiply SREG and register n as signed 8-bit ints, store in DREG
handle_fx_mult_r:
        lsl     vLow, vLow, #1                           @ Shift vLow for 2-byte offset
        ldrsb   rR15, [rSREG]                            @ Load s8 value 1 from SREG
        ldrsb   r2, [rGSU, vLow]                         @ Load s8 value 2 from register N. WYATT_TODO could this use an 8-bit load?
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        smulbb  rR15, rR15, r2                           @ Multiply to get the result
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        movs    rARM, rR15                               @ Set flags
        mrs     rARM, cpsr                               @ Read flags from CPSR
        ldrh    r2, [rGSU, #30]                          @ Load R15. WYATT_TODO unnecessary
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        add     r2, r2, #1                               @ R15++
        strh    r2, [rGSU, #30]                          @ Store R15
        strh    rR15, [rDREG]                            @ Store result
        add     rR15, rGSU, #28                          @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        ldrheq  rR15, [rGSU, #28]                        @  |
        ldreq   r2, [rGSU, #408]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        strbeq  rR15, [rGSU, #38]                        @  |
        b       loop_head                                @ 

@ SBK: store word to last accessed RAM address
handle_fx_sbk:
        ldrh    rR15, [rSREG]                            @ Load value from SREG
        ldrh    r2, [rGSU, #34]                          @ Load vLastRamAdr
        ldr     r1, [rGSU, #404]                         @ Load RAM base pointer
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        strb    rR15, [r1, r2]                           @ Store bottom byte
        ldrh    r2, [rGSU, #34]                          @ Reload vLastRamAdr WYATT_TODO unnecessary
        ldr     r1, [rGSU, #404]                         @ Reload RAM base pointer. WYATT_TODO unnecessary
        lsr     rR15, rR15, #8                           @ Prep top byte
        eor     r2, r2, #1                               @ Flip bottom bit of offset
        strb    rR15, [r1, r2]                           @ Store bottom byte
        ldrh    rR15, [rGSU, #30]                        @ Load R15 WYATT_TODO unnecessary
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        add     rR15, rR15, #1                           @ R15++
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        strh    rR15, [rGSU, #30]                        @ Store R15
        b       loop_head                                @ 

@ LINK: R11 = R15 + immediate
handle_fx_link_i:
        add     vLow, vLow, rR15                         @ Add R15 and immediate
        add     rR15, rR15, #1                           @ R15++
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        strh    vLow, [rGSU, #22]                        @ Store R11
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strh    rR15, [rGSU, #30]                        @ Store R15
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       loop_head                                @ 

@ SEX: sign-extend 8-bit to 16-bit, SREG to DREG
handle_fx_sex:
        ldrh    r2, [rGSU, #30]                          @ Load R15. WYATT_TODO unnecessary
        ldrsb   rR15, [rSREG]                            @ Load value from SREG and sign-extend
        add     r2, r2, #1                               @ R15++
        strh    r2, [rGSU, #30]                          @ Store R15
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        movs    rR15, rR15                               @ Set flags
        mrs     rARM, cpsr                               @ Read flags from CPSR
        strh    rR15, [rDREG]                            @ Store value
        add     rR15, rGSU, #28                          @ TESTR14: pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        ldrheq  rR15, [rGSU, #28]                        @  |
        ldreq   r2, [rGSU, #408]                         @  |
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strbeq  rR15, [rGSU, #38]                        @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       loop_head                                @ 

@ ASR: arithmetic shift right, SREG to DREG
handle_fx_asr:
        ldrh    r2, [rGSU, #30]                          @ Load R15. WYATT_TODO unnecessary
        ldrsh   rR15, [rSREG]                            @ Load value from SREG and sign-extend to 32-bit
        add     r2, r2, #1                               @ R15++
        strh    r2, [rGSU, #30]                          @ Store R15
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        asrs    rR15, rR15, #1                           @ ASR by 1 and set flags
        mrs     rARM, cpsr                               @ Read flags from CPSR
        strh    rR15, [rDREG]                            @ Store result
        add     rR15, rGSU, #28                          @ TESTR14: pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        ldrheq  rR15, [rGSU, #28]                        @  |
        ldreq   r2, [rGSU, #408]                         @  |
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strbeq  rR15, [rGSU, #38]                        @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       loop_head                                @ 

@ ROR: rotate right, SREG to DREG
handle_fx_ror:
        ldrh    r2, [rGSU, #30]                          @ Load R15. WYATT_TODO unnecessary
        ldrh    rR15, [rSREG]                            @ Load value from SREG and sign-extend to 32-bit
        add     r2, r2, #1                               @ R15++
        strh    r2, [rGSU, #30]                          @ Store R15
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        orrcs   rR15, rR15, #65536                       @ If the carry flag was set, set bit 16 of value
        rrxs    rR15, rR15                               @ Rotate right and set flags
        mrs     rARM, cpsr                               @ Read flags from CPSR
        strh    rR15, [rDREG]                            @ Store result
        add     rR15, rGSU, #28                          @ TESTR14: pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        ldrheq  rR15, [rGSU, #28]                        @  |
        ldreq   r2, [rGSU, #408]                         @  |
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strbeq  rR15, [rGSU, #38]                        @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       loop_head                                @ 

@ JMP: jump to address of register N. No delay slot.
handle_fx_jmp_r:
        lsl     vLow, vLow, #1                           @ Shift vLow for 2-byte offset
        ldrh    rR15, [rGSU, vLow]                       @ Load destination from register N
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        strh    rR15, [rGSU, #30]                        @ Store destination to R15
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       loop_head                                @ 

@ LOB: set upper byte to 0, SREG to DREG
handle_fx_lob:
        ldrh    rR15, [rGSU, #30]                        @ Load R15. WYATT_TODO unnecessary
        ldrb    r2, [rSREG]                              @ Load bottom byte of register N and zero-extend
        add     rR15, rR15, #1                           @ R15++
        strh    rR15, [rGSU, #30]                        @ Store R15
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        lsl     rARM, r2, #24                            @ Shift result to top byte of register
        movs    rARM, rARM                               @ Set flags
        mrs     rARM, cpsr                               @ Read flags from CPSR
        strh    r2, [rDREG]                              @ Store result to DREG
        add     rR15, rGSU, #28                          @ TESTR14: pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        ldrheq  rR15, [rGSU, #28]                        @  |
        ldreq   r2, [rGSU, #408]                         @  |
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strbeq  rR15, [rGSU, #38]                        @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       loop_head                                @ 

@ Data table for fx_run_asm
.L242:
        .word   GSU
        .word   opcode_goto_table
        .word   plot_rpix_handler_table

@ FMULT: 16 to 32 bit signed multiply, keep top 16. SREG * R6, store to DREG
handle_fx_fmult:
        ldrh    rR15, [rSREG]                            @ Load value 1 from SREG
        ldrh    r2, [rGSU, #12]                          @ Load value 2 from R6
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        smulbb  rR15, rR15, r2                           @ Signed multiply
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        asrs    rR15, rR15, #16                          @ Shift top half down and set flags
        mrs     rARM, cpsr                               @ Read flags from CPSR
        ldrh    r2, [rGSU, #30]                          @ Load R15. WYATT_TODO unnecessary
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        add     r2, r2, #1                               @ R15++
        strh    r2, [rGSU, #30]                          @ Store R15
        strh    rR15, [rDREG]                            @ Store result
        add     rR15, rGSU, #28                          @ TESTR14: pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        ldrheq  rR15, [rGSU, #28]                        @  |
        ldreq   r2, [rGSU, #408]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        strbeq  rR15, [rGSU, #38]                        @  |
        b       loop_head                                @ 

@ IBT: fetch PIPE and store to register N
handle_fx_ibt_r:
        add     r2, rR15, #1                             @ R15 + 1 into scratch register
        uxth    r2, r2                                   @ Wrap scratch R15 at 16 bits
        strh    r2, [rGSU, #30]                          @ Store R15. WYATT_TODO unnecessary. Aliasing?
        lsl     vLow, vLow, #1                           @ Shift vLow for 2-byte offset
        sxtb    ip, ip                                   @ Sign-extend existing PIPE. WYATT_TODO probably can use rPIPE? Either way sxtb is probably unnecessary
        add     rR15, rR15, #2                           @ R15 + 2
        ldrb    rPIPE, [r1, r2]                          @ FETCHPIPE. We don't immediately use this value! This can be optimized.
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        strh    rR15, [rGSU, #30]                        @ Store R15
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        strh    ip, [rGSU, vLow]                         @ Store result
        b       loop_head                                @ 

@ IBT R14: fetch PIPE and store to register N, then READR14
handle_fx_ibt_r14:
        add     r2, rR15, #1                             @ R15 + 1 into scratch register
        uxth    r2, r2                                   @ Wrap scratch R15 at 16 bits
        strh    r2, [rGSU, #30]                          @ Store R15. WYATT_TODO unnecessary. Aliasing?
        sxtb    ip, ip                                   @ Shift vLow for 2-byte offset
        add     rR15, rR15, #2                           @ R15 + 2
        ldrb    rPIPE, [r1, r2]                          @ FETCHPIPE. We don't immediately use this value!
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        strh    ip, [rGSU, #28]                          @ Store result
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        strh    rR15, [rGSU, #30]                        @ Store R15
        uxth    ip, ip                                   @ Unsigned-extend PIPE? What? It's 8-bit... WYATT_TODO
        ldr     rR15, [rGSU, #408]                       @ READR14: Load ROM base pointer
        ldrb    rR15, [rR15, ip]                         @ READR14: Load ROM(R14)
        strb    rR15, [rGSU, #38]                        @ READR14: Store to ROMBUFFER
        b       loop_head                                @ 

@ FROM: Set SREG to register N
@ If B flag is set, move register N to DREG and set flags instead
@ B is unlikely. WYATT_TODO invert the branch.
handle_fx_from_r:
        tst     rSTAT, #4096                             @ Test B flag
        beq     handle_fx_from_r.b_is_not_set            @ If B is not set, just set SREG and increment R15
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        lsl     vLow, vLow, #1                           @ Shift vLow for 2-byte offset
        ldrh    rR15, [rGSU, vLow]                       @ Load result
        bic     rARM, rARM, #-805306368                  @ Clear NZO flags
        lsls    r2, rR15, #24                            @ Set the flags we need
        orrmi   rARM, rARM, #268435456                   @  |
        lsls    r2, rR15, #16                            @  |
        orrmi   rARM, rARM, #-2147483648                 @  |
        orreq   rARM, rARM, #1073741824                  @  V
        ldrh    r2, [rGSU, #30]                          @ Load R15. WYATT_TODO unnecessary
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        add     r2, r2, #1                               @ R15++
        strh    r2, [rGSU, #30]                          @ Store R15
        strh    rR15, [rDREG]                            @ Store result
        add     rR15, rGSU, #28                          @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        ldrheq  rR15, [rGSU, #28]                        @  |
        ldreq   r2, [rGSU, #408]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        strbeq  rR15, [rGSU, #38]                        @  |
        b       loop_head                                @ 

@ HIB: arithmetic right-shift register by 8, SREG to DREG
handle_fx_hib:
        ldrh    rR15, [rSREG]                            @ Load result from SREG
        ldrh    r2, [rGSU, #30]                          @ Load R15. WYATT_TODO unnecessary
        lsr     rR15, rR15, #8                           @ Prep high byte
        add     r2, r2, #1                               @ R15++
        strh    r2, [rGSU, #30]                          @ Store R15
        strh    rR15, [rDREG]                            @ Store result
        sxtb    r2, rR15                                 @ Sign-extend result into scratch register
        add     rR15, rGSU, #28                          @ TESTR14: Pointer to R14
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        movs    rARM, r2                                 @ Set flags
        mrs     rARM, cpsr                               @ Read flags from CPSR
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        ldrheq  rR15, [rGSU, #28]                        @  |
        ldreq   r2, [rGSU, #408]                         @  |
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strbeq  rR15, [rGSU, #38]                        @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       loop_head                                @ 

@ OR: logically OR SREG and register N, store in DREG
handle_fx_or_r:
        lsl     vLow, vLow, #1                           @ Shift vLow for 2-byte offset
        ldrh    rR15, [rSREG]                            @ Load value 1 from SREG
        ldrh    r2, [rGSU, vLow]                         @ Load value 2 from register N
        add     rR15, rR15, rR15, lsl #16                @ Duplicate value into both halves of a register for flags
        add     r2, r2, r2, lsl #16                      @ Duplicate value into both halves of a register for flags
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        orrs    rR15, rR15, r2                           @ OR and set flags
        mrs     rARM, cpsr                               @ Read flags from CPSR
        ldrh    r2, [rGSU, #30]                          @ Load R15. WYATT_TODO unnecessary
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        add     r2, r2, #1                               @ R15++
        strh    r2, [rGSU, #30]                          @ Store R15
        strh    rR15, [rDREG]                            @ Store result
        add     rR15, rGSU, #28                          @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        ldrheq  rR15, [rGSU, #28]                        @  |
        ldreq   r2, [rGSU, #408]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        strbeq  rR15, [rGSU, #38]                        @  |
        b       loop_head                                @ 

@ INC: increment a register
handle_fx_inc_r:
        lsl     vLow, vLow, #1                           @ Shift vLow for 2-byte offset
        ldrh    rR15, [rGSU, vLow]                       @ Load value
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        add     rR15, rR15, #1                           @ Increment value
        strh    rR15, [rGSU, vLow]                       @ Store result
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        lsl     rARM, rR15, #16                          @ Set flags
        movs    rARM, rARM                               @  |
        mrs     rARM, cpsr                               @ Read flags from CPSR
        ldrh    rR15, [rGSU, #30]                        @ Load R15. Actually has to be reloaded here.
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        add     rR15, rR15, #1                           @ R15++
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        strh    rR15, [rGSU, #30]                        @ Store R15
        b       loop_head                                @ 

@ INC R14: increment R14 and then READR14
handle_fx_inc_r14:
        ldrh    rR15, [rGSU, #28]                        @ Load value from R14
        ldrh    r2, [rGSU, #30]                          @ Load R15. WYATT_TODO unnecessary
        add     rR15, rR15, #1                           @ Increment value
        add     r2, r2, #1                               @ R15++
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        lsl     rARM, rR15, #16                          @ Set flags
        movs    rARM, rARM                               @  |
        mrs     rARM, cpsr                               @ Read flags from CPSR
        uxth    rR15, rR15                               @ Wrap R15 at 16 bits
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strh    rR15, [rGSU, #28]                        @ Store result to R14
        strh    r2, [rGSU, #30]                          @ Store R15
        ldr     r2, [rGSU, #408]                         @ READR14: Load ROM base pointer
        ldrb    rR15, [r2, rR15]                         @ READR14: Load ROM(R14)
        strb    rR15, [rGSU, #38]                        @ READR14: Store to ROMBUFFER
        b       loop_head                                @ 

@ GETC: transfer ROMBUFFER to color register
handle_fx_getc:
        ldrb    r1, [rGSU, #36]                          @ Load plotOptionReg
        ldrb    r2, [rGSU, #38]                          @ Load ROMBUFFER
        tst     r1, #4                                   @ If plotOptionReg & 0x04, duplicate the high nibble of color to the low nibble
        andne   vLow, r2, #240                           @  |
        orrne   r2, vLow, r2, lsr #4                     @  V
        tst     r1, #8                                   @ If plotOptionReg & 0x08, only update the bottom nibble
        ldrbne  r1, [rGSU, #37]                          @  |
        andne   r2, r2, #15                              @  |
        bicne   r1, r1, #15                              @  |
        orrne   r2, r1, r2                               @  V
        add     rR15, rR15, #1                           @ R15++
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        strb    r2, [rGSU, #37]                          @ Store result to GSU.vColorReg
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strh    rR15, [rGSU, #30]                        @ Store R15
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       loop_head                                @ 

@ DEC: decrement a register
handle_fx_dec_r:
        lsl     vLow, vLow, #1                           @ Shift vLow for 2-byte offset
        ldrh    rR15, [rGSU, vLow]                       @ Load value
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        sub     rR15, rR15, #1                           @ Decrement value
        strh    rR15, [rGSU, vLow]                       @ Store result
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        lsl     rARM, rR15, #16                          @ Set flags
        movs    rARM, rARM                               @  |
        mrs     rARM, cpsr                               @ Read flags from CPSR
        ldrh    rR15, [rGSU, #30]                        @ Load R15. Actually has to be reloaded here.
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        add     rR15, rR15, #1                           @ R15++
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        strh    rR15, [rGSU, #30]                        @ Store R15
        b       loop_head                                @ 

@ DEC R14: decrement R14 and then READR14
handle_fx_dec_r14:
        ldrh    rR15, [rGSU, #28]                        @ Load value from R14
        ldrh    r2, [rGSU, #30]                          @ Load R15. WYATT_TODO unnecessary
        sub     rR15, rR15, #1                           @ Decrement value
        add     r2, r2, #1                               @ R15++
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        lsl     rARM, rR15, #16                          @ Set flags
        movs    rARM, rARM                               @  |
        mrs     rARM, cpsr                               @ Read flags from CPSR
        uxth    rR15, rR15                               @ Wrap R15 at 16 bits
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strh    rR15, [rGSU, #28]                        @ Store result to R14
        strh    r2, [rGSU, #30]                          @ Store R15
        ldr     r2, [rGSU, #408]                         @ READR14: Load ROM base pointer
        ldrb    rR15, [r2, rR15]                         @ READR14: Load ROM(R14)
        strb    rR15, [rGSU, #38]                        @ READR14: Store to ROMBUFFER
        b       loop_head                                @ 

@ GETB: get byte from ROMBUFFER
handle_fx_getb:
        add     rR15, rR15, #1                           @ R15++
        strh    rR15, [rGSU, #30]                        @ Store R15
        ldrb    rR15, [rGSU, #38]                        @ Load value from ROMBUFFER
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        strh    rR15, [rDREG]                            @ Store value to DREG
        add     rR15, rGSU, #28                          @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        ldrheq  rR15, [rGSU, #28]                        @  |
        ldreq   r2, [rGSU, #408]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        strbeq  rR15, [rGSU, #38]                        @  |
        b       loop_head                                @ 

@ IWT: Combine existing PIPE and next PIPE into register N, then FETCHPIPE again
handle_fx_iwt_r:
        add     r2, rR15, #1                             @ R15 + 1 into scratch register
        uxth    r2, r2                                   @ Wrap scratch R15 at 16 bits
        ldrb    rPIPE, [r1, r2]                          @ FETCHPIPE
        add     r2, rR15, #2                             @ R15 + 2 into scratch register
        orr     ip, ip, rPIPE, lsl #8                    @ Combine both PIPEs into result
        lsl     vLow, vLow, #1                           @ Shift vLow for 2-byte offset
        uxth    r2, r2                                   @ Wrap scratch R15 at 16 bits
        add     rR15, rR15, #3                           @ R15 += 3
        ldrb    rPIPE, [r1, r2]                          @ FETCHPIPE. Value not immediately used.
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        strh    rR15, [rGSU, #30]                        @ Store R15
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        strh    ip, [rGSU, vLow]                         @ Store result to register N
        b       loop_head                                @ 

@ IWT R14: Combine existing PIPE and next PIPE into register N, then FETCHPIPE again
handle_fx_iwt_r14:
        add     r2, rR15, #1                             @ R15 + 1 into scratch register
        uxth    r2, r2                                   @ Wrap scratch R15 at 16 bits
        ldrb    rPIPE, [r1, r2]                          @ FETCHPIPE
        add     r2, rR15, #2                             @ R15 + 2 into scratch register
        orr     ip, ip, rPIPE, lsl #8                    @ Combine both PIPEs into result
        uxth    r2, r2                                   @ Wrap scratch R15 at 16 bits
        add     rR15, rR15, #3                           @ R15 += 3
        ldrb    rPIPE, [r1, r2]                          @ FETCHPIPE. Value not immediately used.
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strh    rR15, [rGSU, #30]                        @ Store R15
        strh    ip, [rGSU, #28]                          @ Store result to R14
        ldr     rR15, [rGSU, #408]                       @ READR14: Load ROM base pointer
        ldrb    rR15, [rR15, ip]                         @ READR14: Load ROM(R14)
        strb    rR15, [rGSU, #38]                        @ READR14: Store to ROMBUFFER
        b       loop_head                                @ 

@ STB: Store byte in SREG at the RAM location pointed to by register N
handle_fx_stb_r:
        lsl     vLow, vLow, #1                           @ Shift vLow for 2-byte offset
        ldrh    rR15, [rGSU, vLow]                       @ Load destination pointer
        ldr     r2, [rGSU, #404]                         @ Load RAM base pointer
        strh    rR15, [rGSU, #34]                        @ Store destination pointer to GSU.vLastRamAdr
        ldrh    r1, [rSREG]                              @ Load value from SREG
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        strb    r1, [r2, rR15]                           @ Store value to RAM(register N)
        ldrh    rR15, [rGSU, #30]                        @ Load R15. WYATT_TODO unnecessary
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        add     rR15, rR15, #1                           @ R15++
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strh    rR15, [rGSU, #30]                        @ Store R15
        b       loop_head                                @ 

@ LDB: Load byte from the RAM location pointed to by register N into DREG
handle_fx_ldb_r:
        lsl     vLow, vLow, #1                           @ Shift vLow for 2-byte offset
        ldrh    r2, [rGSU, vLow]                         @ Load source pointer
        ldr     r1, [rGSU, #404]                         @ Load RAM base pointer
        strh    r2, [rGSU, #34]                          @ Store source pointer to GSU.vLastRamAdr
        ldrb    r2, [r1, r2]                             @ Load result
        add     rR15, rR15, #1                           @ R15++
        strh    rR15, [rGSU, #30]                        @ Store R15
        strh    r2, [rDREG]                              @ Store result to DREG
        add     rR15, rGSU, #28                          @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        ldrheq  rR15, [rGSU, #28]                        @  |
        ldreq   r2, [rGSU, #408]                         @  |
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strbeq  rR15, [rGSU, #38]                        @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       loop_head                                @ 

@ CMODE: set plot option register to the value in SREG
handle_fx_cmode:
        ldrb    rR15, [rSREG]                            @ Load result in SREG
        tst     rR15, #16                                @ Test plotOptionReg for screenHeight
        strb    rR15, [rGSU, #36]                        @ Store result
        movne   rR15, #256                               @ If plotOptionReg & 0x10, fake screenHeight as 256
        ldreq   rR15, [rGSU, #392]                       @ Else, set screenHeight to its real height
        str     rR15, [rGSU, #388]                       @ Store screenHeight
        bl      fx_computeScreenPointers                 @ Recompute screen ptrs. WYATT_TODO if regs are changed, be careful!
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        ldrh    rR15, [rGSU, #30]                        @ Load R15. WYATT_TODO can be moved above computeScreenPointers
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        add     rR15, rR15, #1                           @ R15++
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        strh    rR15, [rGSU, #30]                        @ Store R15
        b       loop_head                                @ 

@ ADC: add-with-carry, SREG + register N, store in DREG
handle_fx_adc_r:
        ldrh    r2, [rGSU, #30]                          @ Load R15. WYATT_TODO unnecessary
        lsl     vLow, vLow, #1                           @ Shift vLow for 2-byte offset
        ldrh    r1, [rSREG]                              @ Load value 1 from SREG
        ldrh    rR15, [rGSU, vLow]                       @ Load value 2 from register N
        add     r2, r2, #1                               @ R15++
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        lsl     rARM, r1, #16                            @ Shift value 1 into the upper half of the register
        orrcs   rARM, rARM, #32768                       @ Move carry flag into value 1
        orrcs   rR15, rR15, #-2147483648                 @ Move carry flag into value 2
        adds    rR15, rARM, rR15, ror #16                @ Add the values and set flags
        mrs     rARM, cpsr                               @ Read flags from CPSR
        lsr     rR15, rR15, #16                          @ Shift result into bottom half of register
        strh    r2, [rGSU, #30]                          @ Store R15
        strh    rR15, [rDREG]                            @ Store result
        add     rR15, rGSU, #28                          @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        ldrheq  rR15, [rGSU, #28]                        @  |
        ldreq   r2, [rGSU, #408]                         @  |
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strbeq  rR15, [rGSU, #38]                        @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       loop_head                                @ 

@ SBC: subtract-with-carry, SREG - register N, store in DREG
handle_fx_sbc_r:
        ldrh    rR15, [rSREG]                            @ Load value 1
        lsl     vLow, vLow, #1                           @ Shift vLow for 2-byte offset
        ldrh    r2, [rGSU, vLow]                         @ Load value 2
        lsl     rR15, rR15, #16                          @ Shift value 1 into top half of register
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        sbcs    rR15, rR15, r2, lsl #16                  @ Do the subtract-with-carry
        mrs     rARM, cpsr                               @ Read flags from CPSR
        ldrh    r2, [rGSU, #30]                          @ Load R15. WYATT_TODO unnecessary
        lsrs    rR15, rR15, #16                          @ Shift result into bottom half of register and set flags
        add     r2, r2, #1                               @ R15++
        strh    r2, [rGSU, #30]                          @ Store R15
        orreq   rARM, rARM, #1073741824                  @ If the result is 0, set the Z flag
        strh    rR15, [rDREG]                            @ Store the result
        add     rR15, rGSU, #28                          @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        ldrheq  rR15, [rGSU, #28]                        @  |
        ldreq   r2, [rGSU, #408]                         @  |
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strbeq  rR15, [rGSU, #38]                        @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       loop_head                                @ 

@ BIC: DREG = SREG & ~register N
handle_fx_bic_r:
        lsl     vLow, vLow, #1                           @ Shift vLow for 2-byte offset
        ldrh    rR15, [rSREG]                            @ Load value 1
        ldrh    r2, [rGSU, vLow]                         @ Load value 2
        add     rR15, rR15, rR15, lsl #16                @ Duplicate value 1 into both halves of a register for flags.
        add     r2, r2, r2, lsl #16                      @ Duplicate value 2 into both halves of a register for flags.
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        bics    rR15, rR15, r2                           @ Bit clear and set flags
        mrs     rARM, cpsr                               @ Read flags from CPSR
        ldrh    r2, [rGSU, #30]                          @ Load R15. WYATT_TODO unnecessary
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        add     r2, r2, #1                               @ R15++
        strh    r2, [rGSU, #30]                          @ Store R15
        strh    rR15, [rDREG]                            @ Store result to DREG
        add     rR15, rGSU, #28                          @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        ldrheq  rR15, [rGSU, #28]                        @  |
        ldreq   r2, [rGSU, #408]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        strbeq  rR15, [rGSU, #38]                        @  |
        b       loop_head                                @ 

@ UMULT: 8-bit to 16-bit unsigned multiply, SREG * register N, stored in DREG
handle_fx_umult_r:
        ldrb    rR15, [rSREG]                            @ Load value 1
        ldrb    r2, [rGSU, vLow, lsl #1]                 @ Load value 2
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        smulbb  rR15, rR15, r2                           @ Multiply
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        lsl     rARM, rR15, #16                          @ Shift result to top of register
        movs    rARM, rARM                               @ Set flags
        mrs     rARM, cpsr                               @ Read flags from CPSR
        ldrh    r2, [rGSU, #30]                          @ Load R15. WYATT_TODO unnecessary
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        add     r2, r2, #1                               @ R15++
        strh    r2, [rGSU, #30]                          @ Store R15
        strh    rR15, [rDREG]                            @ Store result
        add     rR15, rGSU, #28                          @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        ldrheq  rR15, [rGSU, #28]                        @  |
        ldreq   r2, [rGSU, #408]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        strbeq  rR15, [rGSU, #38]                        @  |
        b       loop_head                                @ 

@ DIV2: Divides SREG by 2 and stores in DREG
handle_fx_div2:
        ldrh    rR15, [rSREG]                            @ Load value
        ldrh    r2, [rGSU, #58]                          @ Load 0xFFFF
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        cmp     r2, rR15                                 @ Compare value to 0xFFFF
        ldrh    r2, [rGSU, #30]                          @ Load R15. WYATT_TODO unnecessary
        moveq   rR15, #1                                 @ If value == 0xFFFF, set value to 1
        add     r2, r2, #1                               @ R15++
        strh    r2, [rGSU, #30]                          @ Store R15
        sxthne  rR15, rR15                               @ Sign-extend value
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        asrs    rR15, rR15, #1                           @ Divide value by 2 with ASR
        mrs     rARM, cpsr                               @ Read flags from CPSR
        strh    rR15, [rDREG]                            @ Store result
        add     rR15, rGSU, #28                          @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        ldrheq  rR15, [rGSU, #28]                        @  |
        ldreq   r2, [rGSU, #408]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        strbeq  rR15, [rGSU, #38]                        @  |
        b       loop_head                                @ 

@ LJMP: set program bank to register N and jump to SREG
handle_fx_ljmp_r:
        lsl     vLow, vLow, #1                           @ Shift vLow for 2-byte offset
        ldrh    rR15, [rGSU, vLow]                       @ Load bank
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        and     rR15, rR15, #127                         @ AND bank to 7-bit
        strb    rR15, [rGSU, #39]                        @ Store bank to GSU.vPrgBankReg 
        add     rR15, rR15, #108                         @ Offset magic for apvRomBank
        ldr     rR15, [rGSU, rR15, lsl #2]               @ Load pointer at GSU.apvRomBank[GSU.vPrgBankReg]
        ldrh    r2, [rSREG]                              @ Load destination
        str     rR15, [rGSU, #412]                       @ Store GSU.pvPrgBank pointer
        mov     rR15, #0                                 @ GSU.vCacheFlags = 0
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        str     rR15, [rGSU, #72]                        @ GSU.vCacheFlags = 0
        mov     rR15, #1                                 @ Enable cache
        strb    rR15, [rGSU, #1456]                      @  |
        bic     rR15, r2, #15                            @ R15 & 0xfff0
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strh    rR15, [rGSU, #32]                        @ GSU.vCacheBaseReg = R15 & 0xfff0
        strh    r2, [rGSU, #30]                          @ Store destination to R15
        b       loop_head                                @ 

@ LMULT: 16-bit to 32-bit signed multiplication SREG * R6, low result in R4, then high result in DREG.
handle_fx_lmult:
        ldrh    rR15, [rSREG]                            @ Load value 1
        ldrh    r2, [rGSU, #12]                          @ Load value 2
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        smulbb  rR15, rR15, r2                           @ Multiply
        ldrh    r2, [rGSU, #30]                          @ Load R15. WYATT_TODO unnecessary
        strh    rR15, [rGSU, #8]                         @ Store low result
        add     r2, r2, #1                               @ R15++
        strh    r2, [rGSU, #30]                          @ Store R15
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        asrs    rR15, rR15, #16                          @ Set flags and shift high result down
        mrs     rARM, cpsr                               @ Read flags from CPSR
        strh    rR15, [rDREG]                            @ Store high result
        add     rR15, rGSU, #28                          @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        ldrheq  rR15, [rGSU, #28]                        @  |
        ldreq   r2, [rGSU, #408]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        strbeq  rR15, [rGSU, #38]                        @  |
        b       loop_head                                @ 

@ LMS: load word from RAM (short address), store in register N
@ WYATT_TODO would this be better with a bespoke R15 version?
handle_fx_lms_r:
        lsl     ip, ip, #1                               @ Shift PIPE left 1
        add     r2, rR15, #1                             @ R15 + 1 into scratch register
        strh    ip, [rGSU, #34]                          @ Store shifted pipe GSU.vLastRamAdr
        uxth    r2, r2                                   @ Wrap scratch R15 at 16 bits
        add     rR15, rR15, #2                           @ R15 + 2
        ldrb    rPIPE, [r1, r2]                          @ FETCHPIPE
        strh    rR15, [rGSU, #30]                        @ Store R15
        ldr     rR15, [rGSU, #404]                       @ Load RAM base pointer
        add     r2, ip, #1                               @ GSU.vLastRamAdr + 1
        ldrb    r2, [rR15, r2]                           @ Load upper byte
        ldrb    rR15, [rR15, ip]                         @ Load lower byte
        lsl     vLow, vLow, #1                           @ Shift vLow for 2-byte offset
        orr     rR15, rR15, r2, lsl #8                   @ Combine both bytes
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strh    rR15, [rGSU, vLow]                       @ Store result
        b       loop_head                                @ 
        
@ LMS: load word from RAM (short address), store in register 14, then READR14
handle_fx_lms_r14:
        lsl     ip, ip, #1                               @ Shift PIPE left 1
        add     r2, rR15, #1                             @ R15 + 1 into scratch register
        strh    ip, [rGSU, #34]                          @ Store shifted pipe GSU.vLastRamAdr
        uxth    r2, r2                                   @ Wrap scratch R15 at 16 bits
        add     rR15, rR15, #2                           @ R15 + 2
        ldrb    rPIPE, [r1, r2]                          @ FETCHPIPE
        strh    rR15, [rGSU, #30]                        @ Store R15 + 2
        ldr     rR15, [rGSU, #404]                       @ Load RAM base pointer
        add     r2, ip, #1                               @ GSU.vLastRamAdr + 1
        ldrb    r2, [rR15, r2]                           @ Load upper byte
        ldrb    rR15, [rR15, ip]                         @ Load lower byte
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        orr     rR15, rR15, r2, lsl #8                   @ Combine both bytes
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        strh    rR15, [rGSU, #28]                        @ Store result in R14
        ldr     r2, [rGSU, #408]                         @ READR14: Load ROM base pointer
        ldrb    rR15, [r2, rR15]                         @ READR14: Load ROM(R14)
        strb    rR15, [rGSU, #38]                        @ READR14: Store to ROMBUFFER
        b       loop_head                                @ 

@ XOR: exclusive OR between SREG and register N, stored in DREG
handle_fx_xor_r:
        lsl     vLow, vLow, #1                           @ Shift vLow for 2-byte offset
        ldrh    rR15, [rSREG]                            @ Load value 1
        ldrh    r2, [rGSU, vLow]                         @ Load value 2
        add     rR15, rR15, rR15, lsl #16                @ Duplicate value 1 into both halves of a register
        add     r2, r2, r2, lsl #16                      @ Duplicate value 2 into both halves of a register
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        eors    rR15, rR15, r2                           @ XOR and set flags
        mrs     rARM, cpsr                               @ Read flags from CPSR
        ldrh    r2, [rGSU, #30]                          @ Load R15. WYATT_TODO unnecessary
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        add     r2, r2, #1                               @ R15++
        strh    r2, [rGSU, #30]                          @ Store R15
        strh    rR15, [rDREG]                            @ Store result
        add     rR15, rGSU, #28                          @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        ldrheq  rR15, [rGSU, #28]                        @  |
        ldreq   r2, [rGSU, #408]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        strbeq  rR15, [rGSU, #38]                        @  |
        b       loop_head                                @ 

@ GETBH: Overwrite the high byte in SREG with ROMBUFFER, stored in DREG
handle_fx_getbh:
        add     r2, rR15, #1                             @ R15++
        ldrb    rR15, [rSREG]                            @ Load SREG bottom byte
        strh    r2, [rGSU, #30]                          @ Store R15
        ldrb    r2, [rGSU, #38]                          @ Load ROMBUFFER
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        orr     rR15, rR15, r2, lsl #8                   @ Combine both sources
        strh    rR15, [rDREG]                            @ Store result
        add     rR15, rGSU, #28                          @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        ldrheq  rR15, [rGSU, #28]                        @  |
        ldreq   r2, [rGSU, #408]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        strbeq  rR15, [rGSU, #38]                        @  |
        b       loop_head                                @ 

@ LM: Load word from RAM and store it in register N. The address is fetched from PIPE.
@ WYATT_TODO validate me.
handle_fx_lm_r:
        lsl     vLow, vLow, #1                           @ Shift vLow for 2-byte offset
        add     r2, rR15, #1                             @ R15 + 1 into scratch register
        uxth    r2, r2                                   @ Wrap R15 at 16 bits
        ldrb    rPIPE, [r1, r2]                          @ FETCHPIPE
        add     r2, rR15, #2                             @ R15 + 2 into scratch register
        orr     ip, ip, rPIPE, lsl #8                    @ Combine both bytes of destination
        strh    ip, [rGSU, #34]                          @ Store destination to vLastRamAdr
        uxth    r2, r2                                   @ Wrap R15 at 16 bits
        add     rR15, rR15, #3                           @ R15 + 3
        ldrb    rPIPE, [r1, r2]                          @ FETCHPIPE
        strh    rR15, [rGSU, #30]                        @ Store R15
        ldr     rR15, [rGSU, #404]                       @ Load RAM base pointer
        eor     r2, ip, #1                               @ Flip bottom bit of offset
        ldrb    r2, [rR15, r2]                           @ Load top half of result
        ldrb    ip, [rR15, ip]                           @ Load bottom half of result
        orr     ip, ip, r2, lsl #8                       @ Combine result
        strh    ip, [rGSU, vLow]                         @ Store result
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        b       loop_head                                @ 

@ LM: Load word from RAM and store it in register N, then READR14. The address is fetched from PIPE.
@ WYATT_TODO validate me.
handle_fx_lm_r14:
        add     r2, rR15, #1                             @ R15 + 1 into scratch register
        uxth    r2, r2                                   @ Wrap R15 at 16 bits
        ldrb    rPIPE, [r1, r2]                          @ FETCHPIPE
        add     r2, rR15, #2                             @ R15 + 2 into scratch register
        orr     ip, ip, rPIPE, lsl #8                    @ Combine both bytes of destination
        strh    ip, [rGSU, #34]                          @ Store destination to vLastRamAdr
        uxth    r2, r2                                   @ Wrap R15 at 16 bits
        add     rR15, rR15, #3                           @ R15 + 3
        ldrb    rPIPE, [r1, r2]                          @ FETCHPIPE
        strh    rR15, [rGSU, #30]                        @ Store R15
        ldr     rR15, [rGSU, #404]                       @ Load RAM base pointer
        eor     r2, ip, #1                               @ Flip bottom bit of offset
        ldrb    r2, [rR15, r2]                           @ Load top half of result
        ldrb    ip, [rR15, ip]                           @ Load bottom half of result
        orr     ip, ip, r2, lsl #8                       @ Combine result
        strh    ip, [rGSU, #28]                          @ Store result
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        ldr     r2, [rGSU, #408]                         @ READR14: Load ROM base pointer
        ldrb    ip, [r2, ip]                             @ READR14: Load ROM(R14)
        strb    ip, [rGSU, #38]                          @ READR14: Store to ROMBUFFER
        b       loop_head                                @ 

@ ADD_I: Add SREG + 4-bit immediate, store in DREG
handle_fx_add_i:
        ldrh    rARM, [rSREG]                            @ Load SREG
        ldrh    r2, [rGSU, #30]                          @ Load R15. WYATT_TODO unnecessary
        lsl     rARM, rARM, #16                          @ Shift SREG into top half of register
        add     r2, r2, #1                               @ R15++
        adds    rR15, rARM, vLow, lsl #16                @ Add SREG and immediate, set flags
        mrs     rARM, cpsr                               @ Read flags from CPSR
        lsr     rR15, rR15, #16                          @ Shift result to bottom half of register
        strh    r2, [rGSU, #30]                          @ Store R15
        strh    rR15, [rDREG]                            @ Store result
        add     rR15, rGSU, #28                          @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        ldrheq  rR15, [rGSU, #28]                        @  |
        ldreq   r2, [rGSU, #408]                         @  |
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strbeq  rR15, [rGSU, #38]                        @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       loop_head                                @ 

@ SUB_I: Subtract SREG - 4-bit immediate, store in DREG
handle_fx_sub_i:
        ldrh    rARM, [rSREG]                            @ Load SREG
        ldrh    r2, [rGSU, #30]                          @ Load R15. WYATT_TODO unnecessary
        lsl     rARM, rARM, #16                          @ Shift SREG into top half of register
        add     r2, r2, #1                               @ R15++
        subs    rR15, rARM, vLow, lsl #16                @ Subtract SREG and immediate, set flags
        mrs     rARM, cpsr                               @ Read flags from CPSR
        lsr     rR15, rR15, #16                          @ Shift result to bottom half of register
        strh    r2, [rGSU, #30]                          @ Store R15
        strh    rR15, [rDREG]                            @ Store result
        add     rR15, rGSU, #28                          @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        ldrheq  rR15, [rGSU, #28]                        @  |
        ldreq   r2, [rGSU, #408]                         @  |
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strbeq  rR15, [rGSU, #38]                        @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       loop_head                                @ 

@ AND_I: Logically AND SREG and 4-bit immediate, store in DREG
handle_fx_and_i:
        ldrh    r2, [rGSU, #30]                          @ Load R15. WYATT_TODO unnecessary
        ldrh    rR15, [rSREG]                            @ Load SREG
        add     r2, r2, #1                               @ R15++
        strh    r2, [rGSU, #30]                          @ Store R15
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        ands    rR15, rR15, vLow                         @ AND SREG and immediate, set flags
        mrs     rARM, cpsr                               @ Read flags from CPSR
        strh    rR15, [rDREG]                            @ Store result
        add     rR15, rGSU, #28                          @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        ldrheq  rR15, [rGSU, #28]                        @  |
        ldreq   r2, [rGSU, #408]                         @  |
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strbeq  rR15, [rGSU, #38]                        @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       loop_head                                @ 

@ MULT: multiply SREG and 4-bit immediate as signed 8-bit ints, store in DREG
handle_fx_mult_i:
        ldrsb   rR15, [rSREG]                            @ Load SREG as s8
        ldrh    r2, [rGSU, #30]                          @ Load R15. WYATT_TODO unnecessary
        smulbb  rR15, rR15, vLow                         @ Multiply SREG and immediate
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        movs    rARM, rR15                               @ Set flags
        mrs     rARM, cpsr                               @ Read flags from CPSR
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        add     r2, r2, #1                               @ R15++
        strh    r2, [rGSU, #30]                          @ Store R15
        strh    rR15, [rDREG]                            @ Store result
        add     rR15, rGSU, #28                          @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        ldrheq  rR15, [rGSU, #28]                        @  |
        ldreq   r2, [rGSU, #408]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        strbeq  rR15, [rGSU, #38]                        @  |
        b       loop_head                                @ 

@ SMS: Store register N in RAM (short address). The address is fetched from PIPE.
handle_fx_sms_r:
        add     rR15, rR15, #1                           @ R15++
        lsl     ip, ip, #1                               @ Shift PIPE left 1
        uxth    rR15, rR15                               @ Wrap R15 at 16 bits
        lsl     vLow, vLow, #1                           @ Shift vLow for 2-byte offset
        ldrh    r2, [rGSU, vLow]                         @ Load value from register N
        strh    ip, [rGSU, #34]                          @ Store shifted pipe GSU.vLastRamAdr
        strh    rR15, [rGSU, #30]                        @ Store R15. WYATT_TODO unnecessary
        ldrb    rPIPE, [r1, rR15]                        @ FETCHPIPE
        ldr     rR15, [rGSU, #404]                       @ Load RAM base pointer
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        strb    r2, [rR15, ip]                           @ Store bottom byte of result
        ldrh    rR15, [rGSU, #34]                        @ Reload GSU.vLastRamAdr. WYATT_TODO unnecessary
        ldr     r1, [rGSU, #404]                         @ Reload RAM base pointer. WYATT_TODO unnecessary
        add     rR15, rR15, #1                           @ R15++
        lsr     r2, r2, #8                               @ Prep top byte of result
        uxth    rR15, rR15                               @ Wrap R15 at 16 bits
        strb    r2, [r1, rR15]                           @ Store top byte of result
        ldrh    rR15, [rGSU, #30]                        @ Reload R15. WYATT_TODO unnecessary
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        add     rR15, rR15, #1                           @ R15++
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        strh    rR15, [rGSU, #30]                        @ Store R15
        b       loop_head                                @ 

@ OR_I: Logically OR SREG and 4-bit immediate, store in DREG
handle_fx_or_i:
        ldrh    r2, [rGSU, #30]                          @ Load R15. WYATT_TODO unnecessary
        ldrh    rR15, [rSREG]                            @ Load SREG
        add     r2, r2, #1                               @ R15++
        strh    r2, [rGSU, #30]                          @ Store R15
        add     rR15, rR15, rR15, lsl #16                @ Duplicate value into both halves of a register
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        orrs    rR15, rR15, vLow                         @ OR SREG and immediate, set flags
        mrs     rARM, cpsr                               @ Read flags from CPSR
        strh    rR15, [rDREG]                            @ Store result
        add     rR15, rGSU, #28                          @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        ldrheq  rR15, [rGSU, #28]                        @  |
        ldreq   r2, [rGSU, #408]                         @  |
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strbeq  rR15, [rGSU, #38]                        @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       loop_head                                @ 

@ RAMB: Set current RAM bank to SREG
handle_fx_ramb:
        ldrh    r2, [rSREG]                              @ Load SREG
        add     rR15, rR15, #1                           @ R15++
        strh    rR15, [rGSU, #30]                        @ Store R15
        and     rR15, r2, #3                             @ SREG & (FX_RAM_BANKS - 1)
        strb    rR15, [rGSU, #41]                        @ Store to GSU.vRamBankReg
        add     rR15, rR15, #104                         @ Offset magic for apvRamBank
        ldr     rR15, [rGSU, rR15, lsl #2]               @ Load pointer at GSU.apvRamBank[GSU.vRamBankReg]
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        str     rR15, [rGSU, #404]                       @ Store to GSU.pvRamBank
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       loop_head                                @ 

@ GETBL: Overwrite the low byte in SREG with ROMBUFFER, stored in DREG
handle_fx_getbl:
        add     r2, rR15, #1                             @ R15++
        ldrh    rR15, [rSREG]                            @ Load SREG
        strh    r2, [rGSU, #30]                          @ Store R15
        ldrb    r2, [rGSU, #38]                          @ Load ROMBUFFER
        and     rR15, rR15, #65280                       @ Clear SREG bottom byte
        orr     rR15, rR15, r2                           @ Combine both sources
        strh    rR15, [rDREG]                            @ Store result
        add     rR15, rGSU, #28                          @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        ldrheq  rR15, [rGSU, #28]                        @  |
        ldreq   r2, [rGSU, #408]                         @  |
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strbeq  rR15, [rGSU, #38]                        @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       loop_head                                @ 

@ SM: Store register N in RAM. The address is fetched from PIPE.
handle_fx_sm_r:
        lsl     vLow, vLow, #1                           @ Shift vLow for 2-byte offset
        ldrh    r2, [rGSU, vLow]                         @ Load register N
        add     vLow, rR15, #1                           @ R15 + 1 into scratch register
        uxth    vLow, vLow                               @ Wrap R15 at 16 bits
        strh    ip, [rGSU, #34]                          @ Store bottom byte of PIPE at GSU.vLastRamAdr. WYATT_TODO unnecessary
        strh    vLow, [rGSU, #30]                        @ Store R15. WYATT_TODO unnecessary
        ldrb    rPIPE, [r1, vLow]                        @ FETCHPIPE
        add     rR15, rR15, #2                           @ R15 + 2
        orr     ip, ip, rPIPE, lsl #8                    @ Combine both bytes of destination
        uxth    rR15, rR15                               @ Wrap R15 at 16 bits
        strh    rR15, [rGSU, #30]                        @ Store R15. WYATT_TODO unnecessary
        strh    ip, [rGSU, #34]                          @ Store PIPE at GSU.vLastRamAdr
        ldrb    rPIPE, [r1, rR15]                        @ FETCHPIPE
        ldr     rR15, [rGSU, #404]                       @ Load RAM base pointer
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        strb    r2, [rR15, ip]                           @ Store lower byte
        ldrh    rR15, [rGSU, #34]                        @ Reload GSU.vLastRamAdr. WYATT_TODO unnecessary
        ldr     r1, [rGSU, #404]                         @ Reload RAM base pointer. WYATT_TODO unnecessary
        lsr     r2, r2, #8                               @ Prep upper byte
        eor     rR15, rR15, #1                           @ Flip bottom bit of offset
        strb    r2, [r1, rR15]                           @ Store upper byte
        ldrh    rR15, [rGSU, #30]                        @ Reload R15. WYATT_TODO unnecessary
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        add     rR15, rR15, #1                           @ R15++
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        strh    rR15, [rGSU, #30]                        @ Store R15
        b       loop_head                                @ 

@ ADC_I: add-with-carry, SREG + 4-bit immediate, store in DREG
handle_fx_adc_i:
        ldrh    rR15, [rGSU, #30]                        @ Load R15. WYATT_TODO unnecessary
        ldrh    r2, [rSREG]                              @ Load SREG
        add     rR15, rR15, #1                           @ R15++
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        lsl     rARM, r2, #16                            @ Shift SREG into the upper half of the register
        orrcs   rARM, rARM, #32768                       @ Move carry flag into SREG
        orrcs   vLow, vLow, #-2147483648                 @ Move carry flag into immediate
        adds    vLow, rARM, vLow, ror #16                @ Add the values and set flags
        mrs     rARM, cpsr                               @ Read flags from CPSR
        lsr     vLow, vLow, #16                          @ Shift result into bottom half of register
        strh    rR15, [rGSU, #30]                        @ Store R15
        strh    vLow, [rDREG]                            @ Store result
        add     rR15, rGSU, #28                          @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        ldrheq  rR15, [rGSU, #28]                        @  |
        ldreq   r2, [rGSU, #408]                         @  |
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strbeq  rR15, [rGSU, #38]                        @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       loop_head                                @ 

@ CMP: Compare SREG to register N. Effectively a subtract with no result.
handle_fx_cmp_r:
        ldrh    rR15, [rSREG]                            @ Load SREG
        lsl     vLow, vLow, #1                           @ Shift vLow for 2-byte offset
        ldrh    rARM, [rGSU, vLow]                       @ Load register N
        lsl     rR15, rR15, #16                          @ Shift SREG into the upper half of the register
        cmp     rR15, rARM, lsl #16                      @ Compare to set flags
        mrs     rARM, cpsr                               @ Read flags from CPSR
        ldrh    rR15, [rGSU, #30]                        @ Load R15. WYATT_TODO unnecessary
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        add     rR15, rR15, #1                           @ R15++
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        strh    rR15, [rGSU, #30]                        @ Store R15
        b       loop_head                                @ 

@ BIC_I: DREG = SREG & ~4-bit immediate
handle_fx_bic_i:
        ldrh    r2, [rGSU, #30]                          @ Load R15. WYATT_TODO unnecessary
        ldrh    rR15, [rSREG]                            @ Load SREG
        add     r2, r2, #1                               @ R15++
        strh    r2, [rGSU, #30]                          @ Store R15
        add     vLow, vLow, vLow, lsl #16                @ Duplicate immediate into both halves of a register
        add     rR15, rR15, rR15, lsl #16                @ Duplicate SREG into both halves of a register
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        bics    rR15, rR15, vLow                         @ Bit clear and set flags
        mrs     rARM, cpsr                               @ Read flags from CPSR
        strh    rR15, [rDREG]                            @ Store result
        add     rR15, rGSU, #28                          @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        ldrheq  rR15, [rGSU, #28]                        @  |
        ldreq   r2, [rGSU, #408]                         @  |
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strbeq  rR15, [rGSU, #38]                        @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       loop_head                                @ 

@ UMULT_I: 8-bit to 16-bit unsigned multiply, SREG * 4-bit immediate, stored in DREG
handle_fx_umult_i:
        ldrb    rR15, [rSREG]                            @ Load SREG
        ldrh    r2, [rGSU, #30]                          @ Load R15. WYATT_TODO unnecessary
        smulbb  rR15, rR15, vLow                         @ Multiply SREG * immediate
        msr     cpsr_f, rARM                             @ Move flags into CPSR
        movs    rARM, rR15                               @ Set flags
        mrs     rARM, cpsr                               @ Read flags from CPSR
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        add     r2, r2, #1                               @ R15++
        strh    r2, [rGSU, #30]                          @ Store R15
        strh    rR15, [rDREG]                            @ Store result
        add     rR15, rGSU, #28                          @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        ldrheq  rR15, [rGSU, #28]                        @  |
        ldreq   r2, [rGSU, #408]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        strbeq  rR15, [rGSU, #38]                        @  |
        b       loop_head                                @ 

@ XOR_I: exclusive OR between SREG and 4-bit immediate, stored in DREG
handle_fx_xor_i:
        ldrh    r2, [rGSU, #30]                          @ Load R15. WYATT_TODO unnecessary
        ldrh    rR15, [rSREG]                            @ Load SREG
        add     r2, r2, #1                               @ R15++
        strh    r2, [rGSU, #30]                          @ Store R15
        add     vLow, vLow, vLow, lsl #16                @ Duplicate immediate into both halves of a register
        add     rR15, rR15, rR15, lsl #16                @ Duplicate SREG into both halves of a register
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        eors    rR15, rR15, vLow                         @ XOR and set flags
        mrs     rARM, cpsr                               @ Read flags from CPSR
        strh    rR15, [rDREG]                            @ Store result
        add     rR15, rGSU, #28                          @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        ldrheq  rR15, [rGSU, #28]                        @  |
        ldreq   r2, [rGSU, #408]                         @  |
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strbeq  rR15, [rGSU, #38]                        @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       loop_head                                @ 

@ ROMB: set program bank to SREG
handle_fx_romb:
        ldrh    r2, [rSREG]                              @ Load SREG
        add     rR15, rR15, #1                           @ R15++
        strh    rR15, [rGSU, #30]                        @ Store R15
        and     rR15, r2, #127                           @ Clear top bit of SREG
        strb    rR15, [rGSU, #40]                        @ Store SREG to GSU.vRomBankReg
        add     rR15, rR15, #108                         @ Offset magic for apvRomBank
        ldr     rR15, [rGSU, rR15, lsl #2]               @ Load pointer at GSU.apvRomBank[GSU.vPrgBankReg]
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        str     rR15, [rGSU, #408]                       @ Store to GSU.pvRomBank
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       loop_head                                @ 

@ FROM: If B is not set, set SREG to register N and increment R15
handle_fx_from_r.b_is_not_set:
        add     rR15, rR15, #1                           @ R15++
        strh    rR15, [rGSU, #30]                        @ Store R15
        add     rSREG, rGSU, vLow, lsl #1                @ SREG = register N
        b       loop_head                                @ 

@ If B flag is not set, set DREG to R15 and increment R15
handle_fx_to_r15.b_is_not_set:
        add     rR15, rR15, #1                           @ R15++
        strh    rR15, [rGSU, #30]                        @ Store R15
        add     rDREG, rGSU, #30                         @ DREG = R15
        b       loop_head                                @ 

@ If B flag is set, move SREG to R14, CLRFLAGS, and READR14
handle_fx_to_r14.b_is_set:
        ldrh    r2, [rSREG]                              @ Load SREG
        ldr     r1, [rGSU, #408]                         @ READR14: Load GSU.pvRomBank
        strh    r2, [rGSU, #28]                          @ R14 = SREG
        ldrb    r2, [r1, r2]                             @ READR14: Load GSU.pvRomBank[R14]
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strb    r2, [rGSU, #38]                          @ READR14: Store ROMBUFFER
        b       .L84                                     @ Branch back to main handler

@ If (X ^ Y) is odd, use top half of color. Else, use bottom half.
@ Inlining this or not is a bit of a tossup
handle_fx_plot_2bit.L237:
        eor     ip, r1, rR15                             @ X ^ Y
        tst     ip, #1                                   @ Test if odd
        lsrne   r2, r2, #4                               @ Odd X uses top nibble of color
        b       .L15                                     @ 

@ If !((plotOptionReg & 1) || (color & 0xf))
handle_fx_plot_8bit.L239:
        and     ip, r1, #15                              @ 
        orrs    vLow, vLow, ip                           @ 
        bne     .L40                                     @ 
        b       loop_head                                @ 

@ If (X ^ Y) is odd, use top half of color. Else, use bottom half.
@ Inlining this or not is a bit of a tossup
handle_fx_plot_4bit.L238:
        eor     ip, r1, rR15                             @ X ^ Y
        tst     ip, #1                                   @ Test if odd
        lsrne   r2, r2, #4                               @ Odd X uses top nibble of color
        b       .L25                                     @ 

@ fx_cache: second half of the conditional, down here since it's UNLIKELY.
@ Only reached if GSU.vCacheBaseReg says we need a reload
.cache_test_active:
        ldrb    r1, [rGSU, #1456]                        @ Load GSU.bCacheActive
        cmp     r1, #0                                   @ 
        bne     .skip_cache_reload                       @ If active, skip reloading since it's already correct
        b       .reload_cache                            @ Else, we need to reload cache
    .cfi_endproc

    .section	.rodata
    .align	2
    .type	plot_rpix_handler_table, %object
plot_rpix_handler_table:
        .word   handle_fx_plot_2bit
        .word   handle_fx_rpix_2bit
        .word   handle_fx_plot_4bit
        .word   handle_fx_rpix_4bit
        .word   handle_fx_plot_4bit
        .word   handle_fx_rpix_4bit
        .word   handle_fx_plot_8bit
        .word   handle_fx_rpix_8bit

    .data
    .align	2
    .type	opcode_goto_table, %object
opcode_goto_table:
        .word   handle_fx_stop
        .word   handle_fx_nop
        .word   handle_fx_cache
        .word   handle_fx_lsr
        .word   handle_fx_rol
        .word   handle_fx_bra
        .word   handle_fx_bge
        .word   handle_fx_blt
        .word   handle_fx_bne
        .word   handle_fx_beq
        .word   handle_fx_bpl
        .word   handle_fx_bmi
        .word   handle_fx_bcc
        .word   handle_fx_bcs
        .word   handle_fx_bvc
        .word   handle_fx_bvs
        .word   handle_fx_to_r
        .word   handle_fx_to_r
        .word   handle_fx_to_r
        .word   handle_fx_to_r
        .word   handle_fx_to_r
        .word   handle_fx_to_r
        .word   handle_fx_to_r
        .word   handle_fx_to_r
        .word   handle_fx_to_r
        .word   handle_fx_to_r
        .word   handle_fx_to_r
        .word   handle_fx_to_r
        .word   handle_fx_to_r
        .word   handle_fx_to_r
        .word   handle_fx_to_r14
        .word   handle_fx_to_r15
        .word   handle_fx_with
        .word   handle_fx_with
        .word   handle_fx_with
        .word   handle_fx_with
        .word   handle_fx_with
        .word   handle_fx_with
        .word   handle_fx_with
        .word   handle_fx_with
        .word   handle_fx_with
        .word   handle_fx_with
        .word   handle_fx_with
        .word   handle_fx_with
        .word   handle_fx_with
        .word   handle_fx_with
        .word   handle_fx_with
        .word   handle_fx_with
        .word   handle_fx_stw_r
        .word   handle_fx_stw_r
        .word   handle_fx_stw_r
        .word   handle_fx_stw_r
        .word   handle_fx_stw_r
        .word   handle_fx_stw_r
        .word   handle_fx_stw_r
        .word   handle_fx_stw_r
        .word   handle_fx_stw_r
        .word   handle_fx_stw_r
        .word   handle_fx_stw_r
        .word   handle_fx_stw_r
        .word   handle_fx_loop
        .word   handle_fx_alt1
        .word   handle_fx_alt2
        .word   handle_fx_alt3
        .word   handle_fx_ldw_r
        .word   handle_fx_ldw_r
        .word   handle_fx_ldw_r
        .word   handle_fx_ldw_r
        .word   handle_fx_ldw_r
        .word   handle_fx_ldw_r
        .word   handle_fx_ldw_r
        .word   handle_fx_ldw_r
        .word   handle_fx_ldw_r
        .word   handle_fx_ldw_r
        .word   handle_fx_ldw_r
        .word   handle_fx_ldw_r
        .word   handle_fx_plot_2bit
        .word   handle_fx_swap
        .word   handle_fx_color
        .word   handle_fx_not
        .word   handle_fx_add_r
        .word   handle_fx_add_r
        .word   handle_fx_add_r
        .word   handle_fx_add_r
        .word   handle_fx_add_r
        .word   handle_fx_add_r
        .word   handle_fx_add_r
        .word   handle_fx_add_r
        .word   handle_fx_add_r
        .word   handle_fx_add_r
        .word   handle_fx_add_r
        .word   handle_fx_add_r
        .word   handle_fx_add_r
        .word   handle_fx_add_r
        .word   handle_fx_add_r
        .word   handle_fx_add_r
        .word   handle_fx_sub_r
        .word   handle_fx_sub_r
        .word   handle_fx_sub_r
        .word   handle_fx_sub_r
        .word   handle_fx_sub_r
        .word   handle_fx_sub_r
        .word   handle_fx_sub_r
        .word   handle_fx_sub_r
        .word   handle_fx_sub_r
        .word   handle_fx_sub_r
        .word   handle_fx_sub_r
        .word   handle_fx_sub_r
        .word   handle_fx_sub_r
        .word   handle_fx_sub_r
        .word   handle_fx_sub_r
        .word   handle_fx_sub_r
        .word   handle_fx_merge
        .word   handle_fx_and_r
        .word   handle_fx_and_r
        .word   handle_fx_and_r
        .word   handle_fx_and_r
        .word   handle_fx_and_r
        .word   handle_fx_and_r
        .word   handle_fx_and_r
        .word   handle_fx_and_r
        .word   handle_fx_and_r
        .word   handle_fx_and_r
        .word   handle_fx_and_r
        .word   handle_fx_and_r
        .word   handle_fx_and_r
        .word   handle_fx_and_r
        .word   handle_fx_and_r
        .word   handle_fx_mult_r
        .word   handle_fx_mult_r
        .word   handle_fx_mult_r
        .word   handle_fx_mult_r
        .word   handle_fx_mult_r
        .word   handle_fx_mult_r
        .word   handle_fx_mult_r
        .word   handle_fx_mult_r
        .word   handle_fx_mult_r
        .word   handle_fx_mult_r
        .word   handle_fx_mult_r
        .word   handle_fx_mult_r
        .word   handle_fx_mult_r
        .word   handle_fx_mult_r
        .word   handle_fx_mult_r
        .word   handle_fx_mult_r
        .word   handle_fx_sbk
        .word   handle_fx_link_i
        .word   handle_fx_link_i
        .word   handle_fx_link_i
        .word   handle_fx_link_i
        .word   handle_fx_sex
        .word   handle_fx_asr
        .word   handle_fx_ror
        .word   handle_fx_jmp_r
        .word   handle_fx_jmp_r
        .word   handle_fx_jmp_r
        .word   handle_fx_jmp_r
        .word   handle_fx_jmp_r
        .word   handle_fx_jmp_r
        .word   handle_fx_lob
        .word   handle_fx_fmult
        .word   handle_fx_ibt_r
        .word   handle_fx_ibt_r
        .word   handle_fx_ibt_r
        .word   handle_fx_ibt_r
        .word   handle_fx_ibt_r
        .word   handle_fx_ibt_r
        .word   handle_fx_ibt_r
        .word   handle_fx_ibt_r
        .word   handle_fx_ibt_r
        .word   handle_fx_ibt_r
        .word   handle_fx_ibt_r
        .word   handle_fx_ibt_r
        .word   handle_fx_ibt_r
        .word   handle_fx_ibt_r
        .word   handle_fx_ibt_r14
        .word   handle_fx_ibt_r
        .word   handle_fx_from_r
        .word   handle_fx_from_r
        .word   handle_fx_from_r
        .word   handle_fx_from_r
        .word   handle_fx_from_r
        .word   handle_fx_from_r
        .word   handle_fx_from_r
        .word   handle_fx_from_r
        .word   handle_fx_from_r
        .word   handle_fx_from_r
        .word   handle_fx_from_r
        .word   handle_fx_from_r
        .word   handle_fx_from_r
        .word   handle_fx_from_r
        .word   handle_fx_from_r
        .word   handle_fx_from_r
        .word   handle_fx_hib
        .word   handle_fx_or_r
        .word   handle_fx_or_r
        .word   handle_fx_or_r
        .word   handle_fx_or_r
        .word   handle_fx_or_r
        .word   handle_fx_or_r
        .word   handle_fx_or_r
        .word   handle_fx_or_r
        .word   handle_fx_or_r
        .word   handle_fx_or_r
        .word   handle_fx_or_r
        .word   handle_fx_or_r
        .word   handle_fx_or_r
        .word   handle_fx_or_r
        .word   handle_fx_or_r
        .word   handle_fx_inc_r
        .word   handle_fx_inc_r
        .word   handle_fx_inc_r
        .word   handle_fx_inc_r
        .word   handle_fx_inc_r
        .word   handle_fx_inc_r
        .word   handle_fx_inc_r
        .word   handle_fx_inc_r
        .word   handle_fx_inc_r
        .word   handle_fx_inc_r
        .word   handle_fx_inc_r
        .word   handle_fx_inc_r
        .word   handle_fx_inc_r
        .word   handle_fx_inc_r
        .word   handle_fx_inc_r14
        .word   handle_fx_getc
        .word   handle_fx_dec_r
        .word   handle_fx_dec_r
        .word   handle_fx_dec_r
        .word   handle_fx_dec_r
        .word   handle_fx_dec_r
        .word   handle_fx_dec_r
        .word   handle_fx_dec_r
        .word   handle_fx_dec_r
        .word   handle_fx_dec_r
        .word   handle_fx_dec_r
        .word   handle_fx_dec_r
        .word   handle_fx_dec_r
        .word   handle_fx_dec_r
        .word   handle_fx_dec_r
        .word   handle_fx_dec_r14
        .word   handle_fx_getb
        .word   handle_fx_iwt_r
        .word   handle_fx_iwt_r
        .word   handle_fx_iwt_r
        .word   handle_fx_iwt_r
        .word   handle_fx_iwt_r
        .word   handle_fx_iwt_r
        .word   handle_fx_iwt_r
        .word   handle_fx_iwt_r
        .word   handle_fx_iwt_r
        .word   handle_fx_iwt_r
        .word   handle_fx_iwt_r
        .word   handle_fx_iwt_r
        .word   handle_fx_iwt_r
        .word   handle_fx_iwt_r
        .word   handle_fx_iwt_r14
        .word   handle_fx_iwt_r
        .word   handle_fx_stop
        .word   handle_fx_nop
        .word   handle_fx_cache
        .word   handle_fx_lsr
        .word   handle_fx_rol
        .word   handle_fx_bra
        .word   handle_fx_bge
        .word   handle_fx_blt
        .word   handle_fx_bne
        .word   handle_fx_beq
        .word   handle_fx_bpl
        .word   handle_fx_bmi
        .word   handle_fx_bcc
        .word   handle_fx_bcs
        .word   handle_fx_bvc
        .word   handle_fx_bvs
        .word   handle_fx_to_r
        .word   handle_fx_to_r
        .word   handle_fx_to_r
        .word   handle_fx_to_r
        .word   handle_fx_to_r
        .word   handle_fx_to_r
        .word   handle_fx_to_r
        .word   handle_fx_to_r
        .word   handle_fx_to_r
        .word   handle_fx_to_r
        .word   handle_fx_to_r
        .word   handle_fx_to_r
        .word   handle_fx_to_r
        .word   handle_fx_to_r
        .word   handle_fx_to_r14
        .word   handle_fx_to_r15
        .word   handle_fx_with
        .word   handle_fx_with
        .word   handle_fx_with
        .word   handle_fx_with
        .word   handle_fx_with
        .word   handle_fx_with
        .word   handle_fx_with
        .word   handle_fx_with
        .word   handle_fx_with
        .word   handle_fx_with
        .word   handle_fx_with
        .word   handle_fx_with
        .word   handle_fx_with
        .word   handle_fx_with
        .word   handle_fx_with
        .word   handle_fx_with
        .word   handle_fx_stb_r
        .word   handle_fx_stb_r
        .word   handle_fx_stb_r
        .word   handle_fx_stb_r
        .word   handle_fx_stb_r
        .word   handle_fx_stb_r
        .word   handle_fx_stb_r
        .word   handle_fx_stb_r
        .word   handle_fx_stb_r
        .word   handle_fx_stb_r
        .word   handle_fx_stb_r
        .word   handle_fx_stb_r
        .word   handle_fx_loop
        .word   handle_fx_alt1
        .word   handle_fx_alt2
        .word   handle_fx_alt3
        .word   handle_fx_ldb_r
        .word   handle_fx_ldb_r
        .word   handle_fx_ldb_r
        .word   handle_fx_ldb_r
        .word   handle_fx_ldb_r
        .word   handle_fx_ldb_r
        .word   handle_fx_ldb_r
        .word   handle_fx_ldb_r
        .word   handle_fx_ldb_r
        .word   handle_fx_ldb_r
        .word   handle_fx_ldb_r
        .word   handle_fx_ldb_r
        .word   handle_fx_rpix_2bit
        .word   handle_fx_swap
        .word   handle_fx_cmode
        .word   handle_fx_not
        .word   handle_fx_adc_r
        .word   handle_fx_adc_r
        .word   handle_fx_adc_r
        .word   handle_fx_adc_r
        .word   handle_fx_adc_r
        .word   handle_fx_adc_r
        .word   handle_fx_adc_r
        .word   handle_fx_adc_r
        .word   handle_fx_adc_r
        .word   handle_fx_adc_r
        .word   handle_fx_adc_r
        .word   handle_fx_adc_r
        .word   handle_fx_adc_r
        .word   handle_fx_adc_r
        .word   handle_fx_adc_r
        .word   handle_fx_adc_r
        .word   handle_fx_sbc_r
        .word   handle_fx_sbc_r
        .word   handle_fx_sbc_r
        .word   handle_fx_sbc_r
        .word   handle_fx_sbc_r
        .word   handle_fx_sbc_r
        .word   handle_fx_sbc_r
        .word   handle_fx_sbc_r
        .word   handle_fx_sbc_r
        .word   handle_fx_sbc_r
        .word   handle_fx_sbc_r
        .word   handle_fx_sbc_r
        .word   handle_fx_sbc_r
        .word   handle_fx_sbc_r
        .word   handle_fx_sbc_r
        .word   handle_fx_sbc_r
        .word   handle_fx_merge
        .word   handle_fx_bic_r
        .word   handle_fx_bic_r
        .word   handle_fx_bic_r
        .word   handle_fx_bic_r
        .word   handle_fx_bic_r
        .word   handle_fx_bic_r
        .word   handle_fx_bic_r
        .word   handle_fx_bic_r
        .word   handle_fx_bic_r
        .word   handle_fx_bic_r
        .word   handle_fx_bic_r
        .word   handle_fx_bic_r
        .word   handle_fx_bic_r
        .word   handle_fx_bic_r
        .word   handle_fx_bic_r
        .word   handle_fx_umult_r
        .word   handle_fx_umult_r
        .word   handle_fx_umult_r
        .word   handle_fx_umult_r
        .word   handle_fx_umult_r
        .word   handle_fx_umult_r
        .word   handle_fx_umult_r
        .word   handle_fx_umult_r
        .word   handle_fx_umult_r
        .word   handle_fx_umult_r
        .word   handle_fx_umult_r
        .word   handle_fx_umult_r
        .word   handle_fx_umult_r
        .word   handle_fx_umult_r
        .word   handle_fx_umult_r
        .word   handle_fx_umult_r
        .word   handle_fx_sbk
        .word   handle_fx_link_i
        .word   handle_fx_link_i
        .word   handle_fx_link_i
        .word   handle_fx_link_i
        .word   handle_fx_sex
        .word   handle_fx_div2
        .word   handle_fx_ror
        .word   handle_fx_ljmp_r
        .word   handle_fx_ljmp_r
        .word   handle_fx_ljmp_r
        .word   handle_fx_ljmp_r
        .word   handle_fx_ljmp_r
        .word   handle_fx_ljmp_r
        .word   handle_fx_lob
        .word   handle_fx_lmult
        .word   handle_fx_lms_r
        .word   handle_fx_lms_r
        .word   handle_fx_lms_r
        .word   handle_fx_lms_r
        .word   handle_fx_lms_r
        .word   handle_fx_lms_r
        .word   handle_fx_lms_r
        .word   handle_fx_lms_r
        .word   handle_fx_lms_r
        .word   handle_fx_lms_r
        .word   handle_fx_lms_r
        .word   handle_fx_lms_r
        .word   handle_fx_lms_r
        .word   handle_fx_lms_r
        .word   handle_fx_lms_r14
        .word   handle_fx_lms_r
        .word   handle_fx_from_r
        .word   handle_fx_from_r
        .word   handle_fx_from_r
        .word   handle_fx_from_r
        .word   handle_fx_from_r
        .word   handle_fx_from_r
        .word   handle_fx_from_r
        .word   handle_fx_from_r
        .word   handle_fx_from_r
        .word   handle_fx_from_r
        .word   handle_fx_from_r
        .word   handle_fx_from_r
        .word   handle_fx_from_r
        .word   handle_fx_from_r
        .word   handle_fx_from_r
        .word   handle_fx_from_r
        .word   handle_fx_hib
        .word   handle_fx_xor_r
        .word   handle_fx_xor_r
        .word   handle_fx_xor_r
        .word   handle_fx_xor_r
        .word   handle_fx_xor_r
        .word   handle_fx_xor_r
        .word   handle_fx_xor_r
        .word   handle_fx_xor_r
        .word   handle_fx_xor_r
        .word   handle_fx_xor_r
        .word   handle_fx_xor_r
        .word   handle_fx_xor_r
        .word   handle_fx_xor_r
        .word   handle_fx_xor_r
        .word   handle_fx_xor_r
        .word   handle_fx_inc_r
        .word   handle_fx_inc_r
        .word   handle_fx_inc_r
        .word   handle_fx_inc_r
        .word   handle_fx_inc_r
        .word   handle_fx_inc_r
        .word   handle_fx_inc_r
        .word   handle_fx_inc_r
        .word   handle_fx_inc_r
        .word   handle_fx_inc_r
        .word   handle_fx_inc_r
        .word   handle_fx_inc_r
        .word   handle_fx_inc_r
        .word   handle_fx_inc_r
        .word   handle_fx_inc_r14
        .word   handle_fx_getc
        .word   handle_fx_dec_r
        .word   handle_fx_dec_r
        .word   handle_fx_dec_r
        .word   handle_fx_dec_r
        .word   handle_fx_dec_r
        .word   handle_fx_dec_r
        .word   handle_fx_dec_r
        .word   handle_fx_dec_r
        .word   handle_fx_dec_r
        .word   handle_fx_dec_r
        .word   handle_fx_dec_r
        .word   handle_fx_dec_r
        .word   handle_fx_dec_r
        .word   handle_fx_dec_r
        .word   handle_fx_dec_r14
        .word   handle_fx_getbh
        .word   handle_fx_lm_r
        .word   handle_fx_lm_r
        .word   handle_fx_lm_r
        .word   handle_fx_lm_r
        .word   handle_fx_lm_r
        .word   handle_fx_lm_r
        .word   handle_fx_lm_r
        .word   handle_fx_lm_r
        .word   handle_fx_lm_r
        .word   handle_fx_lm_r
        .word   handle_fx_lm_r
        .word   handle_fx_lm_r
        .word   handle_fx_lm_r
        .word   handle_fx_lm_r
        .word   handle_fx_lm_r14
        .word   handle_fx_lm_r
        .word   handle_fx_stop
        .word   handle_fx_nop
        .word   handle_fx_cache
        .word   handle_fx_lsr
        .word   handle_fx_rol
        .word   handle_fx_bra
        .word   handle_fx_bge
        .word   handle_fx_blt
        .word   handle_fx_bne
        .word   handle_fx_beq
        .word   handle_fx_bpl
        .word   handle_fx_bmi
        .word   handle_fx_bcc
        .word   handle_fx_bcs
        .word   handle_fx_bvc
        .word   handle_fx_bvs
        .word   handle_fx_to_r
        .word   handle_fx_to_r
        .word   handle_fx_to_r
        .word   handle_fx_to_r
        .word   handle_fx_to_r
        .word   handle_fx_to_r
        .word   handle_fx_to_r
        .word   handle_fx_to_r
        .word   handle_fx_to_r
        .word   handle_fx_to_r
        .word   handle_fx_to_r
        .word   handle_fx_to_r
        .word   handle_fx_to_r
        .word   handle_fx_to_r
        .word   handle_fx_to_r14
        .word   handle_fx_to_r15
        .word   handle_fx_with
        .word   handle_fx_with
        .word   handle_fx_with
        .word   handle_fx_with
        .word   handle_fx_with
        .word   handle_fx_with
        .word   handle_fx_with
        .word   handle_fx_with
        .word   handle_fx_with
        .word   handle_fx_with
        .word   handle_fx_with
        .word   handle_fx_with
        .word   handle_fx_with
        .word   handle_fx_with
        .word   handle_fx_with
        .word   handle_fx_with
        .word   handle_fx_stw_r
        .word   handle_fx_stw_r
        .word   handle_fx_stw_r
        .word   handle_fx_stw_r
        .word   handle_fx_stw_r
        .word   handle_fx_stw_r
        .word   handle_fx_stw_r
        .word   handle_fx_stw_r
        .word   handle_fx_stw_r
        .word   handle_fx_stw_r
        .word   handle_fx_stw_r
        .word   handle_fx_stw_r
        .word   handle_fx_loop
        .word   handle_fx_alt1
        .word   handle_fx_alt2
        .word   handle_fx_alt3
        .word   handle_fx_ldw_r
        .word   handle_fx_ldw_r
        .word   handle_fx_ldw_r
        .word   handle_fx_ldw_r
        .word   handle_fx_ldw_r
        .word   handle_fx_ldw_r
        .word   handle_fx_ldw_r
        .word   handle_fx_ldw_r
        .word   handle_fx_ldw_r
        .word   handle_fx_ldw_r
        .word   handle_fx_ldw_r
        .word   handle_fx_ldw_r
        .word   handle_fx_plot_2bit
        .word   handle_fx_swap
        .word   handle_fx_color
        .word   handle_fx_not
        .word   handle_fx_add_i
        .word   handle_fx_add_i
        .word   handle_fx_add_i
        .word   handle_fx_add_i
        .word   handle_fx_add_i
        .word   handle_fx_add_i
        .word   handle_fx_add_i
        .word   handle_fx_add_i
        .word   handle_fx_add_i
        .word   handle_fx_add_i
        .word   handle_fx_add_i
        .word   handle_fx_add_i
        .word   handle_fx_add_i
        .word   handle_fx_add_i
        .word   handle_fx_add_i
        .word   handle_fx_add_i
        .word   handle_fx_sub_i
        .word   handle_fx_sub_i
        .word   handle_fx_sub_i
        .word   handle_fx_sub_i
        .word   handle_fx_sub_i
        .word   handle_fx_sub_i
        .word   handle_fx_sub_i
        .word   handle_fx_sub_i
        .word   handle_fx_sub_i
        .word   handle_fx_sub_i
        .word   handle_fx_sub_i
        .word   handle_fx_sub_i
        .word   handle_fx_sub_i
        .word   handle_fx_sub_i
        .word   handle_fx_sub_i
        .word   handle_fx_sub_i
        .word   handle_fx_merge
        .word   handle_fx_and_i
        .word   handle_fx_and_i
        .word   handle_fx_and_i
        .word   handle_fx_and_i
        .word   handle_fx_and_i
        .word   handle_fx_and_i
        .word   handle_fx_and_i
        .word   handle_fx_and_i
        .word   handle_fx_and_i
        .word   handle_fx_and_i
        .word   handle_fx_and_i
        .word   handle_fx_and_i
        .word   handle_fx_and_i
        .word   handle_fx_and_i
        .word   handle_fx_and_i
        .word   handle_fx_mult_i
        .word   handle_fx_mult_i
        .word   handle_fx_mult_i
        .word   handle_fx_mult_i
        .word   handle_fx_mult_i
        .word   handle_fx_mult_i
        .word   handle_fx_mult_i
        .word   handle_fx_mult_i
        .word   handle_fx_mult_i
        .word   handle_fx_mult_i
        .word   handle_fx_mult_i
        .word   handle_fx_mult_i
        .word   handle_fx_mult_i
        .word   handle_fx_mult_i
        .word   handle_fx_mult_i
        .word   handle_fx_mult_i
        .word   handle_fx_sbk
        .word   handle_fx_link_i
        .word   handle_fx_link_i
        .word   handle_fx_link_i
        .word   handle_fx_link_i
        .word   handle_fx_sex
        .word   handle_fx_asr
        .word   handle_fx_ror
        .word   handle_fx_jmp_r
        .word   handle_fx_jmp_r
        .word   handle_fx_jmp_r
        .word   handle_fx_jmp_r
        .word   handle_fx_jmp_r
        .word   handle_fx_jmp_r
        .word   handle_fx_lob
        .word   handle_fx_fmult
        .word   handle_fx_sms_r
        .word   handle_fx_sms_r
        .word   handle_fx_sms_r
        .word   handle_fx_sms_r
        .word   handle_fx_sms_r
        .word   handle_fx_sms_r
        .word   handle_fx_sms_r
        .word   handle_fx_sms_r
        .word   handle_fx_sms_r
        .word   handle_fx_sms_r
        .word   handle_fx_sms_r
        .word   handle_fx_sms_r
        .word   handle_fx_sms_r
        .word   handle_fx_sms_r
        .word   handle_fx_sms_r
        .word   handle_fx_sms_r
        .word   handle_fx_from_r
        .word   handle_fx_from_r
        .word   handle_fx_from_r
        .word   handle_fx_from_r
        .word   handle_fx_from_r
        .word   handle_fx_from_r
        .word   handle_fx_from_r
        .word   handle_fx_from_r
        .word   handle_fx_from_r
        .word   handle_fx_from_r
        .word   handle_fx_from_r
        .word   handle_fx_from_r
        .word   handle_fx_from_r
        .word   handle_fx_from_r
        .word   handle_fx_from_r
        .word   handle_fx_from_r
        .word   handle_fx_hib
        .word   handle_fx_or_i
        .word   handle_fx_or_i
        .word   handle_fx_or_i
        .word   handle_fx_or_i
        .word   handle_fx_or_i
        .word   handle_fx_or_i
        .word   handle_fx_or_i
        .word   handle_fx_or_i
        .word   handle_fx_or_i
        .word   handle_fx_or_i
        .word   handle_fx_or_i
        .word   handle_fx_or_i
        .word   handle_fx_or_i
        .word   handle_fx_or_i
        .word   handle_fx_or_i
        .word   handle_fx_inc_r
        .word   handle_fx_inc_r
        .word   handle_fx_inc_r
        .word   handle_fx_inc_r
        .word   handle_fx_inc_r
        .word   handle_fx_inc_r
        .word   handle_fx_inc_r
        .word   handle_fx_inc_r
        .word   handle_fx_inc_r
        .word   handle_fx_inc_r
        .word   handle_fx_inc_r
        .word   handle_fx_inc_r
        .word   handle_fx_inc_r
        .word   handle_fx_inc_r
        .word   handle_fx_inc_r14
        .word   handle_fx_ramb
        .word   handle_fx_dec_r
        .word   handle_fx_dec_r
        .word   handle_fx_dec_r
        .word   handle_fx_dec_r
        .word   handle_fx_dec_r
        .word   handle_fx_dec_r
        .word   handle_fx_dec_r
        .word   handle_fx_dec_r
        .word   handle_fx_dec_r
        .word   handle_fx_dec_r
        .word   handle_fx_dec_r
        .word   handle_fx_dec_r
        .word   handle_fx_dec_r
        .word   handle_fx_dec_r
        .word   handle_fx_dec_r14
        .word   handle_fx_getbl
        .word   handle_fx_sm_r
        .word   handle_fx_sm_r
        .word   handle_fx_sm_r
        .word   handle_fx_sm_r
        .word   handle_fx_sm_r
        .word   handle_fx_sm_r
        .word   handle_fx_sm_r
        .word   handle_fx_sm_r
        .word   handle_fx_sm_r
        .word   handle_fx_sm_r
        .word   handle_fx_sm_r
        .word   handle_fx_sm_r
        .word   handle_fx_sm_r
        .word   handle_fx_sm_r
        .word   handle_fx_sm_r
        .word   handle_fx_sm_r
        .word   handle_fx_stop
        .word   handle_fx_nop
        .word   handle_fx_cache
        .word   handle_fx_lsr
        .word   handle_fx_rol
        .word   handle_fx_bra
        .word   handle_fx_bge
        .word   handle_fx_blt
        .word   handle_fx_bne
        .word   handle_fx_beq
        .word   handle_fx_bpl
        .word   handle_fx_bmi
        .word   handle_fx_bcc
        .word   handle_fx_bcs
        .word   handle_fx_bvc
        .word   handle_fx_bvs
        .word   handle_fx_to_r
        .word   handle_fx_to_r
        .word   handle_fx_to_r
        .word   handle_fx_to_r
        .word   handle_fx_to_r
        .word   handle_fx_to_r
        .word   handle_fx_to_r
        .word   handle_fx_to_r
        .word   handle_fx_to_r
        .word   handle_fx_to_r
        .word   handle_fx_to_r
        .word   handle_fx_to_r
        .word   handle_fx_to_r
        .word   handle_fx_to_r
        .word   handle_fx_to_r14
        .word   handle_fx_to_r15
        .word   handle_fx_with
        .word   handle_fx_with
        .word   handle_fx_with
        .word   handle_fx_with
        .word   handle_fx_with
        .word   handle_fx_with
        .word   handle_fx_with
        .word   handle_fx_with
        .word   handle_fx_with
        .word   handle_fx_with
        .word   handle_fx_with
        .word   handle_fx_with
        .word   handle_fx_with
        .word   handle_fx_with
        .word   handle_fx_with
        .word   handle_fx_with
        .word   handle_fx_stb_r
        .word   handle_fx_stb_r
        .word   handle_fx_stb_r
        .word   handle_fx_stb_r
        .word   handle_fx_stb_r
        .word   handle_fx_stb_r
        .word   handle_fx_stb_r
        .word   handle_fx_stb_r
        .word   handle_fx_stb_r
        .word   handle_fx_stb_r
        .word   handle_fx_stb_r
        .word   handle_fx_stb_r
        .word   handle_fx_loop
        .word   handle_fx_alt1
        .word   handle_fx_alt2
        .word   handle_fx_alt3
        .word   handle_fx_ldb_r
        .word   handle_fx_ldb_r
        .word   handle_fx_ldb_r
        .word   handle_fx_ldb_r
        .word   handle_fx_ldb_r
        .word   handle_fx_ldb_r
        .word   handle_fx_ldb_r
        .word   handle_fx_ldb_r
        .word   handle_fx_ldb_r
        .word   handle_fx_ldb_r
        .word   handle_fx_ldb_r
        .word   handle_fx_ldb_r
        .word   handle_fx_rpix_2bit
        .word   handle_fx_swap
        .word   handle_fx_cmode
        .word   handle_fx_not
        .word   handle_fx_adc_i
        .word   handle_fx_adc_i
        .word   handle_fx_adc_i
        .word   handle_fx_adc_i
        .word   handle_fx_adc_i
        .word   handle_fx_adc_i
        .word   handle_fx_adc_i
        .word   handle_fx_adc_i
        .word   handle_fx_adc_i
        .word   handle_fx_adc_i
        .word   handle_fx_adc_i
        .word   handle_fx_adc_i
        .word   handle_fx_adc_i
        .word   handle_fx_adc_i
        .word   handle_fx_adc_i
        .word   handle_fx_adc_i
        .word   handle_fx_cmp_r
        .word   handle_fx_cmp_r
        .word   handle_fx_cmp_r
        .word   handle_fx_cmp_r
        .word   handle_fx_cmp_r
        .word   handle_fx_cmp_r
        .word   handle_fx_cmp_r
        .word   handle_fx_cmp_r
        .word   handle_fx_cmp_r
        .word   handle_fx_cmp_r
        .word   handle_fx_cmp_r
        .word   handle_fx_cmp_r
        .word   handle_fx_cmp_r
        .word   handle_fx_cmp_r
        .word   handle_fx_cmp_r
        .word   handle_fx_cmp_r
        .word   handle_fx_merge
        .word   handle_fx_bic_i
        .word   handle_fx_bic_i
        .word   handle_fx_bic_i
        .word   handle_fx_bic_i
        .word   handle_fx_bic_i
        .word   handle_fx_bic_i
        .word   handle_fx_bic_i
        .word   handle_fx_bic_i
        .word   handle_fx_bic_i
        .word   handle_fx_bic_i
        .word   handle_fx_bic_i
        .word   handle_fx_bic_i
        .word   handle_fx_bic_i
        .word   handle_fx_bic_i
        .word   handle_fx_bic_i
        .word   handle_fx_umult_i
        .word   handle_fx_umult_i
        .word   handle_fx_umult_i
        .word   handle_fx_umult_i
        .word   handle_fx_umult_i
        .word   handle_fx_umult_i
        .word   handle_fx_umult_i
        .word   handle_fx_umult_i
        .word   handle_fx_umult_i
        .word   handle_fx_umult_i
        .word   handle_fx_umult_i
        .word   handle_fx_umult_i
        .word   handle_fx_umult_i
        .word   handle_fx_umult_i
        .word   handle_fx_umult_i
        .word   handle_fx_umult_i
        .word   handle_fx_sbk
        .word   handle_fx_link_i
        .word   handle_fx_link_i
        .word   handle_fx_link_i
        .word   handle_fx_link_i
        .word   handle_fx_sex
        .word   handle_fx_div2
        .word   handle_fx_ror
        .word   handle_fx_ljmp_r
        .word   handle_fx_ljmp_r
        .word   handle_fx_ljmp_r
        .word   handle_fx_ljmp_r
        .word   handle_fx_ljmp_r
        .word   handle_fx_ljmp_r
        .word   handle_fx_lob
        .word   handle_fx_lmult
        .word   handle_fx_lms_r
        .word   handle_fx_lms_r
        .word   handle_fx_lms_r
        .word   handle_fx_lms_r
        .word   handle_fx_lms_r
        .word   handle_fx_lms_r
        .word   handle_fx_lms_r
        .word   handle_fx_lms_r
        .word   handle_fx_lms_r
        .word   handle_fx_lms_r
        .word   handle_fx_lms_r
        .word   handle_fx_lms_r
        .word   handle_fx_lms_r
        .word   handle_fx_lms_r
        .word   handle_fx_lms_r14
        .word   handle_fx_lms_r
        .word   handle_fx_from_r
        .word   handle_fx_from_r
        .word   handle_fx_from_r
        .word   handle_fx_from_r
        .word   handle_fx_from_r
        .word   handle_fx_from_r
        .word   handle_fx_from_r
        .word   handle_fx_from_r
        .word   handle_fx_from_r
        .word   handle_fx_from_r
        .word   handle_fx_from_r
        .word   handle_fx_from_r
        .word   handle_fx_from_r
        .word   handle_fx_from_r
        .word   handle_fx_from_r
        .word   handle_fx_from_r
        .word   handle_fx_hib
        .word   handle_fx_xor_i
        .word   handle_fx_xor_i
        .word   handle_fx_xor_i
        .word   handle_fx_xor_i
        .word   handle_fx_xor_i
        .word   handle_fx_xor_i
        .word   handle_fx_xor_i
        .word   handle_fx_xor_i
        .word   handle_fx_xor_i
        .word   handle_fx_xor_i
        .word   handle_fx_xor_i
        .word   handle_fx_xor_i
        .word   handle_fx_xor_i
        .word   handle_fx_xor_i
        .word   handle_fx_xor_i
        .word   handle_fx_inc_r
        .word   handle_fx_inc_r
        .word   handle_fx_inc_r
        .word   handle_fx_inc_r
        .word   handle_fx_inc_r
        .word   handle_fx_inc_r
        .word   handle_fx_inc_r
        .word   handle_fx_inc_r
        .word   handle_fx_inc_r
        .word   handle_fx_inc_r
        .word   handle_fx_inc_r
        .word   handle_fx_inc_r
        .word   handle_fx_inc_r
        .word   handle_fx_inc_r
        .word   handle_fx_inc_r14
        .word   handle_fx_romb
        .word   handle_fx_dec_r
        .word   handle_fx_dec_r
        .word   handle_fx_dec_r
        .word   handle_fx_dec_r
        .word   handle_fx_dec_r
        .word   handle_fx_dec_r
        .word   handle_fx_dec_r
        .word   handle_fx_dec_r
        .word   handle_fx_dec_r
        .word   handle_fx_dec_r
        .word   handle_fx_dec_r
        .word   handle_fx_dec_r
        .word   handle_fx_dec_r
        .word   handle_fx_dec_r
        .word   handle_fx_dec_r14
        .word   handle_fx_getbs
        .word   handle_fx_lm_r
        .word   handle_fx_lm_r
        .word   handle_fx_lm_r
        .word   handle_fx_lm_r
        .word   handle_fx_lm_r
        .word   handle_fx_lm_r
        .word   handle_fx_lm_r
        .word   handle_fx_lm_r
        .word   handle_fx_lm_r
        .word   handle_fx_lm_r
        .word   handle_fx_lm_r
        .word   handle_fx_lm_r
        .word   handle_fx_lm_r
        .word   handle_fx_lm_r
        .word   handle_fx_lm_r14
        .word   handle_fx_lm_r
