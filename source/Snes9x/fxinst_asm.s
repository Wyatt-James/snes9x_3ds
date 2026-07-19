@ "FX_" offset defines
#include "fxinst_asm.h"

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

@ Constants for a wacky linker optimization. See link.ld for more info. Currently disabled.
@ #define GSU_PTR #0x004FFFE4
@ #define R14_PTR #0x00500000

@ R0 contains vLow
@ R1 contains GSU.pvPrgBank, for fetching PIPE
@ R2 contains extended opcode after interpreter
@ R3 contains GSU R15 after interpreter
@ R4 contains the pointer to GSU
@ R5 contains vCounter, the instruction counter
@ R6 contains the GSU STAT register
@ R7 contains the ARM flag register, NZCV flags synchronized with GSU
@ R8 contains the GSU PIPE register
@ R9 contains a pointer to the GSU SREG
@ R10 contains a pointer to the GSU DREG
@ FP contains a pointer to the instruction dispatch table
@ IP contains the dispatch branch destination after interpreter
@ LR is reserved and must be preserved

@ ----- Preferred regalloc order -----
@ R2, IP, vLow
@ rSREG, rDREG (if overwritten later)
@ rARM (if overwritten later)
@ R1 (reload necessary if modified)
@ rR15 (store and reload necessary if modified)

@ WYATT_TODO various optimizations:
@ - Fix doubled loads and stores caused by aliasing
@ - Fix regalloc occasionally reloading R15
@     If CLRFLAGS is called, we can use rSREG as scratch to save a reg
@ - Put the GSU struct in its own over-aligned segment. This would allow us to do certain comparisons, notably the one in TESTR14, in one fewer instruction.
@ - Look into the possibility of avoiding the UXTH instructions in IBT/IWT. Shift to top of reg and load with register lsr 16?
@ - Store some constants in the stack or GSU struct to make reloading them faster? For instance, R0 pointers for SREG and DREG. Cycle timings might work out. Ensure 64-bit alignment and single-cycle issues if so.
@ - Optimize regalloc to minimize reloads of R1 and rR15
@ - If all handlers were the same size, we could possibly save a load in dispatch and the entirety of rGOTO.

@ WYATT_TODO dynarec note: TESTR14 branch prediction is unsolvable in dynarec because execution must flow forward.
@ We can emit based on the prior instruction setting R14 or not, and fall back to interpreter for things like
@ jumps and resuming a session. This should have pretty substantial savings.

@ WYATT_TODO fix stack alignment

    .section .text.fx_run_asm,"ax",%progbits
    .align    2
    .global fx_run_asm
    .syntax unified
    .arm
    .type fx_run_asm, %function
    .cfi_startproc
fx_run_asm:
        push    {rGSU, rVCNT, rSTAT, rARM, rPIPE, rSREG, rDREG, rGOTO, lr}
        ldr     rGSU, .L242                              @ Load GSU pointer
        mov     rVCNT, vLow                              @ Decrement vCounter by 1, move to correct variable
        ldr     rR15, [rGSU, #FX_vMode]                  @ Load GSU.vMode
        ldr     rGOTO, .L242+4                           @ Load GOTO table
      @ cmp     rR15, #3                                 @ If vMode > 3, vMode = 0.  Unreachable.
      @ movhi   r3, #0                                   @  |
        ldr     r2, .L242+8                              @ Load plot/rpix table
        add     r1, r2, rR15, lsl #3                     @ Compute target address
        ldr     r2, [r2, rR15, lsl #3]                   @ Load plot from the table 
        ldr     rR15, [r1, #4]                           @ Load rpix from the table
        ldrh    r1, [rGSU, #FX_R14]                      @ READR14: Load R14
      @ cmp     vLow, #0                                 @ If nInstructions == 0, end. Unreachable.
        ldr     vLow, [rGSU, #FX_pvRomBank]              @ READR14: Load ROM base pointer
        ldrb    r1, [vLow, r1]                           @ READR14: Load ROM(R14)
        ldrb    rSREG, [rGSU, #FX_pvSreg]                @ Load reserved regs
        ldrb    rDREG, [rGSU, #FX_pvDreg]                @  |
        ldrh    rSTAT, [rGSU, #FX_vStatusReg]            @  |
        ldr     rARM, [rGSU, #FX_armFlags]               @  |
        ldrb    rPIPE, [rGSU, #FX_vPipe]                 @  |
        add     rSREG, rGSU, rSREG, lsl #1               @  |
        add     rDREG, rGSU, rDREG, lsl #1               @  V
        strb    r1, [rGSU, #FX_vRomBuffer]               @ READR14: Store to ROMBUFFER
        str     rR15, [rGOTO, #3376]                     @ Populate GOTO table
        str     rR15, [rGOTO, #1328]                     @  |
        str     r2, [rGOTO, #2352]                       @  |
        str     r2, [rGOTO, #304]                        @  V
      @ beq     loop_end                                 @ End if nInstructions == 0. Unreachable.

@ Dispatch for after instructions that do not run CLRFLAGS
dispatch_flags:
        ldr     r1, [rGSU, #FX_pvPrgBank]                @ FETCHPIPE: Load GSU.pvPrgBank. Taken from dispatch to save a cycle.
dispatch_flags.skip_1:
        ldrh    rR15, [rGSU, #FX_R15]                    @ FETCHPIPE: Load R15. Taken from dispatch to reduce memory stalling
dispatch_flags.skip_2:                                   @ If used, be careful to ensure that R15 is still 16-bit
        and     r2, rSTAT, #768                          @ Get opcode mode bits
        orr     r2, rPIPE, r2                            @ Compute opcode
        subs    rVCNT, rVCNT, #1                         @ Decrement vCounter and exit if 0
        ldr     ip, [rGOTO, r2, lsl #2]                  @ Load destination handler
        beq     loop_end                                 @ 
        and     vLow, rPIPE, #15                         @ Compute vLow
        ldrb    rPIPE, [r1, rR15]                        @ FETCHPIPE
        bx      ip                                       @ Branch to handler

@ Dispatch for after instructions that run CLRFLAGS
dispatch:
        ldr     r1, [rGSU, #FX_pvPrgBank]                @ FETCHPIPE: Load GSU.pvPrgBank. Taken from dispatch to save a cycle.
dispatch.skip_1:
        ldrh    rR15, [rGSU, #FX_R15]                    @ FETCHPIPE: Load R15. Taken from dispatch to reduce memory stalling
dispatch.skip_2:                                         @ If used, be careful to ensure that R15 is still 16-bit
        ldr     ip, [rGOTO, rPIPE, lsl #2]               @ Load destination handler
        subs    rVCNT, rVCNT, #1                         @ Decrement vCounter and exit if 0
        beq     loop_end                                 @ 
        and     vLow, rPIPE, #15                         @ Compute vLow
        ldrb    rPIPE, [r1, rR15]                        @ FETCHPIPE
        bx      ip                                       @ Branch to handler

loop_end:
        sub     rR15, rSREG, rGSU                        @ Save reserved registers
        asr     rR15, rR15, #1                           @  |
        strb    rR15, [rGSU, #FX_pvSreg]                 @  |
        sub     rR15, rDREG, rGSU                        @  |
        asr     rR15, rR15, #1                           @  |
        strh    rSTAT, [rGSU, #FX_vStatusReg]            @  |
        str     rARM, [rGSU, #FX_armFlags]               @  |
        strb    rPIPE, [rGSU, #FX_vPipe]                 @  |
        strb    rR15, [rGSU, #FX_pvDreg]                 @  V
        pop     {rGSU, rVCNT, rSTAT, rARM, rPIPE, rSREG, rDREG, rGOTO, pc} @ Return

@ GETBS: get sign extended byte from ROM at address R14
handle_fx_getbs:
        add     rR15, rR15, #1                           @ R15++
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        ldrsb   rR15, [rGSU, #FX_vRomBuffer]             @ R15 = SEX8(ROMBUFFER)
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        strh    rR15, [rDREG]                            @ Store value to DREG
        add     rR15, rGSU, #FX_R14                      @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        beq     testr14_clrflags_dispatch                @ TESTR14: branch
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        b       dispatch                                 @ 

@ STOP: stop GSU execution
handle_fx_stop:
        add     rR15, rR15, #1                           @ R15++
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        mov     rR15, #0                                 @ plotOptionReg = 0
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        ldr     r2, [rGSU, #FX_pvRegisters]              @ R2 = GSU.pvRegisters[GSU_CFGR]
        bic     rSTAT, rSTAT, #32                        @ CF(G)
        ldrsb   r2, [r2, #55]                            @ R2 = GSU_CFGR
        mov     rPIPE, #1                                @ PIPE = 1
        cmp     r2, #0                                   @ If GSU_CFGR == 0, Raise IRQ
        orrge   rSTAT, rSTAT, #32768                     @  |
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @  |
        strb    rR15, [rGSU, #FX_vPlotOptionReg]         @ Store plotOptionReg
        b       loop_end                                 @ 

@ PLOT 2BIT: Draws a pixel at R1,R2 (X,Y), using GSU.vColorReg as the source
handle_fx_plot_2bit:
        ldrb    ip, [rGSU, #FX_R2]                       @ Load Y
        add     rR15, rR15, #1                           @ R15++
        ldr     rSREG, [rGSU, #FX_vScreenHeight]         @ Load screen height
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        ldrh    r1, [rGSU, #FX_R1]                       @ Load X
        cmp     ip, rSREG                                @ Test Y > screen height
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        add     r2, r1, #1                               @ X++
        strh    r2, [rGSU, #FX_R1]                       @  |
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0. Prevents stall from next branch getting folded
        bcs     handle_fx_plot_2bit.return               @ If Y > screen height, return
        ldrb    vLow, [rGSU, #FX_vPlotOptionReg]         @ Load vPlotOptionReg
        ldrb    r2, [rGSU, #FX_vColorReg]                @ Load vColorReg
        uxtb    r1, r1                                   @ Truncate X to 8-bit
        tst     vLow, #2                                 @ If PLOT_DITHER, potentially shift color
        bne     handle_fx_plot_2bit.L237                 @  |

        @ vLow is vPlotOptionReg
        @ R1 is X
        @ R2 is color
        @ IP is Y
        @ rR15 is free
.L15:
        and     vLow, vLow, #1                           @ If the color is transparent and PLOT_TRANSPARENT is disabled, return
        orrs    vLow, vLow, r2, lsl #28                  @  |
        beq     handle_fx_plot_2bit.return               @  |
        lsr     vLow, r1, #3                             @ vLow = GSU.x[X >> 3]
        add     vLow, rGSU, vLow, lsl #2                 @  |
        ldr     vLow, [vLow, #FX_x]                      @  |
        mov     rR15, #128                               @ IP = BIT(7) >> (X & 7)
        and     r1, r1, #7                               @  |
        lsr     rR15, rR15, r1                           @  |
        lsr     r1, ip, #3                               @ R1 = GSU.apvScreen[Y >> 3]
        add     r1, rGSU, r1, lsl #2                     @  |
        ldr     r1, [r1, #FX_apvScreen]                  @  |
        lsl     ip, ip, #29                              @ R15 = pixel 0 pointer
        add     ip, vLow, ip, lsr #28                    @  |  Shifted math is equivalent to vLow + ((y & 7) << 1)
        add     ip, ip, r1                               @  |

        @ vLow is free
        @ R1 is free
        @ R2 is color
        @ IP is the pixel 0 Pointer
        @ rR15 is the pixel mask

        @ The pointer seems to always be 2-byte aligned, so this is a free speedup
        ldrh    vLow, [ip, #0]                           @ Load pixel pair
        tst     r2, #1                                   @ Pixel conditional
        orrne   vLow, vLow, rR15             @ stall 1   @  |
        biceq   vLow, vLow, rR15                         @  |
        tst     r2, #2                                   @ Pixel conditional
        orrne   vLow, vLow, rR15, lsl #8                 @  |
        biceq   vLow, vLow, rR15, lsl #8                 @  |
        strh    vLow, [ip, #0]                           @ Store pixel pair

handle_fx_plot_2bit.return:
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        ldr     r1, [rGSU, #FX_pvPrgBank]                @ Taken from dispatch to allow this return handler to branch fold
        b       dispatch.skip_1                          @ 

@ RPIX 2BIT: Reads the color of pixel R1,R2 (X, Y) and stores to DREG.
handle_fx_rpix_2bit:
        add     rR15, rR15, #1                           @ R15++
        ldr     r1, [rGSU, #FX_vScreenHeight]            @ R1 = screen height
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        ldrb    rR15, [rGSU, #FX_R2]                     @ R15 = Y
        cmp     rR15, r1                                 @ Test Y > screen height
        ldrb    r1, [rGSU, #FX_R1]                       @ R1 = X
        bcs     handle_fx_rpix_8bit.return               @ If Y > screen height, return
        
        @ R1 is X, rR15 is Y
        lsr     vLow, r1, #3                             @ vLow = GSU.x[X >> 3]
        add     vLow, rGSU, vLow, lsl #2                 @  |
        ldr     vLow, [vLow, #FX_x]                      @  |
        mov     ip, #128                                 @ R15 = BIT(7) >> (X & 7)
        and     r1, r1, #7                               @  |
        lsr     ip, ip, r1                               @  |
        lsr     r1, rR15, #3                             @ R1 = GSU.apvScreen[Y >> 3]
        add     r1, rGSU, r1, lsl #2                     @  |
        ldr     r1, [r1, #FX_apvScreen]                  @  |
        lsl     rR15, rR15, #29                          @ IP = pixel 0 pointer
        add     rR15, vLow, rR15, lsr #28                @  |  Shifted math is equivalent to vLow + ((y & 7) << 1)
        add     rR15, rR15, r1                           @  |

        @ rR15 is pixel 0 Pointer, IP is the pixel mask
        ldrh    r1, [rR15, #0]                           @ Load pixel pair 1
        mov     vLow, #0                                 @ Initial result
        add     rR15, rGSU, #FX_R14                      @ TESTR14: Pointer to R14. Lifted from return to save a cycle

        tst r1, ip                                       @ Pixel pair 1
        orrne vLow, vLow, #1                             @  |
        tst r1, ip, lsl #8                               @  |
        orrne vLow, vLow, #2                             @  |

        strh vLow, [rDREG]                               @ Store result
        b handle_fx_rpix_8bit.return_skip_1

@ PLOT 4BIT: Draws a pixel at R1,R2 (X,Y), using GSU.vColorReg as the source
handle_fx_plot_4bit:
        ldrb    ip, [rGSU, #FX_R2]                       @ Load Y
        add     rR15, rR15, #1                           @ R15++
        ldr     rSREG, [rGSU, #FX_vScreenHeight]         @ Load screen height
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        ldrh    r1, [rGSU, #FX_R1]                       @ Load X
        cmp     ip, rSREG                                @ Test Y > screen height
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        add     r2, r1, #1                               @ X++
        strh    r2, [rGSU, #FX_R1]                       @  |
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0. Prevents stall from next branch getting folded
        bcs     handle_fx_plot_4bit.return               @ If Y > screen height, return
        ldrb    vLow, [rGSU, #FX_vPlotOptionReg]         @ Load vPlotOptionReg
        ldrb    r2, [rGSU, #FX_vColorReg]                @ Load vColorReg
        uxtb    r1, r1                                   @ Truncate X to 8-bit
        tst     vLow, #2                                 @ If PLOT_DITHER, potentially shift color
        bne     handle_fx_plot_4bit.L238                 @  |

        @ vLow is vPlotOptionReg
        @ R1 is X
        @ R2 is color
        @ IP is Y
        @ rR15 is free
.L25:
        and     vLow, vLow, #1                           @ If the color is transparent and PLOT_TRANSPARENT is disabled, return
        orrs    vLow, vLow, r2, lsl #28                  @  |
        beq     handle_fx_plot_4bit.return               @  |
        lsr     vLow, r1, #3                             @ vLow = GSU.x[X >> 3]
        add     vLow, rGSU, vLow, lsl #2                 @  |
        ldr     vLow, [vLow, #FX_x]                      @  |
        mov     rR15, #128                               @ R15 = BIT(7) >> (X & 7)
        and     r1, r1, #7                               @  |
        lsr     rR15, rR15, r1                           @  |
        lsr     r1, ip, #3                               @ R1 = GSU.apvScreen[Y >> 3]
        add     r1, rGSU, r1, lsl #2                     @  |
        ldr     r1, [r1, #FX_apvScreen]                  @  |
        lsl     ip, ip, #29                              @ IP = pixel 0 pointer
        add     ip, vLow, ip, lsr #28                    @  |  Shifted math is equivalent to vLow + ((y & 7) << 1)
        add     ip, ip, r1                               @  |

        @ vLow is free
        @ R1 is free
        @ R2 is color
        @ IP is the pixel 0 Pointer
        @ rR15 is the pixel mask

        @ The pointer seems to always be 2-byte aligned, so this is a free speedup
        ldrh    r1, [ip, #0]                             @ Load pixel pair 1
        tst     r2, #1                                   @ Pixel conditional
        ldrh    vLow, [ip, #16]                          @ Load pixel pair 2. Up here to avoid a stall.
        orrne   r1, r1, rR15                             @  |
        biceq   r1, r1, rR15                             @  |
        tst     r2, #2                                   @ Pixel conditional
        orrne   r1, r1, rR15, lsl #8                     @  |
        biceq   r1, r1, rR15, lsl #8                     @  |
        strh    r1, [ip, #0]                             @ Store pixel pair

        @ Interleave between vLow and r1 to prevent stalls
        tst     r2, #4                                   @ Pixel conditional
        orrne   vLow, vLow, rR15                         @  |
        biceq   vLow, vLow, rR15                         @  |
        tst     r2, #8                                   @ Pixel conditional
        orrne   vLow, vLow, rR15, lsl #8                 @  |
        biceq   vLow, vLow, rR15, lsl #8                 @  |
        strh    vLow, [ip, #16]                          @ Store pixel pair

handle_fx_plot_4bit.return:
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        ldr     r1, [rGSU, #FX_pvPrgBank]                @ Taken from dispatch to allow this return handler to branch fold
        b       dispatch.skip_1                          @ 

@ RPIX 4BIT: Reads the color of pixel R1,R2 (X, Y) and stores to DREG.
handle_fx_rpix_4bit:
        add     rR15, rR15, #1                           @ R15++
        ldr     r1, [rGSU, #FX_vScreenHeight]            @ R1 = screen height
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        ldrb    rR15, [rGSU, #FX_R2]                     @ R15 = Y
        cmp     rR15, r1                                 @ Test Y > screen height
        ldrb    r1, [rGSU, #FX_R1]                       @ R1 = X
        bcs     handle_fx_rpix_8bit.return               @ If Y > screen height, return
        
        @ R1 is X, rR15 is Y
        lsr     vLow, r1, #3                             @ vLow = GSU.x[X >> 3]
        add     vLow, rGSU, vLow, lsl #2                 @  |
        ldr     vLow, [vLow, #FX_x]                      @  |
        mov     ip, #128                                 @ IP = BIT(7) >> (X & 7)
        and     r1, r1, #7                               @  |
        lsr     ip, ip, r1                               @  |
        lsr     r1, rR15, #3                             @ R1 = GSU.apvScreen[Y >> 3]
        add     r1, rGSU, r1, lsl #2                     @  |
        ldr     r1, [r1, #FX_apvScreen]                  @  |
        lsl     rR15, rR15, #29                          @ R15 = pixel 0 pointer
        add     rR15, vLow, rR15, lsr #28                @  |  Shifted math is equivalent to vLow + ((y & 7) << 1)
        add     rR15, rR15, r1                           @  |

        @ rR15 is pixel 0 Pointer, IP is the pixel mask
        ldrh r1, [rR15, #0]                              @ Load pixel pair 1
        ldrh r2, [rR15, #16]                             @ Load pixel pair 2
        mov vLow, #0                                     @ Initial result

        tst r1, ip                                       @ Pixel pair 1
        orrne vLow, vLow, #1                             @  |
        tst r1, ip, lsl #8                               @  |
        orrne vLow, vLow, #2                             @  |

        tst r2, ip                                       @ Pixel pair 2
        orrne vLow, vLow, #4                             @  |
        tst r2, ip, lsl #8                               @  |
        orrne vLow, vLow, #8                             @  |

        strh vLow, [rDREG]                               @ Store result
        cmp vLow, #0                                     @ Update ARM Z flag
        bic rARM, rARM, #1073741824                      @  |
        orreq rARM, rARM, #1073741824                    @  |

        strh vLow, [rDREG]                               @ Store result
        b handle_fx_rpix_8bit.return

@ PLOT 8BIT: Draws a pixel at R1,R2 (X,Y), using GSU.vColorReg as the source
handle_fx_plot_8bit:
        ldrb    ip, [rGSU, #FX_R2]                       @ Load Y
        add     rR15, rR15, #1                           @ R15++
        ldr     vLow, [rGSU, #FX_vScreenHeight]          @ Load screen height
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        ldrh    r1, [rGSU, #FX_R1]                       @ Load X
        cmp     ip, vLow                                 @ Test Y > screen height
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0.
        add     r2, r1, #1                               @ X++
        strh    r2, [rGSU, #FX_R1]                       @  |
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0. Prevents stall from next branch getting folded
        bcs     handle_fx_plot_8bit.return               @ If Y > screen height, return
        ldrb    vLow, [rGSU, #FX_vPlotOptionReg]         @ Load vPlotOptionReg
        ldrb    r2, [rGSU, #FX_vColorReg]                @ Load vColorReg
        uxtb    r1, r1                                   @ Truncate X to 8-bit
        tst     vLow, #1                                 @ If !PLOT_TRANSPARENT, handle pixel rejection
        beq     handle_fx_plot_8bit.L239                 @  |

.L40:
        lsr     vLow, r1, #3                             @ vLow = GSU.x[X >> 3]
        add     vLow, rGSU, vLow, lsl #2                 @  |
        ldr     vLow, [vLow, #FX_x]                      @  |
        mov     rR15, #128                               @ R15 = BIT(7) >> (X & 7)
        and     r1, r1, #7                               @  |
        lsr     rR15, rR15, r1                           @  |
        lsr     r1, ip, #3                               @ R1 = GSU.apvScreen[Y >> 3]
        add     r1, rGSU, r1, lsl #2                     @  |
        ldr     r1, [r1, #FX_apvScreen]                  @  |
        lsl     ip, ip, #29                              @ IP = pixel 0 pointer
        add     ip, vLow, ip, lsr #28                    @  |  Shifted math is equivalent to vLow + ((y & 7) << 1)
        add     ip, ip, r1                               @  |

        @ vLow is free
        @ R1 is free
        @ R2 is color
        @ IP is the pixel 0 Pointer
        @ rR15 is the pixel mask

        @ The pointer seems to always be 2-byte aligned, so this is a free speedup
        @ Interleave between vLow and r1 to prevent stalls
        @ WYATT_TODO these could be reversed and tail-merged at no cost
        ldrh    r1, [ip, #0]                 @           @ Load pixel pair 1
        tst     r2, #1                       @           @ Pixel conditional
        ldrh    vLow, [ip, #16]              @           @ Load pixel pair 2. Up here to avoid a stall.
        orrne   r1, r1, rR15                 @           @  |
        biceq   r1, r1, rR15                 @           @  |
        tst     r2, #2                       @           @ Pixel conditional
        orrne   r1, r1, rR15, lsl #8         @           @  |
        biceq   r1, r1, rR15, lsl #8         @           @  |
        strh    r1, [ip, #0]                 @           @ Store pixel pair

        @ Pixel pair 2
        tst     r2, #4                       @           @ Pixel conditional
        orrne   vLow, vLow, rR15             @           @  |
        ldrh    r1, [ip, #32]                @           @ Load pixel pair 3. Up here to avoid a stall.
        biceq   vLow, vLow, rR15             @           @  |
        tst     r2, #8                       @           @ Pixel conditional
        orrne   vLow, vLow, rR15, lsl #8     @           @  |
        biceq   vLow, vLow, rR15, lsl #8     @           @  |
        strh    vLow, [ip, #16]              @           @ Store pixel pair

        @ Pixel pair 3
        tst     r2, #16                      @           @ Pixel conditional
        orrne   r1, r1, rR15                 @           @  |
        ldrh    vLow, [ip, #48]              @           @ Load pixel pair 4. Up here to avoid a stall.
        biceq   r1, r1, rR15                 @           @  |
        tst     r2, #32                      @           @ Pixel conditional
        orrne   r1, r1, rR15, lsl #8         @           @  |
        biceq   r1, r1, rR15, lsl #8         @           @  |
        strh    r1, [ip, #32]                @           @ Store pixel pair

        @ Pixel pair 4
        tst     r2, #64                      @           @ Pixel conditional
        orrne   vLow, vLow, rR15             @           @  |
        biceq   vLow, vLow, rR15             @           @  |
        tst     r2, #128                     @           @ Pixel conditional
        orrne   vLow, vLow, rR15, lsl #8     @           @  |
        biceq   vLow, vLow, rR15, lsl #8     @           @  |
        strh    vLow, [ip, #48]              @           @ Store pixel pair

handle_fx_plot_8bit.return:
        bic     rSTAT, rSTAT, #4864          @           @ CLRFLAGS: STAT
        ldr     r1, [rGSU, #FX_pvPrgBank]    @           @ Taken from dispatch to allow this return handler to branch fold
        b       dispatch.skip_1              @           @ 

@ RPIX 8BIT: Reads the color of pixel R1,R2 (X, Y) and stores to DREG.
handle_fx_rpix_8bit:
        add     rR15, rR15, #1                           @ R15++
        ldr     r1, [rGSU, #FX_vScreenHeight]            @ R1 = screen height
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        ldrb    rR15, [rGSU, #FX_R2]                     @ R15 = Y
        cmp     rR15, r1                                 @ Test Y > screen height
        ldrb    r1, [rGSU, #FX_R1]                       @ R1 = X
        bcs     handle_fx_rpix_8bit.return               @ If Y > screen height, return
        
        @ R1 is X, rR15 is Y
        lsr     vLow, r1, #3                             @ vLow = GSU.x[X >> 3]
        add     vLow, rGSU, vLow, lsl #2                 @  |
        ldr     vLow, [vLow, #FX_x]                      @  |
        mov     ip, #128                                 @ IP = BIT(7) >> (X & 7)
        and     r1, r1, #7                               @  |
        lsr     ip, ip, r1                               @  |
        lsr     r1, rR15, #3                             @ R1 = GSU.apvScreen[Y >> 3]
        add     r1, rGSU, r1, lsl #2                     @  |
        ldr     r1, [r1, #FX_apvScreen]                  @  |
        lsl     rR15, rR15, #29                          @ R15 = pixel 0 pointer
        add     rR15, vLow, rR15, lsr #28                @  |  Shifted math is equivalent to vLow + ((y & 7) << 1)
        add     rR15, rR15, r1                           @  |

        @ rR15 is pixel 0 Pointer, IP is the pixel mask
        ldrh r1, [rR15, #0]                              @ Load pixel pair 1
        ldrh r2, [rR15, #16]                             @ Load pixel pair 2
        mov vLow, #0                                     @ Initial result

        tst r1, ip                                       @ Pixel pair 1
        orrne vLow, vLow, #1                             @  |
        tst r1, ip, lsl #8                               @  |
        orrne vLow, vLow, #2                             @  |

        ldrh r1, [rR15, #32]                             @ Load pixel pair 3
        tst r2, ip                                       @ Pixel pair 2
        orrne vLow, vLow, #4                             @  |
        tst r2, ip, lsl #8                               @  |
        orrne vLow, vLow, #8                             @  |

        ldrh r2, [rR15, #48]                             @ Load pixel pair 4
        tst r1, ip                                       @ Pixel pair 3
        orrne vLow, vLow, #16                            @  |
        tst r1, ip, lsl #8                               @  |
        orrne vLow, vLow, #32                            @  |

        tst r2, ip                                       @ Pixel pair 4
        orrne vLow, vLow, #64                            @  |
        tst r2, ip, lsl #8                               @  |
        orrne vLow, vLow, #128                           @  |

        strh vLow, [rDREG]                               @ Store result
        cmp vLow, #0                                     @ Update ARM Z flag
        bic rARM, rARM, #1073741824                      @  |
        orreq rARM, rARM, #1073741824                    @  |
        
handle_fx_rpix_8bit.return:
        add     rR15, rGSU, #FX_R14                      @ TESTR14: Pointer to R14
handle_fx_rpix_8bit.return_skip_1:
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        beq     testr14_clrflags_dispatch                @ TESTR14: branch
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       dispatch                                 @ 

@ NOP: Clears flags and advances R15
handle_fx_nop:
        add     rR15, rR15, #1                           @ R15++
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       dispatch.skip_1                          @ 

@ CACHE: reintialize GSU cache
handle_fx_cache:
        ldrh    ip, [rGSU, #FX_vCacheBaseReg]            @ ip = GSU.vCacheBaseReg
        bic     r2, rR15, #15                            @ r2 = R15 & 0xfff0
        add     rR15, rR15, #1                           @ R15++
        cmp     ip, r2                                   @ If cache base is incorrect or if cache is disabled, reload
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        beq     dispatch.skip_1                          @ 
        
        @ Reload cache
        strh    r2, [rGSU, #FX_vCacheBaseReg]            @ GSU.vCacheBaseReg = R15 & 0xfff0
        mov     ip, #0                                   @ 
        str     ip, [rGSU, #FX_vCacheFlags]              @ GSU.vCacheFlags = 0
        b       dispatch.skip_1                          @ 

@ LSR: logical shift right
handle_fx_lsr:
        ldrh    r2, [rSREG]                              @ Load SREG
        add     rR15, rR15, #1                           @ R15++
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        lsrs    r2, r2, #1                               @ Do the rightshift
        mrs     rARM, cpsr                               @ Read flags from CPSR
        add     ip, rGSU, #FX_R14                        @ TESTR14: Pointer to R14
        cmp     rDREG, ip                                @ TESTR14: If DREG == 14, load rombuffer
        strh    r2, [rDREG]                              @ Store result into DREG
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        beq     testr14_clrflags_dispatch                @ TESTR14: branch
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       dispatch.skip_1                          @ 

@ ROL: rotate left
handle_fx_rol:
        ldrh    r2, [rSREG]                              @ Load SREG
        add     rR15, rR15, #1                           @ R15++
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        lsl     r2, r2, #16                              @ Shift value into upper half of reg
        orrcs   r2, r2, #32768                           @ If carry is set, set bit 15
        lsls    r2, r2, #1                               @ Shift left 1 to set flags
        mrs     rARM, cpsr                               @ Read flags from CPSR
        add     ip, rGSU, #FX_R14                        @ TESTR14: Pointer to R14
        cmp     rDREG, ip                                @ TESTR14: If DREG == 14, load rombuffer
        lsr     r2, r2, #16                              @ Shift down from top half of register
        strh    r2, [rDREG]                              @ Store result
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        beq     testr14_clrflags_dispatch                @ TESTR14: branch
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       dispatch.skip_1                          @ 

@ BRA: unconditional branch
handle_fx_bra:
        add     rR15, rR15, #1                           @ R15++
        uxth    rR15, rR15                               @ Wrap R15 at 16 bits
        sxtb    r2, rPIPE                                @ Sign-extend PIPE
        add     r2, rR15, r2                             @ Add PIPE to R15
        ldrb    rPIPE, [r1, rR15]                        @ FETCHPIPE
        strh    r2, [rGSU, #FX_R15]                      @ Store destination to R15
        b       dispatch_flags.skip_1                    @ 

@ BGE: branch if greater or equal
handle_fx_bge:
        add     rR15, rR15, #1                           @ R15++
        uxth    rR15, rR15                               @ Wrap R15 at 16 bits
        sxtb    r2, rPIPE                                @ Sign-extend PIPE
        ldrb    rPIPE, [r1, rR15]                        @ FETCHPIPE
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        addge   rR15, rR15, r2                           @ Handle branch
        addlt   rR15, rR15, #1                           @ 
        strh    rR15, [rGSU, #FX_R15]                    @ Store destination to R15
        b       dispatch_flags.skip_1                    @ 

@ BLT: branch if less than
handle_fx_blt:
        add     rR15, rR15, #1                           @ R15++
        uxth    rR15, rR15                               @ Wrap R15 at 16 bits
        sxtb    r2, rPIPE                                @ Sign-extend PIPE
        ldrb    rPIPE, [r1, rR15]                        @ FETCHPIPE
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        addlt   rR15, rR15, r2                           @ Handle branch
        addge   rR15, rR15, #1                           @ 
        strh    rR15, [rGSU, #FX_R15]                    @ Store destination to R15
        b       dispatch_flags.skip_1                    @ 

@ BNE: branch if not equal
handle_fx_bne:
        add     rR15, rR15, #1                           @ R15++
        uxth    rR15, rR15                               @ Wrap R15 at 16 bits
        sxtb    r2, rPIPE                                @ Sign-extend PIPE
        ldrb    rPIPE, [r1, rR15]                        @ FETCHPIPE
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        addne   rR15, rR15, r2                           @ Handle branch
        addeq   rR15, rR15, #1                           @ 
        strh    rR15, [rGSU, #FX_R15]                    @ Store destination to R15
        b       dispatch_flags.skip_1                    @ 

@ BEQ: branch if equal
handle_fx_beq:
        add     rR15, rR15, #1                           @ R15++
        uxth    rR15, rR15                               @ Wrap R15 at 16 bits
        sxtb    r2, rPIPE                                @ Sign-extend PIPE
        ldrb    rPIPE, [r1, rR15]                        @ FETCHPIPE
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        addeq   rR15, rR15, r2                           @ Handle branch
        addne   rR15, rR15, #1                           @ 
        strh    rR15, [rGSU, #FX_R15]                    @ Store destination to R15
        b       dispatch_flags.skip_1                    @ 

@ BPL: branch if positive or zero
handle_fx_bpl:
        add     rR15, rR15, #1                           @ R15++
        uxth    rR15, rR15                               @ Wrap R15 at 16 bits
        sxtb    r2, rPIPE                                @ Sign-extend PIPE
        ldrb    rPIPE, [r1, rR15]                        @ FETCHPIPE
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        addpl   rR15, rR15, r2                           @ Handle branch
        addmi   rR15, rR15, #1                           @ 
        strh    rR15, [rGSU, #FX_R15]                    @ Store destination to R15
        b       dispatch_flags.skip_1                    @ 

@ BMI: branch if negative
handle_fx_bmi:
        add     rR15, rR15, #1                           @ R15++
        uxth    rR15, rR15                               @ Wrap R15 at 16 bits
        sxtb    r2, rPIPE                                @ Sign-extend PIPE
        ldrb    rPIPE, [r1, rR15]                        @ FETCHPIPE
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        addmi   rR15, rR15, r2                           @ Handle branch
        addpl   rR15, rR15, #1                           @ 
        strh    rR15, [rGSU, #FX_R15]                    @ Store destination to R15
        b       dispatch_flags.skip_1                    @ 

@ BCC: branch if lower (unsigned <)
handle_fx_bcc:
        add     rR15, rR15, #1                           @ R15++
        uxth    rR15, rR15                               @ Wrap R15 at 16 bits
        sxtb    r2, rPIPE                                @ Sign-extend PIPE
        ldrb    rPIPE, [r1, rR15]                        @ FETCHPIPE
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        addcc   rR15, rR15, r2                           @ Handle branch
        addcs   rR15, rR15, #1                           @ 
        strh    rR15, [rGSU, #FX_R15]                    @ Store destination to R15
        b       dispatch_flags.skip_1                    @ 

@ BCS: branch if higher or same (unsigned >=)
handle_fx_bcs:
        add     rR15, rR15, #1                           @ R15++
        uxth    rR15, rR15                               @ Wrap R15 at 16 bits
        sxtb    r2, rPIPE                                @ Sign-extend PIPE
        ldrb    rPIPE, [r1, rR15]                        @ FETCHPIPE
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        addcs   rR15, rR15, r2                           @ Handle branch
        addcc   rR15, rR15, #1                           @ 
        strh    rR15, [rGSU, #FX_R15]                    @ Store destination to R15
        b       dispatch_flags.skip_1                    @ 

@ BVC: branch if no overflow
handle_fx_bvc:
        add     rR15, rR15, #1                           @ R15++
        uxth    rR15, rR15                               @ Wrap R15 at 16 bits
        sxtb    r2, rPIPE                                @ Sign-extend PIPE
        ldrb    rPIPE, [r1, rR15]                        @ FETCHPIPE
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        addvc   rR15, rR15, r2                           @ Handle branch
        addvs   rR15, rR15, #1                           @ 
        strh    rR15, [rGSU, #FX_R15]                    @ Store destination to R15
        b       dispatch_flags.skip_1                    @ 

@ BVS: branch if overflow
handle_fx_bvs:
        add     rR15, rR15, #1                           @ R15++
        uxth    rR15, rR15                               @ Wrap R15 at 16 bits
        sxtb    r2, rPIPE                                @ Sign-extend PIPE
        ldrb    rPIPE, [r1, rR15]                        @ FETCHPIPE
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        addvs   rR15, rR15, r2                           @ Handle branch
        addvc   rR15, rR15, #1                           @ 
        strh    rR15, [rGSU, #FX_R15]                    @ Store destination to R15
        b       dispatch_flags.skip_1                    @ 

@ TO: set register n as destination register
@ move one register to another (if B flag is set)
@ Cannot be called on R14 or R15.
handle_fx_to_r:
        tst     rSTAT, #4096                             @ Test B
        add     rR15, rR15, #1                           @ R15++
        beq     handle_fx_to_r.b_is_not_set              @ If B is not set, branch
@ B is set
        ldrh    r2, [rSREG]                              @ Load SREG
        lsl     vLow, vLow, #1                           @ Shift vLow for 2-byte offset
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        strh    r2, [rGSU, vLow]                         @ Register N = SREG
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       dispatch.skip_1                          @ 
handle_fx_to_r.b_is_not_set:
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15. vLow cannot be 15, so early store is valid
        add     rDREG, rGSU, vLow, lsl #1                @ DREG = vLow
        b       dispatch_flags.skip_1                    @ 


@ TO_R14: set register 14 as destination register
@ If B flag is set, move SREG to R14, CLRFLAGS, and READR14 instead
handle_fx_to_r14:
        tst     rSTAT, #4096                             @ Test B
        add     rR15, rR15, #1                           @ R15++
        bne     handle_fx_to_r14.b_is_set                @ If B is set, branch
@ B is not set
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        add     rDREG, rGSU, #FX_R14                     @ DREG = pointer to R14
        b       dispatch_flags.skip_1                    @ 
handle_fx_to_r14.b_is_set:
        ldrh    r2, [rSREG]                              @ Load SREG
        ldr     ip, [rGSU, #FX_pvRomBank]                @ READR14: Load GSU.pvRomBank
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        strh    r2, [rGSU, #FX_R14]                      @ R14 = SREG
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        ldrb    vLow, [ip, r2]                           @ READR14: Load GSU.pvRomBank[R14]
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        strb    vLow, [rGSU, #FX_vRomBuffer]             @ READR14: Store ROMBUFFER
        b       dispatch.skip_1                          @ 

@ TO_R15: Set DREG to R15 and increment R15
@ If B flag is set, move SREG to R15 instead
handle_fx_to_r15:
        tst     rSTAT, #4096                             @ Test B
        beq     handle_fx_to_r15.b_is_not_set            @ If B is not set, branch
@ B is set
        ldrh    rR15, [rSREG]                            @ R15 = SREG
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        strh    rR15, [rGSU, #FX_R15]                    @ R15 = SREG
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        b       dispatch.skip_2                          @ 
handle_fx_to_r15.b_is_not_set:
        add     rR15, rR15, #1                           @ R15++
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        add     rDREG, rGSU, #FX_R15                     @ DREG = pointer to R15
        b       dispatch_flags.skip_1                    @ 

@ WITH: set register n as source and destination register
handle_fx_with_r:
        add     rDREG, rGSU, vLow, lsl #1                @ Calculate register
        add     rR15, rR15, #1                           @ R15++
        mov     rSREG, rDREG                             @ Copy register to SREG
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        orr     rSTAT, rSTAT, #4096                      @ Set flag B
        b       dispatch_flags.skip_1                    @ 

@ STW: store word (16 bits)
handle_fx_stw_r:
        lsl     vLow, vLow, #1                           @ Double vLow for 16-bit offset
        ldrh    vLow, [rGSU, vLow]                       @ Load offset
        ldr     ip, [rGSU, #FX_pvRamBank]                @ Load RAM base pointer
        strh    vLow, [rGSU, #FX_vLastRamAdr]            @ Store offset to GSU.vLastRamAdr
        ldrh    r2, [rSREG]                              @ Load source data
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        strb    r2, [ip, vLow]                           @ Store bottom byte
        eor     vLow, vLow, #1                           @ Flip bottom bit of offset
        add     rR15, rR15, #1                           @ R15++
        lsr     r2, r2, #8                               @ Prep top byte
        strb    r2, [ip, vLow]                           @ Store top byte
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        b       dispatch.skip_1                          @ 

@ LOOP: decrement loop counter R12 and branch to R13 on not zero
handle_fx_loop:
        ldrh    r2, [rGSU, #FX_R12]                      @ Load counter
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        sub     r2, r2, #1                               @ Decrement counter
        strh    r2, [rGSU, #FX_R12]                      @ Store counter
        lsl     rARM, r2, #16                            @ Shift counter to top half of register and test flags
        movs    rARM, rARM                               @ Set flags
        mrs     rARM, cpsr                               @ Read flags from CPSR
        beq     handle_fx_loop.loop_end                  @ 

        ldrh    rR15, [rGSU, #FX_R13]                    @ Load destination
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        b       dispatch.skip_2                          @ 
handle_fx_loop.loop_end:
        add     rR15, rR15, #1                           @ R15++
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       dispatch.skip_1                          @ 

@ ALT1: set ALT mode 1
handle_fx_alt1:
        add     rR15, rR15, #1                           @ R15++
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        bic     rSTAT, rSTAT, #4096                      @ Clear B flag
        orr     rSTAT, rSTAT, #256                       @ Set ALT1 flag
        b       dispatch_flags.skip_1                    @ 

@ ALT2: set ALT mode 2
handle_fx_alt2:
        add     rR15, rR15, #1                           @ R15++
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        bic     rSTAT, rSTAT, #4096                      @ Clear B flag
        orr     rSTAT, rSTAT, #512                       @ Set ALT2 flag
        b       dispatch_flags.skip_1                    @ 
        
@ ALT3: set ALT mode 3
handle_fx_alt3:
        add     rR15, rR15, #1                           @ R15++
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        bic     rSTAT, rSTAT, #4096                      @ Clear B flag
        orr     rSTAT, rSTAT, #768                       @ Set ALT1 + ALT2 flags
        b       dispatch_flags.skip_1                    @ 

@ LDW: load word
handle_fx_ldw_r:
        lsl     vLow, vLow, #1                           @ Double vLow for 16-bit offset
        add     rR15, rR15, #1                           @ R15++
        ldrh    rSREG, [rGSU, vLow]                      @ Load RAM offset
        ldr     vLow, [rGSU, #FX_pvRamBank]              @ Load RAM base pointer
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        eor     ip, rSREG, #1                            @ Flip bottom bit of offset, stored in a separate register
        strh    rSREG, [rGSU, #FX_vLastRamAdr]           @ Store offset to GSU.vLastRamAdr
        ldrb    ip, [vLow, ip]                           @ Load top byte
        ldrb    rSREG, [vLow, rSREG]                     @ Load bottom byte
        add     vLow, rGSU, #FX_R14                      @ TESTR14: Pointer to R14
        cmp     rDREG, vLow                              @ TESTR14: If DREG == 14, load rombuffer
        orr     rSREG, rSREG, ip, lsl #8                 @ Combine bytes into word
        strh    rSREG, [rDREG]                           @ Store word into DREG
        beq     testr14_clrflags_dispatch                @ TESTR14: branch
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        b       dispatch.skip_1                          @ 

@ SWAP: swap low and high bytes of SREG, store in DREG
handle_fx_swap:
        ldrh    ip, [rSREG]                              @ Load value from SREG
        add     rR15, rR15, #1                           @ R15++
        add     r2, rGSU, #FX_R14                        @ TESTR14: Pointer to R14
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        rev16   ip, ip                                   @ Byteswap value
        lsl     rARM, ip, #16                            @ Shift for flag setting
        movs    rARM, rARM                               @ Set flags
        mrs     rARM, cpsr                               @ Read flags from CPSR
        cmp     rDREG, r2                                @ TESTR14: If DREG == 14, load rombuffer
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        strh    ip, [rDREG]                              @ Store value into DREG
        beq     testr14_clrflags_dispatch                @ TESTR14: Branch
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       dispatch.skip_1                          @ 

@ COLOR: copy SREG to color register
handle_fx_color:
        ldrb    ip, [rGSU, #FX_vPlotOptionReg]           @ Load plotOptionReg
        ldrb    r2, [rSREG]                              @ Load color from SREG
        add     rR15, rR15, #1                           @ R15++
        tst     ip, #4                                   @ If PLOT_HIGHNIBBLE, duplicate the high nibble of color to the low nibble
        andne   vLow, r2, #240                           @  |
        orrne   r2, vLow, r2, lsr #4                     @  V
        tst     ip, #8                                   @ If PLOT_FREEZEHIGH, only update the bottom nibble
        ldrbne  ip, [rGSU, #FX_vColorReg]                @  |
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        andne   r2, r2, #15                              @  |
        bicne   ip, ip, #15                              @  |
        orrne   r2, ip, r2                               @  V
        strb    r2, [rGSU, #FX_vColorReg]                @ Store result to GSU.vColorReg
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       dispatch.skip_1                          @ 

@ NOT: bitwise NOT of SREG, store in DREG
handle_fx_not:
        ldrh    ip, [rSREG]                              @ Load value from SREG
        add     vLow, rGSU, #FX_R14                      @ TESTR14: Pointer to R14
        add     rR15, rR15, #1                           @ R15++
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        orr     ip, ip, ip, lsl #16                      @ Duplicate value into both halves of a register
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        mvns    ip, ip                                   @ Negate value and set flags
        mrs     rARM, cpsr                               @ Read flags from CPSR
        cmp     rDREG, vLow                              @ TESTR14: If DREG == 14, load rombuffer
        strh    ip, [rDREG]                              @ Store value
        beq     testr14_clrflags_dispatch                @ TESTR14: branch
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       dispatch.skip_1                          @ 

@ ADD: SREG + register n, store in DREG
handle_fx_add_r:
        lsl     vLow, vLow, #1                           @ Shift vLow for 2-byte offset
        ldrh    ip, [rSREG]                              @ Load value 1 from SREG
        ldrh    r2, [rGSU, vLow]                         @ Load value 2 from register N
        add     vLow, rGSU, #FX_R14                      @ TESTR14: Pointer to R14
        add     rR15, rR15, #1                           @ R15++
        lsl     ip, ip, #16                              @ Shift value 1 to the top half of its register
        adds    ip, ip, r2, lsl #16                      @ Add both values. Overwrites all flags.
        mrs     rARM, cpsr                               @ Read flags from CPSR
        cmp     rDREG, vLow                              @ TESTR14: If DREG == 14, load rombuffer
        lsr     ip, ip, #16                              @ Shift result down from top half of register
        strh    ip, [rDREG]                              @ Store result to DREG
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        beq     testr14_clrflags_dispatch                @ TESTR14: branch
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       dispatch.skip_1                          @ 

@ SUB: SREG - register n, store in DREG
handle_fx_sub_r:
        lsl     vLow, vLow, #1                           @ Shift vLow for 2-byte offset
        ldrh    ip, [rSREG]                              @ Load value 1 from SREG
        ldrh    r2, [rGSU, vLow]                         @ Load value 2 from register N
        add     vLow, rGSU, #FX_R14                      @ TESTR14: Pointer to R14
        add     rR15, rR15, #1                           @ R15++
        lsl     ip, ip, #16                              @ Shift value 1 to the top half of its register
        subs    ip, ip, r2, lsl #16                      @ Subtract value 2 from value 1. Overwrites all flags.
        mrs     rARM, cpsr                               @ Read flags from CPSR
        cmp     rDREG, vLow                              @ TESTR14: If DREG == 14, load rombuffer
        lsr     ip, ip, #16                              @ Shift result down from top half of register
        strh    ip, [rDREG]                              @ Store result to DREG
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        beq     testr14_clrflags_dispatch                @ TESTR14: branch
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       dispatch.skip_1                          @ 

@ MERGE: Top halves of R7 and R8 as upper and lower bytes respectively, store in DREG
handle_fx_merge:
        ldrh    r1, [rGSU, #FX_R7]                       @ Load R7
        ldrh    r2, [rGSU, #FX_R8]                       @ Load R8
        bic     r1, r1, #255                             @ Clear bottom half of R7
        orr     r2, r1, r2, lsr #8                       @ Shift top half of R8 down and OR to create final value
        add     rR15, rR15, #1                           @ R15++
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        lsr     rR15, r2, #4                             @ Calculate merge flag LUT index
        orr     rR15, rR15, r1, lsr #12                  @  |
        and     rR15, rR15, #15                          @  V
        add     rR15, rGSU, rR15                         @ Calculate flag LUT offset
        ldrb    rARM, [rR15, #FX_mergeFlagLut]           @ Load flags from LUT
        strh    r2, [rDREG]                              @ Store result to DREG
        add     rR15, rGSU, #FX_R14                      @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        lsl     rARM, rARM, #28                          @ Shift resultant flags into position. WYATT_TODO could use u32s, but would be more DCACHE.
        beq     testr14_clrflags_dispatch                @ TESTR14: branch
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       dispatch                                 @ 

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
        ldrh    r2, [rGSU, #FX_R15]                      @ Load R15. WYATT_TODO unnecessary
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        add     r2, r2, #1                               @ R15++
        strh    r2, [rGSU, #FX_R15]                      @ Store R15
        strh    rR15, [rDREG]                            @ Store result
        add     rR15, rGSU, #FX_R14                      @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        beq     testr14_clrflags_dispatch                @ TESTR14: branch
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       dispatch                                 @ 

@ MULT: multiply SREG and register n as signed 8-bit ints, store in DREG
handle_fx_mult_r:
        lsl     vLow, vLow, #1                           @ Shift vLow for 2-byte offset
        ldrsb   rR15, [rSREG]                            @ Load s8 value 1 from SREG
        ldrsb   r2, [rGSU, vLow]                         @ Load s8 value 2 from register N. WYATT_TODO could this use an 8-bit load?
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        smulbb  rR15, rR15, r2                           @ Multiply to get the result
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        movs    rARM, rR15                               @ Set flags
        mrs     rARM, cpsr                               @ Read flags from CPSR
        ldrh    r2, [rGSU, #FX_R15]                      @ Load R15. WYATT_TODO unnecessary
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        add     r2, r2, #1                               @ R15++
        strh    r2, [rGSU, #FX_R15]                      @ Store R15
        strh    rR15, [rDREG]                            @ Store result
        add     rR15, rGSU, #FX_R14                      @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        beq     testr14_clrflags_dispatch                @ TESTR14: branch
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        b       dispatch                                 @ 

@ SBK: store word to last accessed RAM address
handle_fx_sbk:
        ldrh    rR15, [rSREG]                            @ Load value from SREG
        ldrh    r2, [rGSU, #FX_vLastRamAdr]              @ Load vLastRamAdr
        ldr     r1, [rGSU, #FX_pvRamBank]                @ Load RAM base pointer
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        strb    rR15, [r1, r2]                           @ Store bottom byte
        ldrh    r2, [rGSU, #FX_vLastRamAdr]              @ Reload vLastRamAdr WYATT_TODO unnecessary
        ldr     r1, [rGSU, #FX_pvRamBank]                @ Reload RAM base pointer. WYATT_TODO unnecessary
        lsr     rR15, rR15, #8                           @ Prep top byte
        eor     r2, r2, #1                               @ Flip bottom bit of offset
        strb    rR15, [r1, r2]                           @ Store bottom byte
        ldrh    rR15, [rGSU, #FX_R15]                    @ Load R15 WYATT_TODO unnecessary
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        add     rR15, rR15, #1                           @ R15++
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        b       dispatch                                 @ 

@ LINK: R11 = R15 + immediate
handle_fx_link_i:
        add     vLow, vLow, rR15                         @ Add R15 and immediate
        add     rR15, rR15, #1                           @ R15++
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        strh    vLow, [rGSU, #FX_R11]                    @ Store R11
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       dispatch                                 @ 

@ SEX: sign-extend 8-bit to 16-bit, SREG to DREG
handle_fx_sex:
        ldrh    r2, [rGSU, #FX_R15]                      @ Load R15. WYATT_TODO unnecessary
        ldrsb   rR15, [rSREG]                            @ Load value from SREG and sign-extend
        add     r2, r2, #1                               @ R15++
        strh    r2, [rGSU, #FX_R15]                      @ Store R15
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        movs    rR15, rR15                               @ Set flags
        mrs     rARM, cpsr                               @ Read flags from CPSR
        strh    rR15, [rDREG]                            @ Store value
        add     rR15, rGSU, #FX_R14                      @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        beq     testr14_clrflags_dispatch                @ TESTR14: branch
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       dispatch                                 @ 

@ ASR: arithmetic shift right, SREG to DREG
handle_fx_asr:
        ldrh    r2, [rGSU, #FX_R15]                      @ Load R15. WYATT_TODO unnecessary
        ldrsh   rR15, [rSREG]                            @ Load value from SREG and sign-extend to 32-bit
        add     r2, r2, #1                               @ R15++
        strh    r2, [rGSU, #FX_R15]                      @ Store R15
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        asrs    rR15, rR15, #1                           @ ASR by 1 and set flags
        mrs     rARM, cpsr                               @ Read flags from CPSR
        strh    rR15, [rDREG]                            @ Store result
        add     rR15, rGSU, #FX_R14                      @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        beq     testr14_clrflags_dispatch                @ TESTR14: branch
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       dispatch                                 @ 

@ ROR: rotate right, SREG to DREG
handle_fx_ror:
        ldrh    r2, [rGSU, #FX_R15]                      @ Load R15. WYATT_TODO unnecessary
        ldrh    rR15, [rSREG]                            @ Load value from SREG and sign-extend to 32-bit
        add     r2, r2, #1                               @ R15++
        strh    r2, [rGSU, #FX_R15]                      @ Store R15
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        orrcs   rR15, rR15, #65536                       @ If the carry flag was set, set bit 16 of value
        rrxs    rR15, rR15                               @ Rotate right and set flags
        mrs     rARM, cpsr                               @ Read flags from CPSR
        strh    rR15, [rDREG]                            @ Store result
        add     rR15, rGSU, #FX_R14                      @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        beq     testr14_clrflags_dispatch                @ TESTR14: branch
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       dispatch                                 @ 

@ JMP: jump to address of register N. No delay slot.
handle_fx_jmp_r:
        lsl     vLow, vLow, #1                           @ Shift vLow for 2-byte offset
        ldrh    rR15, [rGSU, vLow]                       @ Load destination from register N
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        strh    rR15, [rGSU, #FX_R15]                    @ Store destination to R15
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       dispatch                                 @ 

@ LOB: set upper byte to 0, SREG to DREG
handle_fx_lob:
        ldrh    rR15, [rGSU, #FX_R15]                    @ Load R15. WYATT_TODO unnecessary
        ldrb    r2, [rSREG]                              @ Load bottom byte of register N and zero-extend
        add     rR15, rR15, #1                           @ R15++
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        lsl     rARM, r2, #24                            @ Shift result to top byte of register
        movs    rARM, rARM                               @ Set flags
        mrs     rARM, cpsr                               @ Read flags from CPSR
        strh    r2, [rDREG]                              @ Store result to DREG
        add     rR15, rGSU, #FX_R14                      @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        beq     testr14_clrflags_dispatch                @ TESTR14: branch
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       dispatch                                 @ 

@ Data table for fx_run_asm
.L242:
        .word   GSU
        .word   opcode_goto_table
        .word   plot_rpix_handler_table

@ FMULT: 16 to 32 bit signed multiply, keep top 16. SREG * R6, store to DREG
handle_fx_fmult:
        ldrh    rR15, [rSREG]                            @ Load value 1 from SREG
        ldrh    r2, [rGSU, #FX_R6]                       @ Load value 2 from R6
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        smulbb  rR15, rR15, r2                           @ Signed multiply
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        asrs    rR15, rR15, #16                          @ Shift top half down and set flags
        mrs     rARM, cpsr                               @ Read flags from CPSR
        ldrh    r2, [rGSU, #FX_R15]                      @ Load R15. WYATT_TODO unnecessary
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        add     r2, r2, #1                               @ R15++
        strh    r2, [rGSU, #FX_R15]                      @ Store R15
        strh    rR15, [rDREG]                            @ Store result
        add     rR15, rGSU, #FX_R14                      @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        beq     testr14_clrflags_dispatch                @ TESTR14: branch
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        b       dispatch                                 @ 

@ IBT: fetch PIPE and store to register N
handle_fx_ibt_r:
        add     r2, rR15, #1                             @ R15 + 1 into scratch register
        uxth    r2, r2                                   @ Wrap scratch R15 at 16 bits
        strh    r2, [rGSU, #FX_R15]                      @ Store R15. WYATT_TODO unnecessary. Aliasing?
        lsl     vLow, vLow, #1                           @ Shift vLow for 2-byte offset
        sxtb    ip, rPIPE                                @ Sign-extend PIPE
        add     rR15, rR15, #2                           @ R15 + 2
        ldrb    rPIPE, [r1, r2]                          @ FETCHPIPE. We don't immediately use this value! This can be optimized.
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        strh    ip, [rGSU, vLow]                         @ Store result
        b       dispatch                                 @ 

@ IBT R14: fetch PIPE and store to register N, then READR14
handle_fx_ibt_r14:
        add     r2, rR15, #1                             @ R15 + 1 into scratch register
        uxth    r2, r2                                   @ Wrap scratch R15 at 16 bits
        strh    r2, [rGSU, #FX_R15]                      @ Store R15. WYATT_TODO unnecessary. Aliasing?
        sxtb    ip, rPIPE                                @ Sign-extend PIPE
        add     rR15, rR15, #2                           @ R15 + 2
        ldrb    rPIPE, [r1, r2]                          @ FETCHPIPE. We don't immediately use this value!
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        strh    ip, [rGSU, #FX_R14]                      @ Store result
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        uxth    ip, ip                                   @ PIPE was sign-extended, so we need to zero-extend it for the load. WYATT_TODO could probably avoid this.
        ldr     rR15, [rGSU, #FX_pvRomBank]              @ READR14: Load ROM base pointer
        ldrb    rR15, [rR15, ip]                         @ READR14: Load ROM(R14)
        strb    rR15, [rGSU, #FX_vRomBuffer]             @ READR14: Store to ROMBUFFER
        b       dispatch                                 @ 

@ FROM: Set SREG to register N
@ If B flag is set, move register N to DREG and set flags instead
@ B is unlikely. WYATT_TODO invert the branch.
handle_fx_from_r:
        tst     rSTAT, #4096                             @ Test B flag
        beq     handle_fx_from_r.b_is_not_set            @ If B is not set, just set SREG and increment R15
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        lsl     vLow, vLow, #1                           @ Shift vLow for 2-byte offset
        ldrh    rR15, [rGSU, vLow]                       @ Load result
        bic     rARM, rARM, #-805306368                  @ Clear NZO flags
        lsls    r2, rR15, #24                            @ Set the flags we need
        orrmi   rARM, rARM, #268435456                   @  |
        lsls    r2, rR15, #16                            @  |
        orrmi   rARM, rARM, #-2147483648                 @  |
        orreq   rARM, rARM, #1073741824                  @  V
        ldrh    r2, [rGSU, #FX_R15]                      @ Load R15. WYATT_TODO unnecessary
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        add     r2, r2, #1                               @ R15++
        strh    r2, [rGSU, #FX_R15]                      @ Store R15
        strh    rR15, [rDREG]                            @ Store result
        add     rR15, rGSU, #FX_R14                      @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        beq     testr14_clrflags_dispatch                @ TESTR14: branch
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        b       dispatch                                 @ 

@ HIB: arithmetic right-shift register by 8, SREG to DREG
handle_fx_hib:
        ldrh    rR15, [rSREG]                            @ Load result from SREG
        ldrh    r2, [rGSU, #FX_R15]                      @ Load R15. WYATT_TODO unnecessary
        lsr     rR15, rR15, #8                           @ Prep high byte
        add     r2, r2, #1                               @ R15++
        strh    r2, [rGSU, #FX_R15]                      @ Store R15
        strh    rR15, [rDREG]                            @ Store result
        sxtb    r2, rR15                                 @ Sign-extend result into scratch register
        add     rR15, rGSU, #FX_R14                      @ TESTR14: Pointer to R14
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        movs    rARM, r2                                 @ Set flags
        mrs     rARM, cpsr                               @ Read flags from CPSR
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        beq     testr14_clrflags_dispatch                @ TESTR14: branch
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       dispatch                                 @ 

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
        ldrh    r2, [rGSU, #FX_R15]                      @ Load R15. WYATT_TODO unnecessary
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        add     r2, r2, #1                               @ R15++
        strh    r2, [rGSU, #FX_R15]                      @ Store R15
        strh    rR15, [rDREG]                            @ Store result
        add     rR15, rGSU, #FX_R14                      @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        beq     testr14_clrflags_dispatch                @ TESTR14: branch
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       dispatch                                 @ 

@ INC: increment a register. Cannot be called with R15.
handle_fx_inc_r:
        add     rR15, rR15, #1                           @ R15++
        strh    rR15, [rGSU, #FX_R15]                    @  |
        lsl     vLow, vLow, #1                           @ Shift vLow for 2-byte offset
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        ldrh    r2, [rGSU, vLow]                         @ Load value
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        add     r2, r2, #1                               @ Increment value
        strh    r2, [rGSU, vLow]                         @ Store result
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        lsl     rARM, r2, #16                            @ Set flags
        movs    rARM, rARM                               @  |
        mrs     rARM, cpsr                               @ Read flags from CPSR
        b       dispatch.skip_1                          @ Skip reloading r1 and rR15

@ INC R14: increment R14 and then READR14
handle_fx_inc_r14:
        ldrh    r2, [rGSU, #FX_R14]                      @ Load value from R14
        add     rR15, rR15, #1                           @ R15++
        strh    rR15, [rGSU, #FX_R15]                    @  |
        add     r2, r2, #1                               @ Increment value
        strh    r2, [rGSU, #FX_R14]                      @ Store result to R14
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        ldr     ip, [rGSU, #FX_pvRomBank]                @ READR14: Load ROM base pointer
        lsl     r2, r2, #16                              @ Set flags
        movs    r2, r2                                   @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        ldrb    r2, [ip, r2, lsr #16]                    @ READR14: Load ROM(R14)
        mrs     rARM, cpsr                               @ Read flags from CPSR
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        strb    r2, [rGSU, #FX_vRomBuffer]               @ READR14: Store to ROMBUFFER
        b       dispatch.skip_1                          @ Skip reloading r1 and rR15

@ GETC: transfer ROMBUFFER to color register
handle_fx_getc:
        ldrb    r1, [rGSU, #FX_vPlotOptionReg]           @ Load plotOptionReg
        ldrb    r2, [rGSU, #FX_vRomBuffer]               @ Load ROMBUFFER
        tst     r1, #4                                   @ If PLOT_HIGHNIBBLE, duplicate the high nibble of color to the low nibble
        andne   vLow, r2, #240                           @  |
        orrne   r2, vLow, r2, lsr #4                     @  V
        tst     r1, #8                                   @ If PLOT_FREEZEHIGH, only update the bottom nibble
        ldrbne  r1, [rGSU, #FX_vColorReg]                @  |
        andne   r2, r2, #15                              @  |
        bicne   r1, r1, #15                              @  |
        orrne   r2, r1, r2                               @  V
        add     rR15, rR15, #1                           @ R15++
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        strb    r2, [rGSU, #FX_vColorReg]                @ Store result to GSU.vColorReg
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       dispatch                                 @ 

@ DEC: decrement a register
handle_fx_dec_r:
        add     rR15, rR15, #1                           @ R15++
        strh    rR15, [rGSU, #FX_R15]                    @  |
        lsl     vLow, vLow, #1                           @ Shift vLow for 2-byte offset
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        ldrh    r2, [rGSU, vLow]                         @ Load value
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        sub     r2, r2, #1                               @ Decrement value
        strh    r2, [rGSU, vLow]                         @ Store result
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        lsl     rARM, r2, #16                            @ Set flags
        movs    rARM, rARM                               @  |
        mrs     rARM, cpsr                               @ Read flags from CPSR
        b       dispatch.skip_1                          @ Skip reloading r1 and rR15

@ DEC R14: decrement R14 and then READR14
handle_fx_dec_r14:
        ldrh    r2, [rGSU, #FX_R14]                      @ Load value from R14
        add     rR15, rR15, #1                 
                  @ R15++
        strh    rR15, [rGSU, #FX_R15]                    @  |
        sub     r2, r2, #1                               @ Decrement value
        strh    r2, [rGSU, #FX_R14]                      @ Store result to R14
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        ldr     ip, [rGSU, #FX_pvRomBank]                @ READR14: Load ROM base pointer
        lsl     r2, r2, #16                              @ Set flags
        movs    r2, r2                                   @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        ldrb    r2, [ip, r2, lsr #16]                    @ READR14: Load ROM(R14)
        mrs     rARM, cpsr                               @ Read flags from CPSR
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        strb    r2, [rGSU, #FX_vRomBuffer]               @ READR14: Store to ROMBUFFER
        b       dispatch.skip_1                          @ Skip reloading r1 and rR15

@ GETB: get byte from ROMBUFFER
handle_fx_getb:
        add     rR15, rR15, #1                           @ R15++
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        ldrb    rR15, [rGSU, #FX_vRomBuffer]             @ Load value from ROMBUFFER
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        strh    rR15, [rDREG]                            @ Store value to DREG
        add     rR15, rGSU, #FX_R14                      @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        beq     testr14_clrflags_dispatch                @ TESTR14: branch
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       dispatch                                 @ 

@ IWT: Combine existing PIPE and next PIPE into register N, then FETCHPIPE again
handle_fx_iwt_r:
        add     r2, rR15, #1                             @ R15 + 1 into scratch register
        uxth    r2, r2                                   @ Wrap scratch R15 at 16 bits
        mov     ip, rPIPE                                @ We need a copy of PIPE. WYATT_TODO could save here since PIPE is fetched again.
        ldrb    rPIPE, [r1, r2]                          @ FETCHPIPE
        add     r2, rR15, #2                             @ R15 + 2 into scratch register
        orr     ip, ip, rPIPE, lsl #8                    @ Combine both PIPEs into result
        lsl     vLow, vLow, #1                           @ Shift vLow for 2-byte offset
        uxth    r2, r2                                   @ Wrap scratch R15 at 16 bits
        add     rR15, rR15, #3                           @ R15 += 3
        ldrb    rPIPE, [r1, r2]                          @ FETCHPIPE. Value not immediately used.
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        strh    ip, [rGSU, vLow]                         @ Store result to register N
        b       dispatch                                 @ 

@ IWT R14: Combine existing PIPE and next PIPE into register N, then FETCHPIPE again
handle_fx_iwt_r14:
        add     r2, rR15, #1                             @ R15 + 1 into scratch register
        uxth    r2, r2                                   @ Wrap scratch R15 at 16 bits
        mov     ip, rPIPE                                @ We need a copy of PIPE. WYATT_TODO could save here since PIPE is fetched again.
        ldrb    rPIPE, [r1, r2]                          @ FETCHPIPE
        add     r2, rR15, #2                             @ R15 + 2 into scratch register
        orr     ip, ip, rPIPE, lsl #8                    @ Combine both PIPEs into result
        uxth    r2, r2                                   @ Wrap scratch R15 at 16 bits
        add     rR15, rR15, #3                           @ R15 += 3
        ldrb    rPIPE, [r1, r2]                          @ FETCHPIPE. Value not immediately used.
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        strh    ip, [rGSU, #FX_R14]                      @ Store result to R14
        ldr     rR15, [rGSU, #FX_pvRomBank]              @ READR14: Load ROM base pointer
        ldrb    rR15, [rR15, ip]                         @ READR14: Load ROM(R14)
        strb    rR15, [rGSU, #FX_vRomBuffer]             @ READR14: Store to ROMBUFFER
        b       dispatch                                 @ 

@ STB: Store byte in SREG at the RAM location pointed to by register N
handle_fx_stb_r:
        lsl     vLow, vLow, #1                           @ Shift vLow for 2-byte offset
        ldrh    rR15, [rGSU, vLow]                       @ Load destination pointer
        ldr     r2, [rGSU, #FX_pvRamBank]                @ Load RAM base pointer
        strh    rR15, [rGSU, #FX_vLastRamAdr]            @ Store destination pointer to GSU.vLastRamAdr
        ldrh    r1, [rSREG]                              @ Load value from SREG
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        strb    r1, [r2, rR15]                           @ Store value to RAM(register N)
        ldrh    rR15, [rGSU, #FX_R15]                    @ Load R15. WYATT_TODO unnecessary
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        add     rR15, rR15, #1                           @ R15++
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        b       dispatch                                 @ 

@ LDB: Load byte from the RAM location pointed to by register N into DREG
handle_fx_ldb_r:
        lsl     vLow, vLow, #1                           @ Shift vLow for 2-byte offset
        ldrh    r2, [rGSU, vLow]                         @ Load source pointer
        ldr     r1, [rGSU, #FX_pvRamBank]                @ Load RAM base pointer
        strh    r2, [rGSU, #FX_vLastRamAdr]              @ Store source pointer to GSU.vLastRamAdr
        ldrb    r2, [r1, r2]                             @ Load result
        add     rR15, rR15, #1                           @ R15++
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        strh    r2, [rDREG]                              @ Store result to DREG
        add     rR15, rGSU, #FX_R14                      @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        beq     testr14_clrflags_dispatch                @ TESTR14: branch
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       dispatch                                 @ 

@ CMODE: set plot option register to the value in SREG
handle_fx_cmode:
        ldrb    rR15, [rSREG]                            @ Load result in SREG
        tst     rR15, #16                                @ Test plotOptionReg for screenHeight
        strb    rR15, [rGSU, #FX_vPlotOptionReg]         @ Store result
        movne   rR15, #256                               @ If PLOT_OBJECT, fake screenHeight as 256
        ldreq   rR15, [rGSU, #FX_vScreenRealHeight]      @ Else, set screenHeight to its real height
        str     rR15, [rGSU, #FX_vScreenHeight]          @ Store screenHeight
        bl      fx_computeScreenPointers                 @ Recompute screen ptrs. WYATT_TODO if regs are changed, be careful!
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        ldrh    rR15, [rGSU, #FX_R15]                    @ Load R15. WYATT_TODO can be moved above computeScreenPointers
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        add     rR15, rR15, #1                           @ R15++
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        b       dispatch                                 @ 

@ ADC: add-with-carry, SREG + register N, store in DREG
handle_fx_adc_r:
        ldrh    r2, [rGSU, #FX_R15]                      @ Load R15. WYATT_TODO unnecessary
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
        strh    r2, [rGSU, #FX_R15]                      @ Store R15
        strh    rR15, [rDREG]                            @ Store result
        add     rR15, rGSU, #FX_R14                      @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        beq     testr14_clrflags_dispatch                @ TESTR14: branch
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       dispatch                                 @ 

@ SBC: subtract-with-carry, SREG - register N, store in DREG
handle_fx_sbc_r:
        ldrh    rR15, [rSREG]                            @ Load value 1
        lsl     vLow, vLow, #1                           @ Shift vLow for 2-byte offset
        ldrh    r2, [rGSU, vLow]                         @ Load value 2
        lsl     rR15, rR15, #16                          @ Shift value 1 into top half of register
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        sbcs    rR15, rR15, r2, lsl #16                  @ Do the subtract-with-carry
        mrs     rARM, cpsr                               @ Read flags from CPSR
        ldrh    r2, [rGSU, #FX_R15]                      @ Load R15. WYATT_TODO unnecessary
        lsrs    rR15, rR15, #16                          @ Shift result into bottom half of register and set flags
        add     r2, r2, #1                               @ R15++
        strh    r2, [rGSU, #FX_R15]                      @ Store R15
        orreq   rARM, rARM, #1073741824                  @ If the result is 0, set the Z flag
        strh    rR15, [rDREG]                            @ Store the result
        add     rR15, rGSU, #FX_R14                      @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        beq     testr14_clrflags_dispatch                @ TESTR14: branch
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       dispatch                                 @ 

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
        ldrh    r2, [rGSU, #FX_R15]                      @ Load R15. WYATT_TODO unnecessary
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        add     r2, r2, #1                               @ R15++
        strh    r2, [rGSU, #FX_R15]                      @ Store R15
        strh    rR15, [rDREG]                            @ Store result to DREG
        add     rR15, rGSU, #FX_R14                      @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        beq     testr14_clrflags_dispatch                @ TESTR14: branch
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       dispatch                                 @ 

@ UMULT: 8-bit to 16-bit unsigned multiply, SREG * register N, stored in DREG
handle_fx_umult_r:
        ldrb    rR15, [rSREG]                            @ Load value 1
        ldrb    r2, [rGSU, vLow, lsl #1]                 @ Load value 2
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        smulbb  rR15, rR15, r2                           @ Multiply
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        lsl     rARM, rR15, #16                          @ Shift result to top of register
        movs    rARM, rARM                               @ Set flags
        mrs     rARM, cpsr                               @ Read flags from CPSR
        ldrh    r2, [rGSU, #FX_R15]                      @ Load R15. WYATT_TODO unnecessary
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        add     r2, r2, #1                               @ R15++
        strh    r2, [rGSU, #FX_R15]                      @ Store R15
        strh    rR15, [rDREG]                            @ Store result
        add     rR15, rGSU, #FX_R14                      @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        beq     testr14_clrflags_dispatch                @ TESTR14: branch
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        b       dispatch                                 @ 

@ DIV2: Divides SREG by 2 and stores in DREG
handle_fx_div2:
        ldrh    rR15, [rSREG]                            @ Load value
        ldrh    r2, [rGSU, #FX_const_u16Max]             @ Load 0xFFFF
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        cmp     r2, rR15                                 @ Compare value to 0xFFFF
        ldrh    r2, [rGSU, #FX_R15]                      @ Load R15. WYATT_TODO unnecessary
        moveq   rR15, #1                                 @ If value == 0xFFFF, set value to 1
        add     r2, r2, #1                               @ R15++
        strh    r2, [rGSU, #FX_R15]                      @ Store R15
        sxthne  rR15, rR15                               @ Sign-extend value
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        asrs    rR15, rR15, #1                           @ Divide value by 2 with ASR
        mrs     rARM, cpsr                               @ Read flags from CPSR
        strh    rR15, [rDREG]                            @ Store result
        add     rR15, rGSU, #FX_R14                      @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        beq     testr14_clrflags_dispatch                @ TESTR14: branch
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       dispatch                                 @ 

@ LJMP: set program bank to register N and jump to SREG
handle_fx_ljmp_r:
        lsl     vLow, vLow, #1                           @ Shift vLow for 2-byte offset
        ldrh    rR15, [rGSU, vLow]                       @ Load bank
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        and     rR15, rR15, #127                         @ AND bank to 7-bit
        strb    rR15, [rGSU, #FX_vPrgBankReg]            @ Store bank to GSU.vPrgBankReg 
        add     rR15, rR15, #FX_apvRomBank >> 2          @ Offset magic for apvRomBank, pre-shifted down
        ldr     rR15, [rGSU, rR15, lsl #2]               @ Load pointer at GSU.apvRomBank[GSU.vPrgBankReg]
        ldrh    r2, [rSREG]                              @ Load destination
        str     rR15, [rGSU, #FX_pvPrgBank]              @ Store GSU.pvPrgBank pointer
        mov     rR15, #0                                 @ GSU.vCacheFlags = 0
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        str     rR15, [rGSU, #FX_vCacheFlags]            @ GSU.vCacheFlags = 0
        bic     rR15, r2, #15                            @ R15 & 0xfff0
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        strh    rR15, [rGSU, #FX_vCacheBaseReg]          @ GSU.vCacheBaseReg = R15 & 0xfff0
        strh    r2, [rGSU, #FX_R15]                      @ Store destination to R15
        b       dispatch_flags                           @ 

@ LMULT: 16-bit to 32-bit signed multiplication SREG * R6, low result in R4, then high result in DREG.
handle_fx_lmult:
        ldrh    rR15, [rSREG]                            @ Load value 1
        ldrh    r2, [rGSU, #FX_R6]                       @ Load value 2
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        smulbb  rR15, rR15, r2                           @ Multiply
        ldrh    r2, [rGSU, #FX_R15]                      @ Load R15. WYATT_TODO unnecessary
        strh    rR15, [rGSU, #FX_R4]                     @ Store low result
        add     r2, r2, #1                               @ R15++
        strh    r2, [rGSU, #FX_R15]                      @ Store R15
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        asrs    rR15, rR15, #16                          @ Set flags and shift high result down
        mrs     rARM, cpsr                               @ Read flags from CPSR
        strh    rR15, [rDREG]                            @ Store high result
        add     rR15, rGSU, #FX_R14                      @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        beq     testr14_clrflags_dispatch                @ TESTR14: branch
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       dispatch                                 @ 

@ LMS: load word from RAM (short address), store in register N
@ WYATT_TODO would this be better with a bespoke R15 version?
handle_fx_lms_r:
        lsl     ip, rPIPE, #1                            @ Shift PIPE left 1
        add     r2, rR15, #1                             @ R15 + 1 into scratch register
        strh    ip, [rGSU, #FX_vLastRamAdr]              @ Store shifted pipe GSU.vLastRamAdr
        uxth    r2, r2                                   @ Wrap scratch R15 at 16 bits
        add     rR15, rR15, #2                           @ R15 + 2
        ldrb    rPIPE, [r1, r2]                          @ FETCHPIPE
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        ldr     rR15, [rGSU, #FX_pvRamBank]              @ Load RAM base pointer
        add     r2, ip, #1                               @ GSU.vLastRamAdr + 1
        ldrb    r2, [rR15, r2]                           @ Load upper byte
        ldrb    rR15, [rR15, ip]                         @ Load lower byte
        lsl     vLow, vLow, #1                           @ Shift vLow for 2-byte offset
        orr     rR15, rR15, r2, lsl #8                   @ Combine both bytes
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        strh    rR15, [rGSU, vLow]                       @ Store result
        b       dispatch                                 @ 
        
@ LMS: load word from RAM (short address), store in register 14, then READR14
handle_fx_lms_r14:
        lsl     ip, rPIPE, #1                            @ Shift PIPE left 1
        add     r2, rR15, #1                             @ R15 + 1 into scratch register
        strh    ip, [rGSU, #FX_vLastRamAdr]              @ Store shifted pipe GSU.vLastRamAdr
        uxth    r2, r2                                   @ Wrap scratch R15 at 16 bits
        add     rR15, rR15, #2                           @ R15 + 2
        ldrb    rPIPE, [r1, r2]                          @ FETCHPIPE
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15 + 2
        ldr     rR15, [rGSU, #FX_pvRamBank]              @ Load RAM base pointer
        add     r2, ip, #1                               @ GSU.vLastRamAdr + 1
        ldrb    r2, [rR15, r2]                           @ Load upper byte
        ldrb    rR15, [rR15, ip]                         @ Load lower byte
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        orr     rR15, rR15, r2, lsl #8                   @ Combine both bytes
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        strh    rR15, [rGSU, #FX_R14]                    @ Store result in R14
        ldr     r2, [rGSU, #FX_pvRomBank]                @ READR14: Load ROM base pointer
        ldrb    rR15, [r2, rR15]                         @ READR14: Load ROM(R14)
        strb    rR15, [rGSU, #FX_vRomBuffer]             @ READR14: Store to ROMBUFFER
        b       dispatch                                 @ 

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
        ldrh    r2, [rGSU, #FX_R15]                      @ Load R15. WYATT_TODO unnecessary
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        add     r2, r2, #1                               @ R15++
        strh    r2, [rGSU, #FX_R15]                      @ Store R15
        strh    rR15, [rDREG]                            @ Store result
        add     rR15, rGSU, #FX_R14                      @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        beq     testr14_clrflags_dispatch                @ TESTR14: branch
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       dispatch                                 @ 

@ GETBH: Overwrite the high byte in SREG with ROMBUFFER, stored in DREG
handle_fx_getbh:
        add     r2, rR15, #1                             @ R15++
        ldrb    rR15, [rSREG]                            @ Load SREG bottom byte
        strh    r2, [rGSU, #FX_R15]                      @ Store R15
        ldrb    r2, [rGSU, #FX_vRomBuffer]               @ Load ROMBUFFER
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        orr     rR15, rR15, r2, lsl #8                   @ Combine both sources
        strh    rR15, [rDREG]                            @ Store result
        add     rR15, rGSU, #FX_R14                      @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        beq     testr14_clrflags_dispatch                @ TESTR14: branch
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       dispatch                                 @ 

@ LM: Load word from RAM and store it in register N. The address is fetched from PIPE.
@ WYATT_TODO validate me.
handle_fx_lm_r:
        lsl     vLow, vLow, #1                           @ Shift vLow for 2-byte offset
        add     r2, rR15, #1                             @ R15 + 1 into scratch register
        uxth    r2, r2                                   @ Wrap R15 at 16 bits
        mov     ip, rPIPE                                @ We need a copy of PIPE. WYATT_TODO could save here since PIPE is fetched again.
        ldrb    rPIPE, [r1, r2]                          @ FETCHPIPE
        add     r2, rR15, #2                             @ R15 + 2 into scratch register
        orr     ip, ip, rPIPE, lsl #8                    @ Combine both bytes of destination
        strh    ip, [rGSU, #FX_vLastRamAdr]              @ Store destination to vLastRamAdr
        uxth    r2, r2                                   @ Wrap R15 at 16 bits
        add     rR15, rR15, #3                           @ R15 + 3
        ldrb    rPIPE, [r1, r2]                          @ FETCHPIPE
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        ldr     rR15, [rGSU, #FX_pvRamBank]              @ Load RAM base pointer
        eor     r2, ip, #1                               @ Flip bottom bit of offset
        ldrb    r2, [rR15, r2]                           @ Load top half of result
        ldrb    ip, [rR15, ip]                           @ Load bottom half of result
        orr     ip, ip, r2, lsl #8                       @ Combine result
        strh    ip, [rGSU, vLow]                         @ Store result
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        b       dispatch                                 @ 

@ LM: Load word from RAM and store it in register N, then READR14. The address is fetched from PIPE.
@ WYATT_TODO validate me.
handle_fx_lm_r14:
        add     r2, rR15, #1                             @ R15 + 1 into scratch register
        uxth    r2, r2                                   @ Wrap R15 at 16 bits
        mov     ip, rPIPE                                @ We need a copy of PIPE. WYATT_TODO could save here since PIPE is fetched again.
        ldrb    rPIPE, [r1, r2]                          @ FETCHPIPE
        add     r2, rR15, #2                             @ R15 + 2 into scratch register
        orr     ip, ip, rPIPE, lsl #8                    @ Combine both bytes of destination
        strh    ip, [rGSU, #FX_vLastRamAdr]              @ Store destination to vLastRamAdr
        uxth    r2, r2                                   @ Wrap R15 at 16 bits
        add     rR15, rR15, #3                           @ R15 + 3
        ldrb    rPIPE, [r1, r2]                          @ FETCHPIPE
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        ldr     rR15, [rGSU, #FX_pvRamBank]              @ Load RAM base pointer
        eor     r2, ip, #1                               @ Flip bottom bit of offset
        ldrb    r2, [rR15, r2]                           @ Load top half of result
        ldrb    ip, [rR15, ip]                           @ Load bottom half of result
        orr     ip, ip, r2, lsl #8                       @ Combine result
        strh    ip, [rGSU, #FX_R14]                      @ Store result
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        ldr     r2, [rGSU, #FX_pvRomBank]                @ READR14: Load ROM base pointer
        ldrb    ip, [r2, ip]                             @ READR14: Load ROM(R14)
        strb    ip, [rGSU, #FX_vRomBuffer]               @ READR14: Store to ROMBUFFER
        b       dispatch                                 @ 

@ ADD_I: Add SREG + 4-bit immediate, store in DREG
handle_fx_add_i:
        ldrh    rARM, [rSREG]                            @ Load SREG
        ldrh    r2, [rGSU, #FX_R15]                      @ Load R15. WYATT_TODO unnecessary
        lsl     rARM, rARM, #16                          @ Shift SREG into top half of register
        add     r2, r2, #1                               @ R15++
        adds    rR15, rARM, vLow, lsl #16                @ Add SREG and immediate, set flags
        mrs     rARM, cpsr                               @ Read flags from CPSR
        lsr     rR15, rR15, #16                          @ Shift result to bottom half of register
        strh    r2, [rGSU, #FX_R15]                      @ Store R15
        strh    rR15, [rDREG]                            @ Store result
        add     rR15, rGSU, #FX_R14                      @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        beq     testr14_clrflags_dispatch                @ TESTR14: branch
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       dispatch                                 @ 

@ SUB_I: Subtract SREG - 4-bit immediate, store in DREG
handle_fx_sub_i:
        ldrh    rARM, [rSREG]                            @ Load SREG
        ldrh    r2, [rGSU, #FX_R15]                      @ Load R15. WYATT_TODO unnecessary
        lsl     rARM, rARM, #16                          @ Shift SREG into top half of register
        add     r2, r2, #1                               @ R15++
        subs    rR15, rARM, vLow, lsl #16                @ Subtract SREG and immediate, set flags
        mrs     rARM, cpsr                               @ Read flags from CPSR
        lsr     rR15, rR15, #16                          @ Shift result to bottom half of register
        strh    r2, [rGSU, #FX_R15]                      @ Store R15
        strh    rR15, [rDREG]                            @ Store result
        add     rR15, rGSU, #FX_R14                      @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        beq     testr14_clrflags_dispatch                @ TESTR14: branch
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       dispatch                                 @ 

@ AND_I: Logically AND SREG and 4-bit immediate, store in DREG
handle_fx_and_i:
        ldrh    r2, [rGSU, #FX_R15]                      @ Load R15. WYATT_TODO unnecessary
        ldrh    rR15, [rSREG]                            @ Load SREG
        add     r2, r2, #1                               @ R15++
        strh    r2, [rGSU, #FX_R15]                      @ Store R15
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        ands    rR15, rR15, vLow                         @ AND SREG and immediate, set flags
        mrs     rARM, cpsr                               @ Read flags from CPSR
        strh    rR15, [rDREG]                            @ Store result
        add     rR15, rGSU, #FX_R14                      @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        beq     testr14_clrflags_dispatch                @ TESTR14: branch
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       dispatch                                 @ 

@ MULT: multiply SREG and 4-bit immediate as signed 8-bit ints, store in DREG
handle_fx_mult_i:
        ldrsb   rR15, [rSREG]                            @ Load SREG as s8
        ldrh    r2, [rGSU, #FX_R15]                      @ Load R15. WYATT_TODO unnecessary
        smulbb  rR15, rR15, vLow                         @ Multiply SREG and immediate
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        movs    rARM, rR15                               @ Set flags
        mrs     rARM, cpsr                               @ Read flags from CPSR
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        add     r2, r2, #1                               @ R15++
        strh    r2, [rGSU, #FX_R15]                      @ Store R15
        strh    rR15, [rDREG]                            @ Store result
        add     rR15, rGSU, #FX_R14                      @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        beq     testr14_clrflags_dispatch                @ TESTR14: branch
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       dispatch                                 @ 

@ SMS: Store register N in RAM (short address). The address is fetched from PIPE.
handle_fx_sms_r:
        add     rR15, rR15, #1                           @ R15++
        lsl     ip, rPIPE, #1                            @ Shift PIPE left 1
        uxth    rR15, rR15                               @ Wrap R15 at 16 bits
        lsl     vLow, vLow, #1                           @ Shift vLow for 2-byte offset
        ldrh    r2, [rGSU, vLow]                         @ Load value from register N
        strh    ip, [rGSU, #FX_vLastRamAdr]              @ Store shifted pipe GSU.vLastRamAdr
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15. WYATT_TODO unnecessary
        ldrb    rPIPE, [r1, rR15]                        @ FETCHPIPE
        ldr     rR15, [rGSU, #FX_pvRamBank]              @ Load RAM base pointer
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        strb    r2, [rR15, ip]                           @ Store bottom byte of result
        ldrh    rR15, [rGSU, #FX_vLastRamAdr]            @ Reload GSU.vLastRamAdr. WYATT_TODO unnecessary
        ldr     r1, [rGSU, #FX_pvRamBank]                @ Reload RAM base pointer. WYATT_TODO unnecessary
        add     rR15, rR15, #1                           @ R15++
        lsr     r2, r2, #8                               @ Prep top byte of result
        uxth    rR15, rR15                               @ Wrap R15 at 16 bits
        strb    r2, [r1, rR15]                           @ Store top byte of result
        ldrh    rR15, [rGSU, #FX_R15]                    @ Reload R15. WYATT_TODO unnecessary
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        add     rR15, rR15, #1                           @ R15++
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        b       dispatch                                 @ 

@ OR_I: Logically OR SREG and 4-bit immediate, store in DREG
handle_fx_or_i:
        ldrh    r2, [rGSU, #FX_R15]                      @ Load R15. WYATT_TODO unnecessary
        ldrh    rR15, [rSREG]                            @ Load SREG
        add     r2, r2, #1                               @ R15++
        strh    r2, [rGSU, #FX_R15]                      @ Store R15
        add     rR15, rR15, rR15, lsl #16                @ Duplicate value into both halves of a register
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        orrs    rR15, rR15, vLow                         @ OR SREG and immediate, set flags
        mrs     rARM, cpsr                               @ Read flags from CPSR
        strh    rR15, [rDREG]                            @ Store result
        add     rR15, rGSU, #FX_R14                      @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        beq     testr14_clrflags_dispatch                @ TESTR14: branch
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       dispatch                                 @ 

@ RAMB: Set current RAM bank to SREG
handle_fx_ramb:
        ldrh    r2, [rSREG]                              @ Load SREG
        add     rR15, rR15, #1                           @ R15++
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        and     rR15, r2, #3                             @ SREG & (FX_RAM_BANKS - 1)
        strb    rR15, [rGSU, #FX_vRamBankReg]            @ Store to GSU.vRamBankReg
        add     rR15, rR15, #FX_apvRamBank >> 2          @ Add apvRamBank table offset, pre-shifted down
        ldr     rR15, [rGSU, rR15, lsl #2]               @ Load pointer at GSU.apvRamBank[GSU.vRamBankReg]
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        str     rR15, [rGSU, #FX_pvRamBank]              @ Store to GSU.pvRamBank
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       dispatch                                 @ 

@ GETBL: Overwrite the low byte in SREG with ROMBUFFER, stored in DREG
handle_fx_getbl:
        add     r2, rR15, #1                             @ R15++
        ldrh    rR15, [rSREG]                            @ Load SREG
        strh    r2, [rGSU, #FX_R15]                      @ Store R15
        ldrb    r2, [rGSU, #FX_vRomBuffer]               @ Load ROMBUFFER
        and     rR15, rR15, #65280                       @ Clear SREG bottom byte
        orr     rR15, rR15, r2                           @ Combine both sources
        strh    rR15, [rDREG]                            @ Store result
        add     rR15, rGSU, #FX_R14                      @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        beq     testr14_clrflags_dispatch                @ TESTR14: branch
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       dispatch                                 @ 

@ SM: Store register N in RAM. The address is fetched from PIPE.
handle_fx_sm_r:
        lsl     vLow, vLow, #1                           @ Shift vLow for 2-byte offset
        ldrh    r2, [rGSU, vLow]                         @ Load register N
        add     vLow, rR15, #1                           @ R15 + 1 into scratch register
        uxth    vLow, vLow                               @ Wrap R15 at 16 bits
        mov     ip, rPIPE                                @ WYATT_TODO fix this. Temporary hack while removing IP from dispatch.
        strh    ip, [rGSU, #FX_vLastRamAdr]              @ Store bottom byte of PIPE at GSU.vLastRamAdr. WYATT_TODO unnecessary
        strh    vLow, [rGSU, #FX_R15]                    @ Store R15. WYATT_TODO unnecessary
        ldrb    rPIPE, [r1, vLow]                        @ FETCHPIPE
        add     rR15, rR15, #2                           @ R15 + 2
        orr     ip, ip, rPIPE, lsl #8                    @ Combine both bytes of destination
        uxth    rR15, rR15                               @ Wrap R15 at 16 bits
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15. WYATT_TODO unnecessary
        strh    ip, [rGSU, #FX_vLastRamAdr]              @ Store PIPE at GSU.vLastRamAdr
        ldrb    rPIPE, [r1, rR15]                        @ FETCHPIPE
        ldr     rR15, [rGSU, #FX_pvRamBank]              @ Load RAM base pointer
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        strb    r2, [rR15, ip]                           @ Store lower byte
        ldrh    rR15, [rGSU, #FX_vLastRamAdr]            @ Reload GSU.vLastRamAdr. WYATT_TODO unnecessary
        ldr     r1, [rGSU, #FX_pvRamBank]                @ Reload RAM base pointer. WYATT_TODO unnecessary
        lsr     r2, r2, #8                               @ Prep upper byte
        eor     rR15, rR15, #1                           @ Flip bottom bit of offset
        strb    r2, [r1, rR15]                           @ Store upper byte
        ldrh    rR15, [rGSU, #FX_R15]                    @ Reload R15. WYATT_TODO unnecessary
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        add     rR15, rR15, #1                           @ R15++
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        b       dispatch                                 @ 

@ ADC_I: add-with-carry, SREG + 4-bit immediate, store in DREG
handle_fx_adc_i:
        ldrh    rR15, [rGSU, #FX_R15]                    @ Load R15. WYATT_TODO unnecessary
        ldrh    r2, [rSREG]                              @ Load SREG
        add     rR15, rR15, #1                           @ R15++
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        lsl     rARM, r2, #16                            @ Shift SREG into the upper half of the register
        orrcs   rARM, rARM, #32768                       @ Move carry flag into SREG
        orrcs   vLow, vLow, #-2147483648                 @ Move carry flag into immediate
        adds    vLow, rARM, vLow, ror #16                @ Add the values and set flags
        mrs     rARM, cpsr                               @ Read flags from CPSR
        lsr     vLow, vLow, #16                          @ Shift result into bottom half of register
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        strh    vLow, [rDREG]                            @ Store result
        add     rR15, rGSU, #FX_R14                      @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        beq     testr14_clrflags_dispatch                @ TESTR14: branch
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       dispatch                                 @ 

@ CMP: Compare SREG to register N. Effectively a subtract with no result.
handle_fx_cmp_r:
        ldrh    rR15, [rSREG]                            @ Load SREG
        lsl     vLow, vLow, #1                           @ Shift vLow for 2-byte offset
        ldrh    rARM, [rGSU, vLow]                       @ Load register N
        lsl     rR15, rR15, #16                          @ Shift SREG into the upper half of the register
        cmp     rR15, rARM, lsl #16                      @ Compare to set flags
        mrs     rARM, cpsr                               @ Read flags from CPSR
        ldrh    rR15, [rGSU, #FX_R15]                    @ Load R15. WYATT_TODO unnecessary
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        add     rR15, rR15, #1                           @ R15++
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        b       dispatch                                 @ 

@ BIC_I: DREG = SREG & ~4-bit immediate
handle_fx_bic_i:
        ldrh    r2, [rGSU, #FX_R15]                      @ Load R15. WYATT_TODO unnecessary
        ldrh    rR15, [rSREG]                            @ Load SREG
        add     r2, r2, #1                               @ R15++
        strh    r2, [rGSU, #FX_R15]                      @ Store R15
        add     vLow, vLow, vLow, lsl #16                @ Duplicate immediate into both halves of a register
        add     rR15, rR15, rR15, lsl #16                @ Duplicate SREG into both halves of a register
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        bics    rR15, rR15, vLow                         @ Bit clear and set flags
        mrs     rARM, cpsr                               @ Read flags from CPSR
        strh    rR15, [rDREG]                            @ Store result
        add     rR15, rGSU, #FX_R14                      @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        beq     testr14_clrflags_dispatch                @ TESTR14: branch
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       dispatch                                 @ 

@ UMULT_I: 8-bit to 16-bit unsigned multiply, SREG * 4-bit immediate, stored in DREG
handle_fx_umult_i:
        ldrb    rR15, [rSREG]                            @ Load SREG
        ldrh    r2, [rGSU, #FX_R15]                      @ Load R15. WYATT_TODO unnecessary
        smulbb  rR15, rR15, vLow                         @ Multiply SREG * immediate
        msr     cpsr_f, rARM                             @ Move flags into CPSR
        movs    rARM, rR15                               @ Set flags
        mrs     rARM, cpsr                               @ Read flags from CPSR
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        add     r2, r2, #1                               @ R15++
        strh    r2, [rGSU, #FX_R15]                      @ Store R15
        strh    rR15, [rDREG]                            @ Store result
        add     rR15, rGSU, #FX_R14                      @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        beq     testr14_clrflags_dispatch                @ TESTR14: branch
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       dispatch                                 @ 

@ XOR_I: exclusive OR between SREG and 4-bit immediate, stored in DREG
handle_fx_xor_i:
        ldrh    r2, [rGSU, #FX_R15]                      @ Load R15. WYATT_TODO unnecessary
        ldrh    rR15, [rSREG]                            @ Load SREG
        add     r2, r2, #1                               @ R15++
        strh    r2, [rGSU, #FX_R15]                      @ Store R15
        add     vLow, vLow, vLow, lsl #16                @ Duplicate immediate into both halves of a register
        add     rR15, rR15, rR15, lsl #16                @ Duplicate SREG into both halves of a register
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        eors    rR15, rR15, vLow                         @ XOR and set flags
        mrs     rARM, cpsr                               @ Read flags from CPSR
        strh    rR15, [rDREG]                            @ Store result
        add     rR15, rGSU, #FX_R14                      @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        beq     testr14_clrflags_dispatch                @ TESTR14: branch
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       dispatch                                 @ 

@ ROMB: set program bank to SREG
handle_fx_romb:
        ldrh    r2, [rSREG]                              @ Load SREG
        add     rR15, rR15, #1                           @ R15++
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        and     rR15, r2, #127                           @ Clear top bit of SREG
        strb    rR15, [rGSU, #FX_vRomBankReg]            @ Store SREG to GSU.vRomBankReg
        add     rR15, rR15, #FX_apvRomBank >> 2          @ Offset magic for apvRomBank, pre-shifted down
        ldr     rR15, [rGSU, rR15, lsl #2]               @ Load pointer at GSU.apvRomBank[GSU.vPrgBankReg]
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        str     rR15, [rGSU, #FX_pvRomBank]              @ Store to GSU.pvRomBank
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       dispatch                                 @ 

testr14_clrflags_dispatch:
        ldrh    vLow, [rGSU, #FX_R14]                    @ TESTR14
        ldr     r2, [rGSU, #FX_pvRomBank]                @  |
        mov     rSREG, rGSU                              @ CLRFLAGS: SREG = 0
        mov     rDREG, rGSU                              @ CLRFLAGS: DREG = 0
        ldr     r1, [rGSU, #FX_pvPrgBank]                @ FETCHPIPE: Load GSU.pvPrgBank. Taken from dispatch
        ldrb    vLow, [r2, vLow]                         @  |
        ldrh    rR15, [rGSU, #FX_R15]                    @ FETCHPIPE: Load R15. Taken from dispatch
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        strb    vLow, [rGSU, #FX_vRomBuffer]             @  |
        b       dispatch.skip_2                          @ 

@ FROM: If B is not set, set SREG to register N and increment R15
handle_fx_from_r.b_is_not_set:
        add     rR15, rR15, #1                           @ R15++. WYATT_TODO this should be moved to the common handler
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        add     rSREG, rGSU, vLow, lsl #1                @ SREG = register N
        b       dispatch_flags                           @ 

@ If (X ^ Y) is odd, use top half of color. Else, use bottom half.
@ Inlining this or not is a bit of a tossup
@ R1 is X, IP is Y, vLow is vPlotOptionReg, R2 is COLOR
handle_fx_plot_2bit.L237:
        eor     rR15, r1, ip                             @ X ^ Y
        tst     rR15, #1                                 @ Test if odd
        lsrne   r2, r2, #4                               @ Odd X uses top nibble of color
        b       .L15                                     @ 

@ EQ is zero, NE is nonzero
@ Test transparency
@ R1 is X, IP is Y, vLow is vPlotOptionReg, R2 is COLOR
handle_fx_plot_8bit.L239:
        tst     vLow, #8                                 @ Test PLOT_FREEZEHIGH
        mov     vLow, r2                                 @ We need to preserve COLOR, so use vLow
        andne   vLow, vLow, #15                          @ If PLOT_FREEZEHIGH, only test the bottom nibble
        tst     vLow, #255                               @ If COLOR == 0, return. Else, continue drawing
        bne     .L40                                     @  |
        b       handle_fx_plot_8bit.return               @  |

@ If (X ^ Y) is odd, use top half of color. Else, use bottom half.
@ Inlining this or not is a bit of a tossup
@ R1 is X, IP is Y, vLow is vPlotOptionReg, R2 is COLOR
handle_fx_plot_4bit.L238:
        eor     rR15, r1, ip                             @ X ^ Y
        tst     rR15, #1                                 @ Test if odd
        lsrne   r2, r2, #4                               @ Odd X uses top nibble of color
        b       .L25                                     @ 
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
        #include "fxinst_asm_opcode_table.h"
