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
@ - Optimize TESTR14. See below
@ - Fix doubled loads and stores caused by aliasing
@ - Fix regalloc occasionally reloading R15
@     If CLRFLAGS is called, we can use rSREG as scratch to save a reg
@ - Put the GSU struct in its own over-aligned segment. This would allow us to do certain comparisons, notably the one in TESTR14, in one fewer instruction.
@ - Look into the possibility of avoiding the UXTH instructions in IBT/IWT. Shift to top of reg and load with register lsr 16?
@ - Store some constants in the stack or GSU struct to make reloading them faster? For instance, R0 pointers for SREG and DREG. Cycle timings might work out. Ensure 64-bit alignment and single-cycle issues if so.
@ - Once R15 reloads have been fixed, remove R15 saves from handlers that are guaranteed not to use R15 via SREG/DREG. Also add an R15 store in loop_end. Don't forget to truncate to 16-bit!
@     Maybe add alternate opcode tables for versions with R15 DREG/SREG to further save?
@ - Optimize regalloc to minimize reloads of R1 and rR15
@ - If all handlers were the same size, we could possibly save a load in dispatch.

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
loop_head_flags:
        ldr     r1, [rGSU, #FX_pvPrgBank]                @ FETCHPIPE: Load GSU.pvPrgBank. Taken from loop_dispatch to save a cycle.
loop_head_flags.skip_1:
        ldrh    rR15, [rGSU, #FX_R15]                    @ FETCHPIPE: Load R15. Taken from loop_dispatch to reduce memory stalling
loop_dispatch_flags:
        and     r2, rSTAT, #768                          @ Get opcode mode bits
        orr     r2, rPIPE, r2                            @ Compute opcode
        subs    rVCNT, rVCNT, #1                         @ Decrement vCounter and exit if 0
        ldr     ip, [rGOTO, r2, lsl #2]                  @ Load destination handler
        beq     loop_end                                 @ 
        and     vLow, rPIPE, #15                         @ Compute vLow
        ldrb    rPIPE, [r1, rR15]                        @ FETCHPIPE
        bx      ip                                       @ Branch to handler

@ Dispatch for after instructions that run CLRFLAGS
loop_head:
        ldr     r1, [rGSU, #FX_pvPrgBank]                @ FETCHPIPE: Load GSU.pvPrgBank. Taken from loop_dispatch to save a cycle.
loop_head.skip_1:
        ldrh    rR15, [rGSU, #FX_R15]                    @ FETCHPIPE: Load R15. Taken from loop_dispatch to reduce memory stalling
loop_dispatch:
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
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = R0
        strh    rR15, [rDREG]                            @ Store value to DREG
        add     rR15, rGSU, #FX_R14                      @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        ldrheq  rR15, [rGSU, #FX_R14]                    @  |
        ldreq   r2, [rGSU, #FX_pvRomBank]                @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: clear STAT
        ldrbeq  rR15, [r2, rR15]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = R0
        strbeq  rR15, [rGSU, #FX_vRomBuffer]             @  |
        b       loop_head

@ STOP: stop GSU execution
handle_fx_stop:
        add     rR15, rR15, #1                           @ R15++
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        mov     rR15, #0                                 @ plotOptionReg = 0
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        ldr     r2, [rGSU, #FX_pvRegisters]              @ R2 = GSU.pvRegisters[GSU_CFGR]
        bic     rSTAT, rSTAT, #32                        @ CF(G)
        ldrsb   r2, [r2, #55]                            @ R2 = GSU_CFGR
        mov     rPIPE, #1                                @ PIPE = 1
        cmp     r2, #0                                   @ If GSU_CFGR == 0, Raise IRQ
        orrge   rSTAT, rSTAT, #32768                     @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
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
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        add     r2, r1, #1                               @ X++
        strh    r2, [rGSU, #FX_R1]                       @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0. Prevents stall from next branch getting folded
        bcs     handle_fx_plot_2bit.return               @ If Y > screen height, return
        ldrb    vLow, [rGSU, #FX_vPlotOptionReg]          @ Load vPlotOptionReg
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
        ldr     r1, [rGSU, #FX_pvPrgBank]                @ Taken from loop_head to allow this return handler to branch fold
        b       loop_head.skip_1                         @ 

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
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        add     r2, r1, #1                               @ X++
        strh    r2, [rGSU, #FX_R1]                       @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0. Prevents stall from next branch getting folded
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
        ldr     r1, [rGSU, #FX_pvPrgBank]                @ Taken from loop_head to allow this return handler to branch fold
        b       loop_head.skip_1                         @ 

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
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0.
        add     r2, r1, #1                               @ X++
        strh    r2, [rGSU, #FX_R1]                       @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0. Prevents stall from next branch getting folded
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
        ldr     r1, [rGSU, #FX_pvPrgBank]    @           @ Taken from loop_head to allow this return handler to branch fold
        b       loop_head.skip_1             @           @ 

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
        ldrheq  rR15, [rGSU, #FX_R14]                    @  |
        ldreq   r2, [rGSU, #FX_pvRomBank]                @  |
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strbeq  rR15, [rGSU, #FX_vRomBuffer]             @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       loop_head                                @ 

@ NOP: Clears flags and advances R15 
handle_fx_nop:
        add     rR15, rR15, #1                           @ R15++
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       loop_head                                @ 

@ CACHE: reintialize GSU cache
handle_fx_cache:
        ldrh    r1, [rGSU, #FX_vCacheBaseReg]            @ r1 = GSU.vCacheBaseReg
        bic     r2, rR15, #15                            @ r2 = R15 & 0xfff0
        cmp     r1, r2                                   @ If address range is not equal, cache needs a reload
        beq     .cache_test_active                       @ If address range is equal, check if cache is active
@ Reload cache
.reload_cache:
        strh    r2, [rGSU, #FX_vCacheBaseReg]            @ GSU.vCacheBaseReg = R15 & 0xfff0
        mov     r2, #0                                   @ 
        str     r2, [rGSU, #FX_vCacheFlags]              @ GSU.vCacheFlags = 0
        mov     r2, #1                                   @ 
        strb    r2, [rGSU, #FX_bCacheActive]             @ GSU.bCacheActive = TRUE
.skip_cache_reload:
        add     rR15, rR15, #1                           @ R15++
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       loop_head                                @ 

@ LSR: logical shift right
handle_fx_lsr:
        ldrh    r2, [rGSU, #FX_R15]                      @ Load R15 into R2 WYATT_TODO this is inefficient! Does inline ASM break regalloc?
        ldrh    rR15, [rSREG]                            @ Load SREG
        add     r2, r2, #1                               @ R15++
        strh    r2, [rGSU, #FX_R15]                      @ Store R15
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        lsrs    rR15, rR15, #1                           @ Do the rightshift
        mrs     rARM, cpsr                               @ Read flags from CPSR
        strh    rR15, [rDREG]                            @ Store result into DREG
        add     rR15, rGSU, #FX_R14                      @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        ldrheq  rR15, [rGSU, #FX_R14]                    @  |
        ldreq   r2, [rGSU, #FX_pvRomBank]                @  |
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strbeq  rR15, [rGSU, #FX_vRomBuffer]             @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       loop_head                                @ 

@ ROL: rotate left
handle_fx_rol:
        ldrh    r2, [rGSU, #FX_R15]                      @ Load R15 into R2 WYATT_TODO this is inefficient! Does inline ASM break regalloc?
        ldrh    rR15, [rSREG]                            @ Load SREG
        add     r2, r2, #1                               @ R15++
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        lsl     rR15, rR15, #16                          @ Shift value into upper half of reg
        orrcs   rR15, rR15, #32768                       @ If carry is set, set bit 15
        lsls    rR15, rR15, #1                           @ Shift left 1 to set carry
        mrs     rARM, cpsr                               @ Read flags from CPSR
        lsr     rR15, rR15, #16                          @ Shift down from top half of register
        strh    r2, [rGSU, #FX_R15]                      @ Store R15
        strh    rR15, [rDREG]                            @ Store result
        add     rR15, rGSU, #FX_R14                      @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        ldrheq  rR15, [rGSU, #FX_R14]                    @  |
        ldreq   r2, [rGSU, #FX_pvRomBank]                @  |
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strbeq  rR15, [rGSU, #FX_vRomBuffer]             @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       loop_head                                @ 

@ BRA: unconditional branch
handle_fx_bra:
        add     rR15, rR15, #1                           @ R15++
        uxth    rR15, rR15                               @ Wrap R15 at 16 bits
        sxtb    r2, rPIPE                                @ Sign-extend PIPE
        add     r2, rR15, r2                             @ Add PIPE to R15
        ldrb    rPIPE, [r1, rR15]                        @ FETCHPIPE
        strh    r2, [rGSU, #FX_R15]                      @ Store destination to R15
        b       loop_head_flags                          @ 

@ BGE: branch if greater or equal
handle_fx_bge:
        add     rR15, rR15, #1                           @ R15++
        uxth    r2, rR15                                 @ Wrap R15 at 16 bits
        sxtb    ip, rPIPE                                @ Sign-extend PIPE
        ldrb    rPIPE, [r1, r2]                          @ FETCHPIPE
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        addge   rR15, rR15, ip                           @ Handle branch
        addlt   rR15, rR15, #1                           @ 
        strh    rR15, [rGSU, #FX_R15]                    @ Store destination to R15
        b       loop_head_flags                          @ 

@ BLT: branch if less than
handle_fx_blt:
        add     rR15, rR15, #1                           @ R15++
        uxth    r2, rR15                                 @ Wrap R15 at 16 bits
        sxtb    ip, rPIPE                                @ Sign-extend PIPE
        ldrb    rPIPE, [r1, r2]                          @ FETCHPIPE
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        addlt   rR15, rR15, ip                           @ Handle branch
        addge   rR15, rR15, #1                           @ 
        strh    rR15, [rGSU, #FX_R15]                    @ Store destination to R15
        b       loop_head_flags                          @ 

@ BNE: branch if not equal
handle_fx_bne:
        add     rR15, rR15, #1                           @ R15++
        uxth    r2, rR15                                 @ Wrap R15 at 16 bits
        sxtb    ip, rPIPE                                @ Sign-extend PIPE
        ldrb    rPIPE, [r1, r2]                          @ FETCHPIPE
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        addne   rR15, rR15, ip                           @ Handle branch
        addeq   rR15, rR15, #1                           @ 
        strh    rR15, [rGSU, #FX_R15]                    @ Store destination to R15
        b       loop_head_flags                          @ 

@ BEQ: branch if equal
handle_fx_beq:
        add     rR15, rR15, #1                           @ R15++
        uxth    r2, rR15                                 @ Wrap R15 at 16 bits
        sxtb    ip, rPIPE                                @ Sign-extend PIPE
        ldrb    rPIPE, [r1, r2]                          @ FETCHPIPE
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        addeq   rR15, rR15, ip                           @ Handle branch
        addne   rR15, rR15, #1                           @ 
        strh    rR15, [rGSU, #FX_R15]                    @ Store destination to R15
        b       loop_head_flags                          @ 

@ BPL: branch if positive or zero
handle_fx_bpl:
        add     rR15, rR15, #1                           @ R15++
        uxth    r2, rR15                                 @ Wrap R15 at 16 bits
        sxtb    ip, rPIPE                                @ Sign-extend PIPE
        ldrb    rPIPE, [r1, r2]                          @ FETCHPIPE
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        addpl   rR15, rR15, ip                           @ Handle branch
        addmi   rR15, rR15, #1                           @ 
        strh    rR15, [rGSU, #FX_R15]                    @ Store destination to R15
        b       loop_head_flags                          @ 

@ BMI: branch if negative
handle_fx_bmi:
        add     rR15, rR15, #1                           @ R15++
        uxth    r2, rR15                                 @ Wrap R15 at 16 bits
        sxtb    ip, rPIPE                                @ Sign-extend PIPE
        ldrb    rPIPE, [r1, r2]                          @ FETCHPIPE
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        addmi   rR15, rR15, ip                           @ Handle branch
        addpl   rR15, rR15, #1                           @ 
        strh    rR15, [rGSU, #FX_R15]                    @ Store destination to R15
        b       loop_head_flags                          @ 

@ BCC: branch if lower (unsigned <)
handle_fx_bcc:
        add     rR15, rR15, #1                           @ R15++
        uxth    r2, rR15                                 @ Wrap R15 at 16 bits
        sxtb    ip, rPIPE                                @ Sign-extend PIPE
        ldrb    rPIPE, [r1, r2]                          @ FETCHPIPE
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        addcc   rR15, rR15, ip                           @ Handle branch
        addcs   rR15, rR15, #1                           @ 
        strh    rR15, [rGSU, #FX_R15]                    @ Store destination to R15
        b       loop_head_flags                          @ 

@ BCS: branch if higher or same (unsigned >=)
handle_fx_bcs:
        add     rR15, rR15, #1                           @ R15++
        uxth    r2, rR15                                 @ Wrap R15 at 16 bits
        sxtb    ip, rPIPE                                @ Sign-extend PIPE
        ldrb    rPIPE, [r1, r2]                          @ FETCHPIPE
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        addcs   rR15, rR15, ip                           @ Handle branch
        addcc   rR15, rR15, #1                           @ 
        strh    rR15, [rGSU, #FX_R15]                    @ Store destination to R15
        b       loop_head_flags                          @ 

@ BVC: branch if no overflow
handle_fx_bvc:
        add     rR15, rR15, #1                           @ R15++
        uxth    r2, rR15                                 @ Wrap R15 at 16 bits
        sxtb    ip, rPIPE                                @ Sign-extend PIPE
        ldrb    rPIPE, [r1, r2]                          @ FETCHPIPE
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        addvc   rR15, rR15, ip                           @ Handle branch
        addvs   rR15, rR15, #1                           @ 
        strh    rR15, [rGSU, #FX_R15]                    @ Store destination to R15
        b       loop_head_flags                          @ 

@ BVS: branch if overflow
handle_fx_bvs:
        add     rR15, rR15, #1                           @ R15++
        uxth    r2, rR15                                 @ Wrap R15 at 16 bits
        sxtb    ip, rPIPE                                @ Sign-extend PIPE
        ldrb    rPIPE, [r1, r2]                          @ FETCHPIPE
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        addvs   rR15, rR15, ip                           @ Handle branch
        addvc   rR15, rR15, #1                           @ 
        strh    rR15, [rGSU, #FX_R15]                    @ Store destination to R15
        b       loop_head_flags                          @ 

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
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strh    r2, [rGSU, vLow]                         @ Register N = SREG
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       loop_head
handle_fx_to_r.b_is_not_set:
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15. vLow cannot be 15, so early store is valid
        add     rDREG, rGSU, vLow, lsl #1                @ DREG = vLow
        b       loop_head_flags                          @ 


@ TO_R14: set register 14 as destination register
@ If B flag is set, move SREG to R14, CLRFLAGS, and READR14 instead
handle_fx_to_r14:
        tst     rSTAT, #4096                             @ Test B
        add     rR15, rR15, #1                           @ R15++
        bne     handle_fx_to_r14.b_is_set                @ If B is set, branch
@ B is not set
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        add     rDREG, rGSU, #FX_R14                     @ DREG = pointer to R14
        b       loop_head_flags                          @ 
handle_fx_to_r14.b_is_set:
        ldrh    r2, [rSREG]                              @ Load SREG
        ldr     r1, [rGSU, #FX_pvRomBank]                @ READR14: Load GSU.pvRomBank
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        strh    r2, [rGSU, #FX_R14]                      @ R14 = SREG
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        ldrb    vLow, [r1, r2]                           @ READR14: Load GSU.pvRomBank[R14]
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        strb    vLow, [rGSU, #FX_vRomBuffer]             @ READR14: Store ROMBUFFER
        b       loop_head                                @ Branch back to main handler

@ TO_R15: Set DREG to R15 and increment R15
@ If B flag is set, move SREG to R15 instead
handle_fx_to_r15:
        tst     rSTAT, #4096                             @ Test B
        beq     handle_fx_to_r15.b_is_not_set            @ If B is not set, branch
@ B is set
        ldrh    rR15, [rSREG]                            @ Load SREG into rR15
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        strh    rR15, [rGSU, #FX_R15]                    @ R15 = SREG
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        b       loop_head                                @ 
handle_fx_to_r15.b_is_not_set:
        add     rR15, rR15, #1                           @ R15++
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        add     rDREG, rGSU, #FX_R15                     @ DREG = pointer to R15
        b       loop_head_flags                          @ 

@ WITH: set register n as source and destination register
handle_fx_with_r:
        add     rDREG, rGSU, vLow, lsl #1                @ Calculate register
        add     rR15, rR15, #1                           @ R15++
        mov     rSREG, rDREG                             @ Copy register to SREG
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        orr     rSTAT, rSTAT, #4096                      @ Set flag B
        b       loop_head_flags                          @ 

@ STW: store word (16 bits)
handle_fx_stw_r:
        lsl     vLow, vLow, #1                           @ Double vLow for 16-bit offset
        ldrh    rR15, [rGSU, vLow]                       @ Load offset into rR15. WYATT_TODO can probably just load into vLow.
        ldr     r1, [rGSU, #FX_pvRamBank]                @ Load RAM base pointer
        strh    rR15, [rGSU, #FX_vLastRamAdr]            @ Store offset to GSU.vLastRamAdr
        ldrh    r2, [rSREG]                              @ Load source data
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        strb    r2, [r1, rR15]                           @ Store bottom byte
        eor     rR15, rR15, #1                           @ Flip bottom bit of offset
        lsr     r2, r2, #8                               @ Prep top byte
        strb    r2, [r1, rR15]                           @ Store top byte
        ldrh    rR15, [rGSU, #FX_R15]                    @ Load R15. WYATT_TODO unnecessary.
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        add     rR15, rR15, #1                           @ R15++
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        b       loop_head                                @ 

@ LOOP: decrement loop counter R12 and branch to R13 on not zero
handle_fx_loop:
        ldrh    rR15, [rGSU, #FX_R12]                    @ Load counter
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        sub     rR15, rR15, #1                           @ Decrement counter
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        lsl     rARM, rR15, #16                          @ Shift counter to top half of register and test flags
        movs    rARM, rARM                               @ 
        mrs     rARM, cpsr                               @ Read flags from CPSR
        cmp     rR15, #0                                 @ Test counter
        strh    rR15, [rGSU, #FX_R12]                    @ Store counter
        ldrheq  rR15, [rGSU, #FX_R15]                    @ If counter is 0, load R15. WYATT_TODO can probably use move instead of load
        ldrhne  rR15, [rGSU, #FX_R13]                    @ If counter is nonzero, load R13
        addeq   rR15, rR15, #1                           @ If counter is 0, increment R15
        uxtheq  rR15, rR15                               @ Wrap R15 at 16 bits. WYATT_TODO unnecessary
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       loop_head                                @ 

@ ALT1: set ALT mode 1
handle_fx_alt1:
        add     rR15, rR15, #1                           @ R15++
        bic     rSTAT, rSTAT, #4096                      @ Clear B flag
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        orr     rSTAT, rSTAT, #256                       @ Set ALT1 flag
        b       loop_head_flags                          @ 

@ ALT2: set ALT mode 2
handle_fx_alt2:
        add     rR15, rR15, #1                           @ R15++
        bic     rSTAT, rSTAT, #4096                      @ Clear B flag
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        orr     rSTAT, rSTAT, #512                       @ Set ALT2 flag
        b       loop_head_flags                          @ 
        
@ ALT3: set ALT mode 3
handle_fx_alt3:
        add     rR15, rR15, #1                           @ R15++
        bic     rSTAT, rSTAT, #4096                      @ Clear B flag
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        orr     rSTAT, rSTAT, #768                       @ Set ALT1 + ALT2 flags
        b       loop_head_flags                          @ 

@ LDW: load word
handle_fx_ldw_r:
        lsl     vLow, vLow, #1                           @ Double vLow for 16-bit offset
        ldrh    r2, [rGSU, vLow]                         @ Load offset into r2. WYATT_TODO can probably just load into vLow. 
        ldr     r1, [rGSU, #FX_pvRamBank]                @ Load RAM base pointer
        strh    r2, [rGSU, #FX_vLastRamAdr]              @ Store offset to GSU.vLastRamAdr
        eor     ip, r2, #1                               @ Flip bottom bit of offset, stored in a separate register
        add     vLow, rR15, #1                           @ R15++
        ldrb    rR15, [r1, r2]                           @ Load bottom byte
        ldrb    r2, [r1, ip]                             @ Load top byte
        strh    vLow, [rGSU, #FX_R15]                    @ Store R15
        orr     rR15, rR15, r2, lsl #8                   @ Combine bytes into word
        strh    rR15, [rDREG]                            @ Store word into DREG
        add     rR15, rGSU, #FX_R14                      @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        ldrheq  rR15, [rGSU, #FX_R14]                    @  |
        ldreq   r2, [rGSU, #FX_pvRomBank]                @  |
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strbeq  rR15, [rGSU, #FX_vRomBuffer]             @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       loop_head                                @ 

@ SWAP: swap low and high bytes of SREG, store in DREG
handle_fx_swap:
        add     r2, rR15, #1                             @ R15++
        ldrh    rR15, [rSREG]                            @ Load value from SREG
        strh    r2, [rGSU, #FX_R15]                      @ Store R15
        rev16   rR15, rR15                               @ Byteswap value
        add     r2, rGSU, #FX_R14                        @ TESTR14: Pointer to R14
        strh    rR15, [rDREG]                            @ Store value into DREG
        orr     r1, rR15, rR15, lsl #16                  @ Duplicate value into both halves of a register for flags. WYATT_TODO could technically just shift here.
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        movs    rARM, r1                                 @ Set flags
        mrs     rARM, cpsr                               @ Read flags from CPSR
        cmp     rDREG, r2                                @ TESTR14: If DREG == 14, load rombuffer
        ldrheq  rR15, [rGSU, #FX_R14]                    @  |
        ldreq   r2, [rGSU, #FX_pvRomBank]                @  |
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strbeq  rR15, [rGSU, #FX_vRomBuffer]             @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       loop_head                                @ 

@ COLOR: copy SREG to color register
handle_fx_color:
        ldrb    r1, [rGSU, #FX_vPlotOptionReg]           @ Load plotOptionReg
        ldrb    r2, [rSREG]                              @ Load color from SREG
        tst     r1, #4                                   @ If PLOT_HIGHNIBBLE, duplicate the high nibble of color to the low nibble
        andne   vLow, r2, #240                           @  |
        orrne   r2, vLow, r2, lsr #4                     @  V
        tst     r1, #8                                   @ If PLOT_FREEZEHIGH, only update the bottom nibble
        ldrbne  r1, [rGSU, #FX_vColorReg]                @  |
        andne   r2, r2, #15                              @  |
        bicne   r1, r1, #15                              @  |
        orrne   r2, r1, r2                               @  V
        add     rR15, rR15, #1                           @ R15++
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        strb    r2, [rGSU, #FX_vColorReg]                @ Store result to GSU.vColorReg
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       loop_head                                @ 

@ NOT: bitwise NOT of SREG, store in DREG
handle_fx_not:
        ldrh    r2, [rGSU, #FX_R15]                      @ Load R15. WYATT_TODO unnecessary
        ldrh    rR15, [rSREG]                            @ Load value from SREG
        add     r2, r2, #1                               @ R15++
        strh    r2, [rGSU, #FX_R15]                      @ Store R15
        add     rR15, rR15, rR15, lsl #16                @ Duplicate value into both halves of a register
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        mvns    rR15, rR15                               @ Negate value and set flags
        mrs     rARM, cpsr                               @ Read flags from CPSR
        strh    rR15, [rDREG]                            @ Store value
        add     rR15, rGSU, #FX_R14                      @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        ldrheq  rR15, [rGSU, #FX_R14]                    @  |
        ldreq   r2, [rGSU, #FX_pvRomBank]                @  |
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strbeq  rR15, [rGSU, #FX_vRomBuffer]             @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       loop_head                                @ 

@ ADD: SREG + register n, store in DREG
handle_fx_add_r:
        ldrh    rR15, [rSREG]                            @ Load value 1 from SREG
        ldrh    r2, [rGSU, #FX_R15]                      @ Load R15. WYATT_TODO unnecessary
        lsl     vLow, vLow, #1                           @ Shift vLow for 2-byte offset
        ldrh    rARM, [rGSU, vLow]                       @ Load value 2 from register N
        add     r2, r2, #1                               @ R15++
        lsl     rR15, rR15, #16                          @ Duplicate value 1 into both halves of a register
        adds    rR15, rR15, rARM, lsl #16                @ Add both values. Overwrites all flags.
        mrs     rARM, cpsr                               @ Read flags from CPSR
        lsr     rR15, rR15, #16                          @ Shift result down from top half of register
        strh    r2, [rGSU, #FX_R15]                      @ Store R15
        strh    rR15, [rDREG]                            @ Store result to DREG
        add     rR15, rGSU, #FX_R14                      @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        ldrheq  rR15, [rGSU, #FX_R14]                    @  |
        ldreq   r2, [rGSU, #FX_pvRomBank]                @  |
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strbeq  rR15, [rGSU, #FX_vRomBuffer]             @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       loop_head                                @ 

@ SUB: SREG - register n, store in DREG
handle_fx_sub_r:
        ldrh    rR15, [rSREG]                            @ Load value 1 from SREG
        ldrh    r2, [rGSU, #FX_R15]                      @ Load R15. WYATT_TODO unnecessary
        lsl     vLow, vLow, #1                           @ Shift vLow for 2-byte offset
        ldrh    rARM, [rGSU, vLow]                       @ Load value 2 from register N
        add     r2, r2, #1                               @ R15++
        lsl     rR15, rR15, #16                          @ Duplicate value 1 into both halves of a register
        subs    rR15, rR15, rARM, lsl #16                @ Subtract value 2 from value 1. Overwrites all flags.
        mrs     rARM, cpsr                               @ Read flags from CPSR
        lsr     rR15, rR15, #16                          @ Shift result down from top half of register
        strh    r2, [rGSU, #FX_R15]                      @ Store R15
        strh    rR15, [rDREG]                            @ Store result to DREG
        add     rR15, rGSU, #FX_R14                      @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        ldrheq  rR15, [rGSU, #FX_R14]                    @  |
        ldreq   r2, [rGSU, #FX_pvRomBank]                @  |
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strbeq  rR15, [rGSU, #FX_vRomBuffer]             @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       loop_head                                @ 

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
        ldrheq  rR15, [rGSU, #FX_R14]                    @  |
        ldreq   r2, [rGSU, #FX_pvRomBank]                @  |
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        lsl     rARM, rARM, #28                          @ Shift resultant flags into position. WYATT_TODO could use u32s, but would be more DCACHE.
        strbeq  rR15, [rGSU, #FX_vRomBuffer]             @  |
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
        ldrh    r2, [rGSU, #FX_R15]                      @ Load R15. WYATT_TODO unnecessary
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        add     r2, r2, #1                               @ R15++
        strh    r2, [rGSU, #FX_R15]                      @ Store R15
        strh    rR15, [rDREG]                            @ Store result
        add     rR15, rGSU, #FX_R14                      @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        ldrheq  rR15, [rGSU, #FX_R14]                    @  |
        ldreq   r2, [rGSU, #FX_pvRomBank]                @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        strbeq  rR15, [rGSU, #FX_vRomBuffer]             @  |
        b       loop_head                                @ 

@ MULT: multiply SREG and register n as signed 8-bit ints, store in DREG
handle_fx_mult_r:
        lsl     vLow, vLow, #1                           @ Shift vLow for 2-byte offset
        ldrsb   rR15, [rSREG]                            @ Load s8 value 1 from SREG
        ldrsb   r2, [rGSU, vLow]                         @ Load s8 value 2 from register N. WYATT_TODO could this use an 8-bit load?
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
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
        ldrheq  rR15, [rGSU, #FX_R14]                    @  |
        ldreq   r2, [rGSU, #FX_pvRomBank]                @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        strbeq  rR15, [rGSU, #FX_vRomBuffer]             @  |
        b       loop_head                                @ 

@ SBK: store word to last accessed RAM address
handle_fx_sbk:
        ldrh    rR15, [rSREG]                            @ Load value from SREG
        ldrh    r2, [rGSU, #FX_vLastRamAdr]              @ Load vLastRamAdr
        ldr     r1, [rGSU, #FX_pvRamBank]                @ Load RAM base pointer
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        strb    rR15, [r1, r2]                           @ Store bottom byte
        ldrh    r2, [rGSU, #FX_vLastRamAdr]              @ Reload vLastRamAdr WYATT_TODO unnecessary
        ldr     r1, [rGSU, #FX_pvRamBank]                @ Reload RAM base pointer. WYATT_TODO unnecessary
        lsr     rR15, rR15, #8                           @ Prep top byte
        eor     r2, r2, #1                               @ Flip bottom bit of offset
        strb    rR15, [r1, r2]                           @ Store bottom byte
        ldrh    rR15, [rGSU, #FX_R15]                    @ Load R15 WYATT_TODO unnecessary
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        add     rR15, rR15, #1                           @ R15++
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        b       loop_head                                @ 

@ LINK: R11 = R15 + immediate
handle_fx_link_i:
        add     vLow, vLow, rR15                         @ Add R15 and immediate
        add     rR15, rR15, #1                           @ R15++
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        strh    vLow, [rGSU, #FX_R11]                    @ Store R11
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       loop_head                                @ 

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
        ldrheq  rR15, [rGSU, #FX_R14]                    @  |
        ldreq   r2, [rGSU, #FX_pvRomBank]                @  |
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strbeq  rR15, [rGSU, #FX_vRomBuffer]             @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       loop_head                                @ 

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
        ldrheq  rR15, [rGSU, #FX_R14]                    @  |
        ldreq   r2, [rGSU, #FX_pvRomBank]                @  |
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strbeq  rR15, [rGSU, #FX_vRomBuffer]             @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       loop_head                                @ 

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
        ldrheq  rR15, [rGSU, #FX_R14]                    @  |
        ldreq   r2, [rGSU, #FX_pvRomBank]                @  |
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strbeq  rR15, [rGSU, #FX_vRomBuffer]             @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       loop_head                                @ 

@ JMP: jump to address of register N. No delay slot.
handle_fx_jmp_r:
        lsl     vLow, vLow, #1                           @ Shift vLow for 2-byte offset
        ldrh    rR15, [rGSU, vLow]                       @ Load destination from register N
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        strh    rR15, [rGSU, #FX_R15]                    @ Store destination to R15
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       loop_head                                @ 

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
        ldrheq  rR15, [rGSU, #FX_R14]                    @  |
        ldreq   r2, [rGSU, #FX_pvRomBank]                @  |
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strbeq  rR15, [rGSU, #FX_vRomBuffer]             @  |
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
        ldrh    r2, [rGSU, #FX_R6]                       @ Load value 2 from R6
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
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
        ldrheq  rR15, [rGSU, #FX_R14]                    @  |
        ldreq   r2, [rGSU, #FX_pvRomBank]                @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        strbeq  rR15, [rGSU, #FX_vRomBuffer]             @  |
        b       loop_head                                @ 

@ IBT: fetch PIPE and store to register N
handle_fx_ibt_r:
        add     r2, rR15, #1                             @ R15 + 1 into scratch register
        uxth    r2, r2                                   @ Wrap scratch R15 at 16 bits
        strh    r2, [rGSU, #FX_R15]                      @ Store R15. WYATT_TODO unnecessary. Aliasing?
        lsl     vLow, vLow, #1                           @ Shift vLow for 2-byte offset
        sxtb    ip, rPIPE                                @ Sign-extend PIPE
        add     rR15, rR15, #2                           @ R15 + 2
        ldrb    rPIPE, [r1, r2]                          @ FETCHPIPE. We don't immediately use this value! This can be optimized.
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        strh    ip, [rGSU, vLow]                         @ Store result
        b       loop_head                                @ 

@ IBT R14: fetch PIPE and store to register N, then READR14
handle_fx_ibt_r14:
        add     r2, rR15, #1                             @ R15 + 1 into scratch register
        uxth    r2, r2                                   @ Wrap scratch R15 at 16 bits
        strh    r2, [rGSU, #FX_R15]                      @ Store R15. WYATT_TODO unnecessary. Aliasing?
        sxtb    ip, rPIPE                                @ Sign-extend PIPE
        add     rR15, rR15, #2                           @ R15 + 2
        ldrb    rPIPE, [r1, r2]                          @ FETCHPIPE. We don't immediately use this value!
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        strh    ip, [rGSU, #FX_R14]                      @ Store result
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        uxth    ip, ip                                   @ PIPE was sign-extended, so we need to zero-extend it for the load. WYATT_TODO could probably avoid this.
        ldr     rR15, [rGSU, #FX_pvRomBank]              @ READR14: Load ROM base pointer
        ldrb    rR15, [rR15, ip]                         @ READR14: Load ROM(R14)
        strb    rR15, [rGSU, #FX_vRomBuffer]             @ READR14: Store to ROMBUFFER
        b       loop_head                                @ 

@ FROM: Set SREG to register N
@ If B flag is set, move register N to DREG and set flags instead
@ B is unlikely. WYATT_TODO invert the branch.
handle_fx_from_r:
        tst     rSTAT, #4096                             @ Test B flag
        beq     handle_fx_from_r.b_is_not_set            @ If B is not set, just set SREG and increment R15
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
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
        ldrheq  rR15, [rGSU, #FX_R14]                    @  |
        ldreq   r2, [rGSU, #FX_pvRomBank]                @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        strbeq  rR15, [rGSU, #FX_vRomBuffer]             @  |
        b       loop_head                                @ 

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
        ldrheq  rR15, [rGSU, #FX_R14]                    @  |
        ldreq   r2, [rGSU, #FX_pvRomBank]                @  |
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strbeq  rR15, [rGSU, #FX_vRomBuffer]             @  |
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
        ldrh    r2, [rGSU, #FX_R15]                      @ Load R15. WYATT_TODO unnecessary
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        add     r2, r2, #1                               @ R15++
        strh    r2, [rGSU, #FX_R15]                      @ Store R15
        strh    rR15, [rDREG]                            @ Store result
        add     rR15, rGSU, #FX_R14                      @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        ldrheq  rR15, [rGSU, #FX_R14]                    @  |
        ldreq   r2, [rGSU, #FX_pvRomBank]                @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        strbeq  rR15, [rGSU, #FX_vRomBuffer]             @  |
        b       loop_head                                @ 

@ INC: increment a register. Cannot be called with R15.
handle_fx_inc_r:
        add     rR15, rR15, #1                           @ R15++
        strh    rR15, [rGSU, #FX_R15]                    @  |
        lsl     vLow, vLow, #1                           @ Shift vLow for 2-byte offset
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        ldrh    r2, [rGSU, vLow]                         @ Load value
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        add     r2, r2, #1                               @ Increment value
        strh    r2, [rGSU, vLow]                         @ Store result
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        lsl     rARM, r2, #16                            @ Set flags
        movs    rARM, rARM                               @  |
        mrs     rARM, cpsr                               @ Read flags from CPSR
        b       loop_dispatch                            @ Skip reloading r1 and rR15

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
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strb    r2, [rGSU, #FX_vRomBuffer]               @ READR14: Store to ROMBUFFER
        b       loop_dispatch                            @ Skip reloading r1 and rR15

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
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        strb    r2, [rGSU, #FX_vColorReg]                @ Store result to GSU.vColorReg
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       loop_head                                @ 

@ DEC: decrement a register
handle_fx_dec_r:
        add     rR15, rR15, #1                           @ R15++
        strh    rR15, [rGSU, #FX_R15]                    @  |
        lsl     vLow, vLow, #1                           @ Shift vLow for 2-byte offset
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        ldrh    r2, [rGSU, vLow]                         @ Load value
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        sub     r2, r2, #1                               @ Decrement value
        strh    r2, [rGSU, vLow]                         @ Store result
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        lsl     rARM, r2, #16                            @ Set flags
        movs    rARM, rARM                               @  |
        mrs     rARM, cpsr                               @ Read flags from CPSR
        b       loop_dispatch                            @ Skip reloading r1 and rR15

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
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strb    r2, [rGSU, #FX_vRomBuffer]               @ READR14: Store to ROMBUFFER
        b       loop_dispatch                            @ Skip reloading r1 and rR15

@ GETB: get byte from ROMBUFFER
handle_fx_getb:
        add     rR15, rR15, #1                           @ R15++
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        ldrb    rR15, [rGSU, #FX_vRomBuffer]             @ Load value from ROMBUFFER
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        strh    rR15, [rDREG]                            @ Store value to DREG
        add     rR15, rGSU, #FX_R14                      @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        ldrheq  rR15, [rGSU, #FX_R14]                    @  |
        ldreq   r2, [rGSU, #FX_pvRomBank]                @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        strbeq  rR15, [rGSU, #FX_vRomBuffer]             @  |
        b       loop_head                                @ 

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
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        strh    ip, [rGSU, vLow]                         @ Store result to register N
        b       loop_head                                @ 

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
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        strh    ip, [rGSU, #FX_R14]                      @ Store result to R14
        ldr     rR15, [rGSU, #FX_pvRomBank]              @ READR14: Load ROM base pointer
        ldrb    rR15, [rR15, ip]                         @ READR14: Load ROM(R14)
        strb    rR15, [rGSU, #FX_vRomBuffer]             @ READR14: Store to ROMBUFFER
        b       loop_head                                @ 

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
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        add     rR15, rR15, #1                           @ R15++
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        b       loop_head                                @ 

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
        ldrheq  rR15, [rGSU, #FX_R14]                    @  |
        ldreq   r2, [rGSU, #FX_pvRomBank]                @  |
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strbeq  rR15, [rGSU, #FX_vRomBuffer]             @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       loop_head                                @ 

@ CMODE: set plot option register to the value in SREG
handle_fx_cmode:
        ldrb    rR15, [rSREG]                            @ Load result in SREG
        tst     rR15, #16                                @ Test plotOptionReg for screenHeight
        strb    rR15, [rGSU, #FX_vPlotOptionReg]         @ Store result
        movne   rR15, #256                               @ If PLOT_OBJECT, fake screenHeight as 256
        ldreq   rR15, [rGSU, #FX_vScreenRealHeight]      @ Else, set screenHeight to its real height
        str     rR15, [rGSU, #FX_vScreenHeight]          @ Store screenHeight
        bl      fx_computeScreenPointers                 @ Recompute screen ptrs. WYATT_TODO if regs are changed, be careful!
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        ldrh    rR15, [rGSU, #FX_R15]                    @ Load R15. WYATT_TODO can be moved above computeScreenPointers
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        add     rR15, rR15, #1                           @ R15++
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        b       loop_head                                @ 

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
        ldrheq  rR15, [rGSU, #FX_R14]                    @  |
        ldreq   r2, [rGSU, #FX_pvRomBank]                @  |
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strbeq  rR15, [rGSU, #FX_vRomBuffer]             @  |
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
        ldrh    r2, [rGSU, #FX_R15]                      @ Load R15. WYATT_TODO unnecessary
        lsrs    rR15, rR15, #16                          @ Shift result into bottom half of register and set flags
        add     r2, r2, #1                               @ R15++
        strh    r2, [rGSU, #FX_R15]                      @ Store R15
        orreq   rARM, rARM, #1073741824                  @ If the result is 0, set the Z flag
        strh    rR15, [rDREG]                            @ Store the result
        add     rR15, rGSU, #FX_R14                      @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        ldrheq  rR15, [rGSU, #FX_R14]                    @  |
        ldreq   r2, [rGSU, #FX_pvRomBank]                @  |
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strbeq  rR15, [rGSU, #FX_vRomBuffer]             @  |
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
        ldrh    r2, [rGSU, #FX_R15]                      @ Load R15. WYATT_TODO unnecessary
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        add     r2, r2, #1                               @ R15++
        strh    r2, [rGSU, #FX_R15]                      @ Store R15
        strh    rR15, [rDREG]                            @ Store result to DREG
        add     rR15, rGSU, #FX_R14                      @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        ldrheq  rR15, [rGSU, #FX_R14]                    @  |
        ldreq   r2, [rGSU, #FX_pvRomBank]                @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        strbeq  rR15, [rGSU, #FX_vRomBuffer]             @  |
        b       loop_head                                @ 

@ UMULT: 8-bit to 16-bit unsigned multiply, SREG * register N, stored in DREG
handle_fx_umult_r:
        ldrb    rR15, [rSREG]                            @ Load value 1
        ldrb    r2, [rGSU, vLow, lsl #1]                 @ Load value 2
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
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
        ldrheq  rR15, [rGSU, #FX_R14]                    @  |
        ldreq   r2, [rGSU, #FX_pvRomBank]                @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        strbeq  rR15, [rGSU, #FX_vRomBuffer]             @  |
        b       loop_head                                @ 

@ DIV2: Divides SREG by 2 and stores in DREG
handle_fx_div2:
        ldrh    rR15, [rSREG]                            @ Load value
        ldrh    r2, [rGSU, #FX_const_u16Max]             @ Load 0xFFFF
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
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
        ldrheq  rR15, [rGSU, #FX_R14]                    @  |
        ldreq   r2, [rGSU, #FX_pvRomBank]                @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        strbeq  rR15, [rGSU, #FX_vRomBuffer]             @  |
        b       loop_head                                @ 

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
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        str     rR15, [rGSU, #FX_vCacheFlags]            @ GSU.vCacheFlags = 0
        mov     rR15, #1                                 @ Enable cache
        strb    rR15, [rGSU, #FX_bCacheActive]           @  |
        bic     rR15, r2, #15                            @ R15 & 0xfff0
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strh    rR15, [rGSU, #FX_vCacheBaseReg]          @ GSU.vCacheBaseReg = R15 & 0xfff0
        strh    r2, [rGSU, #FX_R15]                      @ Store destination to R15
        b       loop_head_flags                          @ 

@ LMULT: 16-bit to 32-bit signed multiplication SREG * R6, low result in R4, then high result in DREG.
handle_fx_lmult:
        ldrh    rR15, [rSREG]                            @ Load value 1
        ldrh    r2, [rGSU, #FX_R6]                       @ Load value 2
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
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
        ldrheq  rR15, [rGSU, #FX_R14]                    @  |
        ldreq   r2, [rGSU, #FX_pvRomBank]                @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        strbeq  rR15, [rGSU, #FX_vRomBuffer]             @  |
        b       loop_head                                @ 

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
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strh    rR15, [rGSU, vLow]                       @ Store result
        b       loop_head                                @ 
        
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
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        orr     rR15, rR15, r2, lsl #8                   @ Combine both bytes
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        strh    rR15, [rGSU, #FX_R14]                    @ Store result in R14
        ldr     r2, [rGSU, #FX_pvRomBank]                @ READR14: Load ROM base pointer
        ldrb    rR15, [r2, rR15]                         @ READR14: Load ROM(R14)
        strb    rR15, [rGSU, #FX_vRomBuffer]             @ READR14: Store to ROMBUFFER
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
        ldrh    r2, [rGSU, #FX_R15]                      @ Load R15. WYATT_TODO unnecessary
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        add     r2, r2, #1                               @ R15++
        strh    r2, [rGSU, #FX_R15]                      @ Store R15
        strh    rR15, [rDREG]                            @ Store result
        add     rR15, rGSU, #FX_R14                      @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        ldrheq  rR15, [rGSU, #FX_R14]                    @  |
        ldreq   r2, [rGSU, #FX_pvRomBank]                @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        strbeq  rR15, [rGSU, #FX_vRomBuffer]             @  |
        b       loop_head                                @ 

@ GETBH: Overwrite the high byte in SREG with ROMBUFFER, stored in DREG
handle_fx_getbh:
        add     r2, rR15, #1                             @ R15++
        ldrb    rR15, [rSREG]                            @ Load SREG bottom byte
        strh    r2, [rGSU, #FX_R15]                      @ Store R15
        ldrb    r2, [rGSU, #FX_vRomBuffer]               @ Load ROMBUFFER
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        orr     rR15, rR15, r2, lsl #8                   @ Combine both sources
        strh    rR15, [rDREG]                            @ Store result
        add     rR15, rGSU, #FX_R14                      @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        ldrheq  rR15, [rGSU, #FX_R14]                    @  |
        ldreq   r2, [rGSU, #FX_pvRomBank]                @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        strbeq  rR15, [rGSU, #FX_vRomBuffer]             @  |
        b       loop_head                                @ 

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
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        b       loop_head                                @ 

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
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        ldr     r2, [rGSU, #FX_pvRomBank]                @ READR14: Load ROM base pointer
        ldrb    ip, [r2, ip]                             @ READR14: Load ROM(R14)
        strb    ip, [rGSU, #FX_vRomBuffer]               @ READR14: Store to ROMBUFFER
        b       loop_head                                @ 

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
        ldrheq  rR15, [rGSU, #FX_R14]                    @  |
        ldreq   r2, [rGSU, #FX_pvRomBank]                @  |
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strbeq  rR15, [rGSU, #FX_vRomBuffer]             @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       loop_head                                @ 

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
        ldrheq  rR15, [rGSU, #FX_R14]                    @  |
        ldreq   r2, [rGSU, #FX_pvRomBank]                @  |
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strbeq  rR15, [rGSU, #FX_vRomBuffer]             @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       loop_head                                @ 

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
        ldrheq  rR15, [rGSU, #FX_R14]                    @  |
        ldreq   r2, [rGSU, #FX_pvRomBank]                @  |
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strbeq  rR15, [rGSU, #FX_vRomBuffer]             @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       loop_head                                @ 

@ MULT: multiply SREG and 4-bit immediate as signed 8-bit ints, store in DREG
handle_fx_mult_i:
        ldrsb   rR15, [rSREG]                            @ Load SREG as s8
        ldrh    r2, [rGSU, #FX_R15]                      @ Load R15. WYATT_TODO unnecessary
        smulbb  rR15, rR15, vLow                         @ Multiply SREG and immediate
        msr     cpsr_f, rARM                             @ Load flags into CPSR
        movs    rARM, rR15                               @ Set flags
        mrs     rARM, cpsr                               @ Read flags from CPSR
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        add     r2, r2, #1                               @ R15++
        strh    r2, [rGSU, #FX_R15]                      @ Store R15
        strh    rR15, [rDREG]                            @ Store result
        add     rR15, rGSU, #FX_R14                      @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        ldrheq  rR15, [rGSU, #FX_R14]                    @  |
        ldreq   r2, [rGSU, #FX_pvRomBank]                @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        strbeq  rR15, [rGSU, #FX_vRomBuffer]             @  |
        b       loop_head                                @ 

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
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        strb    r2, [rR15, ip]                           @ Store bottom byte of result
        ldrh    rR15, [rGSU, #FX_vLastRamAdr]            @ Reload GSU.vLastRamAdr. WYATT_TODO unnecessary
        ldr     r1, [rGSU, #FX_pvRamBank]                @ Reload RAM base pointer. WYATT_TODO unnecessary
        add     rR15, rR15, #1                           @ R15++
        lsr     r2, r2, #8                               @ Prep top byte of result
        uxth    rR15, rR15                               @ Wrap R15 at 16 bits
        strb    r2, [r1, rR15]                           @ Store top byte of result
        ldrh    rR15, [rGSU, #FX_R15]                    @ Reload R15. WYATT_TODO unnecessary
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        add     rR15, rR15, #1                           @ R15++
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        b       loop_head                                @ 

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
        ldrheq  rR15, [rGSU, #FX_R14]                    @  |
        ldreq   r2, [rGSU, #FX_pvRomBank]                @  |
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strbeq  rR15, [rGSU, #FX_vRomBuffer]             @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       loop_head                                @ 

@ RAMB: Set current RAM bank to SREG
handle_fx_ramb:
        ldrh    r2, [rSREG]                              @ Load SREG
        add     rR15, rR15, #1                           @ R15++
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        and     rR15, r2, #3                             @ SREG & (FX_RAM_BANKS - 1)
        strb    rR15, [rGSU, #FX_vRamBankReg]            @ Store to GSU.vRamBankReg
        add     rR15, rR15, #FX_apvRamBank >> 2          @ Add apvRamBank table offset, pre-shifted down
        ldr     rR15, [rGSU, rR15, lsl #2]               @ Load pointer at GSU.apvRamBank[GSU.vRamBankReg]
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        str     rR15, [rGSU, #FX_pvRamBank]              @ Store to GSU.pvRamBank
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       loop_head                                @ 

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
        ldrheq  rR15, [rGSU, #FX_R14]                    @  |
        ldreq   r2, [rGSU, #FX_pvRomBank]                @  |
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strbeq  rR15, [rGSU, #FX_vRomBuffer]             @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       loop_head                                @ 

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
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        strb    r2, [rR15, ip]                           @ Store lower byte
        ldrh    rR15, [rGSU, #FX_vLastRamAdr]            @ Reload GSU.vLastRamAdr. WYATT_TODO unnecessary
        ldr     r1, [rGSU, #FX_pvRamBank]                @ Reload RAM base pointer. WYATT_TODO unnecessary
        lsr     r2, r2, #8                               @ Prep upper byte
        eor     rR15, rR15, #1                           @ Flip bottom bit of offset
        strb    r2, [r1, rR15]                           @ Store upper byte
        ldrh    rR15, [rGSU, #FX_R15]                    @ Reload R15. WYATT_TODO unnecessary
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        add     rR15, rR15, #1                           @ R15++
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        b       loop_head                                @ 

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
        ldrheq  rR15, [rGSU, #FX_R14]                    @  |
        ldreq   r2, [rGSU, #FX_pvRomBank]                @  |
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strbeq  rR15, [rGSU, #FX_vRomBuffer]             @  |
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
        ldrh    rR15, [rGSU, #FX_R15]                    @ Load R15. WYATT_TODO unnecessary
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        add     rR15, rR15, #1                           @ R15++
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        b       loop_head                                @ 

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
        ldrheq  rR15, [rGSU, #FX_R14]                    @  |
        ldreq   r2, [rGSU, #FX_pvRomBank]                @  |
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strbeq  rR15, [rGSU, #FX_vRomBuffer]             @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       loop_head                                @ 

@ UMULT_I: 8-bit to 16-bit unsigned multiply, SREG * 4-bit immediate, stored in DREG
handle_fx_umult_i:
        ldrb    rR15, [rSREG]                            @ Load SREG
        ldrh    r2, [rGSU, #FX_R15]                      @ Load R15. WYATT_TODO unnecessary
        smulbb  rR15, rR15, vLow                         @ Multiply SREG * immediate
        msr     cpsr_f, rARM                             @ Move flags into CPSR
        movs    rARM, rR15                               @ Set flags
        mrs     rARM, cpsr                               @ Read flags from CPSR
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        add     r2, r2, #1                               @ R15++
        strh    r2, [rGSU, #FX_R15]                      @ Store R15
        strh    rR15, [rDREG]                            @ Store result
        add     rR15, rGSU, #FX_R14                      @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        ldrheq  rR15, [rGSU, #FX_R14]                    @  |
        ldreq   r2, [rGSU, #FX_pvRomBank]                @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        strbeq  rR15, [rGSU, #FX_vRomBuffer]             @  |
        b       loop_head                                @ 

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
        ldrheq  rR15, [rGSU, #FX_R14]                    @  |
        ldreq   r2, [rGSU, #FX_pvRomBank]                @  |
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        ldrbeq  rR15, [r2, rR15]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        strbeq  rR15, [rGSU, #FX_vRomBuffer]             @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       loop_head                                @ 

@ ROMB: set program bank to SREG
handle_fx_romb:
        ldrh    r2, [rSREG]                              @ Load SREG
        add     rR15, rR15, #1                           @ R15++
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        and     rR15, r2, #127                           @ Clear top bit of SREG
        strb    rR15, [rGSU, #FX_vRomBankReg]            @ Store SREG to GSU.vRomBankReg
        add     rR15, rR15, #FX_apvRomBank >> 2          @ Offset magic for apvRomBank, pre-shifted down
        ldr     rR15, [rGSU, rR15, lsl #2]               @ Load pointer at GSU.apvRomBank[GSU.vPrgBankReg]
        add     rSREG, rGSU, #FX_R0                      @ CLRFLAGS: SREG = 0
        str     rR15, [rGSU, #FX_pvRomBank]              @ Store to GSU.pvRomBank
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: STAT
        b       loop_head                                @ 

@ FROM: If B is not set, set SREG to register N and increment R15
handle_fx_from_r.b_is_not_set:
        add     rR15, rR15, #1                           @ R15++. WYATT_TODO this should be moved to the common handler
        strh    rR15, [rGSU, #FX_R15]                    @ Store R15
        add     rSREG, rGSU, vLow, lsl #1                @ SREG = register N
        b       loop_head_flags                          @ 

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

@ fx_cache: second half of the conditional, down here since it's UNLIKELY.
@ Only reached if GSU.vCacheBaseReg says we need a reload
.cache_test_active:
        ldrb    r1, [rGSU, #FX_bCacheActive]             @ Load GSU.bCacheActive
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
        #include "fxinst_asm_opcode_table.h"
