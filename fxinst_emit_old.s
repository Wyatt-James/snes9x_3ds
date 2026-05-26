; Registers:
; rVCNT     R0  vCounter, reserved by fx_run.
; GSU R15   R1  (left by the interpreter loop)
; rGSU      R4  Pointer to GSU, reserved by fx_run.
; rSTAT     R6
; rARM      R7
; rPIPE     R8
; rSREG     R9
; rDREG     R10
; vLow      LR  (left by the interpreter loop)

fx_with:
  add rDREG, rGSU, lr, lsl #1       ; Register pointer, store to R10 (DREG)
  add r1, r1, #1                    ; Increment R15
  mov rSREG, rDREG                  ; Copy to SREG
  strh r1, [rGSU, #30]              ; Store R15
  orr rSTAT, rSTAT, #4096           ; Set B flag
  EXIT                              ; Generate dynamically

fx_stw:
  lsl lr, lr, #1                    ; GSU.avReg[] requires explicit shift
  ldrh r3, [rGSU, lr]               ; R3 = GSU.avReg[reg]
  ldr r1, [rGSU, #400]              ; R1 = GSU.pvRamBank
  strh r3, [rGSU, #34]              ; GSU.vLastRamAdr = R3
  ldrh r2, [rSREG]                  ; R2 = data
  bic rSTAT, rSTAT, #4864           ; CLRFLAGS
  strb r2, [r1, r3]                 ; Write data low byte
  eor r3, r3, #1                    ; Swap address LSB
  lsr r2, r2, #8                    ; Shift data
  strb r2, [r1, r3]                 ; Write data high byte
  ; L298
  ldrh r3, [rGSU, #30]              ; Load R15 (unnecessary if we can avoid clobber)
  add rSREG, rGSU, #0               ; Reset SREG
  add r3, r3, #1                    ; Increment R15
  mov rDREG, rSREG                  ; Reset DREG
  strh r3, [rGSU, #30]              ; Store R15
  EXIT                              ; Generate dynamically

fx_stb:
  lsl lr, lr, #1                    ; GSU.avReg[] requires explicit shift
  ldrh r3, [rGSU, lr]               ; R3 = GSU.avReg[reg]
  ldr r1, [rGSU, #400]              ; R1 = GSU.pvRamBank
  strh r3, [rGSU, #34]              ; GSU.vLastRamAdr = R3
  ldrh r2, [rSREG]                  ; R2 = data
  bic rSTAT, rSTAT, #4864           ; CLRFLAGS
  strb r2, [r1, r3]                 ; Write data
  ; L298
  ldrh r3, [rGSU, #30]              ; Load R15 (unnecessary if we can avoid clobber)
  add rSREG, rGSU, #0               ; Reset SREG
  add r3, r3, #1                    ; Increment R15
  mov rDREG, rSREG                  ; Reset DREG
  strh r3, [rGSU, #30]              ; Store R15
  EXIT                              ; Generate dynamically

fx_loop:
  ldrh r3, [rGSU, #24]              ; R3 = GSU.avReg[R12]
  sub r3, r3, #1                    ; Decrement GSU R12

  msr cpsr_f, rARM                  ; Inline ASM: Set sign and zero
  lsl rARM, r3, #16                 ;
  movs rARM, rARM                   ;
  mrs rARM, cpsr                    ;

  cmp r3, #0                        ; Check if R12 == 0 (unnecessary, done above)
  strh r3, [rGSU, #24]              ; Write GSU R12
  ldrheq r3, [rGSU, #30]            ; If R12 == 0, End Loop (R15++)
  ldrhne r3, [rGSU, #26]            ; If R12 != 0, Continue loop (R15 = G13)
  addeq r3, r3, #1                  ;
  uxtheq r3, r3                     ; Zero-extend destination (unnecessary)
  ; L300 (fx_jmp)
  add rSREG, rGSU, #0               ; Reset SREG
  strh r3, [rGSU, #30]              ; R15 = R3
  mov rDREG, rSREG                  ; Reset DREG
  bic rSTAT, rSTAT, #4864           ; CLRFLAGS
  EXIT                              ; Generate dynamically

fx_alt1:
  bic rSTAT, rSTAT, #4096           ; Clear B flag
  add r1, r1, #1                    ; R15++
  strh r1, [rGSU, #30]              ; Store R15
  orr rSTAT, rSTAT, #256            ; Set ALT1
  EXIT                              ; Generate dynamically

fx_alt2:
  bic rSTAT, rSTAT, #4096           ; Clear B flag
  add r1, r1, #1                    ; R15++
  strh r1, [rGSU, #30]              ; Store R15
  orr rSTAT, rSTAT, #512            ; Set ALT2
  EXIT                              ; Generate dynamically

fx_alt3:
  bic rSTAT, rSTAT, #4096           ; Clear B flag
  add r1, r1, #1                    ; R15++
  strh r1, [rGSU, #30]              ; Store R15
  orr rSTAT, rSTAT, #768            ; Set ALT1 + ALT2
  EXIT                              ; Generate dynamically

fx_ldw:
  lsl lr, lr, #1                    ; GSU.avReg[] requires explicit shift
  ldrh r3, [rGSU, lr]               ; R3 = GSU.avReg[reg]
  ldr r2, [rGSU, #400]              ; R2 = GSU.pvRamBank
  strh r3, [rGSU, #34]              ; GSU.vLastRamAdr = R3
  eor ip, r3, #1                    ; Swap address LSB
  add r1, r1, #1                    ; R15++
  ldrb r3, [r2, r3]                 ; Load lower byte from RAM
  ldrb r2, [r2, ip]                 ; Load upper byte from RAM
  strh r1, [rGSU, #30]              ; Store R15

 .L323: ; branched to by fx_getbh
  orr r3, r3, r2, lsl #8            ; Combine lower and upper bytes
  strh r3, [rDREG]                  ; Store loaded value to DREG. Must be after R15
  add r3, rGSU, #28                 ; TESTR14
  cmp rDREG, r3                     ; 
  beq .read_r14                     ; If DREG == R14, READR14
 .L274:
 .CLRFLAGS_RET:
  add rSREG, rGSU, #0               ; Reset SREG
  bic rSTAT, rSTAT, #4864           ; CLRFLAGS
  mov rDREG, rSREG                  ; Reset DREG
  EXIT                              ; Generate dynamically

 .L306:
 .READR14_CLRFLAGS_RET:
  ldrh r3, [rGSU, #28]              ; R3 = the value of GSU R14
  ldr r2, [rGSU, #404]              ; R2 = GSU.pvRomBank
  ldrb r3, [r2, r3]                 ; Load the ROM byte into R3
  strb r3, [rGSU, #38]              ; Store the ROM byte to GSU.vRomBuffer
  b .CLRFLAGS_RET                   ; Branch back to CLRFLAGS

fx_ldb:
  lsl lr, lr, #1                    ; GSU.avReg[] requires explicit shift
  ldrh r3, [rGSU, lr]               ; R3 = GSU.avReg[reg]
  ldr r2, [rGSU, #400]              ; R2 = GSU.pvRamBank
  strh r3, [rGSU, #34]              ; GSU.vLastRamAdr = R3
  ldrb r3, [r2, r3]                 ; Load the byte from RAM
  add r1, r1, #1                    ; R15++
  strh r1, [rGSU, #30]              ; Store R15
  strh r3, [rDREG]                  ; Store loaded value to DREG. Must be after R15
  add r3, rGSU, #28                 ; TESTR14
  cmp rDREG, r3                     ; 
  bne .CLRFLAGS_RET                 ; If DREG != R14, CLRFLAGS
  b .READR14_CLRFLAGS_RET           ; Else, CLRFLAGS

; fx_plot_2bit
; fx_plot_4bit
; fx_plot_8bit
; fx_plot_obj (stub)
; fx_rpix_2bit
; fx_rpix_4bit
; fx_rpix_8bit
; fx_rpix_obj (stub)

fx_swap:
  add r1, r1, #1                    ; R15++
  ldrh r3, [rSREG]                  ; R3 = the value of SREG
  add r2, rGSU, #28                 ; R2 = pointer to GSU R14
  strh r2, [rGSU, #30]              ; Store R15
  rev16 r3, r3                      ; Swap bytes of R3

  orr r1, r3, r3, lsl #16           ; Inline ASM: Set sign and zero
  msr cpsr_f, rARM                  ; 
  movs rARM, r1                     ; 
  mrs rARM, cpsr                    ; 

  cmp rDREG, r2                     ; TESTR14
  strh r3, [rDREG]                  ; Store result
  bne .CLRFLAGS_RET                 ; If DREG != R14, CLRFLAGS
  b .READR14_CLRFLAGS_RET           ; Else, READR14

fx_color: WYATT_TODO

fx_cmode:
  ldrb r3, [rSREG]                  ; R3 = value of SREG
  str rVCNT, [sp, #12]              ; Prevent rVCNT from being clobbered by the function call
  tst r3, #16                       ; Test bit
  strb r3, [rGSU, #36]              ; GSU.vPlotOptionReg = R3
  movne r3, #256                    ; If GSU.vPlotOptionReg & 0x10, R3 = 256
  ldreq r3, [rGSU, #388]            ; Else, R3 = GSU.vScreenRealHeight
  str r3, [rGSU, #384]              ; GSU.vScreenHeight = R3
  bl _Z24fx_computeScreenPointersv  ; 
  add rSREG, rGSU, #0               ; Reset SREG
  ldrh r3, [rGSU, #30]              ; Load R15
  mov rDREG, rSREG                  ; Reset DREG
  add r3, r3, #1                    ; R15++
  ldr rVCNT, [sp, #12]              ; Restore value of R0
  bic rSTAT, rSTAT, #4864           ; CLRFLAGS
  strh r3, [rGSU, #30]              ; Store R15
  EXIT                              ; Generate dynamically

; Registers:
; rVCNT     R0  vCounter, reserved by fx_run.
; GSU R15   R1  (left by the interpreter loop)
; rGSU      R4  Pointer to GSU, reserved by fx_run.
; rSTAT     R6
; rARM      R7
; rPIPE     R8
; rSREG     R9
; rDREG     R10
; vLow      LR  (left by the interpreter loop)

fx_not:
  ldrh r3, [rSREG]                  ; R3 = value of SREG
  add r3, r3, r3, lsl #16           ; Inline ASM: duplicate u16 to top and bottom halves of reg
  msr cpsr_f, r7                    ; Inline ASM: negate and set sign and zero
  mvns r3, r3                       ; 
  mrs r7, cpsr                      ; 
  b .L311                           ; WYATT_TODO handled in fx_xor_i

fx_xor_i:
