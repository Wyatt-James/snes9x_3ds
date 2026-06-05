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
        ldrh    r1, [rGSU, #28]                          @ READR14: Load GSU R14
      @ cmp     vLow, #0                                 @ If nInstructions == 0, end. Unreachable.
        ldr     vLow, [rGSU, #408]                       @ READR14: Load GSU.pvRomBank
        ldrb    r1, [vLow, r1]                           @ READR14: Load GSU.pvRomBank[R14]
        ldrb    rSREG, [rGSU, #61]                       @ Load reserved regs
        ldrb    rDREG, [rGSU, #60]                       @  |
        ldrh    rSTAT, [rGSU, #64]                       @  |
        ldr     rARM, [rGSU, #68]                        @  |
        ldrb    rPIPE, [rGSU, #62]                       @  |
        add     rSREG, rGSU, rSREG, lsl #1               @  |
        add     rDREG, rGSU, rDREG, lsl #1               @  V
        strb    r1, [rGSU, #38]                          @ READR14: Store loaded value to GSU.vRomBuffer
        str     r2, [rGOTO, #2352]                       @ Populate GOTO table
        str     r2, [rGOTO, #304]                        @  |
        str     rR15, [rGOTO, #3376]                     @  |
        str     rR15, [rGOTO, #1328]                     @  V
      @ beq     loop_end                                 @ End if nInstructions == 0. Unreachable.
        ldr     r1, [rGSU, #412]                         @ FETCHPIPE: Load GSU.pvPrgBank. Taken from loop_dispatch to save a cycle.
loop_dispatch:
        ldrh    rR15, [rGSU, #30]                        @ FETCHPIPE: Load R15
        ldrb    ip, [r1, rR15]                           @ FETCHPIPE: Load from memory
        and     r2, rSTAT, #768                          @ Get opcode mode bits
        orr     r2, rPIPE, r2                            @ Compute opcode
        and     vLow, rPIPE, #15                         @ Compute vLow
        mov     rPIPE, ip                                @ FETCHPIPE: redundant move? WYATT_TODO IP is used but rPIPE might be better.
        ldr     pc, [rGOTO, r2, lsl #2]                  @ Branch to handler

@ GETBS: get sign extended byte from ROM at address R14
handle_fx_getbs:
        add     rR15, rR15, #1                           @ R15++
        strh    rR15, [rGSU, #30]                        @ Store R15
        ldrsb   rR15, [rGSU, #38]                        @ R15 = SEX8(GSU.vRomBuffer)
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = R0
        strh    rR15, [rDREG]                            @ Store value to DREG
        add     rR15, rGSU, #28                          @ TESTR14: Pointer to R14
        cmp     rDREG, rR15                              @ TESTR14: If DREG == 14, load rombuffer
        ldrheq  rR15, [rGSU, #28]                        @  |
        ldreq   r2, [rGSU, #408]                         @  |
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS: clear STAT
        ldrbeq  rR15, [r2, rR15]                         @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = R0
        strbeq  rR15, [rGSU, #38]                        @  V
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
        mov     rR15, #0                                 @ GSU.vPlotOptionReg = 0
        add     rSREG, rGSU, #0                          @ CLRFLAGS: SREG = 0
        ldr     r2, [rGSU, #100]                         @ R2 = GSU.pvRegisters[GSU_CFGR]
        bic     rSTAT, rSTAT, #32                        @ CF(G)
        ldrsb   r2, [r2, #55]                            @ R2 = GSU_CFGR
        mov     rPIPE, #1                                @ PIPE = 1
        cmp     r2, #0                                   @ If GSU_CFGR == 0, Raise IRQ
        orrge   rSTAT, rSTAT, #32768                     @  |
        mov     rDREG, rSREG                             @ CLRFLAGS: DREG = 0
        bic     rSTAT, rSTAT, #4864                      @  |
        strb    rR15, [rGSU, #36]                        @ GSU.vPlotOptionReg = 0
        b       loop_end                                 @ 
handle_fx_plot_2bit:
        add     rR15, rR15, #1                           @ 
        ldrh    r1, [rGSU, #2]                           @ 
        ldr     r2, [rGSU, #388]                         @ 
        strh    rR15, [rGSU, #30]                        @ 
        ldrb    rR15, [rGSU, #4]                         @ 
        add     rSREG, rGSU, #0                          @ 
        cmp     rR15, r2                                 @ 
        add     r2, r1, #1                               @ 
        mov     rDREG, rSREG                             @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        strh    r2, [rGSU, #2]                           @ 
        bcs     loop_head                                @ 
        ldrb    vLow, [rGSU, #36]                        @ 
        ldrb    r2, [rGSU, #37]                          @ 
        tst     vLow, #2                                 @ 
        uxtb    r1, r1                                   @ 
        bne     .L237                                    @ 
.L15:
        and     ip, r2, #15                              @ 
.L17:
        and     vLow, vLow, #1                           @ 
        orrs    vLow, ip, vLow                           @ 
        beq     loop_head                                @ 
        mov     ip, #128                                 @ 
        lsr     vLow, r1, #3                             @ 
        and     r1, r1, #7                               @ 
        asr     ip, ip, r1                               @ 
        uxtb    r1, ip                                   @ 
        mov     ip, r1                                   @ 
        add     vLow, rGSU, vLow, lsl #2                 @ 
        lsr     r1, rR15, #3                             @ 
        ldr     vLow, [vLow, #260]                       @ 
        add     r1, rGSU, r1, lsl #2                     @ 
        lsl     rR15, rR15, #1                           @ 
        ldr     r1, [r1, #132]                           @ 
        and     rR15, rR15, #14                          @ 
        add     rR15, rR15, vLow                         @ 
        ldrb    vLow, [r1, rR15]                         @ 
        tst     r2, #1                                   @ 
        str     vLow, [sp, #4]                           @ 
        add     vLow, r1, rR15                           @ 
        str     vLow, [sp]                               @ 
        ldr     vLow, [sp, #4]                           @ 
        orrne   vLow, vLow, ip                           @ 
        biceq   vLow, vLow, ip                           @ 
        strb    vLow, [r1, rR15]                         @ 
        ldr     rR15, [sp]                               @ 
        tst     r2, #2                                   @ 
        ldrb    rR15, [rR15, #1]                         @ 
        ldr     r2, [sp]                                 @ 
        orrne   rR15, ip, rR15                           @ 
        biceq   rR15, rR15, ip                           @ 
        strb    rR15, [r2, #1]                           @ 
        b       loop_head                                @ 
handle_fx_rpix_2bit:
        add     rR15, rR15, #1                           @ 
        ldr     r2, [rGSU, #388]                         @ 
        strh    rR15, [rGSU, #30]                        @ 
        ldrb    rR15, [rGSU, #4]                         @ 
        add     r1, rGSU, #0                             @ 
        cmp     rR15, r2                                 @ 
        mov     rSREG, r1                                @ 
        mov     rDREG, r1                                @ 
        ldrh    r2, [rGSU, #2]                           @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        bcs     loop_head                                @ 
        mov     vLow, #128                               @ 
        uxtb    r2, r2                                   @ 
        lsr     ip, r2, #3                               @ 
        and     r2, r2, #7                               @ 
        asr     vLow, vLow, r2                           @ 
        uxtb    r2, vLow                                 @ 
        add     ip, rGSU, ip, lsl #2                     @ 
        lsr     vLow, rR15, #3                           @ 
        ldr     ip, [ip, #260]                           @ 
        add     vLow, rGSU, vLow, lsl #2                 @ 
        lsl     rR15, rR15, #1                           @ 
        ldr     vLow, [vLow, #132]                       @ 
        and     rR15, rR15, #14                          @ 
        add     rR15, rR15, ip                           @ 
        add     ip, vLow, rR15                           @ 
        ldrb    vLow, [vLow, rR15]                       @ 
        ldrb    rR15, [ip, #1]                           @ 
        str     r2, [sp]                                 @ 
        str     rR15, [sp, #4]                           @ 
        ldr     ip, [sp]                                 @ 
        mov     rR15, #1                                 @ 
        mov     r2, #0                                   @ 
        tst     ip, vLow                                 @ 
        orrne   r2, r2, rR15, lsl #0                     @ 
        ldr     vLow, [sp, #4]                           @ 
        tst     ip, vLow                                 @ 
        orrne   r2, r2, rR15, lsl #1                     @ 
        add     rR15, rGSU, #28                          @ 
        strh    r2, [r1]                                 @ 
        cmp     r1, rR15                                 @ 
        ldrheq  rR15, [rGSU, #28]                        @ 
        ldreq   r2, [rGSU, #408]                         @ 
        ldrbeq  rR15, [r2, rR15]                         @ 
        strbeq  rR15, [rGSU, #38]                        @ 
        b       loop_head                                @ 
handle_fx_plot_4bit:
        add     rR15, rR15, #1                           @ 
        ldr     r2, [rGSU, #388]                         @ 
        ldrb    r1, [rGSU, #4]                           @ 
        strh    rR15, [rGSU, #30]                        @ 
        ldrh    rR15, [rGSU, #2]                         @ 
        cmp     r1, r2                                   @ 
        add     r2, rR15, #1                             @ 
        add     rSREG, rGSU, #0                          @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        mov     rDREG, rSREG                             @ 
        strh    r2, [rGSU, #2]                           @ 
        bcs     loop_head                                @ 
        ldrb    vLow, [rGSU, #36]                        @ 
        ldrb    r2, [rGSU, #37]                          @ 
        tst     vLow, #2                                 @ 
        uxtb    rR15, rR15                               @ 
        bne     .L238                                    @ 
.L25:
        and     ip, r2, #15                              @ 
.L27:
        and     vLow, vLow, #1                           @ 
        orrs    vLow, ip, vLow                           @ 
        beq     loop_head                                @ 
        mov     vLow, #128                               @ 
        lsr     ip, rR15, #3                             @ 
        and     rR15, rR15, #7                           @ 
        add     ip, rGSU, ip, lsl #2                     @ 
        asr     rR15, vLow, rR15                         @ 
        lsr     vLow, r1, #3                             @ 
        ldr     ip, [ip, #260]                           @ 
        add     vLow, rGSU, vLow, lsl #2                 @ 
        lsl     r1, r1, #1                               @ 
        ldr     vLow, [vLow, #132]                       @ 
        and     r1, r1, #14                              @ 
        add     ip, r1, ip                               @ 
        uxtb    rR15, rR15                               @ 
        ldrb    r1, [vLow, ip]                           @ 
        str     rR15, [sp]                               @ 
        mov     rR15, vLow                               @ 
        str     vLow, [sp, #4]                           @ 
        mov     vLow, r1                                 @ 
        add     r1, rR15, ip                             @ 
        ldr     rR15, [sp]                               @ 
        tst     r2, #1                                   @ 
        orrne   vLow, vLow, rR15                         @ 
        biceq   vLow, vLow, rR15                         @ 
        ldr     rR15, [sp, #4]                           @ 
        tst     r2, #2                                   @ 
        strb    vLow, [rR15, ip]                         @ 
        ldrb    vLow, [r1, #1]                           @ 
        ldr     rR15, [sp]                               @ 
        orrne   vLow, rR15, vLow                         @ 
        biceq   vLow, vLow, rR15                         @ 
        strb    vLow, [r1, #1]                           @ 
        ldr     rR15, [sp]                               @ 
        ldrb    vLow, [r1, #16]                          @ 
        tst     r2, #4                                   @ 
        orrne   vLow, rR15, vLow                         @ 
        biceq   vLow, vLow, rR15                         @ 
        ldr     rR15, [sp]                               @ 
        tst     r2, #8                                   @ 
        ldrb    r2, [r1, #17]                            @ 
        strb    vLow, [r1, #16]                          @ 
        orrne   rR15, rR15, r2                           @ 
        biceq   rR15, r2, rR15                           @ 
        strb    rR15, [r1, #17]                          @ 
        b       loop_head                                @ 
handle_fx_rpix_4bit:
        add     r2, rGSU, #0                             @ 
        mov     rSREG, r2                                @ 
        add     rR15, rR15, #1                           @ 
        ldrb    r1, [rGSU, #4]                           @ 
        strh    rR15, [rGSU, #30]                        @ 
        ldr     rR15, [rGSU, #388]                       @ 
        mov     rDREG, rSREG                             @ 
        cmp     r1, rR15                                 @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        ldrh    rR15, [rGSU, #2]                         @ 
        str     rSREG, [sp]                              @ 
        bcs     loop_head                                @ 
        mov     ip, #0                                   @ 
        mov     r2, #128                                 @ 
        uxtb    rR15, rR15                               @ 
        lsr     vLow, rR15, #3                           @ 
        add     vLow, rGSU, vLow, lsl #2                 @ 
        ldr     vLow, [vLow, #260]                       @ 
        and     rR15, rR15, #7                           @ 
        str     vLow, [sp, #4]                           @ 
        lsr     vLow, r1, #3                             @ 
        add     vLow, rGSU, vLow, lsl #2                 @ 
        asr     r2, r2, rR15                             @ 
        lsl     r1, r1, #1                               @ 
        mov     rR15, ip                                 @ 
        ldr     ip, [vLow, #132]                         @ 
        ldr     vLow, [sp, #4]                           @ 
        and     r1, r1, #14                              @ 
        add     r1, r1, vLow                             @ 
        add     vLow, ip, r1                             @ 
        uxtb    r2, r2                                   @ 
        ldrb    ip, [ip, r1]                             @ 
        mov     r1, #1                                   @ 
        tst     r2, ip                                   @ 
        orrne   rR15, rR15, r1, lsl #0                   @ 
        ldrb    ip, [vLow, #1]                           @ 
        tst     r2, ip                                   @ 
        orrne   rR15, rR15, r1, lsl #1                   @ 
        ldrb    ip, [vLow, #16]                          @ 
        ldrb    vLow, [vLow, #17]                        @ 
        tst     r2, ip                                   @ 
        orrne   rR15, rR15, r1, lsl #2                   @ 
        tst     r2, vLow                                 @ 
        orrne   rR15, rR15, r1, lsl #3                   @ 
        mov     r2, rDREG                                @ 
        strh    rR15, [rDREG]                            @ 
        add     rR15, rGSU, #28                          @ 
        cmp     rDREG, rR15                              @ 
        ldrheq  rR15, [rGSU, #28]                        @ 
        ldreq   r2, [rGSU, #408]                         @ 
        ldrbeq  rR15, [r2, rR15]                         @ 
        strbeq  rR15, [rGSU, #38]                        @ 
        b       loop_head                                @ 
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
        beq     .L239                                    @ 
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
handle_fx_rpix_8bit:
        add     rR15, rR15, #1                           @ 
        ldrb    r1, [rGSU, #4]                           @ 
        strh    rR15, [rGSU, #30]                        @ 
        ldr     rR15, [rGSU, #388]                       @ 
        add     vLow, rGSU, #0                           @ 
        cmp     r1, rR15                                 @ 
        mov     rSREG, vLow                              @ 
        mov     rDREG, vLow                              @ 
        ldrh    r2, [rGSU, #2]                           @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        bcs     loop_head                                @ 
        mov     ip, #128                                 @ 
        uxtb    r2, r2                                   @ 
        bic     rR15, rARM, #1073741824                  @ 
        lsr     rARM, r2, #3                             @ 
        and     r2, r2, #7                               @ 
        add     rARM, rGSU, rARM, lsl #2                 @ 
        asr     r2, ip, r2                               @ 
        lsr     ip, r1, #3                               @ 
        ldr     rARM, [rARM, #260]                       @ 
        add     ip, rGSU, ip, lsl #2                     @ 
        lsl     r1, r1, #1                               @ 
        ldr     ip, [ip, #132]                           @ 
        and     r1, r1, #14                              @ 
        add     rARM, r1, rARM                           @ 
        add     r1, ip, rARM                             @ 
        uxtb    r2, r2                                   @ 
        ldrb    rARM, [ip, rARM]                         @ 
        str     rR15, [sp]                               @ 
        mov     ip, #1                                   @ 
        mov     rR15, #0                                 @ 
        tst     r2, rARM                                 @ 
        orrne   rR15, rR15, ip, lsl #0                   @ 
        ldrb    rARM, [r1, #1]                           @ 
        tst     r2, rARM                                 @ 
        orrne   rR15, rR15, ip, lsl #1                   @ 
        ldrb    rARM, [r1, #16]                          @ 
        tst     r2, rARM                                 @ 
        orrne   rR15, rR15, ip, lsl #2                   @ 
        ldrb    rARM, [r1, #17]                          @ 
        tst     r2, rARM                                 @ 
        orrne   rR15, rR15, ip, lsl #3                   @ 
        ldrb    rARM, [r1, #32]                          @ 
        tst     r2, rARM                                 @ 
        orrne   rR15, rR15, ip, lsl #4                   @ 
        ldrb    rARM, [r1, #33]                          @ 
        tst     r2, rARM                                 @ 
        orrne   rR15, rR15, ip, lsl #5                   @ 
        ldrb    rARM, [r1, #48]                          @ 
        ldrb    r1, [r1, #49]                            @ 
        tst     r2, rARM                                 @ 
        orrne   rR15, rR15, ip, lsl #6                   @ 
        tst     r2, r1                                   @ 
        orrne   rR15, rR15, ip, lsl #7                   @ 
        strh    rR15, [vLow]                             @ 
        uxth    rR15, rR15                               @ 
        cmp     rR15, #0                                 @ 
        ldr     rR15, [sp]                               @ 
        mov     rARM, rR15                               @ 
        orreq   rARM, rR15, #1073741824                  @ 
        add     rR15, rGSU, #28                          @ 
        cmp     rR15, vLow                               @ 
        ldrheq  rR15, [rGSU, #28]                        @ 
        ldreq   r2, [rGSU, #408]                         @ 
        ldrbeq  rR15, [r2, rR15]                         @ 
        strbeq  rR15, [rGSU, #38]                        @ 
        b       loop_head                                @ 

@ NOP: Clears flags and advances R15 
handle_fx_nop:
        add     rR15, rR15, #1                           @ R15++
        add     rSREG, rGSU, #0                          @ CLRFLAGS SREG = 0
        strh    rR15, [rGSU, #30]                        @ Store R15
        mov     rDREG, rSREG                             @ CLRFLAGS DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS STAT
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
        add     rSREG, rGSU, #0                          @ CLRFLAGS SREG = 0
        strh    rR15, [rGSU, #30]                        @ Store R15
        mov     rDREG, rSREG                             @ CLRFLAGS DREG = 0
        bic     rSTAT, rSTAT, #4864                      @ CLRFLAGS STAT
        b       loop_head                                @ 

handle_fx_lsr:
        ldrh    r2, [rGSU, #30]                          @ 
        ldrh    rR15, [rSREG]                            @ 
        add     r2, r2, #1                               @ 
        strh    r2, [rGSU, #30]                          @ 
        msr     cpsr_f, rARM                             @ 
        lsrs    rR15, rR15, #1                           @ 
        mrs     rARM, cpsr                               @ 
        strh    rR15, [rDREG]                            @ 
        add     rR15, rGSU, #28                          @ 
        cmp     rDREG, rR15                              @ 
        ldrheq  rR15, [rGSU, #28]                        @ 
        ldreq   r2, [rGSU, #408]                         @ 
        add     rSREG, rGSU, #0                          @ 
        ldrbeq  rR15, [r2, rR15]                         @ 
        mov     rDREG, rSREG                             @ 
        strbeq  rR15, [rGSU, #38]                        @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        b       loop_head                                @ 
handle_fx_rol:
        ldrh    r2, [rGSU, #30]                          @ 
        ldrh    rR15, [rSREG]                            @ 
        add     r2, r2, #1                               @ 
        msr     cpsr_f, rARM                             @ 
        lsl     rR15, rR15, #16                          @ 
        orrcs   rR15, rR15, #32768                       @ 
        lsls    rR15, rR15, #1                           @ 
        mrs     rARM, cpsr                               @ 
        lsr     rR15, rR15, #16                          @ 
        strh    r2, [rGSU, #30]                          @ 
        strh    rR15, [rDREG]                            @ 
        add     rR15, rGSU, #28                          @ 
        cmp     rDREG, rR15                              @ 
        ldrheq  rR15, [rGSU, #28]                        @ 
        ldreq   r2, [rGSU, #408]                         @ 
        add     rSREG, rGSU, #0                          @ 
        ldrbeq  rR15, [r2, rR15]                         @ 
        mov     rDREG, rSREG                             @ 
        strbeq  rR15, [rGSU, #38]                        @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        b       loop_head                                @ 
handle_fx_bra:
        add     rR15, rR15, #1                           @ 
        uxth    rR15, rR15                               @ 
        sxtb    r2, ip                                   @ 
        add     r2, rR15, r2                             @ 
        ldrb    rPIPE, [r1, rR15]                        @ 
        strh    r2, [rGSU, #30]                          @ 
        b       loop_head                                @ 
handle_fx_bge:
        add     rR15, rR15, #1                           @ 
        uxth    r2, rR15                                 @ 
        ldrb    rPIPE, [r1, r2]                          @ 
        sxtb    ip, ip                                   @ 
        msr     cpsr_f, rARM                             @ 
        addge   rR15, rR15, ip                           @ 
        addlt   rR15, rR15, #1                           @ 
        strh    rR15, [rGSU, #30]                        @ 
        b       loop_head                                @ 
handle_fx_blt:
        add     rR15, rR15, #1                           @ 
        uxth    r2, rR15                                 @ 
        ldrb    rPIPE, [r1, r2]                          @ 
        sxtb    ip, ip                                   @ 
        msr     cpsr_f, rARM                             @ 
        addlt   rR15, rR15, ip                           @ 
        addge   rR15, rR15, #1                           @ 
        strh    rR15, [rGSU, #30]                        @ 
        b       loop_head                                @ 
handle_fx_bne:
        add     rR15, rR15, #1                           @ 
        uxth    r2, rR15                                 @ 
        ldrb    rPIPE, [r1, r2]                          @ 
        sxtb    ip, ip                                   @ 
        msr     cpsr_f, rARM                             @ 
        addne   rR15, rR15, ip                           @ 
        addeq   rR15, rR15, #1                           @ 
        strh    rR15, [rGSU, #30]                        @ 
        b       loop_head                                @ 
handle_fx_beq:
        add     rR15, rR15, #1                           @ 
        uxth    r2, rR15                                 @ 
        ldrb    rPIPE, [r1, r2]                          @ 
        sxtb    ip, ip                                   @ 
        msr     cpsr_f, rARM                             @ 
        addeq   rR15, rR15, ip                           @ 
        addne   rR15, rR15, #1                           @ 
        strh    rR15, [rGSU, #30]                        @ 
        b       loop_head                                @ 
handle_fx_bpl:
        add     rR15, rR15, #1                           @ 
        uxth    r2, rR15                                 @ 
        ldrb    rPIPE, [r1, r2]                          @ 
        sxtb    ip, ip                                   @ 
        msr     cpsr_f, rARM                             @ 
        addpl   rR15, rR15, ip                           @ 
        addmi   rR15, rR15, #1                           @ 
        strh    rR15, [rGSU, #30]                        @ 
        b       loop_head                                @ 
handle_fx_bmi:
        add     rR15, rR15, #1                           @ 
        uxth    r2, rR15                                 @ 
        ldrb    rPIPE, [r1, r2]                          @ 
        sxtb    ip, ip                                   @ 
        msr     cpsr_f, rARM                             @ 
        addmi   rR15, rR15, ip                           @ 
        addpl   rR15, rR15, #1                           @ 
        strh    rR15, [rGSU, #30]                        @ 
        b       loop_head                                @ 
handle_fx_bcc:
        add     rR15, rR15, #1                           @ 
        uxth    r2, rR15                                 @ 
        ldrb    rPIPE, [r1, r2]                          @ 
        sxtb    ip, ip                                   @ 
        msr     cpsr_f, rARM                             @ 
        addcc   rR15, rR15, ip                           @ 
        addcs   rR15, rR15, #1                           @ 
        strh    rR15, [rGSU, #30]                        @ 
        b       loop_head                                @ 
handle_fx_bcs:
        add     rR15, rR15, #1                           @ 
        uxth    r2, rR15                                 @ 
        ldrb    rPIPE, [r1, r2]                          @ 
        sxtb    ip, ip                                   @ 
        msr     cpsr_f, rARM                             @ 
        addcs   rR15, rR15, ip                           @ 
        addcc   rR15, rR15, #1                           @ 
        strh    rR15, [rGSU, #30]                        @ 
        b       loop_head                                @ 
handle_fx_bvc:
        add     rR15, rR15, #1                           @ 
        uxth    r2, rR15                                 @ 
        ldrb    rPIPE, [r1, r2]                          @ 
        sxtb    ip, ip                                   @ 
        msr     cpsr_f, rARM                             @ 
        addvc   rR15, rR15, ip                           @ 
        addvs   rR15, rR15, #1                           @ 
        strh    rR15, [rGSU, #30]                        @ 
        b       loop_head                                @ 
handle_fx_bvs:
        add     rR15, rR15, #1                           @ 
        uxth    r2, rR15                                 @ 
        ldrb    rPIPE, [r1, r2]                          @ 
        sxtb    ip, ip                                   @ 
        msr     cpsr_f, rARM                             @ 
        addvs   rR15, rR15, ip                           @ 
        addvc   rR15, rR15, #1                           @ 
        strh    rR15, [rGSU, #30]                        @ 
        b       loop_head                                @ 
handle_fx_to_r:
        tst     rSTAT, #4096                             @ 
        addeq   vLow, rGSU, vLow, lsl #1                 @ 
        beq     .L81                                     @ 
        ldrh    r2, [rSREG]                              @ 
        lsl     vLow, vLow, #1                           @ 
        strh    r2, [rGSU, vLow]                         @ 
        add     vLow, rGSU, #0                           @ 
        mov     rSREG, vLow                              @ 
        bic     rSTAT, rSTAT, #4864                      @ 
.L81:
        add     rR15, rR15, #1                           @ 
        mov     rDREG, vLow                              @ 
        strh    rR15, [rGSU, #30]                        @ 
        b       loop_head                                @ 
handle_fx_to_r14:
        tst     rSTAT, #4096                             @ 
        bne     .L241                                    @ 
        add     rDREG, rGSU, #28                         @ 
.L84:
        add     rR15, rR15, #1                           @ 
        strh    rR15, [rGSU, #30]                        @ 
        b       loop_head                                @ 
handle_fx_to_r15:
        tst     rSTAT, #4096                             @ 
        beq     .L86                                     @ 
        ldrh    rR15, [rSREG]                            @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        add     rSREG, rGSU, #0                          @ 
        strh    rR15, [rGSU, #30]                        @ 
        mov     rDREG, rSREG                             @ 
        b       loop_head                                @ 
handle_fx_with:
        add     rDREG, rGSU, vLow, lsl #1                @ 
        add     rR15, rR15, #1                           @ 
        mov     rSREG, rDREG                             @ 
        strh    rR15, [rGSU, #30]                        @ 
        orr     rSTAT, rSTAT, #4096                      @ 
        b       loop_head                                @ 
handle_fx_stw_r:
        lsl     vLow, vLow, #1                           @ 
        ldrh    rR15, [rGSU, vLow]                       @ 
        ldr     r1, [rGSU, #404]                         @ 
        strh    rR15, [rGSU, #34]                        @ 
        ldrh    r2, [rSREG]                              @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        strb    r2, [r1, rR15]                           @ 
        eor     rR15, rR15, #1                           @ 
        lsr     r2, r2, #8                               @ 
        strb    r2, [r1, rR15]                           @ 
        ldrh    rR15, [rGSU, #30]                        @ 
        add     rSREG, rGSU, #0                          @ 
        add     rR15, rR15, #1                           @ 
        mov     rDREG, rSREG                             @ 
        strh    rR15, [rGSU, #30]                        @ 
        b       loop_head                                @ 
handle_fx_loop:
        ldrh    rR15, [rGSU, #24]                        @ 
        add     rSREG, rGSU, #0                          @ 
        sub     rR15, rR15, #1                           @ 
        msr     cpsr_f, rARM                             @ 
        lsl     rARM, rR15, #16                          @ 
        movs    rARM, rARM                               @ 
        mrs     rARM, cpsr                               @ 
        cmp     rR15, #0                                 @ 
        strh    rR15, [rGSU, #24]                        @ 
        ldrheq  rR15, [rGSU, #30]                        @ 
        ldrhne  rR15, [rGSU, #26]                        @ 
        addeq   rR15, rR15, #1                           @ 
        uxtheq  rR15, rR15                               @ 
        mov     rDREG, rSREG                             @ 
        strh    rR15, [rGSU, #30]                        @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        b       loop_head                                @ 
handle_fx_alt1:
        add     rR15, rR15, #1                           @ 
        bic     rSTAT, rSTAT, #4096                      @ 
        strh    rR15, [rGSU, #30]                        @ 
        orr     rSTAT, rSTAT, #256                       @ 
        b       loop_head                                @ 
handle_fx_alt2:
        add     rR15, rR15, #1                           @ 
        bic     rSTAT, rSTAT, #4096                      @ 
        strh    rR15, [rGSU, #30]                        @ 
        orr     rSTAT, rSTAT, #512                       @ 
        b       loop_head                                @ 
handle_fx_alt3:
        add     rR15, rR15, #1                           @ 
        bic     rSTAT, rSTAT, #4096                      @ 
        strh    rR15, [rGSU, #30]                        @ 
        orr     rSTAT, rSTAT, #768                       @ 
        b       loop_head                                @ 
handle_fx_ldw_r:
        lsl     vLow, vLow, #1                           @ 
        ldrh    r2, [rGSU, vLow]                         @ 
        ldr     r1, [rGSU, #404]                         @ 
        strh    r2, [rGSU, #34]                          @ 
        eor     ip, r2, #1                               @ 
        add     vLow, rR15, #1                           @ 
        ldrb    rR15, [r1, r2]                           @ 
        ldrb    r2, [r1, ip]                             @ 
        strh    vLow, [rGSU, #30]                        @ 
        orr     rR15, rR15, r2, lsl #8                   @ 
        strh    rR15, [rDREG]                            @ 
        add     rR15, rGSU, #28                          @ 
        cmp     rDREG, rR15                              @ 
        ldrheq  rR15, [rGSU, #28]                        @ 
        ldreq   r2, [rGSU, #408]                         @ 
        add     rSREG, rGSU, #0                          @ 
        ldrbeq  rR15, [r2, rR15]                         @ 
        mov     rDREG, rSREG                             @ 
        strbeq  rR15, [rGSU, #38]                        @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        b       loop_head                                @ 
handle_fx_swap:
        add     r2, rR15, #1                             @ 
        ldrh    rR15, [rSREG]                            @ 
        strh    r2, [rGSU, #30]                          @ 
        rev16   rR15, rR15                               @ 
        add     r2, rGSU, #28                            @ 
        strh    rR15, [rDREG]                            @ 
        orr     r1, rR15, rR15, lsl #16                  @ 
        msr     cpsr_f, rARM                             @ 
        movs    rARM, r1                                 @ 
        mrs     rARM, cpsr                               @ 
        cmp     rDREG, r2                                @ 
        ldrheq  rR15, [rGSU, #28]                        @ 
        ldreq   r2, [rGSU, #408]                         @ 
        add     rSREG, rGSU, #0                          @ 
        ldrbeq  rR15, [r2, rR15]                         @ 
        mov     rDREG, rSREG                             @ 
        strbeq  rR15, [rGSU, #38]                        @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        b       loop_head                                @ 
handle_fx_color:
        ldrb    r1, [rGSU, #36]                          @ 
        ldrb    r2, [rSREG]                              @ 
        tst     r1, #4                                   @ 
        andne   vLow, r2, #240                           @ 
        orrne   r2, vLow, r2, lsr #4                     @ 
        tst     r1, #8                                   @ 
        ldrbne  r1, [rGSU, #37]                          @ 
        andne   r2, r2, #15                              @ 
        bicne   r1, r1, #15                              @ 
        orrne   r2, r1, r2                               @ 
        add     rR15, rR15, #1                           @ 
        add     rSREG, rGSU, #0                          @ 
        strb    r2, [rGSU, #37]                          @ 
        mov     rDREG, rSREG                             @ 
        strh    rR15, [rGSU, #30]                        @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        b       loop_head                                @ 
handle_fx_not:
        ldrh    r2, [rGSU, #30]                          @ 
        ldrh    rR15, [rSREG]                            @ 
        add     r2, r2, #1                               @ 
        strh    r2, [rGSU, #30]                          @ 
        add     rR15, rR15, rR15, lsl #16                @ 
        msr     cpsr_f, rARM                             @ 
        mvns    rR15, rR15                               @ 
        mrs     rARM, cpsr                               @ 
        strh    rR15, [rDREG]                            @ 
        add     rR15, rGSU, #28                          @ 
        cmp     rDREG, rR15                              @ 
        ldrheq  rR15, [rGSU, #28]                        @ 
        ldreq   r2, [rGSU, #408]                         @ 
        add     rSREG, rGSU, #0                          @ 
        ldrbeq  rR15, [r2, rR15]                         @ 
        mov     rDREG, rSREG                             @ 
        strbeq  rR15, [rGSU, #38]                        @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        b       loop_head                                @ 
handle_fx_add_r:
        ldrh    rR15, [rSREG]                            @ 
        ldrh    r2, [rGSU, #30]                          @ 
        lsl     vLow, vLow, #1                           @ 
        ldrh    rARM, [rGSU, vLow]                       @ 
        add     r2, r2, #1                               @ 
        lsl     rR15, rR15, #16                          @ 
        adds    rR15, rR15, rARM, lsl #16                @ 
        mrs     rARM, cpsr                               @ 
        lsr     rR15, rR15, #16                          @ 
        strh    r2, [rGSU, #30]                          @ 
        strh    rR15, [rDREG]                            @ 
        add     rR15, rGSU, #28                          @ 
        cmp     rDREG, rR15                              @ 
        ldrheq  rR15, [rGSU, #28]                        @ 
        ldreq   r2, [rGSU, #408]                         @ 
        add     rSREG, rGSU, #0                          @ 
        ldrbeq  rR15, [r2, rR15]                         @ 
        mov     rDREG, rSREG                             @ 
        strbeq  rR15, [rGSU, #38]                        @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        b       loop_head                                @ 
handle_fx_sub_r:
        ldrh    rR15, [rSREG]                            @ 
        ldrh    r2, [rGSU, #30]                          @ 
        lsl     vLow, vLow, #1                           @ 
        ldrh    rARM, [rGSU, vLow]                       @ 
        add     r2, r2, #1                               @ 
        lsl     rR15, rR15, #16                          @ 
        subs    rR15, rR15, rARM, lsl #16                @ 
        mrs     rARM, cpsr                               @ 
        lsr     rR15, rR15, #16                          @ 
        strh    r2, [rGSU, #30]                          @ 
        strh    rR15, [rDREG]                            @ 
        add     rR15, rGSU, #28                          @ 
        cmp     rDREG, rR15                              @ 
        ldrheq  rR15, [rGSU, #28]                        @ 
        ldreq   r2, [rGSU, #408]                         @ 
        add     rSREG, rGSU, #0                          @ 
        ldrbeq  rR15, [r2, rR15]                         @ 
        mov     rDREG, rSREG                             @ 
        strbeq  rR15, [rGSU, #38]                        @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        b       loop_head                                @ 
handle_fx_merge:
        ldrh    r1, [rGSU, #14]                          @ 
        ldrh    r2, [rGSU, #16]                          @ 
        bic     r1, r1, #255                             @ 
        orr     r2, r1, r2, lsr #8                       @ 
        add     rR15, rR15, #1                           @ 
        strh    rR15, [rGSU, #30]                        @ 
        lsr     rR15, r2, #4                             @ 
        orr     rR15, rR15, r1, lsr #12                  @ 
        and     rR15, rR15, #15                          @ 
        add     rR15, rGSU, rR15                         @ 
        ldrb    rARM, [rR15, #42]                        @ 
        strh    r2, [rDREG]                              @ 
        add     rR15, rGSU, #28                          @ 
        cmp     rDREG, rR15                              @ 
        ldrheq  rR15, [rGSU, #28]                        @ 
        ldreq   r2, [rGSU, #408]                         @ 
        add     rSREG, rGSU, #0                          @ 
        ldrbeq  rR15, [r2, rR15]                         @ 
        mov     rDREG, rSREG                             @ 
        lsl     rARM, rARM, #28                          @ 
        strbeq  rR15, [rGSU, #38]                        @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        b       loop_head                                @ 
handle_fx_and_r:
        lsl     vLow, vLow, #1                           @ 
        ldrh    rR15, [rSREG]                            @ 
        ldrh    r2, [rGSU, vLow]                         @ 
        add     rR15, rR15, rR15, lsl #16                @ 
        add     r2, r2, r2, lsl #16                      @ 
        msr     cpsr_f, rARM                             @ 
        ands    rR15, rR15, r2                           @ 
        mrs     rARM, cpsr                               @ 
        ldrh    r2, [rGSU, #30]                          @ 
        add     rSREG, rGSU, #0                          @ 
        add     r2, r2, #1                               @ 
        strh    r2, [rGSU, #30]                          @ 
        strh    rR15, [rDREG]                            @ 
        add     rR15, rGSU, #28                          @ 
        cmp     rDREG, rR15                              @ 
        ldrheq  rR15, [rGSU, #28]                        @ 
        ldreq   r2, [rGSU, #408]                         @ 
        mov     rDREG, rSREG                             @ 
        ldrbeq  rR15, [r2, rR15]                         @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        strbeq  rR15, [rGSU, #38]                        @ 
        b       loop_head                                @ 
handle_fx_mult_r:
        lsl     vLow, vLow, #1                           @ 
        ldrsb   rR15, [rSREG]                            @ 
        ldrsb   r2, [rGSU, vLow]                         @ 
        add     rSREG, rGSU, #0                          @ 
        smulbb  rR15, rR15, r2                           @ 
        msr     cpsr_f, rARM                             @ 
        movs    rARM, rR15                               @ 
        mrs     rARM, cpsr                               @ 
        ldrh    r2, [rGSU, #30]                          @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        add     r2, r2, #1                               @ 
        strh    r2, [rGSU, #30]                          @ 
        strh    rR15, [rDREG]                            @ 
        add     rR15, rGSU, #28                          @ 
        cmp     rDREG, rR15                              @ 
        ldrheq  rR15, [rGSU, #28]                        @ 
        ldreq   r2, [rGSU, #408]                         @ 
        mov     rDREG, rSREG                             @ 
        ldrbeq  rR15, [r2, rR15]                         @ 
        strbeq  rR15, [rGSU, #38]                        @ 
        b       loop_head                                @ 
handle_fx_sbk:
        ldrh    rR15, [rSREG]                            @ 
        ldrh    r2, [rGSU, #34]                          @ 
        ldr     r1, [rGSU, #404]                         @ 
        add     rSREG, rGSU, #0                          @ 
        strb    rR15, [r1, r2]                           @ 
        ldrh    r2, [rGSU, #34]                          @ 
        ldr     r1, [rGSU, #404]                         @ 
        lsr     rR15, rR15, #8                           @ 
        eor     r2, r2, #1                               @ 
        strb    rR15, [r1, r2]                           @ 
        ldrh    rR15, [rGSU, #30]                        @ 
        mov     rDREG, rSREG                             @ 
        add     rR15, rR15, #1                           @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        strh    rR15, [rGSU, #30]                        @ 
        b       loop_head                                @ 
handle_fx_link_i:
        add     vLow, vLow, rR15                         @ 
        add     rR15, rR15, #1                           @ 
        add     rSREG, rGSU, #0                          @ 
        strh    vLow, [rGSU, #22]                        @ 
        mov     rDREG, rSREG                             @ 
        strh    rR15, [rGSU, #30]                        @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        b       loop_head                                @ 
handle_fx_sex:
        ldrh    r2, [rGSU, #30]                          @ 
        ldrsb   rR15, [rSREG]                            @ 
        add     r2, r2, #1                               @ 
        strh    r2, [rGSU, #30]                          @ 
        msr     cpsr_f, rARM                             @ 
        movs    rR15, rR15                               @ 
        mrs     rARM, cpsr                               @ 
        strh    rR15, [rDREG]                            @ 
        add     rR15, rGSU, #28                          @ 
        cmp     rDREG, rR15                              @ 
        ldrheq  rR15, [rGSU, #28]                        @ 
        ldreq   r2, [rGSU, #408]                         @ 
        add     rSREG, rGSU, #0                          @ 
        ldrbeq  rR15, [r2, rR15]                         @ 
        mov     rDREG, rSREG                             @ 
        strbeq  rR15, [rGSU, #38]                        @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        b       loop_head                                @ 
handle_fx_asr:
        ldrh    r2, [rGSU, #30]                          @ 
        ldrsh   rR15, [rSREG]                            @ 
        add     r2, r2, #1                               @ 
        strh    r2, [rGSU, #30]                          @ 
        msr     cpsr_f, rARM                             @ 
        asrs    rR15, rR15, #1                           @ 
        mrs     rARM, cpsr                               @ 
        strh    rR15, [rDREG]                            @ 
        add     rR15, rGSU, #28                          @ 
        cmp     rDREG, rR15                              @ 
        ldrheq  rR15, [rGSU, #28]                        @ 
        ldreq   r2, [rGSU, #408]                         @ 
        add     rSREG, rGSU, #0                          @ 
        ldrbeq  rR15, [r2, rR15]                         @ 
        mov     rDREG, rSREG                             @ 
        strbeq  rR15, [rGSU, #38]                        @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        b       loop_head                                @ 
handle_fx_ror:
        ldrh    r2, [rGSU, #30]                          @ 
        ldrh    rR15, [rSREG]                            @ 
        add     r2, r2, #1                               @ 
        strh    r2, [rGSU, #30]                          @ 
        msr     cpsr_f, rARM                             @ 
        orrcs   rR15, rR15, #65536                       @ 
        rrxs    rR15, rR15                               @ 
        mrs     rARM, cpsr                               @ 
        strh    rR15, [rDREG]                            @ 
        add     rR15, rGSU, #28                          @ 
        cmp     rDREG, rR15                              @ 
        ldrheq  rR15, [rGSU, #28]                        @ 
        ldreq   r2, [rGSU, #408]                         @ 
        add     rSREG, rGSU, #0                          @ 
        ldrbeq  rR15, [r2, rR15]                         @ 
        mov     rDREG, rSREG                             @ 
        strbeq  rR15, [rGSU, #38]                        @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        b       loop_head                                @ 
handle_fx_jmp_r:
        lsl     vLow, vLow, #1                           @ 
        ldrh    rR15, [rGSU, vLow]                       @ 
        add     rSREG, rGSU, #0                          @ 
        strh    rR15, [rGSU, #30]                        @ 
        mov     rDREG, rSREG                             @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        b       loop_head                                @ 
handle_fx_lob:
        ldrh    rR15, [rGSU, #30]                        @ 
        ldrb    r2, [rSREG]                              @ 
        add     rR15, rR15, #1                           @ 
        strh    rR15, [rGSU, #30]                        @ 
        msr     cpsr_f, rARM                             @ 
        lsl     rARM, r2, #24                            @ 
        movs    rARM, rARM                               @ 
        mrs     rARM, cpsr                               @ 
        strh    r2, [rDREG]                              @ 
        add     rR15, rGSU, #28                          @ 
        cmp     rDREG, rR15                              @ 
        ldrheq  rR15, [rGSU, #28]                        @ 
        ldreq   r2, [rGSU, #408]                         @ 
        add     rSREG, rGSU, #0                          @ 
        ldrbeq  rR15, [r2, rR15]                         @ 
        mov     rDREG, rSREG                             @ 
        strbeq  rR15, [rGSU, #38]                        @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        b       loop_head                                @ 
.L242:
        .word   GSU
        .word   opcode_goto_table
        .word   plot_rpix_handler_table
handle_fx_fmult:
        ldrh    rR15, [rSREG]                            @ 
        ldrh    r2, [rGSU, #12]                          @ 
        add     rSREG, rGSU, #0                          @ 
        smulbb  rR15, rR15, r2                           @ 
        msr     cpsr_f, rARM                             @ 
        asrs    rR15, rR15, #16                          @ 
        mrs     rARM, cpsr                               @ 
        ldrh    r2, [rGSU, #30]                          @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        add     r2, r2, #1                               @ 
        strh    r2, [rGSU, #30]                          @ 
        strh    rR15, [rDREG]                            @ 
        add     rR15, rGSU, #28                          @ 
        cmp     rDREG, rR15                              @ 
        ldrheq  rR15, [rGSU, #28]                        @ 
        ldreq   r2, [rGSU, #408]                         @ 
        mov     rDREG, rSREG                             @ 
        ldrbeq  rR15, [r2, rR15]                         @ 
        strbeq  rR15, [rGSU, #38]                        @ 
        b       loop_head                                @ 
handle_fx_ibt_r:
        add     r2, rR15, #1                             @ 
        uxth    r2, r2                                   @ 
        strh    r2, [rGSU, #30]                          @ 
        lsl     vLow, vLow, #1                           @ 
        sxtb    ip, ip                                   @ 
        add     rR15, rR15, #2                           @ 
        ldrb    rPIPE, [r1, r2]                          @ 
        add     rSREG, rGSU, #0                          @ 
        strh    rR15, [rGSU, #30]                        @ 
        mov     rDREG, rSREG                             @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        strh    ip, [rGSU, vLow]                         @ 
        b       loop_head                                @ 
handle_fx_ibt_r14:
        add     r2, rR15, #1                             @ 
        uxth    r2, r2                                   @ 
        strh    r2, [rGSU, #30]                          @ 
        sxtb    ip, ip                                   @ 
        add     rR15, rR15, #2                           @ 
        ldrb    rPIPE, [r1, r2]                          @ 
        add     rSREG, rGSU, #0                          @ 
        strh    ip, [rGSU, #28]                          @ 
        mov     rDREG, rSREG                             @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        strh    rR15, [rGSU, #30]                        @ 
        uxth    ip, ip                                   @ 
        ldr     rR15, [rGSU, #408]                       @ 
        ldrb    rR15, [rR15, ip]                         @ 
        strb    rR15, [rGSU, #38]                        @ 
        b       loop_head                                @ 
handle_fx_from_r:
        tst     rSTAT, #4096                             @ 
        beq     .L131                                    @ 
        add     rSREG, rGSU, #0                          @ 
        lsl     vLow, vLow, #1                           @ 
        ldrh    rR15, [rGSU, vLow]                       @ 
        bic     rARM, rARM, #-805306368                  @ 
        lsls    r2, rR15, #24                            @ 
        orrmi   rARM, rARM, #268435456                   @ 
        lsls    r2, rR15, #16                            @ 
        orrmi   rARM, rARM, #-2147483648                 @ 
        orreq   rARM, rARM, #1073741824                  @ 
        ldrh    r2, [rGSU, #30]                          @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        add     r2, r2, #1                               @ 
        strh    r2, [rGSU, #30]                          @ 
        strh    rR15, [rDREG]                            @ 
        add     rR15, rGSU, #28                          @ 
        cmp     rDREG, rR15                              @ 
        ldrheq  rR15, [rGSU, #28]                        @ 
        ldreq   r2, [rGSU, #408]                         @ 
        mov     rDREG, rSREG                             @ 
        ldrbeq  rR15, [r2, rR15]                         @ 
        strbeq  rR15, [rGSU, #38]                        @ 
        b       loop_head                                @ 
handle_fx_hib:
        ldrh    rR15, [rSREG]                            @ 
        ldrh    r2, [rGSU, #30]                          @ 
        lsr     rR15, rR15, #8                           @ 
        add     r2, r2, #1                               @ 
        strh    r2, [rGSU, #30]                          @ 
        strh    rR15, [rDREG]                            @ 
        sxtb    r2, rR15                                 @ 
        add     rR15, rGSU, #28                          @ 
        msr     cpsr_f, rARM                             @ 
        movs    rARM, r2                                 @ 
        mrs     rARM, cpsr                               @ 
        cmp     rDREG, rR15                              @ 
        ldrheq  rR15, [rGSU, #28]                        @ 
        ldreq   r2, [rGSU, #408]                         @ 
        add     rSREG, rGSU, #0                          @ 
        ldrbeq  rR15, [r2, rR15]                         @ 
        mov     rDREG, rSREG                             @ 
        strbeq  rR15, [rGSU, #38]                        @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        b       loop_head                                @ 
handle_fx_or_r:
        lsl     vLow, vLow, #1                           @ 
        ldrh    rR15, [rSREG]                            @ 
        ldrh    r2, [rGSU, vLow]                         @ 
        add     rR15, rR15, rR15, lsl #16                @ 
        add     r2, r2, r2, lsl #16                      @ 
        msr     cpsr_f, rARM                             @ 
        orrs    rR15, rR15, r2                           @ 
        mrs     rARM, cpsr                               @ 
        ldrh    r2, [rGSU, #30]                          @ 
        add     rSREG, rGSU, #0                          @ 
        add     r2, r2, #1                               @ 
        strh    r2, [rGSU, #30]                          @ 
        strh    rR15, [rDREG]                            @ 
        add     rR15, rGSU, #28                          @ 
        cmp     rDREG, rR15                              @ 
        ldrheq  rR15, [rGSU, #28]                        @ 
        ldreq   r2, [rGSU, #408]                         @ 
        mov     rDREG, rSREG                             @ 
        ldrbeq  rR15, [r2, rR15]                         @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        strbeq  rR15, [rGSU, #38]                        @ 
        b       loop_head                                @ 
handle_fx_inc_r:
        lsl     vLow, vLow, #1                           @ 
        ldrh    rR15, [rGSU, vLow]                       @ 
        add     rSREG, rGSU, #0                          @ 
        add     rR15, rR15, #1                           @ 
        strh    rR15, [rGSU, vLow]                       @ 
        msr     cpsr_f, rARM                             @ 
        lsl     rARM, rR15, #16                          @ 
        movs    rARM, rARM                               @ 
        mrs     rARM, cpsr                               @ 
        ldrh    rR15, [rGSU, #30]                        @ 
        mov     rDREG, rSREG                             @ 
        add     rR15, rR15, #1                           @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        strh    rR15, [rGSU, #30]                        @ 
        b       loop_head                                @ 
handle_fx_inc_r14:
        ldrh    rR15, [rGSU, #28]                        @ 
        ldrh    r2, [rGSU, #30]                          @ 
        add     rR15, rR15, #1                           @ 
        add     r2, r2, #1                               @ 
        msr     cpsr_f, rARM                             @ 
        lsl     rARM, rR15, #16                          @ 
        movs    rARM, rARM                               @ 
        mrs     rARM, cpsr                               @ 
        uxth    rR15, rR15                               @ 
        add     rSREG, rGSU, #0                          @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        mov     rDREG, rSREG                             @ 
        strh    rR15, [rGSU, #28]                        @ 
        strh    r2, [rGSU, #30]                          @ 
        ldr     r2, [rGSU, #408]                         @ 
        ldrb    rR15, [r2, rR15]                         @ 
        strb    rR15, [rGSU, #38]                        @ 
        b       loop_head                                @ 
handle_fx_getc:
        ldrb    r1, [rGSU, #36]                          @ 
        ldrb    r2, [rGSU, #38]                          @ 
        tst     r1, #4                                   @ 
        andne   vLow, r2, #240                           @ 
        orrne   r2, vLow, r2, lsr #4                     @ 
        tst     r1, #8                                   @ 
        ldrbne  r1, [rGSU, #37]                          @ 
        andne   r2, r2, #15                              @ 
        bicne   r1, r1, #15                              @ 
        orrne   r2, r1, r2                               @ 
        add     rR15, rR15, #1                           @ 
        add     rSREG, rGSU, #0                          @ 
        strb    r2, [rGSU, #37]                          @ 
        mov     rDREG, rSREG                             @ 
        strh    rR15, [rGSU, #30]                        @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        b       loop_head                                @ 
handle_fx_dec_r:
        lsl     vLow, vLow, #1                           @ 
        ldrh    rR15, [rGSU, vLow]                       @ 
        add     rSREG, rGSU, #0                          @ 
        sub     rR15, rR15, #1                           @ 
        strh    rR15, [rGSU, vLow]                       @ 
        msr     cpsr_f, rARM                             @ 
        lsl     rARM, rR15, #16                          @ 
        movs    rARM, rARM                               @ 
        mrs     rARM, cpsr                               @ 
        ldrh    rR15, [rGSU, #30]                        @ 
        mov     rDREG, rSREG                             @ 
        add     rR15, rR15, #1                           @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        strh    rR15, [rGSU, #30]                        @ 
        b       loop_head                                @ 
handle_fx_dec_r14:
        ldrh    rR15, [rGSU, #28]                        @ 
        ldrh    r2, [rGSU, #30]                          @ 
        sub     rR15, rR15, #1                           @ 
        add     r2, r2, #1                               @ 
        msr     cpsr_f, rARM                             @ 
        lsl     rARM, rR15, #16                          @ 
        movs    rARM, rARM                               @ 
        mrs     rARM, cpsr                               @ 
        uxth    rR15, rR15                               @ 
        add     rSREG, rGSU, #0                          @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        mov     rDREG, rSREG                             @ 
        strh    rR15, [rGSU, #28]                        @ 
        strh    r2, [rGSU, #30]                          @ 
        ldr     r2, [rGSU, #408]                         @ 
        ldrb    rR15, [r2, rR15]                         @ 
        strb    rR15, [rGSU, #38]                        @ 
        b       loop_head                                @ 
handle_fx_getb:
        add     rR15, rR15, #1                           @ 
        strh    rR15, [rGSU, #30]                        @ 
        ldrb    rR15, [rGSU, #38]                        @ 
        add     rSREG, rGSU, #0                          @ 
        strh    rR15, [rDREG]                            @ 
        add     rR15, rGSU, #28                          @ 
        cmp     rDREG, rR15                              @ 
        ldrheq  rR15, [rGSU, #28]                        @ 
        ldreq   r2, [rGSU, #408]                         @ 
        mov     rDREG, rSREG                             @ 
        ldrbeq  rR15, [r2, rR15]                         @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        strbeq  rR15, [rGSU, #38]                        @ 
        b       loop_head                                @ 
handle_fx_iwt_r:
        add     r2, rR15, #1                             @ 
        uxth    r2, r2                                   @ 
        ldrb    rPIPE, [r1, r2]                          @ 
        add     r2, rR15, #2                             @ 
        orr     ip, ip, rPIPE, lsl #8                    @ 
        lsl     vLow, vLow, #1                           @ 
        uxth    r2, r2                                   @ 
        add     rR15, rR15, #3                           @ 
        ldrb    rPIPE, [r1, r2]                          @ 
        add     rSREG, rGSU, #0                          @ 
        strh    rR15, [rGSU, #30]                        @ 
        mov     rDREG, rSREG                             @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        strh    ip, [rGSU, vLow]                         @ 
        b       loop_head                                @ 
handle_fx_iwt_r14:
        add     r2, rR15, #1                             @ 
        uxth    r2, r2                                   @ 
        ldrb    rPIPE, [r1, r2]                          @ 
        add     r2, rR15, #2                             @ 
        orr     ip, ip, rPIPE, lsl #8                    @ 
        uxth    r2, r2                                   @ 
        add     rR15, rR15, #3                           @ 
        ldrb    rPIPE, [r1, r2]                          @ 
        add     rSREG, rGSU, #0                          @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        mov     rDREG, rSREG                             @ 
        strh    rR15, [rGSU, #30]                        @ 
        strh    ip, [rGSU, #28]                          @ 
        ldr     rR15, [rGSU, #408]                       @ 
        ldrb    rR15, [rR15, ip]                         @ 
        strb    rR15, [rGSU, #38]                        @ 
        b       loop_head                                @ 
handle_fx_stb_r:
        lsl     vLow, vLow, #1                           @ 
        ldrh    rR15, [rGSU, vLow]                       @ 
        ldr     r2, [rGSU, #404]                         @ 
        strh    rR15, [rGSU, #34]                        @ 
        ldrh    r1, [rSREG]                              @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        strb    r1, [r2, rR15]                           @ 
        ldrh    rR15, [rGSU, #30]                        @ 
        add     rSREG, rGSU, #0                          @ 
        add     rR15, rR15, #1                           @ 
        mov     rDREG, rSREG                             @ 
        strh    rR15, [rGSU, #30]                        @ 
        b       loop_head                                @ 
handle_fx_ldb_r:
        lsl     vLow, vLow, #1                           @ 
        ldrh    r2, [rGSU, vLow]                         @ 
        ldr     r1, [rGSU, #404]                         @ 
        strh    r2, [rGSU, #34]                          @ 
        ldrb    r2, [r1, r2]                             @ 
        add     rR15, rR15, #1                           @ 
        strh    rR15, [rGSU, #30]                        @ 
        strh    r2, [rDREG]                              @ 
        add     rR15, rGSU, #28                          @ 
        cmp     rDREG, rR15                              @ 
        ldrheq  rR15, [rGSU, #28]                        @ 
        ldreq   r2, [rGSU, #408]                         @ 
        add     rSREG, rGSU, #0                          @ 
        ldrbeq  rR15, [r2, rR15]                         @ 
        mov     rDREG, rSREG                             @ 
        strbeq  rR15, [rGSU, #38]                        @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        b       loop_head                                @ 
handle_fx_cmode:
        ldrb    rR15, [rSREG]                            @ 
        tst     rR15, #16                                @ 
        strb    rR15, [rGSU, #36]                        @ 
        movne   rR15, #256                               @ 
        ldreq   rR15, [rGSU, #392]                       @ 
        str     rR15, [rGSU, #388]                       @ 
        bl      fx_computeScreenPointers                 @ 
        add     rSREG, rGSU, #0                          @ 
        ldrh    rR15, [rGSU, #30]                        @ 
        mov     rDREG, rSREG                             @ 
        add     rR15, rR15, #1                           @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        strh    rR15, [rGSU, #30]                        @ 
        b       loop_head                                @ 
handle_fx_adc_r:
        ldrh    r2, [rGSU, #30]                          @ 
        lsl     vLow, vLow, #1                           @ 
        ldrh    r1, [rSREG]                              @ 
        ldrh    rR15, [rGSU, vLow]                       @ 
        add     r2, r2, #1                               @ 
        msr     cpsr_f, rARM                             @ 
        lsl     rARM, r1, #16                            @ 
        orrcs   rARM, rARM, #32768                       @ 
        orrcs   rR15, rR15, #-2147483648                 @ 
        adds    rR15, rARM, rR15, ror #16                @ 
        mrs     rARM, cpsr                               @ 
        lsr     rR15, rR15, #16                          @ 
        strh    r2, [rGSU, #30]                          @ 
        strh    rR15, [rDREG]                            @ 
        add     rR15, rGSU, #28                          @ 
        cmp     rDREG, rR15                              @ 
        ldrheq  rR15, [rGSU, #28]                        @ 
        ldreq   r2, [rGSU, #408]                         @ 
        add     rSREG, rGSU, #0                          @ 
        ldrbeq  rR15, [r2, rR15]                         @ 
        mov     rDREG, rSREG                             @ 
        strbeq  rR15, [rGSU, #38]                        @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        b       loop_head                                @ 
handle_fx_sbc_r:
        ldrh    rR15, [rSREG]                            @ 
        lsl     vLow, vLow, #1                           @ 
        ldrh    r2, [rGSU, vLow]                         @ 
        lsl     rR15, rR15, #16                          @ 
        msr     cpsr_f, rARM                             @ 
        sbcs    rR15, rR15, r2, lsl #16                  @ 
        mrs     rARM, cpsr                               @ 
        ldrh    r2, [rGSU, #30]                          @ 
        lsrs    rR15, rR15, #16                          @ 
        add     r2, r2, #1                               @ 
        strh    r2, [rGSU, #30]                          @ 
        orreq   rARM, rARM, #1073741824                  @ 
        strh    rR15, [rDREG]                            @ 
        add     rR15, rGSU, #28                          @ 
        cmp     rDREG, rR15                              @ 
        ldrheq  rR15, [rGSU, #28]                        @ 
        ldreq   r2, [rGSU, #408]                         @ 
        add     rSREG, rGSU, #0                          @ 
        ldrbeq  rR15, [r2, rR15]                         @ 
        mov     rDREG, rSREG                             @ 
        strbeq  rR15, [rGSU, #38]                        @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        b       loop_head                                @ 
handle_fx_bic_r:
        lsl     vLow, vLow, #1                           @ 
        ldrh    rR15, [rSREG]                            @ 
        ldrh    r2, [rGSU, vLow]                         @ 
        add     rR15, rR15, rR15, lsl #16                @ 
        add     r2, r2, r2, lsl #16                      @ 
        msr     cpsr_f, rARM                             @ 
        bics    rR15, rR15, r2                           @ 
        mrs     rARM, cpsr                               @ 
        ldrh    r2, [rGSU, #30]                          @ 
        add     rSREG, rGSU, #0                          @ 
        add     r2, r2, #1                               @ 
        strh    r2, [rGSU, #30]                          @ 
        strh    rR15, [rDREG]                            @ 
        add     rR15, rGSU, #28                          @ 
        cmp     rDREG, rR15                              @ 
        ldrheq  rR15, [rGSU, #28]                        @ 
        ldreq   r2, [rGSU, #408]                         @ 
        mov     rDREG, rSREG                             @ 
        ldrbeq  rR15, [r2, rR15]                         @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        strbeq  rR15, [rGSU, #38]                        @ 
        b       loop_head                                @ 
handle_fx_umult_r:
        ldrb    rR15, [rSREG]                            @ 
        ldrb    r2, [rGSU, vLow, lsl #1]                 @ 
        add     rSREG, rGSU, #0                          @ 
        smulbb  rR15, rR15, r2                           @ 
        msr     cpsr_f, rARM                             @ 
        lsl     rARM, rR15, #16                          @ 
        movs    rARM, rARM                               @ 
        mrs     rARM, cpsr                               @ 
        ldrh    r2, [rGSU, #30]                          @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        add     r2, r2, #1                               @ 
        strh    r2, [rGSU, #30]                          @ 
        strh    rR15, [rDREG]                            @ 
        add     rR15, rGSU, #28                          @ 
        cmp     rDREG, rR15                              @ 
        ldrheq  rR15, [rGSU, #28]                        @ 
        ldreq   r2, [rGSU, #408]                         @ 
        mov     rDREG, rSREG                             @ 
        ldrbeq  rR15, [r2, rR15]                         @ 
        strbeq  rR15, [rGSU, #38]                        @ 
        b       loop_head                                @ 
handle_fx_div2:
        ldrh    rR15, [rSREG]                            @ 
        ldrh    r2, [rGSU, #58]                          @ 
        add     rSREG, rGSU, #0                          @ 
        cmp     r2, rR15                                 @ 
        ldrh    r2, [rGSU, #30]                          @ 
        moveq   rR15, #1                                 @ 
        add     r2, r2, #1                               @ 
        strh    r2, [rGSU, #30]                          @ 
        sxthne  rR15, rR15                               @ 
        msr     cpsr_f, rARM                             @ 
        asrs    rR15, rR15, #1                           @ 
        mrs     rARM, cpsr                               @ 
        strh    rR15, [rDREG]                            @ 
        add     rR15, rGSU, #28                          @ 
        cmp     rDREG, rR15                              @ 
        ldrheq  rR15, [rGSU, #28]                        @ 
        ldreq   r2, [rGSU, #408]                         @ 
        mov     rDREG, rSREG                             @ 
        ldrbeq  rR15, [r2, rR15]                         @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        strbeq  rR15, [rGSU, #38]                        @ 
        b       loop_head                                @ 
handle_fx_ljmp_r:
        lsl     vLow, vLow, #1                           @ 
        ldrh    rR15, [rGSU, vLow]                       @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        and     rR15, rR15, #127                         @ 
        strb    rR15, [rGSU, #39]                        @ 
        add     rR15, rR15, #108                         @ 
        ldr     rR15, [rGSU, rR15, lsl #2]               @ 
        ldrh    r2, [rSREG]                              @ 
        str     rR15, [rGSU, #412]                       @ 
        mov     rR15, #0                                 @ 
        add     rSREG, rGSU, #0                          @ 
        str     rR15, [rGSU, #72]                        @ 
        mov     rR15, #1                                 @ 
        strb    rR15, [rGSU, #1456]                      @ 
        bic     rR15, r2, #15                            @ 
        mov     rDREG, rSREG                             @ 
        strh    rR15, [rGSU, #32]                        @ 
        strh    r2, [rGSU, #30]                          @ 
        b       loop_head                                @ 
handle_fx_lmult:
        ldrh    rR15, [rSREG]                            @ 
        ldrh    r2, [rGSU, #12]                          @ 
        add     rSREG, rGSU, #0                          @ 
        smulbb  rR15, rR15, r2                           @ 
        ldrh    r2, [rGSU, #30]                          @ 
        strh    rR15, [rGSU, #8]                         @ 
        add     r2, r2, #1                               @ 
        strh    r2, [rGSU, #30]                          @ 
        msr     cpsr_f, rARM                             @ 
        asrs    rR15, rR15, #16                          @ 
        mrs     rARM, cpsr                               @ 
        strh    rR15, [rDREG]                            @ 
        add     rR15, rGSU, #28                          @ 
        cmp     rDREG, rR15                              @ 
        ldrheq  rR15, [rGSU, #28]                        @ 
        ldreq   r2, [rGSU, #408]                         @ 
        mov     rDREG, rSREG                             @ 
        ldrbeq  rR15, [r2, rR15]                         @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        strbeq  rR15, [rGSU, #38]                        @ 
        b       loop_head                                @ 
handle_fx_lms_r:
        lsl     ip, ip, #1                               @ 
        add     r2, rR15, #1                             @ 
        strh    ip, [rGSU, #34]                          @ 
        uxth    r2, r2                                   @ 
        add     rR15, rR15, #2                           @ 
        ldrb    rPIPE, [r1, r2]                          @ 
        strh    rR15, [rGSU, #30]                        @ 
        ldr     rR15, [rGSU, #404]                       @ 
        add     r2, ip, #1                               @ 
        ldrb    r2, [rR15, r2]                           @ 
        ldrb    rR15, [rR15, ip]                         @ 
        lsl     vLow, vLow, #1                           @ 
        orr     rR15, rR15, r2, lsl #8                   @ 
        add     rSREG, rGSU, #0                          @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        mov     rDREG, rSREG                             @ 
        strh    rR15, [rGSU, vLow]                       @ 
        b       loop_head                                @ 
handle_fx_lms_r14:
        lsl     ip, ip, #1                               @ 
        add     r2, rR15, #1                             @ 
        strh    ip, [rGSU, #34]                          @ 
        uxth    r2, r2                                   @ 
        add     rR15, rR15, #2                           @ 
        ldrb    rPIPE, [r1, r2]                          @ 
        strh    rR15, [rGSU, #30]                        @ 
        ldr     rR15, [rGSU, #404]                       @ 
        add     r2, ip, #1                               @ 
        ldrb    r2, [rR15, r2]                           @ 
        ldrb    rR15, [rR15, ip]                         @ 
        add     rSREG, rGSU, #0                          @ 
        orr     rR15, rR15, r2, lsl #8                   @ 
        mov     rDREG, rSREG                             @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        strh    rR15, [rGSU, #28]                        @ 
        ldr     r2, [rGSU, #408]                         @ 
        ldrb    rR15, [r2, rR15]                         @ 
        strb    rR15, [rGSU, #38]                        @ 
        b       loop_head                                @ 
handle_fx_xor_r:
        lsl     vLow, vLow, #1                           @ 
        ldrh    rR15, [rSREG]                            @ 
        ldrh    r2, [rGSU, vLow]                         @ 
        add     rR15, rR15, rR15, lsl #16                @ 
        add     r2, r2, r2, lsl #16                      @ 
        msr     cpsr_f, rARM                             @ 
        eors    rR15, rR15, r2                           @ 
        mrs     rARM, cpsr                               @ 
        ldrh    r2, [rGSU, #30]                          @ 
        add     rSREG, rGSU, #0                          @ 
        add     r2, r2, #1                               @ 
        strh    r2, [rGSU, #30]                          @ 
        strh    rR15, [rDREG]                            @ 
        add     rR15, rGSU, #28                          @ 
        cmp     rDREG, rR15                              @ 
        ldrheq  rR15, [rGSU, #28]                        @ 
        ldreq   r2, [rGSU, #408]                         @ 
        mov     rDREG, rSREG                             @ 
        ldrbeq  rR15, [r2, rR15]                         @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        strbeq  rR15, [rGSU, #38]                        @ 
        b       loop_head                                @ 
handle_fx_getbh:
        add     r2, rR15, #1                             @ 
        ldrb    rR15, [rSREG]                            @ 
        strh    r2, [rGSU, #30]                          @ 
        ldrb    r2, [rGSU, #38]                          @ 
        add     rSREG, rGSU, #0                          @ 
        orr     rR15, rR15, r2, lsl #8                   @ 
        strh    rR15, [rDREG]                            @ 
        add     rR15, rGSU, #28                          @ 
        cmp     rDREG, rR15                              @ 
        ldrheq  rR15, [rGSU, #28]                        @ 
        ldreq   r2, [rGSU, #408]                         @ 
        mov     rDREG, rSREG                             @ 
        ldrbeq  rR15, [r2, rR15]                         @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        strbeq  rR15, [rGSU, #38]                        @ 
        b       loop_head                                @ 

handle_fx_lm_r_common:
        ldr     rSREG, .L3                               @ 
        uxtb    rR15, rPIPE                              @ 
        ldrh    r2, [rSREG, #30]                         @ 
        ldr     ip, [rSREG, #412]                        @ 
        add     r1, r2, #1                               @ 
        strh    rR15, [rSREG, #34]                       @ 
        uxth    r1, r1                                   @ 
        ldrb    rPIPE, [ip, r1]                          @ 
        add     r1, r2, #2                               @ 
        orr     rR15, rR15, rPIPE, lsl #8                @ 
        strh    rR15, [rSREG, #34]                       @ 
        uxth    r1, r1                                   @ 
        add     r2, r2, #3                               @ 
        ldrb    rPIPE, [ip, r1]                          @ 
        strh    r2, [rSREG, #30]                         @ 
        ldr     r2, [rSREG, #404]                        @ 
        eor     r1, rR15, #1                             @ 
        ldrb    r1, [r2, r1]                             @ 
        ldrb    rR15, [r2, rR15]                         @ 
        lsl     vLow, vLow, #1                           @ 
        orr     rR15, rR15, r1, lsl #8                   @ 
        strh    rR15, [rSREG, vLow]                      @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        add     rSREG, rSREG, #0                         @ 
        mov     rDREG, rSREG                             @ 
        bx      lr                                       @ 
.L3:
        .word   GSU

handle_fx_lm_r:
        bl      handle_fx_lm_r_common                    @ 
        b       loop_head                                @ 
handle_fx_lm_r14:
        mov     vLow, #14                                @ 
        bl      handle_fx_lm_r_common                    @ 
        ldrh    rR15, [rGSU, #28]                        @ 
        ldr     r2, [rGSU, #408]                         @ 
        ldrb    rR15, [r2, rR15]                         @ 
        strb    rR15, [rGSU, #38]                        @ 
        b       loop_head                                @ 
handle_fx_add_i:
        ldrh    rARM, [rSREG]                            @ 
        ldrh    r2, [rGSU, #30]                          @ 
        lsl     rARM, rARM, #16                          @ 
        add     r2, r2, #1                               @ 
        adds    rR15, rARM, vLow, lsl #16                @ 
        mrs     rARM, cpsr                               @ 
        lsr     rR15, rR15, #16                          @ 
        strh    r2, [rGSU, #30]                          @ 
        strh    rR15, [rDREG]                            @ 
        add     rR15, rGSU, #28                          @ 
        cmp     rDREG, rR15                              @ 
        ldrheq  rR15, [rGSU, #28]                        @ 
        ldreq   r2, [rGSU, #408]                         @ 
        add     rSREG, rGSU, #0                          @ 
        ldrbeq  rR15, [r2, rR15]                         @ 
        mov     rDREG, rSREG                             @ 
        strbeq  rR15, [rGSU, #38]                        @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        b       loop_head                                @ 
handle_fx_sub_i:
        ldrh    rARM, [rSREG]                            @ 
        ldrh    r2, [rGSU, #30]                          @ 
        lsl     rARM, rARM, #16                          @ 
        add     r2, r2, #1                               @ 
        subs    rR15, rARM, vLow, lsl #16                @ 
        mrs     rARM, cpsr                               @ 
        lsr     rR15, rR15, #16                          @ 
        strh    r2, [rGSU, #30]                          @ 
        strh    rR15, [rDREG]                            @ 
        add     rR15, rGSU, #28                          @ 
        cmp     rDREG, rR15                              @ 
        ldrheq  rR15, [rGSU, #28]                        @ 
        ldreq   r2, [rGSU, #408]                         @ 
        add     rSREG, rGSU, #0                          @ 
        ldrbeq  rR15, [r2, rR15]                         @ 
        mov     rDREG, rSREG                             @ 
        strbeq  rR15, [rGSU, #38]                        @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        b       loop_head                                @ 
handle_fx_and_i:
        ldrh    r2, [rGSU, #30]                          @ 
        ldrh    rR15, [rSREG]                            @ 
        add     r2, r2, #1                               @ 
        strh    r2, [rGSU, #30]                          @ 
        msr     cpsr_f, rARM                             @ 
        ands    rR15, rR15, vLow                         @ 
        mrs     rARM, cpsr                               @ 
        strh    rR15, [rDREG]                            @ 
        add     rR15, rGSU, #28                          @ 
        cmp     rDREG, rR15                              @ 
        ldrheq  rR15, [rGSU, #28]                        @ 
        ldreq   r2, [rGSU, #408]                         @ 
        add     rSREG, rGSU, #0                          @ 
        ldrbeq  rR15, [r2, rR15]                         @ 
        mov     rDREG, rSREG                             @ 
        strbeq  rR15, [rGSU, #38]                        @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        b       loop_head                                @ 
handle_fx_mult_i:
        ldrsb   rR15, [rSREG]                            @ 
        ldrh    r2, [rGSU, #30]                          @ 
        smulbb  rR15, rR15, vLow                         @ 
        msr     cpsr_f, rARM                             @ 
        movs    rARM, rR15                               @ 
        mrs     rARM, cpsr                               @ 
        add     rSREG, rGSU, #0                          @ 
        add     r2, r2, #1                               @ 
        strh    r2, [rGSU, #30]                          @ 
        strh    rR15, [rDREG]                            @ 
        add     rR15, rGSU, #28                          @ 
        cmp     rDREG, rR15                              @ 
        ldrheq  rR15, [rGSU, #28]                        @ 
        ldreq   r2, [rGSU, #408]                         @ 
        mov     rDREG, rSREG                             @ 
        ldrbeq  rR15, [r2, rR15]                         @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        strbeq  rR15, [rGSU, #38]                        @ 
        b       loop_head                                @ 
handle_fx_sms_r:
        add     rR15, rR15, #1                           @ 
        lsl     ip, ip, #1                               @ 
        uxth    rR15, rR15                               @ 
        lsl     vLow, vLow, #1                           @ 
        ldrh    r2, [rGSU, vLow]                         @ 
        strh    ip, [rGSU, #34]                          @ 
        strh    rR15, [rGSU, #30]                        @ 
        ldrb    rPIPE, [r1, rR15]                        @ 
        ldr     rR15, [rGSU, #404]                       @ 
        add     rSREG, rGSU, #0                          @ 
        strb    r2, [rR15, ip]                           @ 
        ldrh    rR15, [rGSU, #34]                        @ 
        ldr     r1, [rGSU, #404]                         @ 
        add     rR15, rR15, #1                           @ 
        lsr     r2, r2, #8                               @ 
        uxth    rR15, rR15                               @ 
        strb    r2, [r1, rR15]                           @ 
        ldrh    rR15, [rGSU, #30]                        @ 
        mov     rDREG, rSREG                             @ 
        add     rR15, rR15, #1                           @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        strh    rR15, [rGSU, #30]                        @ 
        b       loop_head                                @ 
handle_fx_or_i:
        ldrh    r2, [rGSU, #30]                          @ 
        ldrh    rR15, [rSREG]                            @ 
        add     r2, r2, #1                               @ 
        strh    r2, [rGSU, #30]                          @ 
        add     rR15, rR15, rR15, lsl #16                @ 
        msr     cpsr_f, rARM                             @ 
        orrs    rR15, rR15, vLow                         @ 
        mrs     rARM, cpsr                               @ 
        strh    rR15, [rDREG]                            @ 
        add     rR15, rGSU, #28                          @ 
        cmp     rDREG, rR15                              @ 
        ldrheq  rR15, [rGSU, #28]                        @ 
        ldreq   r2, [rGSU, #408]                         @ 
        add     rSREG, rGSU, #0                          @ 
        ldrbeq  rR15, [r2, rR15]                         @ 
        mov     rDREG, rSREG                             @ 
        strbeq  rR15, [rGSU, #38]                        @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        b       loop_head                                @ 
handle_fx_ramb:
        ldrh    r2, [rSREG]                              @ 
        add     rR15, rR15, #1                           @ 
        strh    rR15, [rGSU, #30]                        @ 
        and     rR15, r2, #3                             @ 
        strb    rR15, [rGSU, #41]                        @ 
        add     rR15, rR15, #104                         @ 
        ldr     rR15, [rGSU, rR15, lsl #2]               @ 
        add     rSREG, rGSU, #0                          @ 
        str     rR15, [rGSU, #404]                       @ 
        mov     rDREG, rSREG                             @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        b       loop_head                                @ 
handle_fx_getbl:
        add     r2, rR15, #1                             @ 
        ldrh    rR15, [rSREG]                            @ 
        strh    r2, [rGSU, #30]                          @ 
        ldrb    r2, [rGSU, #38]                          @ 
        and     rR15, rR15, #65280                       @ 
        orr     rR15, rR15, r2                           @ 
        strh    rR15, [rDREG]                            @ 
        add     rR15, rGSU, #28                          @ 
        cmp     rDREG, rR15                              @ 
        ldrheq  rR15, [rGSU, #28]                        @ 
        ldreq   r2, [rGSU, #408]                         @ 
        add     rSREG, rGSU, #0                          @ 
        ldrbeq  rR15, [r2, rR15]                         @ 
        mov     rDREG, rSREG                             @ 
        strbeq  rR15, [rGSU, #38]                        @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        b       loop_head                                @ 
handle_fx_sm_r:
        lsl     vLow, vLow, #1                           @ 
        ldrh    r2, [rGSU, vLow]                         @ 
        add     vLow, rR15, #1                           @ 
        uxth    vLow, vLow                               @ 
        strh    ip, [rGSU, #34]                          @ 
        strh    vLow, [rGSU, #30]                        @ 
        ldrb    rPIPE, [r1, vLow]                        @ 
        add     rR15, rR15, #2                           @ 
        orr     ip, ip, rPIPE, lsl #8                    @ 
        uxth    rR15, rR15                               @ 
        strh    rR15, [rGSU, #30]                        @ 
        strh    ip, [rGSU, #34]                          @ 
        ldrb    rPIPE, [r1, rR15]                        @ 
        ldr     rR15, [rGSU, #404]                       @ 
        add     rSREG, rGSU, #0                          @ 
        strb    r2, [rR15, ip]                           @ 
        ldrh    rR15, [rGSU, #34]                        @ 
        ldr     r1, [rGSU, #404]                         @ 
        lsr     r2, r2, #8                               @ 
        eor     rR15, rR15, #1                           @ 
        strb    r2, [r1, rR15]                           @ 
        ldrh    rR15, [rGSU, #30]                        @ 
        mov     rDREG, rSREG                             @ 
        add     rR15, rR15, #1                           @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        strh    rR15, [rGSU, #30]                        @ 
        b       loop_head                                @ 
handle_fx_adc_i:
        ldrh    rR15, [rGSU, #30]                        @ 
        ldrh    r2, [rSREG]                              @ 
        add     rR15, rR15, #1                           @ 
        msr     cpsr_f, rARM                             @ 
        lsl     rARM, r2, #16                            @ 
        orrcs   rARM, rARM, #32768                       @ 
        orrcs   vLow, vLow, #-2147483648                 @ 
        adds    vLow, rARM, vLow, ror #16                @ 
        mrs     rARM, cpsr                               @ 
        lsr     vLow, vLow, #16                          @ 
        strh    rR15, [rGSU, #30]                        @ 
        strh    vLow, [rDREG]                            @ 
        add     rR15, rGSU, #28                          @ 
        cmp     rDREG, rR15                              @ 
        ldrheq  rR15, [rGSU, #28]                        @ 
        ldreq   r2, [rGSU, #408]                         @ 
        add     rSREG, rGSU, #0                          @ 
        ldrbeq  rR15, [r2, rR15]                         @ 
        mov     rDREG, rSREG                             @ 
        strbeq  rR15, [rGSU, #38]                        @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        b       loop_head                                @ 
handle_fx_cmp_r:
        ldrh    rR15, [rSREG]                            @ 
        lsl     vLow, vLow, #1                           @ 
        ldrh    rARM, [rGSU, vLow]                       @ 
        lsl     rR15, rR15, #16                          @ 
        cmp     rR15, rARM, lsl #16                      @ 
        mrs     rARM, cpsr                               @ 
        ldrh    rR15, [rGSU, #30]                        @ 
        add     rSREG, rGSU, #0                          @ 
        add     rR15, rR15, #1                           @ 
        mov     rDREG, rSREG                             @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        strh    rR15, [rGSU, #30]                        @ 
        b       loop_head                                @ 
handle_fx_bic_i:
        ldrh    r2, [rGSU, #30]                          @ 
        ldrh    rR15, [rSREG]                            @ 
        add     r2, r2, #1                               @ 
        strh    r2, [rGSU, #30]                          @ 
        add     vLow, vLow, vLow, lsl #16                @ 
        add     rR15, rR15, rR15, lsl #16                @ 
        msr     cpsr_f, rARM                             @ 
        bics    rR15, rR15, vLow                         @ 
        mrs     rARM, cpsr                               @ 
        strh    rR15, [rDREG]                            @ 
        add     rR15, rGSU, #28                          @ 
        cmp     rDREG, rR15                              @ 
        ldrheq  rR15, [rGSU, #28]                        @ 
        ldreq   r2, [rGSU, #408]                         @ 
        add     rSREG, rGSU, #0                          @ 
        ldrbeq  rR15, [r2, rR15]                         @ 
        mov     rDREG, rSREG                             @ 
        strbeq  rR15, [rGSU, #38]                        @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        b       loop_head                                @ 
handle_fx_umult_i:
        ldrb    rR15, [rSREG]                            @ 
        ldrh    r2, [rGSU, #30]                          @ 
        smulbb  rR15, rR15, vLow                         @ 
        msr     cpsr_f, rARM                             @ 
        movs    rARM, rR15                               @ 
        mrs     rARM, cpsr                               @ 
        add     rSREG, rGSU, #0                          @ 
        add     r2, r2, #1                               @ 
        strh    r2, [rGSU, #30]                          @ 
        strh    rR15, [rDREG]                            @ 
        add     rR15, rGSU, #28                          @ 
        cmp     rDREG, rR15                              @ 
        ldrheq  rR15, [rGSU, #28]                        @ 
        ldreq   r2, [rGSU, #408]                         @ 
        mov     rDREG, rSREG                             @ 
        ldrbeq  rR15, [r2, rR15]                         @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        strbeq  rR15, [rGSU, #38]                        @ 
        b       loop_head                                @ 
handle_fx_xor_i:
        ldrh    r2, [rGSU, #30]                          @ 
        ldrh    rR15, [rSREG]                            @ 
        add     r2, r2, #1                               @ 
        strh    r2, [rGSU, #30]                          @ 
        add     vLow, vLow, vLow, lsl #16                @ 
        add     rR15, rR15, rR15, lsl #16                @ 
        msr     cpsr_f, rARM                             @ 
        eors    rR15, rR15, vLow                         @ 
        mrs     rARM, cpsr                               @ 
        strh    rR15, [rDREG]                            @ 
        add     rR15, rGSU, #28                          @ 
        cmp     rDREG, rR15                              @ 
        ldrheq  rR15, [rGSU, #28]                        @ 
        ldreq   r2, [rGSU, #408]                         @ 
        add     rSREG, rGSU, #0                          @ 
        ldrbeq  rR15, [r2, rR15]                         @ 
        mov     rDREG, rSREG                             @ 
        strbeq  rR15, [rGSU, #38]                        @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        b       loop_head                                @ 
handle_fx_romb:
        ldrh    r2, [rSREG]                              @ 
        add     rR15, rR15, #1                           @ 
        strh    rR15, [rGSU, #30]                        @ 
        and     rR15, r2, #127                           @ 
        strb    rR15, [rGSU, #40]                        @ 
        add     rR15, rR15, #108                         @ 
        ldr     rR15, [rGSU, rR15, lsl #2]               @ 
        add     rSREG, rGSU, #0                          @ 
        str     rR15, [rGSU, #408]                       @ 
        mov     rDREG, rSREG                             @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        b       loop_head                                @ 
.L131:
        add     rR15, rR15, #1                           @ 
        strh    rR15, [rGSU, #30]                        @ 
        add     rSREG, rGSU, vLow, lsl #1                @ 
        b       loop_head                                @ 
.L86:
        add     rR15, rR15, #1                           @ 
        strh    rR15, [rGSU, #30]                        @ 
        add     rDREG, rGSU, #30                         @ 
        b       loop_head                                @ 
.L241:
        ldrh    r2, [rSREG]                              @ 
        ldr     r1, [rGSU, #408]                         @ 
        strh    r2, [rGSU, #28]                          @ 
        ldrb    r2, [r1, r2]                             @ 
        add     rSREG, rGSU, #0                          @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        mov     rDREG, rSREG                             @ 
        strb    r2, [rGSU, #38]                          @ 
        b       .L84                                     @ 
.L237:
        eor     ip, r1, rR15                             @ 
        tst     ip, #1                                   @ 
        lsrne   r2, r2, #4                               @ 
        movne   ip, r2                                   @ 
        bne     .L17                                     @ 
        b       .L15                                     @ 
.L239:
        and     ip, r1, #15                              @ 
        orrs    vLow, vLow, ip                           @ 
        bne     .L40                                     @ 
        b       loop_head                                @ 
.L238:
        eor     ip, rR15, r1                             @ 
        tst     ip, #1                                   @ 
        lsrne   r2, r2, #4                               @ 
        movne   ip, r2                                   @ 
        bne     .L27                                     @ 
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
