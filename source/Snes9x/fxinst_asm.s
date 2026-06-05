#define vLow   r0
#define rR15   r2
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
        push    {rGSU, rVCNT, rGOTO, lr}                 @ 
        sub     sp, sp, #8                               @ 
        push    {rSTAT, rARM, rPIPE, rSREG, rDREG, r11}  @ 
        ldr     rGSU, .L242                              @ 
        sub     rVCNT, vLow, #1                          @ 
        ldr     r3, [rGSU, #120]                         @ 
        ldr     rGOTO, .L242+4                           @ 
        cmp     r3, #3                                   @ 
        ldrls   rR15, .L242+8                            @ 
        ldrhi   r3, .L242+12                             @ 
        addls   r1, rR15, r3, lsl #3                     @ 
        ldrhi   rR15, .L242+16                           @ 
        ldrls   rR15, [rR15, r3, lsl #3]                 @ 
        ldrls   r3, [r1, #4]                             @ 
        ldrh    r1, [rGSU, #28]                          @ 
        cmp     vLow, #0                                 @ 
        ldr     vLow, [rGSU, #408]                       @ 
        ldrb    rSREG, [rGSU, #61]                       @ 
        ldrb    rDREG, [rGSU, #60]                       @ 
        ldrb    r1, [vLow, r1]                           @ 
        ldrh    rSTAT, [rGSU, #64]                       @ 
        ldr     rARM, [rGSU, #68]                        @ 
        ldrb    rPIPE, [rGSU, #62]                       @ 
        add     rSREG, rGSU, rSREG, lsl #1               @ 
        add     rDREG, rGSU, rDREG, lsl #1               @ 
        strb    r1, [rGSU, #38]                          @ 
        str     rR15, [rGOTO, #2352]                     @ 
        str     rR15, [rGOTO, #304]                      @ 
        str     r3, [rGOTO, #3376]                       @ 
        str     r3, [rGOTO, #1328]                       @ 
        beq     loop_end                                 @ 
loop_dispatch:
        ldr     r1, [rGSU, #412]                         @ 
        ldrh    r3, [rGSU, #30]                          @ 
        uxtb    rPIPE, rPIPE                             @ 
        ldrb    ip, [r1, r3]                             @ 
        and     rR15, rSTAT, #768                        @ 
        orr     rR15, rPIPE, rR15                        @ 
        and     vLow, rPIPE, #15                         @ 
        mov     rPIPE, ip                                @ 
        ldr     pc, [rGOTO, rR15, lsl #2]                @ 
handle_fx_getbs:
        add     r3, r3, #1                               @ 
        strh    r3, [rGSU, #30]                          @ 
        ldrsb   r3, [rGSU, #38]                          @ 
        add     rSREG, rGSU, #0                          @ 
        strh    r3, [rDREG]                              @ 
        add     r3, rGSU, #28                            @ 
        cmp     rDREG, r3                                @ 
        ldrheq  r3, [rGSU, #28]                          @ 
        ldreq   rR15, [rGSU, #408]                       @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        ldrbeq  r3, [rR15, r3]                           @ 
        mov     rDREG, rSREG                             @ 
        strbeq  r3, [rGSU, #38]                          @ 
loop_head:
        subs    rVCNT, rVCNT, #1                         @ 
        bcs     loop_dispatch                            @ 
loop_end:
        sub     r3, rSREG, rGSU                          @ 
        asr     r3, r3, #1                               @ 
        strb    r3, [rGSU, #61]                          @ 
        sub     r3, rDREG, rGSU                          @ 
        asr     r3, r3, #1                               @ 
        strh    rSTAT, [rGSU, #64]                       @ 
        str     rARM, [rGSU, #68]                        @ 
        strb    rPIPE, [rGSU, #62]                       @ 
        strb    r3, [rGSU, #60]                          @ 
        pop     {rSTAT, rARM, rPIPE, rSREG, rDREG, r11}  @ 
        add     sp, sp, #8                               @ 
        pop     {rGSU, rVCNT, rGOTO, pc}                 @ 
handle_fx_stop:
        add     r3, r3, #1                               @ 
        strh    r3, [rGSU, #30]                          @ 
        mov     r3, #0                                   @ 
        add     rSREG, rGSU, r3                          @ 
        ldr     rR15, [rGSU, #100]                       @ 
        bic     rSTAT, rSTAT, #32                        @ 
        ldrsb   rR15, [rR15, #55]                        @ 
        mov     rPIPE, #1                                @ 
        cmp     rR15, #0                                 @ 
        orrge   rSTAT, rSTAT, #32768                     @ 
        mov     rDREG, rSREG                             @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        strb    r3, [rGSU, #36]                          @ 
        b       loop_end                                 @ 
handle_fx_plot_2bit:
        add     r3, r3, #1                               @ 
        ldrh    r1, [rGSU, #2]                           @ 
        ldr     rR15, [rGSU, #388]                       @ 
        strh    r3, [rGSU, #30]                          @ 
        ldrb    r3, [rGSU, #4]                           @ 
        add     rSREG, rGSU, #0                          @ 
        cmp     r3, rR15                                 @ 
        add     rR15, r1, #1                             @ 
        mov     rDREG, rSREG                             @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        strh    rR15, [rGSU, #2]                         @ 
        bcs     loop_head                                @ 
        ldrb    vLow, [rGSU, #36]                        @ 
        ldrb    rR15, [rGSU, #37]                        @ 
        tst     vLow, #2                                 @ 
        uxtb    r1, r1                                   @ 
        bne     .L237                                    @ 
.L15:
        and     ip, rR15, #15                            @ 
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
        lsr     r1, r3, #3                               @ 
        ldr     vLow, [vLow, #260]                       @ 
        add     r1, rGSU, r1, lsl #2                     @ 
        lsl     r3, r3, #1                               @ 
        ldr     r1, [r1, #132]                           @ 
        and     r3, r3, #14                              @ 
        add     r3, r3, vLow                             @ 
        ldrb    vLow, [r1, r3]                           @ 
        tst     rR15, #1                                 @ 
        str     vLow, [sp, #4]                           @ 
        add     vLow, r1, r3                             @ 
        str     vLow, [sp]                               @ 
        ldr     vLow, [sp, #4]                           @ 
        orrne   vLow, vLow, ip                           @ 
        biceq   vLow, vLow, ip                           @ 
        strb    vLow, [r1, r3]                           @ 
        ldr     r3, [sp]                                 @ 
        tst     rR15, #2                                 @ 
        ldrb    r3, [r3, #1]                             @ 
        ldr     rR15, [sp]                               @ 
        orrne   r3, ip, r3                               @ 
        biceq   r3, r3, ip                               @ 
        strb    r3, [rR15, #1]                           @ 
        b       loop_head                                @ 
handle_fx_rpix_2bit:
        add     r3, r3, #1                               @ 
        ldr     rR15, [rGSU, #388]                       @ 
        strh    r3, [rGSU, #30]                          @ 
        ldrb    r3, [rGSU, #4]                           @ 
        add     r1, rGSU, #0                             @ 
        cmp     r3, rR15                                 @ 
        mov     rSREG, r1                                @ 
        mov     rDREG, r1                                @ 
        ldrh    rR15, [rGSU, #2]                         @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        bcs     loop_head                                @ 
        mov     vLow, #128                               @ 
        uxtb    rR15, rR15                               @ 
        lsr     ip, rR15, #3                             @ 
        and     rR15, rR15, #7                           @ 
        asr     vLow, vLow, rR15                         @ 
        uxtb    rR15, vLow                               @ 
        add     ip, rGSU, ip, lsl #2                     @ 
        lsr     vLow, r3, #3                             @ 
        ldr     ip, [ip, #260]                           @ 
        add     vLow, rGSU, vLow, lsl #2                 @ 
        lsl     r3, r3, #1                               @ 
        ldr     vLow, [vLow, #132]                       @ 
        and     r3, r3, #14                              @ 
        add     r3, r3, ip                               @ 
        add     ip, vLow, r3                             @ 
        ldrb    vLow, [vLow, r3]                         @ 
        ldrb    r3, [ip, #1]                             @ 
        str     rR15, [sp]                               @ 
        str     r3, [sp, #4]                             @ 
        ldr     ip, [sp]                                 @ 
        mov     r3, #1                                   @ 
        mov     rR15, #0                                 @ 
        tst     ip, vLow                                 @ 
        orrne   rR15, rR15, r3, lsl #0                   @ 
        ldr     vLow, [sp, #4]                           @ 
        tst     ip, vLow                                 @ 
        orrne   rR15, rR15, r3, lsl #1                   @ 
        add     r3, rGSU, #28                            @ 
        strh    rR15, [r1]                               @ 
        cmp     r1, r3                                   @ 
        ldrheq  r3, [rGSU, #28]                          @ 
        ldreq   rR15, [rGSU, #408]                       @ 
        ldrbeq  r3, [rR15, r3]                           @ 
        strbeq  r3, [rGSU, #38]                          @ 
        b       loop_head                                @ 
handle_fx_plot_4bit:
        add     r3, r3, #1                               @ 
        ldr     rR15, [rGSU, #388]                       @ 
        ldrb    r1, [rGSU, #4]                           @ 
        strh    r3, [rGSU, #30]                          @ 
        ldrh    r3, [rGSU, #2]                           @ 
        cmp     r1, rR15                                 @ 
        add     rR15, r3, #1                             @ 
        add     rSREG, rGSU, #0                          @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        mov     rDREG, rSREG                             @ 
        strh    rR15, [rGSU, #2]                         @ 
        bcs     loop_head                                @ 
        ldrb    vLow, [rGSU, #36]                        @ 
        ldrb    rR15, [rGSU, #37]                        @ 
        tst     vLow, #2                                 @ 
        uxtb    r3, r3                                   @ 
        bne     .L238                                    @ 
.L25:
        and     ip, rR15, #15                            @ 
.L27:
        and     vLow, vLow, #1                           @ 
        orrs    vLow, ip, vLow                           @ 
        beq     loop_head                                @ 
        mov     vLow, #128                               @ 
        lsr     ip, r3, #3                               @ 
        and     r3, r3, #7                               @ 
        add     ip, rGSU, ip, lsl #2                     @ 
        asr     r3, vLow, r3                             @ 
        lsr     vLow, r1, #3                             @ 
        ldr     ip, [ip, #260]                           @ 
        add     vLow, rGSU, vLow, lsl #2                 @ 
        lsl     r1, r1, #1                               @ 
        ldr     vLow, [vLow, #132]                       @ 
        and     r1, r1, #14                              @ 
        add     ip, r1, ip                               @ 
        uxtb    r3, r3                                   @ 
        ldrb    r1, [vLow, ip]                           @ 
        str     r3, [sp]                                 @ 
        mov     r3, vLow                                 @ 
        str     vLow, [sp, #4]                           @ 
        mov     vLow, r1                                 @ 
        add     r1, r3, ip                               @ 
        ldr     r3, [sp]                                 @ 
        tst     rR15, #1                                 @ 
        orrne   vLow, vLow, r3                           @ 
        biceq   vLow, vLow, r3                           @ 
        ldr     r3, [sp, #4]                             @ 
        tst     rR15, #2                                 @ 
        strb    vLow, [r3, ip]                           @ 
        ldrb    vLow, [r1, #1]                           @ 
        ldr     r3, [sp]                                 @ 
        orrne   vLow, r3, vLow                           @ 
        biceq   vLow, vLow, r3                           @ 
        strb    vLow, [r1, #1]                           @ 
        ldr     r3, [sp]                                 @ 
        ldrb    vLow, [r1, #16]                          @ 
        tst     rR15, #4                                 @ 
        orrne   vLow, r3, vLow                           @ 
        biceq   vLow, vLow, r3                           @ 
        ldr     r3, [sp]                                 @ 
        tst     rR15, #8                                 @ 
        ldrb    rR15, [r1, #17]                          @ 
        strb    vLow, [r1, #16]                          @ 
        orrne   r3, r3, rR15                             @ 
        biceq   r3, rR15, r3                             @ 
        strb    r3, [r1, #17]                            @ 
        b       loop_head                                @ 
handle_fx_rpix_4bit:
        add     rR15, rGSU, #0                           @ 
        mov     rSREG, rR15                              @ 
        add     r3, r3, #1                               @ 
        ldrb    r1, [rGSU, #4]                           @ 
        strh    r3, [rGSU, #30]                          @ 
        ldr     r3, [rGSU, #388]                         @ 
        mov     rDREG, rSREG                             @ 
        cmp     r1, r3                                   @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        ldrh    r3, [rGSU, #2]                           @ 
        str     rSREG, [sp]                              @ 
        bcs     loop_head                                @ 
        mov     ip, #0                                   @ 
        mov     rR15, #128                               @ 
        uxtb    r3, r3                                   @ 
        lsr     vLow, r3, #3                             @ 
        add     vLow, rGSU, vLow, lsl #2                 @ 
        ldr     vLow, [vLow, #260]                       @ 
        and     r3, r3, #7                               @ 
        str     vLow, [sp, #4]                           @ 
        lsr     vLow, r1, #3                             @ 
        add     vLow, rGSU, vLow, lsl #2                 @ 
        asr     rR15, rR15, r3                           @ 
        lsl     r1, r1, #1                               @ 
        mov     r3, ip                                   @ 
        ldr     ip, [vLow, #132]                         @ 
        ldr     vLow, [sp, #4]                           @ 
        and     r1, r1, #14                              @ 
        add     r1, r1, vLow                             @ 
        add     vLow, ip, r1                             @ 
        uxtb    rR15, rR15                               @ 
        ldrb    ip, [ip, r1]                             @ 
        mov     r1, #1                                   @ 
        tst     rR15, ip                                 @ 
        orrne   r3, r3, r1, lsl #0                       @ 
        ldrb    ip, [vLow, #1]                           @ 
        tst     rR15, ip                                 @ 
        orrne   r3, r3, r1, lsl #1                       @ 
        ldrb    ip, [vLow, #16]                          @ 
        ldrb    vLow, [vLow, #17]                        @ 
        tst     rR15, ip                                 @ 
        orrne   r3, r3, r1, lsl #2                       @ 
        tst     rR15, vLow                               @ 
        orrne   r3, r3, r1, lsl #3                       @ 
        mov     rR15, rDREG                              @ 
        strh    r3, [rDREG]                              @ 
        add     r3, rGSU, #28                            @ 
        cmp     rDREG, r3                                @ 
        ldrheq  r3, [rGSU, #28]                          @ 
        ldreq   rR15, [rGSU, #408]                       @ 
        ldrbeq  r3, [rR15, r3]                           @ 
        strbeq  r3, [rGSU, #38]                          @ 
        b       loop_head                                @ 
handle_fx_plot_8bit:
        add     r3, r3, #1                               @ 
        ldrh    rR15, [rGSU, #2]                         @ 
        ldr     r1, [rGSU, #388]                         @ 
        strh    r3, [rGSU, #30]                          @ 
        ldrb    r3, [rGSU, #4]                           @ 
        add     rSREG, rGSU, #0                          @ 
        cmp     r3, r1                                   @ 
        add     r1, rR15, #1                             @ 
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
        uxtb    rR15, rR15                               @ 
        lsr     ip, rR15, #3                             @ 
        and     rR15, rR15, #7                           @ 
        add     ip, rGSU, ip, lsl #2                     @ 
        asr     rR15, vLow, rR15                         @ 
        lsr     vLow, r3, #3                             @ 
        ldr     ip, [ip, #260]                           @ 
        add     vLow, rGSU, vLow, lsl #2                 @ 
        lsl     r3, r3, #1                               @ 
        ldr     vLow, [vLow, #132]                       @ 
        and     r3, r3, #14                              @ 
        add     ip, r3, ip                               @ 
        uxtb    rR15, rR15                               @ 
        ldrb    r3, [vLow, ip]                           @ 
        str     rR15, [sp]                               @ 
        mov     rR15, vLow                               @ 
        str     vLow, [sp, #4]                           @ 
        mov     vLow, r3                                 @ 
        add     r3, rR15, ip                             @ 
        ldr     rR15, [sp]                               @ 
        tst     r1, #1                                   @ 
        orrne   vLow, vLow, rR15                         @ 
        biceq   vLow, vLow, rR15                         @ 
        ldr     rR15, [sp, #4]                           @ 
        tst     r1, #2                                   @ 
        strb    vLow, [rR15, ip]                         @ 
        ldrb    vLow, [r3, #1]                           @ 
        ldr     rR15, [sp]                               @ 
        orrne   vLow, rR15, vLow                         @ 
        biceq   vLow, vLow, rR15                         @ 
        strb    vLow, [r3, #1]                           @ 
        ldr     rR15, [sp]                               @ 
        ldrb    vLow, [r3, #16]                          @ 
        tst     r1, #4                                   @ 
        orrne   vLow, rR15, vLow                         @ 
        biceq   vLow, vLow, rR15                         @ 
        strb    vLow, [r3, #16]                          @ 
        ldr     rR15, [sp]                               @ 
        ldrb    vLow, [r3, #17]                          @ 
        tst     r1, #8                                   @ 
        orrne   vLow, rR15, vLow                         @ 
        biceq   vLow, vLow, rR15                         @ 
        strb    vLow, [r3, #17]                          @ 
        ldr     rR15, [sp]                               @ 
        ldrb    vLow, [r3, #32]                          @ 
        tst     r1, #16                                  @ 
        orrne   vLow, rR15, vLow                         @ 
        biceq   vLow, vLow, rR15                         @ 
        strb    vLow, [r3, #32]                          @ 
        ldr     rR15, [sp]                               @ 
        ldrb    vLow, [r3, #33]                          @ 
        tst     r1, #32                                  @ 
        orrne   vLow, rR15, vLow                         @ 
        biceq   vLow, vLow, rR15                         @ 
        strb    vLow, [r3, #33]                          @ 
        ldr     rR15, [sp]                               @ 
        ldrb    vLow, [r3, #48]                          @ 
        tst     r1, #64                                  @ 
        orrne   vLow, rR15, vLow                         @ 
        biceq   vLow, vLow, rR15                         @ 
        ldr     rR15, [sp]                               @ 
        tst     r1, #128                                 @ 
        ldrb    r1, [r3, #49]                            @ 
        strb    vLow, [r3, #48]                          @ 
        orrne   rR15, rR15, r1                           @ 
        biceq   rR15, r1, rR15                           @ 
        strb    rR15, [r3, #49]                          @ 
        b       loop_head                                @ 
handle_fx_rpix_8bit:
        add     r3, r3, #1                               @ 
        ldrb    r1, [rGSU, #4]                           @ 
        strh    r3, [rGSU, #30]                          @ 
        ldr     r3, [rGSU, #388]                         @ 
        add     vLow, rGSU, #0                           @ 
        cmp     r1, r3                                   @ 
        mov     rSREG, vLow                              @ 
        mov     rDREG, vLow                              @ 
        ldrh    rR15, [rGSU, #2]                         @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        bcs     loop_head                                @ 
        mov     ip, #128                                 @ 
        uxtb    rR15, rR15                               @ 
        bic     r3, rARM, #1073741824                    @ 
        lsr     rARM, rR15, #3                           @ 
        and     rR15, rR15, #7                           @ 
        add     rARM, rGSU, rARM, lsl #2                 @ 
        asr     rR15, ip, rR15                           @ 
        lsr     ip, r1, #3                               @ 
        ldr     rARM, [rARM, #260]                       @ 
        add     ip, rGSU, ip, lsl #2                     @ 
        lsl     r1, r1, #1                               @ 
        ldr     ip, [ip, #132]                           @ 
        and     r1, r1, #14                              @ 
        add     rARM, r1, rARM                           @ 
        add     r1, ip, rARM                             @ 
        uxtb    rR15, rR15                               @ 
        ldrb    rARM, [ip, rARM]                         @ 
        str     r3, [sp]                                 @ 
        mov     ip, #1                                   @ 
        mov     r3, #0                                   @ 
        tst     rR15, rARM                               @ 
        orrne   r3, r3, ip, lsl #0                       @ 
        ldrb    rARM, [r1, #1]                           @ 
        tst     rR15, rARM                               @ 
        orrne   r3, r3, ip, lsl #1                       @ 
        ldrb    rARM, [r1, #16]                          @ 
        tst     rR15, rARM                               @ 
        orrne   r3, r3, ip, lsl #2                       @ 
        ldrb    rARM, [r1, #17]                          @ 
        tst     rR15, rARM                               @ 
        orrne   r3, r3, ip, lsl #3                       @ 
        ldrb    rARM, [r1, #32]                          @ 
        tst     rR15, rARM                               @ 
        orrne   r3, r3, ip, lsl #4                       @ 
        ldrb    rARM, [r1, #33]                          @ 
        tst     rR15, rARM                               @ 
        orrne   r3, r3, ip, lsl #5                       @ 
        ldrb    rARM, [r1, #48]                          @ 
        ldrb    r1, [r1, #49]                            @ 
        tst     rR15, rARM                               @ 
        orrne   r3, r3, ip, lsl #6                       @ 
        tst     rR15, r1                                 @ 
        orrne   r3, r3, ip, lsl #7                       @ 
        strh    r3, [vLow]                               @ 
        uxth    r3, r3                                   @ 
        cmp     r3, #0                                   @ 
        ldr     r3, [sp]                                 @ 
        mov     rARM, r3                                 @ 
        orreq   rARM, r3, #1073741824                    @ 
        add     r3, rGSU, #28                            @ 
        cmp     r3, vLow                                 @ 
        ldrheq  r3, [rGSU, #28]                          @ 
        ldreq   rR15, [rGSU, #408]                       @ 
        ldrbeq  r3, [rR15, r3]                           @ 
        strbeq  r3, [rGSU, #38]                          @ 
        b       loop_head                                @ 
handle_fx_nop:
        add     r3, r3, #1                               @ 
        add     rSREG, rGSU, #0                          @ 
        strh    r3, [rGSU, #30]                          @ 
        mov     rDREG, rSREG                             @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        b       loop_head                                @ 
handle_fx_cache:
        ldrh    r1, [rGSU, #32]                          @ 
        bic     rR15, r3, #15                            @ 
        cmp     r1, rR15                                 @ 
        uxth    rR15, rR15                               @ 
        beq     .L240                                    @ 
.L62:
        strh    rR15, [rGSU, #32]                        @ 
        mov     rR15, #0                                 @ 
        str     rR15, [rGSU, #72]                        @ 
        mov     rR15, #1                                 @ 
        strb    rR15, [rGSU, #1456]                      @ 
.L63:
        add     r3, r3, #1                               @ 
        add     rSREG, rGSU, #0                          @ 
        strh    r3, [rGSU, #30]                          @ 
        mov     rDREG, rSREG                             @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        b       loop_head                                @ 
handle_fx_lsr:
        ldrh    rR15, [rGSU, #30]                        @ 
        ldrh    r3, [rSREG]                              @ 
        add     rR15, rR15, #1                           @ 
        strh    rR15, [rGSU, #30]                        @ 
        msr     cpsr_f, rARM                             @ 
        lsrs    r3, r3, #1                               @ 
        mrs     rARM, cpsr                               @ 
        strh    r3, [rDREG]                              @ 
        add     r3, rGSU, #28                            @ 
        cmp     rDREG, r3                                @ 
        ldrheq  r3, [rGSU, #28]                          @ 
        ldreq   rR15, [rGSU, #408]                       @ 
        add     rSREG, rGSU, #0                          @ 
        ldrbeq  r3, [rR15, r3]                           @ 
        mov     rDREG, rSREG                             @ 
        strbeq  r3, [rGSU, #38]                          @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        b       loop_head                                @ 
handle_fx_rol:
        ldrh    rR15, [rGSU, #30]                        @ 
        ldrh    r3, [rSREG]                              @ 
        add     rR15, rR15, #1                           @ 
        msr     cpsr_f, rARM                             @ 
        lsl     r3, r3, #16                              @ 
        orrcs   r3, r3, #32768                           @ 
        lsls    r3, r3, #1                               @ 
        mrs     rARM, cpsr                               @ 
        lsr     r3, r3, #16                              @ 
        strh    rR15, [rGSU, #30]                        @ 
        strh    r3, [rDREG]                              @ 
        add     r3, rGSU, #28                            @ 
        cmp     rDREG, r3                                @ 
        ldrheq  r3, [rGSU, #28]                          @ 
        ldreq   rR15, [rGSU, #408]                       @ 
        add     rSREG, rGSU, #0                          @ 
        ldrbeq  r3, [rR15, r3]                           @ 
        mov     rDREG, rSREG                             @ 
        strbeq  r3, [rGSU, #38]                          @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        b       loop_head                                @ 
handle_fx_bra:
        add     r3, r3, #1                               @ 
        uxth    r3, r3                                   @ 
        sxtb    rR15, ip                                 @ 
        add     rR15, r3, rR15                           @ 
        ldrb    rPIPE, [r1, r3]                          @ 
        strh    rR15, [rGSU, #30]                        @ 
        b       loop_head                                @ 
handle_fx_bge:
        add     r3, r3, #1                               @ 
        uxth    rR15, r3                                 @ 
        ldrb    rPIPE, [r1, rR15]                        @ 
        sxtb    ip, ip                                   @ 
        msr     cpsr_f, rARM                             @ 
        addge   r3, r3, ip                               @ 
        addlt   r3, r3, #1                               @ 
        strh    r3, [rGSU, #30]                          @ 
        b       loop_head                                @ 
handle_fx_blt:
        add     r3, r3, #1                               @ 
        uxth    rR15, r3                                 @ 
        ldrb    rPIPE, [r1, rR15]                        @ 
        sxtb    ip, ip                                   @ 
        msr     cpsr_f, rARM                             @ 
        addlt   r3, r3, ip                               @ 
        addge   r3, r3, #1                               @ 
        strh    r3, [rGSU, #30]                          @ 
        b       loop_head                                @ 
handle_fx_bne:
        add     r3, r3, #1                               @ 
        uxth    rR15, r3                                 @ 
        ldrb    rPIPE, [r1, rR15]                        @ 
        sxtb    ip, ip                                   @ 
        msr     cpsr_f, rARM                             @ 
        addne   r3, r3, ip                               @ 
        addeq   r3, r3, #1                               @ 
        strh    r3, [rGSU, #30]                          @ 
        b       loop_head                                @ 
handle_fx_beq:
        add     r3, r3, #1                               @ 
        uxth    rR15, r3                                 @ 
        ldrb    rPIPE, [r1, rR15]                        @ 
        sxtb    ip, ip                                   @ 
        msr     cpsr_f, rARM                             @ 
        addeq   r3, r3, ip                               @ 
        addne   r3, r3, #1                               @ 
        strh    r3, [rGSU, #30]                          @ 
        b       loop_head                                @ 
handle_fx_bpl:
        add     r3, r3, #1                               @ 
        uxth    rR15, r3                                 @ 
        ldrb    rPIPE, [r1, rR15]                        @ 
        sxtb    ip, ip                                   @ 
        msr     cpsr_f, rARM                             @ 
        addpl   r3, r3, ip                               @ 
        addmi   r3, r3, #1                               @ 
        strh    r3, [rGSU, #30]                          @ 
        b       loop_head                                @ 
handle_fx_bmi:
        add     r3, r3, #1                               @ 
        uxth    rR15, r3                                 @ 
        ldrb    rPIPE, [r1, rR15]                        @ 
        sxtb    ip, ip                                   @ 
        msr     cpsr_f, rARM                             @ 
        addmi   r3, r3, ip                               @ 
        addpl   r3, r3, #1                               @ 
        strh    r3, [rGSU, #30]                          @ 
        b       loop_head                                @ 
handle_fx_bcc:
        add     r3, r3, #1                               @ 
        uxth    rR15, r3                                 @ 
        ldrb    rPIPE, [r1, rR15]                        @ 
        sxtb    ip, ip                                   @ 
        msr     cpsr_f, rARM                             @ 
        addcc   r3, r3, ip                               @ 
        addcs   r3, r3, #1                               @ 
        strh    r3, [rGSU, #30]                          @ 
        b       loop_head                                @ 
handle_fx_bcs:
        add     r3, r3, #1                               @ 
        uxth    rR15, r3                                 @ 
        ldrb    rPIPE, [r1, rR15]                        @ 
        sxtb    ip, ip                                   @ 
        msr     cpsr_f, rARM                             @ 
        addcs   r3, r3, ip                               @ 
        addcc   r3, r3, #1                               @ 
        strh    r3, [rGSU, #30]                          @ 
        b       loop_head                                @ 
handle_fx_bvc:
        add     r3, r3, #1                               @ 
        uxth    rR15, r3                                 @ 
        ldrb    rPIPE, [r1, rR15]                        @ 
        sxtb    ip, ip                                   @ 
        msr     cpsr_f, rARM                             @ 
        addvc   r3, r3, ip                               @ 
        addvs   r3, r3, #1                               @ 
        strh    r3, [rGSU, #30]                          @ 
        b       loop_head                                @ 
handle_fx_bvs:
        add     r3, r3, #1                               @ 
        uxth    rR15, r3                                 @ 
        ldrb    rPIPE, [r1, rR15]                        @ 
        sxtb    ip, ip                                   @ 
        msr     cpsr_f, rARM                             @ 
        addvs   r3, r3, ip                               @ 
        addvc   r3, r3, #1                               @ 
        strh    r3, [rGSU, #30]                          @ 
        b       loop_head                                @ 
handle_fx_to_r:
        tst     rSTAT, #4096                             @ 
        addeq   vLow, rGSU, vLow, lsl #1                 @ 
        beq     .L81                                     @ 
        ldrh    rR15, [rSREG]                            @ 
        lsl     vLow, vLow, #1                           @ 
        strh    rR15, [rGSU, vLow]                       @ 
        add     vLow, rGSU, #0                           @ 
        mov     rSREG, vLow                              @ 
        bic     rSTAT, rSTAT, #4864                      @ 
.L81:
        add     r3, r3, #1                               @ 
        mov     rDREG, vLow                              @ 
        strh    r3, [rGSU, #30]                          @ 
        b       loop_head                                @ 
handle_fx_to_r14:
        tst     rSTAT, #4096                             @ 
        bne     .L241                                    @ 
        add     rDREG, rGSU, #28                         @ 
.L84:
        add     r3, r3, #1                               @ 
        strh    r3, [rGSU, #30]                          @ 
        b       loop_head                                @ 
handle_fx_to_r15:
        tst     rSTAT, #4096                             @ 
        beq     .L86                                     @ 
        ldrh    r3, [rSREG]                              @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        add     rSREG, rGSU, #0                          @ 
        strh    r3, [rGSU, #30]                          @ 
        mov     rDREG, rSREG                             @ 
        b       loop_head                                @ 
handle_fx_with:
        add     rDREG, rGSU, vLow, lsl #1                @ 
        add     r3, r3, #1                               @ 
        mov     rSREG, rDREG                             @ 
        strh    r3, [rGSU, #30]                          @ 
        orr     rSTAT, rSTAT, #4096                      @ 
        b       loop_head                                @ 
handle_fx_stw_r:
        lsl     vLow, vLow, #1                           @ 
        ldrh    r3, [rGSU, vLow]                         @ 
        ldr     r1, [rGSU, #404]                         @ 
        strh    r3, [rGSU, #34]                          @ 
        ldrh    rR15, [rSREG]                            @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        strb    rR15, [r1, r3]                           @ 
        eor     r3, r3, #1                               @ 
        lsr     rR15, rR15, #8                           @ 
        strb    rR15, [r1, r3]                           @ 
        ldrh    r3, [rGSU, #30]                          @ 
        add     rSREG, rGSU, #0                          @ 
        add     r3, r3, #1                               @ 
        mov     rDREG, rSREG                             @ 
        strh    r3, [rGSU, #30]                          @ 
        b       loop_head                                @ 
handle_fx_loop:
        ldrh    r3, [rGSU, #24]                          @ 
        add     rSREG, rGSU, #0                          @ 
        sub     r3, r3, #1                               @ 
        msr     cpsr_f, rARM                             @ 
        lsl     rARM, r3, #16                            @ 
        movs    rARM, rARM                               @ 
        mrs     rARM, cpsr                               @ 
        cmp     r3, #0                                   @ 
        strh    r3, [rGSU, #24]                          @ 
        ldrheq  r3, [rGSU, #30]                          @ 
        ldrhne  r3, [rGSU, #26]                          @ 
        addeq   r3, r3, #1                               @ 
        uxtheq  r3, r3                                   @ 
        mov     rDREG, rSREG                             @ 
        strh    r3, [rGSU, #30]                          @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        b       loop_head                                @ 
handle_fx_alt1:
        add     r3, r3, #1                               @ 
        bic     rSTAT, rSTAT, #4096                      @ 
        strh    r3, [rGSU, #30]                          @ 
        orr     rSTAT, rSTAT, #256                       @ 
        b       loop_head                                @ 
handle_fx_alt2:
        add     r3, r3, #1                               @ 
        bic     rSTAT, rSTAT, #4096                      @ 
        strh    r3, [rGSU, #30]                          @ 
        orr     rSTAT, rSTAT, #512                       @ 
        b       loop_head                                @ 
handle_fx_alt3:
        add     r3, r3, #1                               @ 
        bic     rSTAT, rSTAT, #4096                      @ 
        strh    r3, [rGSU, #30]                          @ 
        orr     rSTAT, rSTAT, #768                       @ 
        b       loop_head                                @ 
handle_fx_ldw_r:
        lsl     vLow, vLow, #1                           @ 
        ldrh    rR15, [rGSU, vLow]                       @ 
        ldr     r1, [rGSU, #404]                         @ 
        strh    rR15, [rGSU, #34]                        @ 
        eor     ip, rR15, #1                             @ 
        add     vLow, r3, #1                             @ 
        ldrb    r3, [r1, rR15]                           @ 
        ldrb    rR15, [r1, ip]                           @ 
        strh    vLow, [rGSU, #30]                        @ 
        orr     r3, r3, rR15, lsl #8                     @ 
        strh    r3, [rDREG]                              @ 
        add     r3, rGSU, #28                            @ 
        cmp     rDREG, r3                                @ 
        ldrheq  r3, [rGSU, #28]                          @ 
        ldreq   rR15, [rGSU, #408]                       @ 
        add     rSREG, rGSU, #0                          @ 
        ldrbeq  r3, [rR15, r3]                           @ 
        mov     rDREG, rSREG                             @ 
        strbeq  r3, [rGSU, #38]                          @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        b       loop_head                                @ 
handle_fx_swap:
        add     rR15, r3, #1                             @ 
        ldrh    r3, [rSREG]                              @ 
        strh    rR15, [rGSU, #30]                        @ 
        rev16   r3, r3                                   @ 
        add     rR15, rGSU, #28                          @ 
        strh    r3, [rDREG]                              @ 
        orr     r1, r3, r3, lsl #16                      @ 
        msr     cpsr_f, rARM                             @ 
        movs    rARM, r1                                 @ 
        mrs     rARM, cpsr                               @ 
        cmp     rDREG, rR15                              @ 
        ldrheq  r3, [rGSU, #28]                          @ 
        ldreq   rR15, [rGSU, #408]                       @ 
        add     rSREG, rGSU, #0                          @ 
        ldrbeq  r3, [rR15, r3]                           @ 
        mov     rDREG, rSREG                             @ 
        strbeq  r3, [rGSU, #38]                          @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        b       loop_head                                @ 
handle_fx_color:
        ldrb    r1, [rGSU, #36]                          @ 
        ldrb    rR15, [rSREG]                            @ 
        tst     r1, #4                                   @ 
        andne   vLow, rR15, #240                         @ 
        orrne   rR15, vLow, rR15, lsr #4                 @ 
        tst     r1, #8                                   @ 
        ldrbne  r1, [rGSU, #37]                          @ 
        andne   rR15, rR15, #15                          @ 
        bicne   r1, r1, #15                              @ 
        orrne   rR15, r1, rR15                           @ 
        add     r3, r3, #1                               @ 
        add     rSREG, rGSU, #0                          @ 
        strb    rR15, [rGSU, #37]                        @ 
        mov     rDREG, rSREG                             @ 
        strh    r3, [rGSU, #30]                          @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        b       loop_head                                @ 
handle_fx_not:
        ldrh    rR15, [rGSU, #30]                        @ 
        ldrh    r3, [rSREG]                              @ 
        add     rR15, rR15, #1                           @ 
        strh    rR15, [rGSU, #30]                        @ 
        add     r3, r3, r3, lsl #16                      @ 
        msr     cpsr_f, rARM                             @ 
        mvns    r3, r3                                   @ 
        mrs     rARM, cpsr                               @ 
        strh    r3, [rDREG]                              @ 
        add     r3, rGSU, #28                            @ 
        cmp     rDREG, r3                                @ 
        ldrheq  r3, [rGSU, #28]                          @ 
        ldreq   rR15, [rGSU, #408]                       @ 
        add     rSREG, rGSU, #0                          @ 
        ldrbeq  r3, [rR15, r3]                           @ 
        mov     rDREG, rSREG                             @ 
        strbeq  r3, [rGSU, #38]                          @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        b       loop_head                                @ 
handle_fx_add_r:
        ldrh    r3, [rSREG]                              @ 
        ldrh    rR15, [rGSU, #30]                        @ 
        lsl     vLow, vLow, #1                           @ 
        ldrh    rARM, [rGSU, vLow]                       @ 
        add     rR15, rR15, #1                           @ 
        lsl     r3, r3, #16                              @ 
        adds    r3, r3, rARM, lsl #16                    @ 
        mrs     rARM, cpsr                               @ 
        lsr     r3, r3, #16                              @ 
        strh    rR15, [rGSU, #30]                        @ 
        strh    r3, [rDREG]                              @ 
        add     r3, rGSU, #28                            @ 
        cmp     rDREG, r3                                @ 
        ldrheq  r3, [rGSU, #28]                          @ 
        ldreq   rR15, [rGSU, #408]                       @ 
        add     rSREG, rGSU, #0                          @ 
        ldrbeq  r3, [rR15, r3]                           @ 
        mov     rDREG, rSREG                             @ 
        strbeq  r3, [rGSU, #38]                          @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        b       loop_head                                @ 
handle_fx_sub_r:
        ldrh    r3, [rSREG]                              @ 
        ldrh    rR15, [rGSU, #30]                        @ 
        lsl     vLow, vLow, #1                           @ 
        ldrh    rARM, [rGSU, vLow]                       @ 
        add     rR15, rR15, #1                           @ 
        lsl     r3, r3, #16                              @ 
        subs    r3, r3, rARM, lsl #16                    @ 
        mrs     rARM, cpsr                               @ 
        lsr     r3, r3, #16                              @ 
        strh    rR15, [rGSU, #30]                        @ 
        strh    r3, [rDREG]                              @ 
        add     r3, rGSU, #28                            @ 
        cmp     rDREG, r3                                @ 
        ldrheq  r3, [rGSU, #28]                          @ 
        ldreq   rR15, [rGSU, #408]                       @ 
        add     rSREG, rGSU, #0                          @ 
        ldrbeq  r3, [rR15, r3]                           @ 
        mov     rDREG, rSREG                             @ 
        strbeq  r3, [rGSU, #38]                          @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        b       loop_head                                @ 
handle_fx_merge:
        ldrh    r1, [rGSU, #14]                          @ 
        ldrh    rR15, [rGSU, #16]                        @ 
        bic     r1, r1, #255                             @ 
        orr     rR15, r1, rR15, lsr #8                   @ 
        add     r3, r3, #1                               @ 
        strh    r3, [rGSU, #30]                          @ 
        lsr     r3, rR15, #4                             @ 
        orr     r3, r3, r1, lsr #12                      @ 
        and     r3, r3, #15                              @ 
        add     r3, rGSU, r3                             @ 
        ldrb    rARM, [r3, #42]                          @ 
        strh    rR15, [rDREG]                            @ 
        add     r3, rGSU, #28                            @ 
        cmp     rDREG, r3                                @ 
        ldrheq  r3, [rGSU, #28]                          @ 
        ldreq   rR15, [rGSU, #408]                       @ 
        add     rSREG, rGSU, #0                          @ 
        ldrbeq  r3, [rR15, r3]                           @ 
        mov     rDREG, rSREG                             @ 
        lsl     rARM, rARM, #28                          @ 
        strbeq  r3, [rGSU, #38]                          @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        b       loop_head                                @ 
handle_fx_and_r:
        lsl     vLow, vLow, #1                           @ 
        ldrh    r3, [rSREG]                              @ 
        ldrh    rR15, [rGSU, vLow]                       @ 
        add     r3, r3, r3, lsl #16                      @ 
        add     rR15, rR15, rR15, lsl #16                @ 
        msr     cpsr_f, rARM                             @ 
        ands    r3, r3, rR15                             @ 
        mrs     rARM, cpsr                               @ 
        ldrh    rR15, [rGSU, #30]                        @ 
        add     rSREG, rGSU, #0                          @ 
        add     rR15, rR15, #1                           @ 
        strh    rR15, [rGSU, #30]                        @ 
        strh    r3, [rDREG]                              @ 
        add     r3, rGSU, #28                            @ 
        cmp     rDREG, r3                                @ 
        ldrheq  r3, [rGSU, #28]                          @ 
        ldreq   rR15, [rGSU, #408]                       @ 
        mov     rDREG, rSREG                             @ 
        ldrbeq  r3, [rR15, r3]                           @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        strbeq  r3, [rGSU, #38]                          @ 
        b       loop_head                                @ 
handle_fx_mult_r:
        lsl     vLow, vLow, #1                           @ 
        ldrsb   r3, [rSREG]                              @ 
        ldrsb   rR15, [rGSU, vLow]                       @ 
        add     rSREG, rGSU, #0                          @ 
        smulbb  r3, r3, rR15                             @ 
        msr     cpsr_f, rARM                             @ 
        movs    rARM, r3                                 @ 
        mrs     rARM, cpsr                               @ 
        ldrh    rR15, [rGSU, #30]                        @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        add     rR15, rR15, #1                           @ 
        strh    rR15, [rGSU, #30]                        @ 
        strh    r3, [rDREG]                              @ 
        add     r3, rGSU, #28                            @ 
        cmp     rDREG, r3                                @ 
        ldrheq  r3, [rGSU, #28]                          @ 
        ldreq   rR15, [rGSU, #408]                       @ 
        mov     rDREG, rSREG                             @ 
        ldrbeq  r3, [rR15, r3]                           @ 
        strbeq  r3, [rGSU, #38]                          @ 
        b       loop_head                                @ 
handle_fx_sbk:
        ldrh    r3, [rSREG]                              @ 
        ldrh    rR15, [rGSU, #34]                        @ 
        ldr     r1, [rGSU, #404]                         @ 
        add     rSREG, rGSU, #0                          @ 
        strb    r3, [r1, rR15]                           @ 
        ldrh    rR15, [rGSU, #34]                        @ 
        ldr     r1, [rGSU, #404]                         @ 
        lsr     r3, r3, #8                               @ 
        eor     rR15, rR15, #1                           @ 
        strb    r3, [r1, rR15]                           @ 
        ldrh    r3, [rGSU, #30]                          @ 
        mov     rDREG, rSREG                             @ 
        add     r3, r3, #1                               @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        strh    r3, [rGSU, #30]                          @ 
        b       loop_head                                @ 
handle_fx_link_i:
        add     vLow, vLow, r3                           @ 
        add     r3, r3, #1                               @ 
        add     rSREG, rGSU, #0                          @ 
        strh    vLow, [rGSU, #22]                        @ 
        mov     rDREG, rSREG                             @ 
        strh    r3, [rGSU, #30]                          @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        b       loop_head                                @ 
handle_fx_sex:
        ldrh    rR15, [rGSU, #30]                        @ 
        ldrsb   r3, [rSREG]                              @ 
        add     rR15, rR15, #1                           @ 
        strh    rR15, [rGSU, #30]                        @ 
        msr     cpsr_f, rARM                             @ 
        movs    r3, r3                                   @ 
        mrs     rARM, cpsr                               @ 
        strh    r3, [rDREG]                              @ 
        add     r3, rGSU, #28                            @ 
        cmp     rDREG, r3                                @ 
        ldrheq  r3, [rGSU, #28]                          @ 
        ldreq   rR15, [rGSU, #408]                       @ 
        add     rSREG, rGSU, #0                          @ 
        ldrbeq  r3, [rR15, r3]                           @ 
        mov     rDREG, rSREG                             @ 
        strbeq  r3, [rGSU, #38]                          @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        b       loop_head                                @ 
handle_fx_asr:
        ldrh    rR15, [rGSU, #30]                        @ 
        ldrsh   r3, [rSREG]                              @ 
        add     rR15, rR15, #1                           @ 
        strh    rR15, [rGSU, #30]                        @ 
        msr     cpsr_f, rARM                             @ 
        asrs    r3, r3, #1                               @ 
        mrs     rARM, cpsr                               @ 
        strh    r3, [rDREG]                              @ 
        add     r3, rGSU, #28                            @ 
        cmp     rDREG, r3                                @ 
        ldrheq  r3, [rGSU, #28]                          @ 
        ldreq   rR15, [rGSU, #408]                       @ 
        add     rSREG, rGSU, #0                          @ 
        ldrbeq  r3, [rR15, r3]                           @ 
        mov     rDREG, rSREG                             @ 
        strbeq  r3, [rGSU, #38]                          @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        b       loop_head                                @ 
handle_fx_ror:
        ldrh    rR15, [rGSU, #30]                        @ 
        ldrh    r3, [rSREG]                              @ 
        add     rR15, rR15, #1                           @ 
        strh    rR15, [rGSU, #30]                        @ 
        msr     cpsr_f, rARM                             @ 
        orrcs   r3, r3, #65536                           @ 
        rrxs    r3, r3                                   @ 
        mrs     rARM, cpsr                               @ 
        strh    r3, [rDREG]                              @ 
        add     r3, rGSU, #28                            @ 
        cmp     rDREG, r3                                @ 
        ldrheq  r3, [rGSU, #28]                          @ 
        ldreq   rR15, [rGSU, #408]                       @ 
        add     rSREG, rGSU, #0                          @ 
        ldrbeq  r3, [rR15, r3]                           @ 
        mov     rDREG, rSREG                             @ 
        strbeq  r3, [rGSU, #38]                          @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        b       loop_head                                @ 
handle_fx_jmp_r:
        lsl     vLow, vLow, #1                           @ 
        ldrh    r3, [rGSU, vLow]                         @ 
        add     rSREG, rGSU, #0                          @ 
        strh    r3, [rGSU, #30]                          @ 
        mov     rDREG, rSREG                             @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        b       loop_head                                @ 
handle_fx_lob:
        ldrh    r3, [rGSU, #30]                          @ 
        ldrb    rR15, [rSREG]                            @ 
        add     r3, r3, #1                               @ 
        strh    r3, [rGSU, #30]                          @ 
        msr     cpsr_f, rARM                             @ 
        lsl     rARM, rR15, #24                          @ 
        movs    rARM, rARM                               @ 
        mrs     rARM, cpsr                               @ 
        strh    rR15, [rDREG]                            @ 
        add     r3, rGSU, #28                            @ 
        cmp     rDREG, r3                                @ 
        ldrheq  r3, [rGSU, #28]                          @ 
        ldreq   rR15, [rGSU, #408]                       @ 
        add     rSREG, rGSU, #0                          @ 
        ldrbeq  r3, [rR15, r3]                           @ 
        mov     rDREG, rSREG                             @ 
        strbeq  r3, [rGSU, #38]                          @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        b       loop_head                                @ 
.L242:
        .word   GSU
        .word   _ZZ6fx_runE17opcode_goto_table
        .word   _ZZ6fx_runE23plot_rpix_handler_table
        .word   handle_fx_rpix_2bit
        .word   handle_fx_plot_2bit
handle_fx_fmult:
        ldrh    r3, [rSREG]                              @ 
        ldrh    rR15, [rGSU, #12]                        @ 
        add     rSREG, rGSU, #0                          @ 
        smulbb  r3, r3, rR15                             @ 
        msr     cpsr_f, rARM                             @ 
        asrs    r3, r3, #16                              @ 
        mrs     rARM, cpsr                               @ 
        ldrh    rR15, [rGSU, #30]                        @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        add     rR15, rR15, #1                           @ 
        strh    rR15, [rGSU, #30]                        @ 
        strh    r3, [rDREG]                              @ 
        add     r3, rGSU, #28                            @ 
        cmp     rDREG, r3                                @ 
        ldrheq  r3, [rGSU, #28]                          @ 
        ldreq   rR15, [rGSU, #408]                       @ 
        mov     rDREG, rSREG                             @ 
        ldrbeq  r3, [rR15, r3]                           @ 
        strbeq  r3, [rGSU, #38]                          @ 
        b       loop_head                                @ 
handle_fx_ibt_r:
        add     rR15, r3, #1                             @ 
        uxth    rR15, rR15                               @ 
        strh    rR15, [rGSU, #30]                        @ 
        lsl     vLow, vLow, #1                           @ 
        sxtb    ip, ip                                   @ 
        add     r3, r3, #2                               @ 
        ldrb    rPIPE, [r1, rR15]                        @ 
        add     rSREG, rGSU, #0                          @ 
        strh    r3, [rGSU, #30]                          @ 
        mov     rDREG, rSREG                             @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        strh    ip, [rGSU, vLow]                         @ 
        b       loop_head                                @ 
handle_fx_ibt_r14:
        add     rR15, r3, #1                             @ 
        uxth    rR15, rR15                               @ 
        strh    rR15, [rGSU, #30]                        @ 
        sxtb    ip, ip                                   @ 
        add     r3, r3, #2                               @ 
        ldrb    rPIPE, [r1, rR15]                        @ 
        add     rSREG, rGSU, #0                          @ 
        strh    ip, [rGSU, #28]                          @ 
        mov     rDREG, rSREG                             @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        strh    r3, [rGSU, #30]                          @ 
        uxth    ip, ip                                   @ 
        ldr     r3, [rGSU, #408]                         @ 
        ldrb    r3, [r3, ip]                             @ 
        strb    r3, [rGSU, #38]                          @ 
        b       loop_head                                @ 
handle_fx_from_r:
        tst     rSTAT, #4096                             @ 
        beq     .L131                                    @ 
        add     rSREG, rGSU, #0                          @ 
        lsl     vLow, vLow, #1                           @ 
        ldrh    r3, [rGSU, vLow]                         @ 
        bic     rARM, rARM, #-805306368                  @ 
        lsls    rR15, r3, #24                            @ 
        orrmi   rARM, rARM, #268435456                   @ 
        lsls    rR15, r3, #16                            @ 
        orrmi   rARM, rARM, #-2147483648                 @ 
        orreq   rARM, rARM, #1073741824                  @ 
        ldrh    rR15, [rGSU, #30]                        @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        add     rR15, rR15, #1                           @ 
        strh    rR15, [rGSU, #30]                        @ 
        strh    r3, [rDREG]                              @ 
        add     r3, rGSU, #28                            @ 
        cmp     rDREG, r3                                @ 
        ldrheq  r3, [rGSU, #28]                          @ 
        ldreq   rR15, [rGSU, #408]                       @ 
        mov     rDREG, rSREG                             @ 
        ldrbeq  r3, [rR15, r3]                           @ 
        strbeq  r3, [rGSU, #38]                          @ 
        b       loop_head                                @ 
handle_fx_hib:
        ldrh    r3, [rSREG]                              @ 
        ldrh    rR15, [rGSU, #30]                        @ 
        lsr     r3, r3, #8                               @ 
        add     rR15, rR15, #1                           @ 
        strh    rR15, [rGSU, #30]                        @ 
        strh    r3, [rDREG]                              @ 
        sxtb    rR15, r3                                 @ 
        add     r3, rGSU, #28                            @ 
        msr     cpsr_f, rARM                             @ 
        movs    rARM, rR15                               @ 
        mrs     rARM, cpsr                               @ 
        cmp     rDREG, r3                                @ 
        ldrheq  r3, [rGSU, #28]                          @ 
        ldreq   rR15, [rGSU, #408]                       @ 
        add     rSREG, rGSU, #0                          @ 
        ldrbeq  r3, [rR15, r3]                           @ 
        mov     rDREG, rSREG                             @ 
        strbeq  r3, [rGSU, #38]                          @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        b       loop_head                                @ 
handle_fx_or_r:
        lsl     vLow, vLow, #1                           @ 
        ldrh    r3, [rSREG]                              @ 
        ldrh    rR15, [rGSU, vLow]                       @ 
        add     r3, r3, r3, lsl #16                      @ 
        add     rR15, rR15, rR15, lsl #16                @ 
        msr     cpsr_f, rARM                             @ 
        orrs    r3, r3, rR15                             @ 
        mrs     rARM, cpsr                               @ 
        ldrh    rR15, [rGSU, #30]                        @ 
        add     rSREG, rGSU, #0                          @ 
        add     rR15, rR15, #1                           @ 
        strh    rR15, [rGSU, #30]                        @ 
        strh    r3, [rDREG]                              @ 
        add     r3, rGSU, #28                            @ 
        cmp     rDREG, r3                                @ 
        ldrheq  r3, [rGSU, #28]                          @ 
        ldreq   rR15, [rGSU, #408]                       @ 
        mov     rDREG, rSREG                             @ 
        ldrbeq  r3, [rR15, r3]                           @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        strbeq  r3, [rGSU, #38]                          @ 
        b       loop_head                                @ 
handle_fx_inc_r:
        lsl     vLow, vLow, #1                           @ 
        ldrh    r3, [rGSU, vLow]                         @ 
        add     rSREG, rGSU, #0                          @ 
        add     r3, r3, #1                               @ 
        strh    r3, [rGSU, vLow]                         @ 
        msr     cpsr_f, rARM                             @ 
        lsl     rARM, r3, #16                            @ 
        movs    rARM, rARM                               @ 
        mrs     rARM, cpsr                               @ 
        ldrh    r3, [rGSU, #30]                          @ 
        mov     rDREG, rSREG                             @ 
        add     r3, r3, #1                               @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        strh    r3, [rGSU, #30]                          @ 
        b       loop_head                                @ 
handle_fx_inc_r14:
        ldrh    r3, [rGSU, #28]                          @ 
        ldrh    rR15, [rGSU, #30]                        @ 
        add     r3, r3, #1                               @ 
        add     rR15, rR15, #1                           @ 
        msr     cpsr_f, rARM                             @ 
        lsl     rARM, r3, #16                            @ 
        movs    rARM, rARM                               @ 
        mrs     rARM, cpsr                               @ 
        uxth    r3, r3                                   @ 
        add     rSREG, rGSU, #0                          @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        mov     rDREG, rSREG                             @ 
        strh    r3, [rGSU, #28]                          @ 
        strh    rR15, [rGSU, #30]                        @ 
        ldr     rR15, [rGSU, #408]                       @ 
        ldrb    r3, [rR15, r3]                           @ 
        strb    r3, [rGSU, #38]                          @ 
        b       loop_head                                @ 
handle_fx_getc:
        ldrb    r1, [rGSU, #36]                          @ 
        ldrb    rR15, [rGSU, #38]                        @ 
        tst     r1, #4                                   @ 
        andne   vLow, rR15, #240                         @ 
        orrne   rR15, vLow, rR15, lsr #4                 @ 
        tst     r1, #8                                   @ 
        ldrbne  r1, [rGSU, #37]                          @ 
        andne   rR15, rR15, #15                          @ 
        bicne   r1, r1, #15                              @ 
        orrne   rR15, r1, rR15                           @ 
        add     r3, r3, #1                               @ 
        add     rSREG, rGSU, #0                          @ 
        strb    rR15, [rGSU, #37]                        @ 
        mov     rDREG, rSREG                             @ 
        strh    r3, [rGSU, #30]                          @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        b       loop_head                                @ 
handle_fx_dec_r:
        lsl     vLow, vLow, #1                           @ 
        ldrh    r3, [rGSU, vLow]                         @ 
        add     rSREG, rGSU, #0                          @ 
        sub     r3, r3, #1                               @ 
        strh    r3, [rGSU, vLow]                         @ 
        msr     cpsr_f, rARM                             @ 
        lsl     rARM, r3, #16                            @ 
        movs    rARM, rARM                               @ 
        mrs     rARM, cpsr                               @ 
        ldrh    r3, [rGSU, #30]                          @ 
        mov     rDREG, rSREG                             @ 
        add     r3, r3, #1                               @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        strh    r3, [rGSU, #30]                          @ 
        b       loop_head                                @ 
handle_fx_dec_r14:
        ldrh    r3, [rGSU, #28]                          @ 
        ldrh    rR15, [rGSU, #30]                        @ 
        sub     r3, r3, #1                               @ 
        add     rR15, rR15, #1                           @ 
        msr     cpsr_f, rARM                             @ 
        lsl     rARM, r3, #16                            @ 
        movs    rARM, rARM                               @ 
        mrs     rARM, cpsr                               @ 
        uxth    r3, r3                                   @ 
        add     rSREG, rGSU, #0                          @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        mov     rDREG, rSREG                             @ 
        strh    r3, [rGSU, #28]                          @ 
        strh    rR15, [rGSU, #30]                        @ 
        ldr     rR15, [rGSU, #408]                       @ 
        ldrb    r3, [rR15, r3]                           @ 
        strb    r3, [rGSU, #38]                          @ 
        b       loop_head                                @ 
handle_fx_getb:
        add     r3, r3, #1                               @ 
        strh    r3, [rGSU, #30]                          @ 
        ldrb    r3, [rGSU, #38]                          @ 
        add     rSREG, rGSU, #0                          @ 
        strh    r3, [rDREG]                              @ 
        add     r3, rGSU, #28                            @ 
        cmp     rDREG, r3                                @ 
        ldrheq  r3, [rGSU, #28]                          @ 
        ldreq   rR15, [rGSU, #408]                       @ 
        mov     rDREG, rSREG                             @ 
        ldrbeq  r3, [rR15, r3]                           @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        strbeq  r3, [rGSU, #38]                          @ 
        b       loop_head                                @ 
handle_fx_iwt_r:
        add     rR15, r3, #1                             @ 
        uxth    rR15, rR15                               @ 
        ldrb    rPIPE, [r1, rR15]                        @ 
        add     rR15, r3, #2                             @ 
        orr     ip, ip, rPIPE, lsl #8                    @ 
        lsl     vLow, vLow, #1                           @ 
        uxth    rR15, rR15                               @ 
        add     r3, r3, #3                               @ 
        ldrb    rPIPE, [r1, rR15]                        @ 
        add     rSREG, rGSU, #0                          @ 
        strh    r3, [rGSU, #30]                          @ 
        mov     rDREG, rSREG                             @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        strh    ip, [rGSU, vLow]                         @ 
        b       loop_head                                @ 
handle_fx_iwt_r14:
        add     rR15, r3, #1                             @ 
        uxth    rR15, rR15                               @ 
        ldrb    rPIPE, [r1, rR15]                        @ 
        add     rR15, r3, #2                             @ 
        orr     ip, ip, rPIPE, lsl #8                    @ 
        uxth    rR15, rR15                               @ 
        add     r3, r3, #3                               @ 
        ldrb    rPIPE, [r1, rR15]                        @ 
        add     rSREG, rGSU, #0                          @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        mov     rDREG, rSREG                             @ 
        strh    r3, [rGSU, #30]                          @ 
        strh    ip, [rGSU, #28]                          @ 
        ldr     r3, [rGSU, #408]                         @ 
        ldrb    r3, [r3, ip]                             @ 
        strb    r3, [rGSU, #38]                          @ 
        b       loop_head                                @ 
handle_fx_stb_r:
        lsl     vLow, vLow, #1                           @ 
        ldrh    r3, [rGSU, vLow]                         @ 
        ldr     rR15, [rGSU, #404]                       @ 
        strh    r3, [rGSU, #34]                          @ 
        ldrh    r1, [rSREG]                              @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        strb    r1, [rR15, r3]                           @ 
        ldrh    r3, [rGSU, #30]                          @ 
        add     rSREG, rGSU, #0                          @ 
        add     r3, r3, #1                               @ 
        mov     rDREG, rSREG                             @ 
        strh    r3, [rGSU, #30]                          @ 
        b       loop_head                                @ 
handle_fx_ldb_r:
        lsl     vLow, vLow, #1                           @ 
        ldrh    rR15, [rGSU, vLow]                       @ 
        ldr     r1, [rGSU, #404]                         @ 
        strh    rR15, [rGSU, #34]                        @ 
        ldrb    rR15, [r1, rR15]                         @ 
        add     r3, r3, #1                               @ 
        strh    r3, [rGSU, #30]                          @ 
        strh    rR15, [rDREG]                            @ 
        add     r3, rGSU, #28                            @ 
        cmp     rDREG, r3                                @ 
        ldrheq  r3, [rGSU, #28]                          @ 
        ldreq   rR15, [rGSU, #408]                       @ 
        add     rSREG, rGSU, #0                          @ 
        ldrbeq  r3, [rR15, r3]                           @ 
        mov     rDREG, rSREG                             @ 
        strbeq  r3, [rGSU, #38]                          @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        b       loop_head                                @ 
handle_fx_cmode:
        ldrb    r3, [rSREG]                              @ 
        tst     r3, #16                                  @ 
        strb    r3, [rGSU, #36]                          @ 
        movne   r3, #256                                 @ 
        ldreq   r3, [rGSU, #392]                         @ 
        str     r3, [rGSU, #388]                         @ 
        bl      _Z24fx_computeScreenPointersv            @ 
        add     rSREG, rGSU, #0                          @ 
        ldrh    r3, [rGSU, #30]                          @ 
        mov     rDREG, rSREG                             @ 
        add     r3, r3, #1                               @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        strh    r3, [rGSU, #30]                          @ 
        b       loop_head                                @ 
handle_fx_adc_r:
        ldrh    rR15, [rGSU, #30]                        @ 
        lsl     vLow, vLow, #1                           @ 
        ldrh    r1, [rSREG]                              @ 
        ldrh    r3, [rGSU, vLow]                         @ 
        add     rR15, rR15, #1                           @ 
        msr     cpsr_f, rARM                             @ 
        lsl     rARM, r1, #16                            @ 
        orrcs   rARM, rARM, #32768                       @ 
        orrcs   r3, r3, #-2147483648                     @ 
        adds    r3, rARM, r3, ror #16                    @ 
        mrs     rARM, cpsr                               @ 
        lsr     r3, r3, #16                              @ 
        strh    rR15, [rGSU, #30]                        @ 
        strh    r3, [rDREG]                              @ 
        add     r3, rGSU, #28                            @ 
        cmp     rDREG, r3                                @ 
        ldrheq  r3, [rGSU, #28]                          @ 
        ldreq   rR15, [rGSU, #408]                       @ 
        add     rSREG, rGSU, #0                          @ 
        ldrbeq  r3, [rR15, r3]                           @ 
        mov     rDREG, rSREG                             @ 
        strbeq  r3, [rGSU, #38]                          @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        b       loop_head                                @ 
handle_fx_sbc_r:
        ldrh    r3, [rSREG]                              @ 
        lsl     vLow, vLow, #1                           @ 
        ldrh    rR15, [rGSU, vLow]                       @ 
        lsl     r3, r3, #16                              @ 
        msr     cpsr_f, rARM                             @ 
        sbcs    r3, r3, rR15, lsl #16                    @ 
        mrs     rARM, cpsr                               @ 
        ldrh    rR15, [rGSU, #30]                        @ 
        lsrs    r3, r3, #16                              @ 
        add     rR15, rR15, #1                           @ 
        strh    rR15, [rGSU, #30]                        @ 
        orreq   rARM, rARM, #1073741824                  @ 
        strh    r3, [rDREG]                              @ 
        add     r3, rGSU, #28                            @ 
        cmp     rDREG, r3                                @ 
        ldrheq  r3, [rGSU, #28]                          @ 
        ldreq   rR15, [rGSU, #408]                       @ 
        add     rSREG, rGSU, #0                          @ 
        ldrbeq  r3, [rR15, r3]                           @ 
        mov     rDREG, rSREG                             @ 
        strbeq  r3, [rGSU, #38]                          @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        b       loop_head                                @ 
handle_fx_bic_r:
        lsl     vLow, vLow, #1                           @ 
        ldrh    r3, [rSREG]                              @ 
        ldrh    rR15, [rGSU, vLow]                       @ 
        add     r3, r3, r3, lsl #16                      @ 
        add     rR15, rR15, rR15, lsl #16                @ 
        msr     cpsr_f, rARM                             @ 
        bics    r3, r3, rR15                             @ 
        mrs     rARM, cpsr                               @ 
        ldrh    rR15, [rGSU, #30]                        @ 
        add     rSREG, rGSU, #0                          @ 
        add     rR15, rR15, #1                           @ 
        strh    rR15, [rGSU, #30]                        @ 
        strh    r3, [rDREG]                              @ 
        add     r3, rGSU, #28                            @ 
        cmp     rDREG, r3                                @ 
        ldrheq  r3, [rGSU, #28]                          @ 
        ldreq   rR15, [rGSU, #408]                       @ 
        mov     rDREG, rSREG                             @ 
        ldrbeq  r3, [rR15, r3]                           @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        strbeq  r3, [rGSU, #38]                          @ 
        b       loop_head                                @ 
handle_fx_umult_r:
        ldrb    r3, [rSREG]                              @ 
        ldrb    rR15, [rGSU, vLow, lsl #1]               @ 
        add     rSREG, rGSU, #0                          @ 
        smulbb  r3, r3, rR15                             @ 
        msr     cpsr_f, rARM                             @ 
        lsl     rARM, r3, #16                            @ 
        movs    rARM, rARM                               @ 
        mrs     rARM, cpsr                               @ 
        ldrh    rR15, [rGSU, #30]                        @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        add     rR15, rR15, #1                           @ 
        strh    rR15, [rGSU, #30]                        @ 
        strh    r3, [rDREG]                              @ 
        add     r3, rGSU, #28                            @ 
        cmp     rDREG, r3                                @ 
        ldrheq  r3, [rGSU, #28]                          @ 
        ldreq   rR15, [rGSU, #408]                       @ 
        mov     rDREG, rSREG                             @ 
        ldrbeq  r3, [rR15, r3]                           @ 
        strbeq  r3, [rGSU, #38]                          @ 
        b       loop_head                                @ 
handle_fx_div2:
        ldrh    r3, [rSREG]                              @ 
        ldrh    rR15, [rGSU, #58]                        @ 
        add     rSREG, rGSU, #0                          @ 
        cmp     rR15, r3                                 @ 
        ldrh    rR15, [rGSU, #30]                        @ 
        moveq   r3, #1                                   @ 
        add     rR15, rR15, #1                           @ 
        strh    rR15, [rGSU, #30]                        @ 
        sxthne  r3, r3                                   @ 
        msr     cpsr_f, rARM                             @ 
        asrs    r3, r3, #1                               @ 
        mrs     rARM, cpsr                               @ 
        strh    r3, [rDREG]                              @ 
        add     r3, rGSU, #28                            @ 
        cmp     rDREG, r3                                @ 
        ldrheq  r3, [rGSU, #28]                          @ 
        ldreq   rR15, [rGSU, #408]                       @ 
        mov     rDREG, rSREG                             @ 
        ldrbeq  r3, [rR15, r3]                           @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        strbeq  r3, [rGSU, #38]                          @ 
        b       loop_head                                @ 
handle_fx_ljmp_r:
        lsl     vLow, vLow, #1                           @ 
        ldrh    r3, [rGSU, vLow]                         @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        and     r3, r3, #127                             @ 
        strb    r3, [rGSU, #39]                          @ 
        add     r3, r3, #108                             @ 
        ldr     r3, [rGSU, r3, lsl #2]                   @ 
        ldrh    rR15, [rSREG]                            @ 
        str     r3, [rGSU, #412]                         @ 
        mov     r3, #0                                   @ 
        add     rSREG, rGSU, #0                          @ 
        str     r3, [rGSU, #72]                          @ 
        mov     r3, #1                                   @ 
        strb    r3, [rGSU, #1456]                        @ 
        bic     r3, rR15, #15                            @ 
        mov     rDREG, rSREG                             @ 
        strh    r3, [rGSU, #32]                          @ 
        strh    rR15, [rGSU, #30]                        @ 
        b       loop_head                                @ 
handle_fx_lmult:
        ldrh    r3, [rSREG]                              @ 
        ldrh    rR15, [rGSU, #12]                        @ 
        add     rSREG, rGSU, #0                          @ 
        smulbb  r3, r3, rR15                             @ 
        ldrh    rR15, [rGSU, #30]                        @ 
        strh    r3, [rGSU, #8]                           @ 
        add     rR15, rR15, #1                           @ 
        strh    rR15, [rGSU, #30]                        @ 
        msr     cpsr_f, rARM                             @ 
        asrs    r3, r3, #16                              @ 
        mrs     rARM, cpsr                               @ 
        strh    r3, [rDREG]                              @ 
        add     r3, rGSU, #28                            @ 
        cmp     rDREG, r3                                @ 
        ldrheq  r3, [rGSU, #28]                          @ 
        ldreq   rR15, [rGSU, #408]                       @ 
        mov     rDREG, rSREG                             @ 
        ldrbeq  r3, [rR15, r3]                           @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        strbeq  r3, [rGSU, #38]                          @ 
        b       loop_head                                @ 
handle_fx_lms_r:
        lsl     ip, ip, #1                               @ 
        add     rR15, r3, #1                             @ 
        strh    ip, [rGSU, #34]                          @ 
        uxth    rR15, rR15                               @ 
        add     r3, r3, #2                               @ 
        ldrb    rPIPE, [r1, rR15]                        @ 
        strh    r3, [rGSU, #30]                          @ 
        ldr     r3, [rGSU, #404]                         @ 
        add     rR15, ip, #1                             @ 
        ldrb    rR15, [r3, rR15]                         @ 
        ldrb    r3, [r3, ip]                             @ 
        lsl     vLow, vLow, #1                           @ 
        orr     r3, r3, rR15, lsl #8                     @ 
        add     rSREG, rGSU, #0                          @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        mov     rDREG, rSREG                             @ 
        strh    r3, [rGSU, vLow]                         @ 
        b       loop_head                                @ 
handle_fx_lms_r14:
        lsl     ip, ip, #1                               @ 
        add     rR15, r3, #1                             @ 
        strh    ip, [rGSU, #34]                          @ 
        uxth    rR15, rR15                               @ 
        add     r3, r3, #2                               @ 
        ldrb    rPIPE, [r1, rR15]                        @ 
        strh    r3, [rGSU, #30]                          @ 
        ldr     r3, [rGSU, #404]                         @ 
        add     rR15, ip, #1                             @ 
        ldrb    rR15, [r3, rR15]                         @ 
        ldrb    r3, [r3, ip]                             @ 
        add     rSREG, rGSU, #0                          @ 
        orr     r3, r3, rR15, lsl #8                     @ 
        mov     rDREG, rSREG                             @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        strh    r3, [rGSU, #28]                          @ 
        ldr     rR15, [rGSU, #408]                       @ 
        ldrb    r3, [rR15, r3]                           @ 
        strb    r3, [rGSU, #38]                          @ 
        b       loop_head                                @ 
handle_fx_xor_r:
        lsl     vLow, vLow, #1                           @ 
        ldrh    r3, [rSREG]                              @ 
        ldrh    rR15, [rGSU, vLow]                       @ 
        add     r3, r3, r3, lsl #16                      @ 
        add     rR15, rR15, rR15, lsl #16                @ 
        msr     cpsr_f, rARM                             @ 
        eors    r3, r3, rR15                             @ 
        mrs     rARM, cpsr                               @ 
        ldrh    rR15, [rGSU, #30]                        @ 
        add     rSREG, rGSU, #0                          @ 
        add     rR15, rR15, #1                           @ 
        strh    rR15, [rGSU, #30]                        @ 
        strh    r3, [rDREG]                              @ 
        add     r3, rGSU, #28                            @ 
        cmp     rDREG, r3                                @ 
        ldrheq  r3, [rGSU, #28]                          @ 
        ldreq   rR15, [rGSU, #408]                       @ 
        mov     rDREG, rSREG                             @ 
        ldrbeq  r3, [rR15, r3]                           @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        strbeq  r3, [rGSU, #38]                          @ 
        b       loop_head                                @ 
handle_fx_getbh:
        add     rR15, r3, #1                             @ 
        ldrb    r3, [rSREG]                              @ 
        strh    rR15, [rGSU, #30]                        @ 
        ldrb    rR15, [rGSU, #38]                        @ 
        add     rSREG, rGSU, #0                          @ 
        orr     r3, r3, rR15, lsl #8                     @ 
        strh    r3, [rDREG]                              @ 
        add     r3, rGSU, #28                            @ 
        cmp     rDREG, r3                                @ 
        ldrheq  r3, [rGSU, #28]                          @ 
        ldreq   rR15, [rGSU, #408]                       @ 
        mov     rDREG, rSREG                             @ 
        ldrbeq  r3, [rR15, r3]                           @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        strbeq  r3, [rGSU, #38]                          @ 
        b       loop_head                                @ 

_ZL7fx_lm_rh:
        ldr     rSREG, .L3                               @ 
        uxtb    r3, rPIPE                                @ 
        ldrh    rR15, [rSREG, #30]                       @ 
        ldr     ip, [rSREG, #412]                        @ 
        add     r1, rR15, #1                             @ 
        strh    r3, [rSREG, #34]                         @ 
        uxth    r1, r1                                   @ 
        ldrb    rPIPE, [ip, r1]                          @ 
        add     r1, rR15, #2                             @ 
        orr     r3, r3, rPIPE, lsl #8                    @ 
        strh    r3, [rSREG, #34]                         @ 
        uxth    r1, r1                                   @ 
        add     rR15, rR15, #3                           @ 
        ldrb    rPIPE, [ip, r1]                          @ 
        strh    rR15, [rSREG, #30]                       @ 
        ldr     rR15, [rSREG, #404]                      @ 
        eor     r1, r3, #1                               @ 
        ldrb    r1, [rR15, r1]                           @ 
        ldrb    r3, [rR15, r3]                           @ 
        lsl     vLow, vLow, #1                           @ 
        orr     r3, r3, r1, lsl #8                       @ 
        strh    r3, [rSREG, vLow]                        @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        add     rSREG, rSREG, #0                         @ 
        mov     rDREG, rSREG                             @ 
        bx      lr                                       @ 
.L3:
        .word   GSU

handle_fx_lm_r:
        bl      _ZL7fx_lm_rh                             @ 
        b       loop_head                                @ 
handle_fx_lm_r14:
        mov     vLow, #14                                @ 
        bl      _ZL7fx_lm_rh                             @ 
        ldrh    r3, [rGSU, #28]                          @ 
        ldr     rR15, [rGSU, #408]                       @ 
        ldrb    r3, [rR15, r3]                           @ 
        strb    r3, [rGSU, #38]                          @ 
        b       loop_head                                @ 
handle_fx_add_i:
        ldrh    rARM, [rSREG]                            @ 
        ldrh    rR15, [rGSU, #30]                        @ 
        lsl     rARM, rARM, #16                          @ 
        add     rR15, rR15, #1                           @ 
        adds    r3, rARM, vLow, lsl #16                  @ 
        mrs     rARM, cpsr                               @ 
        lsr     r3, r3, #16                              @ 
        strh    rR15, [rGSU, #30]                        @ 
        strh    r3, [rDREG]                              @ 
        add     r3, rGSU, #28                            @ 
        cmp     rDREG, r3                                @ 
        ldrheq  r3, [rGSU, #28]                          @ 
        ldreq   rR15, [rGSU, #408]                       @ 
        add     rSREG, rGSU, #0                          @ 
        ldrbeq  r3, [rR15, r3]                           @ 
        mov     rDREG, rSREG                             @ 
        strbeq  r3, [rGSU, #38]                          @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        b       loop_head                                @ 
handle_fx_sub_i:
        ldrh    rARM, [rSREG]                            @ 
        ldrh    rR15, [rGSU, #30]                        @ 
        lsl     rARM, rARM, #16                          @ 
        add     rR15, rR15, #1                           @ 
        subs    r3, rARM, vLow, lsl #16                  @ 
        mrs     rARM, cpsr                               @ 
        lsr     r3, r3, #16                              @ 
        strh    rR15, [rGSU, #30]                        @ 
        strh    r3, [rDREG]                              @ 
        add     r3, rGSU, #28                            @ 
        cmp     rDREG, r3                                @ 
        ldrheq  r3, [rGSU, #28]                          @ 
        ldreq   rR15, [rGSU, #408]                       @ 
        add     rSREG, rGSU, #0                          @ 
        ldrbeq  r3, [rR15, r3]                           @ 
        mov     rDREG, rSREG                             @ 
        strbeq  r3, [rGSU, #38]                          @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        b       loop_head                                @ 
handle_fx_and_i:
        ldrh    rR15, [rGSU, #30]                        @ 
        ldrh    r3, [rSREG]                              @ 
        add     rR15, rR15, #1                           @ 
        strh    rR15, [rGSU, #30]                        @ 
        msr     cpsr_f, rARM                             @ 
        ands    r3, r3, vLow                             @ 
        mrs     rARM, cpsr                               @ 
        strh    r3, [rDREG]                              @ 
        add     r3, rGSU, #28                            @ 
        cmp     rDREG, r3                                @ 
        ldrheq  r3, [rGSU, #28]                          @ 
        ldreq   rR15, [rGSU, #408]                       @ 
        add     rSREG, rGSU, #0                          @ 
        ldrbeq  r3, [rR15, r3]                           @ 
        mov     rDREG, rSREG                             @ 
        strbeq  r3, [rGSU, #38]                          @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        b       loop_head                                @ 
handle_fx_mult_i:
        ldrsb   r3, [rSREG]                              @ 
        ldrh    rR15, [rGSU, #30]                        @ 
        smulbb  r3, r3, vLow                             @ 
        msr     cpsr_f, rARM                             @ 
        movs    rARM, r3                                 @ 
        mrs     rARM, cpsr                               @ 
        add     rSREG, rGSU, #0                          @ 
        add     rR15, rR15, #1                           @ 
        strh    rR15, [rGSU, #30]                        @ 
        strh    r3, [rDREG]                              @ 
        add     r3, rGSU, #28                            @ 
        cmp     rDREG, r3                                @ 
        ldrheq  r3, [rGSU, #28]                          @ 
        ldreq   rR15, [rGSU, #408]                       @ 
        mov     rDREG, rSREG                             @ 
        ldrbeq  r3, [rR15, r3]                           @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        strbeq  r3, [rGSU, #38]                          @ 
        b       loop_head                                @ 
handle_fx_sms_r:
        add     r3, r3, #1                               @ 
        lsl     ip, ip, #1                               @ 
        uxth    r3, r3                                   @ 
        lsl     vLow, vLow, #1                           @ 
        ldrh    rR15, [rGSU, vLow]                       @ 
        strh    ip, [rGSU, #34]                          @ 
        strh    r3, [rGSU, #30]                          @ 
        ldrb    rPIPE, [r1, r3]                          @ 
        ldr     r3, [rGSU, #404]                         @ 
        add     rSREG, rGSU, #0                          @ 
        strb    rR15, [r3, ip]                           @ 
        ldrh    r3, [rGSU, #34]                          @ 
        ldr     r1, [rGSU, #404]                         @ 
        add     r3, r3, #1                               @ 
        lsr     rR15, rR15, #8                           @ 
        uxth    r3, r3                                   @ 
        strb    rR15, [r1, r3]                           @ 
        ldrh    r3, [rGSU, #30]                          @ 
        mov     rDREG, rSREG                             @ 
        add     r3, r3, #1                               @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        strh    r3, [rGSU, #30]                          @ 
        b       loop_head                                @ 
handle_fx_or_i:
        ldrh    rR15, [rGSU, #30]                        @ 
        ldrh    r3, [rSREG]                              @ 
        add     rR15, rR15, #1                           @ 
        strh    rR15, [rGSU, #30]                        @ 
        add     r3, r3, r3, lsl #16                      @ 
        msr     cpsr_f, rARM                             @ 
        orrs    r3, r3, vLow                             @ 
        mrs     rARM, cpsr                               @ 
        strh    r3, [rDREG]                              @ 
        add     r3, rGSU, #28                            @ 
        cmp     rDREG, r3                                @ 
        ldrheq  r3, [rGSU, #28]                          @ 
        ldreq   rR15, [rGSU, #408]                       @ 
        add     rSREG, rGSU, #0                          @ 
        ldrbeq  r3, [rR15, r3]                           @ 
        mov     rDREG, rSREG                             @ 
        strbeq  r3, [rGSU, #38]                          @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        b       loop_head                                @ 
handle_fx_ramb:
        ldrh    rR15, [rSREG]                            @ 
        add     r3, r3, #1                               @ 
        strh    r3, [rGSU, #30]                          @ 
        and     r3, rR15, #3                             @ 
        strb    r3, [rGSU, #41]                          @ 
        add     r3, r3, #104                             @ 
        ldr     r3, [rGSU, r3, lsl #2]                   @ 
        add     rSREG, rGSU, #0                          @ 
        str     r3, [rGSU, #404]                         @ 
        mov     rDREG, rSREG                             @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        b       loop_head                                @ 
handle_fx_getbl:
        add     rR15, r3, #1                             @ 
        ldrh    r3, [rSREG]                              @ 
        strh    rR15, [rGSU, #30]                        @ 
        ldrb    rR15, [rGSU, #38]                        @ 
        and     r3, r3, #65280                           @ 
        orr     r3, r3, rR15                             @ 
        strh    r3, [rDREG]                              @ 
        add     r3, rGSU, #28                            @ 
        cmp     rDREG, r3                                @ 
        ldrheq  r3, [rGSU, #28]                          @ 
        ldreq   rR15, [rGSU, #408]                       @ 
        add     rSREG, rGSU, #0                          @ 
        ldrbeq  r3, [rR15, r3]                           @ 
        mov     rDREG, rSREG                             @ 
        strbeq  r3, [rGSU, #38]                          @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        b       loop_head                                @ 
handle_fx_sm_r:
        lsl     vLow, vLow, #1                           @ 
        ldrh    rR15, [rGSU, vLow]                       @ 
        add     vLow, r3, #1                             @ 
        uxth    vLow, vLow                               @ 
        strh    ip, [rGSU, #34]                          @ 
        strh    vLow, [rGSU, #30]                        @ 
        ldrb    rPIPE, [r1, vLow]                        @ 
        add     r3, r3, #2                               @ 
        orr     ip, ip, rPIPE, lsl #8                    @ 
        uxth    r3, r3                                   @ 
        strh    r3, [rGSU, #30]                          @ 
        strh    ip, [rGSU, #34]                          @ 
        ldrb    rPIPE, [r1, r3]                          @ 
        ldr     r3, [rGSU, #404]                         @ 
        add     rSREG, rGSU, #0                          @ 
        strb    rR15, [r3, ip]                           @ 
        ldrh    r3, [rGSU, #34]                          @ 
        ldr     r1, [rGSU, #404]                         @ 
        lsr     rR15, rR15, #8                           @ 
        eor     r3, r3, #1                               @ 
        strb    rR15, [r1, r3]                           @ 
        ldrh    r3, [rGSU, #30]                          @ 
        mov     rDREG, rSREG                             @ 
        add     r3, r3, #1                               @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        strh    r3, [rGSU, #30]                          @ 
        b       loop_head                                @ 
handle_fx_adc_i:
        ldrh    r3, [rGSU, #30]                          @ 
        ldrh    rR15, [rSREG]                            @ 
        add     r3, r3, #1                               @ 
        msr     cpsr_f, rARM                             @ 
        lsl     rARM, rR15, #16                          @ 
        orrcs   rARM, rARM, #32768                       @ 
        orrcs   vLow, vLow, #-2147483648                 @ 
        adds    vLow, rARM, vLow, ror #16                @ 
        mrs     rARM, cpsr                               @ 
        lsr     vLow, vLow, #16                          @ 
        strh    r3, [rGSU, #30]                          @ 
        strh    vLow, [rDREG]                            @ 
        add     r3, rGSU, #28                            @ 
        cmp     rDREG, r3                                @ 
        ldrheq  r3, [rGSU, #28]                          @ 
        ldreq   rR15, [rGSU, #408]                       @ 
        add     rSREG, rGSU, #0                          @ 
        ldrbeq  r3, [rR15, r3]                           @ 
        mov     rDREG, rSREG                             @ 
        strbeq  r3, [rGSU, #38]                          @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        b       loop_head                                @ 
handle_fx_cmp_r:
        ldrh    r3, [rSREG]                              @ 
        lsl     vLow, vLow, #1                           @ 
        ldrh    rARM, [rGSU, vLow]                       @ 
        lsl     r3, r3, #16                              @ 
        cmp     r3, rARM, lsl #16                        @ 
        mrs     rARM, cpsr                               @ 
        ldrh    r3, [rGSU, #30]                          @ 
        add     rSREG, rGSU, #0                          @ 
        add     r3, r3, #1                               @ 
        mov     rDREG, rSREG                             @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        strh    r3, [rGSU, #30]                          @ 
        b       loop_head                                @ 
handle_fx_bic_i:
        ldrh    rR15, [rGSU, #30]                        @ 
        ldrh    r3, [rSREG]                              @ 
        add     rR15, rR15, #1                           @ 
        strh    rR15, [rGSU, #30]                        @ 
        add     vLow, vLow, vLow, lsl #16                @ 
        add     r3, r3, r3, lsl #16                      @ 
        msr     cpsr_f, rARM                             @ 
        bics    r3, r3, vLow                             @ 
        mrs     rARM, cpsr                               @ 
        strh    r3, [rDREG]                              @ 
        add     r3, rGSU, #28                            @ 
        cmp     rDREG, r3                                @ 
        ldrheq  r3, [rGSU, #28]                          @ 
        ldreq   rR15, [rGSU, #408]                       @ 
        add     rSREG, rGSU, #0                          @ 
        ldrbeq  r3, [rR15, r3]                           @ 
        mov     rDREG, rSREG                             @ 
        strbeq  r3, [rGSU, #38]                          @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        b       loop_head                                @ 
handle_fx_umult_i:
        ldrb    r3, [rSREG]                              @ 
        ldrh    rR15, [rGSU, #30]                        @ 
        smulbb  r3, r3, vLow                             @ 
        msr     cpsr_f, rARM                             @ 
        movs    rARM, r3                                 @ 
        mrs     rARM, cpsr                               @ 
        add     rSREG, rGSU, #0                          @ 
        add     rR15, rR15, #1                           @ 
        strh    rR15, [rGSU, #30]                        @ 
        strh    r3, [rDREG]                              @ 
        add     r3, rGSU, #28                            @ 
        cmp     rDREG, r3                                @ 
        ldrheq  r3, [rGSU, #28]                          @ 
        ldreq   rR15, [rGSU, #408]                       @ 
        mov     rDREG, rSREG                             @ 
        ldrbeq  r3, [rR15, r3]                           @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        strbeq  r3, [rGSU, #38]                          @ 
        b       loop_head                                @ 
handle_fx_xor_i:
        ldrh    rR15, [rGSU, #30]                        @ 
        ldrh    r3, [rSREG]                              @ 
        add     rR15, rR15, #1                           @ 
        strh    rR15, [rGSU, #30]                        @ 
        add     vLow, vLow, vLow, lsl #16                @ 
        add     r3, r3, r3, lsl #16                      @ 
        msr     cpsr_f, rARM                             @ 
        eors    r3, r3, vLow                             @ 
        mrs     rARM, cpsr                               @ 
        strh    r3, [rDREG]                              @ 
        add     r3, rGSU, #28                            @ 
        cmp     rDREG, r3                                @ 
        ldrheq  r3, [rGSU, #28]                          @ 
        ldreq   rR15, [rGSU, #408]                       @ 
        add     rSREG, rGSU, #0                          @ 
        ldrbeq  r3, [rR15, r3]                           @ 
        mov     rDREG, rSREG                             @ 
        strbeq  r3, [rGSU, #38]                          @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        b       loop_head                                @ 
handle_fx_romb:
        ldrh    rR15, [rSREG]                            @ 
        add     r3, r3, #1                               @ 
        strh    r3, [rGSU, #30]                          @ 
        and     r3, rR15, #127                           @ 
        strb    r3, [rGSU, #40]                          @ 
        add     r3, r3, #108                             @ 
        ldr     r3, [rGSU, r3, lsl #2]                   @ 
        add     rSREG, rGSU, #0                          @ 
        str     r3, [rGSU, #408]                         @ 
        mov     rDREG, rSREG                             @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        b       loop_head                                @ 
.L131:
        add     r3, r3, #1                               @ 
        strh    r3, [rGSU, #30]                          @ 
        add     rSREG, rGSU, vLow, lsl #1                @ 
        b       loop_head                                @ 
.L86:
        add     r3, r3, #1                               @ 
        strh    r3, [rGSU, #30]                          @ 
        add     rDREG, rGSU, #30                         @ 
        b       loop_head                                @ 
.L241:
        ldrh    rR15, [rSREG]                            @ 
        ldr     r1, [rGSU, #408]                         @ 
        strh    rR15, [rGSU, #28]                        @ 
        ldrb    rR15, [r1, rR15]                         @ 
        add     rSREG, rGSU, #0                          @ 
        bic     rSTAT, rSTAT, #4864                      @ 
        mov     rDREG, rSREG                             @ 
        strb    rR15, [rGSU, #38]                        @ 
        b       .L84                                     @ 
.L237:
        eor     ip, r1, r3                               @ 
        tst     ip, #1                                   @ 
        lsrne   rR15, rR15, #4                           @ 
        movne   ip, rR15                                 @ 
        bne     .L17                                     @ 
        b       .L15                                     @ 
.L239:
        and     ip, r1, #15                              @ 
        orrs    vLow, vLow, ip                           @ 
        bne     .L40                                     @ 
        b       loop_head                                @ 
.L238:
        eor     ip, r3, r1                               @ 
        tst     ip, #1                                   @ 
        lsrne   rR15, rR15, #4                           @ 
        movne   ip, rR15                                 @ 
        bne     .L27                                     @ 
        b       .L25                                     @ 
.L240:
        ldrb    r1, [rGSU, #1456]                        @ 
        cmp     r1, #0                                   @ 
        bne     .L63                                     @ 
        b       .L62                                     @ 
    .cfi_endproc

    .section	.rodata
    .align	2
    .type	_ZZ6fx_runE23plot_rpix_handler_table, %object
_ZZ6fx_runE23plot_rpix_handler_table:
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
    .type	_ZZ6fx_runE17opcode_goto_table, %object
_ZZ6fx_runE17opcode_goto_table:
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
