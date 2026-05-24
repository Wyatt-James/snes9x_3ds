#include "copyright.h"


#define FX_DO_ROMBUFFER

#include "fxemu.h"
#include "fxinst.h"
#include "fxinst_arm.h"
#include <string.h>
#include <stdio.h>

#define LIKELY(cond_) __builtin_expect(!!(cond_), 1)
#define UNLIKELY(cond_) __builtin_expect(!!(cond_), 0)
#define ASSUME(cond_) if (!(cond_)) __builtin_unreachable()
#define COLD __attribute__ ((cold))
#define FETCHPIPE2(r15_) { PIPE = PRGBANK(r15_); } // For optimization
#define REV16(v_) asm ("rev16 %0, %1":"=r"(v_):"r"(v_));
#define ALIGNED16 __attribute__((aligned(16)))

// Our ASSUME_ macros generate these with u8 vLow
#define ENW_ _Pragma("GCC diagnostic push"); _Pragma("GCC diagnostic ignored \"-Wtype-limits\"")
#define DIW_ _Pragma("GCC diagnostic pop")
#define ASSUME_REG(min_, max_) do {ENW_; ASSUME(reg >= min_ && reg <= max_); DIW_; } while(0)
#define ASSUME_IMM(min_, max_) do {ENW_; ASSUME(imm >= min_ && imm <= max_); DIW_; } while(0)
#define ASSUME_LKN(min_, max_) do {ENW_; ASSUME(lkn >= min_ && lkn <= max_); DIW_; } while(0)

extern struct FxRegs_s GSU;

// If 1, this file will reserve registers throughout this
// file. This improves performance significantly. If you
// wish to modify reservations, be sure that the registers
// that you choose are free as per the ARM AAPCS!
// The gist:
// 0-3 are caller-saved and must be manually saved if you
//    call into code in another file.
// 4-10 are callee-saved and are fair game for reservation
// 11-15 have special purposes depending on compiler flags.
//    Best to just let the compiler use them.
#define REGISTER_RESERVATIONS 1

// If 1, some nonsense C code will ATTEMPT to circumvent
// tail merging of the instruction handlers. This is not
// guaranteed to work perfectly on all compilers, so you
// must double-check the ASM that the compiler produces!
#define ATTEMPT_TO_DISABLE_TAIL_MERGE 1

#if ATTEMPT_TO_DISABLE_TAIL_MERGE == 1
#define DEFEAT_TAIL_MERGE asm volatile ("" : : "i" (__LINE__))
// #define DEFEAT_TAIL_MERGE asm volatile ("eor r0, r0, #0" : : "i" (__LINE__)) // For searching ASM
#else
#define DEFEAT_TAIL_MERGE do {} while(0)
#endif

#if REGISTER_RESERVATIONS == 1

// GSU status register, sans the NZCV flags
#undef SFR
register uint32 statusRegLocal asm("r6");
#define SFR statusRegLocal

// ARM NZCV flags. Always synchronized with GSU flags.
register uint32 armFlagsLocal asm("r7");
#define ARMFLAGS armFlagsLocal

// GSU PIPE
#undef PIPE
register uint8 pipeLocal asm("r8");
#define PIPE pipeLocal

// GSU SREG
#undef SREG
#undef SREG_PTR
register uint16* pvSregLocal asm("r9");
#define SREG_PTR pvSregLocal
#define SREG *SREG_PTR

// GSU DREG
#undef DREG
#undef DREG_PTR
register uint16* pvDregLocal asm("r10");
#define DREG_PTR pvDregLocal
#define DREG *DREG_PTR

// If any of these registers are used by your function or its
// statically-linked subroutines, these must be placed at the
// start and end of said function if it is externally linked.
#define PUSH_RESERVED asm volatile ("push {r6, r7, r8, r9, r10}")
#define POP_RESERVED  asm volatile ("pop  {r6, r7, r8, r9, r10}")

// Necessary redefs if DREG and SREG are pointers
#undef TESTR14
#undef CLRFLAGS
#define CLRFLAGS SFR &= ~(FLG_ALT1|FLG_ALT2|FLG_B); DREG_PTR = SREG_PTR = GETR(0);
#define TESTR14 if((pvDregLocal) == GETR(14)) READR14

// The compiler doesn't realize it can do this, so it loads from memory
//!!! This relies on the fact that GSU.avReg is at the start of GSU!
static inline uint16* GETR(size_t reg)
{
    uint16* ptr;
    asm ("add %0, %1, %2" : "=r" (ptr) : "r" (&GSU), "iIr" (reg * sizeof(uint16)));
    return ptr;
}

// Saves the reserved registers back to GSU
static inline void fx_save_reserved(void)
{
    GSU.vStatusReg = SFR;
    GSU.armFlags = ARMFLAGS;
    GSU.vPipe = PIPE;
    GSU.pvSreg = SREG_PTR - GSU.avReg;
    GSU.pvDreg = DREG_PTR - GSU.avReg;
}

// Loads the reserved registers from GSU
static inline void fx_load_reserved(void)
{
    SFR = GSU.vStatusReg;
    ARMFLAGS = GSU.armFlags;
    PIPE = GSU.vPipe;
    pvSregLocal = &GSU.avReg[GSU.pvSreg];
    pvDregLocal = &GSU.avReg[GSU.pvDreg];
}

// register reservations are disabled
#else
#define ARMFLAGS (GSU.armFlags)
#define PUSH_RESERVED do {} while(0)
#define POP_RESERVED do {} while(0)
static inline void fx_save_reserved(void) {} // Stub
static inline void fx_load_reserved(void) {} // Stub
#endif

/* Set this define if you wish the plot instruction to check for y-pos limits */
/* (I don't think it's nessecary) */
#define CHECK_LIMITS

/* Codes used:
 *
 * rn   = a GSU register (r0-r15)
 * #n   = 4 bit immediate value
 * #pp  = 8 bit immediate value
 * (yy) = 8 bit word address (0x0000 - 0x01fe)
 * #xx  = 16 bit immediate value
 * (xx) = 16 bit address (0x0000 - 0xffff)
 *
 */

/* 00 - stop - stop GSU execution (and maybe generate an IRQ) */
static inline void fx_stop(uint8 unused)
{
    CF(G);

    /* Check if we need to generate an IRQ */
    if(!(GSU.pvRegisters[GSU_CFGR] & 0x80))
	    SF(IRQ);

    GSU.vPlotOptionReg = 0;
    PIPE = 1;
    CLRFLAGS;
    R15++;

    DEFEAT_TAIL_MERGE;
}

/* 01 - nop - no operation */
static inline void fx_nop(uint8 unused) {
    CLRFLAGS;
    R15++;

    DEFEAT_TAIL_MERGE;
}

/* 02 - cache - reintialize GSU cache */
static inline void fx_cache(uint8 unused)
{
    uint32 c = R15 & 0xfff0;
    if(GSU.vCacheBaseReg != c || !GSU.bCacheActive)
    {
        GSU.vCacheFlags = 0;
        GSU.vCacheBaseReg = c;
        GSU.bCacheActive = TRUE;
#if 0
        if(c < (0x10000-512))
        {
            uint8 const* t = &ROM(c);
            memcpy(GSU.pvCache,t,512);
        }
        else
        {
            uint8 const* t1;
            uint8 const* t2;
            uint32 i = 0x10000 - c;
            t1 = &ROM(c);
            t2 = &ROM(0);
            memcpy(GSU.pvCache,t1,i);
            memcpy(&GSU.pvCache[i],t2,512-i);
        }
#endif	
    }
    R15++;
    CLRFLAGS;
    
    DEFEAT_TAIL_MERGE;
}

/* 03 - lsr - logic shift right */
static inline void fx_lsr(uint8 unused)
{
    uint32 v;
    asm (
        "msr cpsr_f, %0\n\t"
        "lsrs %1, %2, #1\n\t"
        "mrs %0, cpsr\n\t"
        : "+r" (ARMFLAGS),
          "=r" (v)
        : "r" (SREG)
        : "cc"
    );

    R15++;
    DREG = v;
    TESTR14;
    CLRFLAGS;
    
    DEFEAT_TAIL_MERGE;
}

/* 04 - rol - rotate left */
static inline void fx_rol(uint8 unused)
{
    uint32 v;
    asm (
        "msr cpsr_f, %0\n\t"
        "lsl %1, %2, #16\n\t"
        "orrcs %1, %1, %3\n\t"
        "lsls %1, %1, #1\n\t"
        "mrs %0, cpsr\n\t"
        : "+r" (ARMFLAGS),
          "=r" (v)
        : "r" (SREG),
          "i" (BIT(15))
        : "cc"
    );
    v >>= 16;

    R15++;
    DREG = v;
    TESTR14;
    CLRFLAGS;
    
    DEFEAT_TAIL_MERGE;
}

/* Branch on condition */
#define BRA_COND(condT_, condF_) {      \
    uint8 v = PIPE;                     \
    uint32 r15 = R15 + 1;               \
    FETCHPIPE2(r15);                    \
    asm (                               \
        "msr cpsr_f, %0\n\t"            \
        "add" condT_ " %1, %1, %2\n\t"  \
        "add" condF_ " %1, %1, #1\n\t"  \
        : "+r" (ARMFLAGS),              \
          "+r" (r15)                    \
        : "r" (SEX8(v))                 \
        : "cc"                          \
    );                                  \
    R15 = r15;                          \
                                        \
    DEFEAT_TAIL_MERGE;                  \
}

/* 05 - bra - branch always */
static inline void fx_bra(uint8 unused) {
    uint8 v = PIPE;
    uint32 r15 = R15 + 1;
    FETCHPIPE2(r15);
    R15 = r15 + SEX8(v);
    
    DEFEAT_TAIL_MERGE;
}

/* 06 - blt - branch on less than */
static inline void fx_blt(uint8 unused) { BRA_COND( "lt", "ge" ); }

/* 07 - bge - branch on greater or equals */
static inline void fx_bge(uint8 unused) { BRA_COND( "ge", "lt" ); }

/* 08 - bne - branch on not equal */
static inline void fx_bne(uint8 unused) { BRA_COND( "ne", "eq" ); }

/* 09 - beq - branch on equal */
static inline void fx_beq(uint8 unused) { BRA_COND( "eq", "ne" ); }

/* 0a - bpl - branch on plus */
static inline void fx_bpl(uint8 unused) { BRA_COND( "pl", "mi" ); }

/* 0b - bmi - branch on minus */
static inline void fx_bmi(uint8 unused) { BRA_COND( "mi", "pl" ); }

/* 0c - bcc - branch on carry clear */
static inline void fx_bcc(uint8 unused) { BRA_COND( "cc", "cs" ); }

/* 0d - bcs - branch on carry set */
static inline void fx_bcs(uint8 unused) { BRA_COND( "cs", "cc" ); }

/* 0e - bvc - branch on overflow clear */
static inline void fx_bvc(uint8 unused) { BRA_COND( "vc", "vs" ); }

/* 0f - bvs - branch on overflow set */
static inline void fx_bvs(uint8 unused) { BRA_COND( "vs", "vc" ); }

/* 10-1f - to rn - set register n as destination register */
/* 10-1f(B) - move rn - move one register to another (if B flag is set) */

static inline void fx_to_r(uint8 reg) {
    ASSUME_REG(0, 13);
    if(TF(B))
    {
        GSU.avReg[reg] = SREG;
        CLRFLAGS;
    }
    else
        DREG_PTR = &GSU.avReg[reg];

    R15++;
    
    DEFEAT_TAIL_MERGE;
}

static inline void fx_to_r14(uint8 unused) {
    if(TF(B)) {
        R14 = SREG;
        CLRFLAGS;
        READR14;
    }
    else
        DREG_PTR = GETR(14);
    R15++;
    
    DEFEAT_TAIL_MERGE;
}

static inline void fx_to_r15(uint8 unused) {
    if(TF(B)) {
        R15 = SREG;
        CLRFLAGS;
    }
    else {
        DREG_PTR = GETR(15);
        R15++;
    }
    
    DEFEAT_TAIL_MERGE;
}

/* 20-2f - to rn - set register n as source and destination register */
static inline void fx_with(uint8 reg) {
    ASSUME_REG(0, 15);
    SF(B);
    SREG_PTR = DREG_PTR = &GSU.avReg[reg];
    R15++;
    
    DEFEAT_TAIL_MERGE;
}

/* 30-3b - stw (rn) - store word */
static inline void fx_stw_r(uint8 reg) {
    ASSUME_REG(0, 11);
    uint16 r = GSU.vLastRamAdr = GSU.avReg[reg];
    uint16 sReg = SREG;
    uint8* ram = &RAM(0);
    ram[r] = (uint8)sReg;
    ram[r^1] = (uint8)(sReg>>8);
    CLRFLAGS;
    R15++;
    
    DEFEAT_TAIL_MERGE;
}

/* 30-3b(ALT1) - stb (rn) - store byte */
static inline void fx_stb_r(uint8 reg) {
    ASSUME_REG(0, 11);
    GSU.vLastRamAdr = GSU.avReg[reg];
    RAM(GSU.avReg[reg]) = (uint8)SREG;
    CLRFLAGS;
    R15++;
    
    DEFEAT_TAIL_MERGE;
}

/* 3c - loop - decrement loop counter, and branch on not zero */
static inline void fx_loop(uint8 unused)
{
    uint32 r12 = R12 - 1; // Gotta do math with a u32 to avoid a UXTH instruction
    asm (
        "msr cpsr_f, %0\n\t"
        "lsl %0, %1, #16\n\t"
        "movs %0, %0\n\t"
        "mrs %0, cpsr\n\t"
        : "+r" (ARMFLAGS)
        : "r" (r12)
        : "cc"
    );

    R12 = r12;
    if(LIKELY( r12 != 0 ))
	    R15 = R13;
    else
	    R15++;

    CLRFLAGS;
    
    DEFEAT_TAIL_MERGE;
}

/* 3d - alt1 - set alt1 mode */
// WYATT_TODO see if this can be collapsed
static inline void fx_alt1(uint8 unused) {
    SF(ALT1);
    CF(B);
    R15++;
    
    DEFEAT_TAIL_MERGE;
}

/* 3e - alt2 - set alt2 mode */
static inline void fx_alt2(uint8 unused) {
    SF(ALT2);
    CF(B);
    R15++;
    
    DEFEAT_TAIL_MERGE;
}

/* 3f - alt3 - set alt3 mode */
static inline void fx_alt3(uint8 unused) {
    SF(ALT1);
    SF(ALT2);
    CF(B);
    R15++;
    
    DEFEAT_TAIL_MERGE;
}
    
/* 40-4b - ldw (rn) - load word from RAM */
static inline void fx_ldw_r(uint8 reg)  { 
    ASSUME_REG(0, 11);
    uint32 v;
    GSU.vLastRamAdr = GSU.avReg[reg];
    v =   (uint32)RAM(GSU.avReg[reg]);
    v |= ((uint32)RAM(GSU.avReg[reg]^1))<<8;
    R15++;
    DREG = v;
    TESTR14;
    CLRFLAGS;
    
    DEFEAT_TAIL_MERGE;
}

/* 40-4b(ALT1) - ldb (rn) - load byte */
static inline void fx_ldb_r(uint8 reg) {
    ASSUME_REG(0, 11);
    uint32 v;
    GSU.vLastRamAdr = GSU.avReg[reg];
    v = (uint32)RAM(GSU.avReg[reg]);
    R15++;
    DREG = v;
    TESTR14;
    CLRFLAGS;
    
    DEFEAT_TAIL_MERGE;
}

/* 4c - plot - plot pixel with R1,R2 as x,y and the color register as the color */
static inline void fx_plot_2bit(uint8 unused)
{
    uint32 x = USEX8(R1);
    uint32 y = USEX8(R2);
    uint8 *a;
    uint8 c;

    R15++;
    CLRFLAGS;
    R1++;

#ifdef CHECK_LIMITS
    if(y >= GSU.vScreenHeight) return;
#endif

    if(GSU.vPlotOptionReg & 0x02)
	    c = (x ^ y) & 1 ? (GSU.vColorReg >> 4) : GSU.vColorReg; // WYATT_TODO check this ASM
    else
	    c = GSU.vColorReg;
    
    if( !(GSU.vPlotOptionReg & 0x01) && !(c & 0xf)) 
        return;

    a = GSU.apvScreen[y >> 3] + GSU.x[x >> 3] + ((y & 7) << 1);
    uint32 v = 128 >> (x&7);

    if(c & 0x01) a[0] |= v;
    else         a[0] &= ~v;
    if(c & 0x02) a[1] |= v;
    else         a[1] &= ~v;

    DEFEAT_TAIL_MERGE;
}

#define TESTBIT(offset_, shift_)   \
asm (                              \
    "tst %1, %2\n\t"               \
    "orrne %0, %0, %4, lsl %3\n\t" \
    : "+r" (dReg)                  \
    : "r" (v),                     \
      "r" (a[offset_]),            \
      "i" (shift_),                \
      "r" (1)                      \
    : "cc"                         \
)

/* 2c(ALT1) - rpix - read color of the pixel with R1,R2 as x,y */
static inline void fx_rpix_2bit(uint8 unused)
{
    uint32 x = USEX8(R1);
    uint32 y = USEX8(R2);
    uint8 *a;
    uint8 v;

    R15++;
    CLRFLAGS;

#ifdef CHECK_LIMITS
    if(y >= GSU.vScreenHeight) return;
#endif

    a = GSU.apvScreen[y >> 3] + GSU.x[x >> 3] + ((y & 7) << 1);
    v = 128 >> (x&7);

    uint32 dReg = 0;
    TESTBIT(0, 0);
    TESTBIT(1, 1);
    DREG = dReg;
    TESTR14;

    DEFEAT_TAIL_MERGE;
}

/* 4c - plot - plot pixel with R1,R2 as x,y and the color register as the color */
static inline void fx_plot_4bit(uint8 unused)
{
    uint32 x = USEX8(R1);
    uint32 y = USEX8(R2);
    uint8 *a;
    uint8 c;

    R15++;
    CLRFLAGS;
    R1++;
    
#ifdef CHECK_LIMITS
    if(y >= GSU.vScreenHeight) return;
#endif

    if(GSU.vPlotOptionReg & 0x02)
	    c = (x ^ y) & 1 ? (GSU.vColorReg >> 4) : GSU.vColorReg;
    else
	    c = GSU.vColorReg;

    if( !(GSU.vPlotOptionReg & 0x01) && !(c & 0xf))
        return;

    a = GSU.apvScreen[y >> 3] + GSU.x[x >> 3] + ((y & 7) << 1);
    uint32 v = 128 >> (x&7);

    if(c & 0x01) a[0x00] |= v;
    else         a[0x00] &= ~v;
    if(c & 0x02) a[0x01] |= v;
    else         a[0x01] &= ~v;
    if(c & 0x04) a[0x10] |= v;
    else         a[0x10] &= ~v;
    if(c & 0x08) a[0x11] |= v;
    else         a[0x11] &= ~v;

    DEFEAT_TAIL_MERGE;
}

/* 4c(ALT1) - rpix - read color of the pixel with R1,R2 as x,y */
static inline void fx_rpix_4bit(uint8 unused)
{
    uint32 x = USEX8(R1);
    uint32 y = USEX8(R2);
    uint8 *a;
    uint8 v;

    R15++;
    CLRFLAGS;

#ifdef CHECK_LIMITS
    if(y >= GSU.vScreenHeight) return;
#endif

    a = GSU.apvScreen[y >> 3] + GSU.x[x >> 3] + ((y & 7) << 1);
    v = 128 >> (x&7);

    uint32 dReg = 0;
    TESTBIT(0x00, 0);
    TESTBIT(0x01, 1);
    TESTBIT(0x10, 2);
    TESTBIT(0x11, 3);
    DREG = dReg;
    TESTR14;

    DEFEAT_TAIL_MERGE;
}

/* 8c - plot - plot pixel with R1,R2 as x,y and the color register as the color */
static inline void fx_plot_8bit(uint8 unused)
{
    uint32 x = USEX8(R1);
    uint32 y = USEX8(R2);
    uint8 *a;
    uint8 c;

    R15++;
    CLRFLAGS;
    R1++;
    
#ifdef CHECK_LIMITS
    if(y >= GSU.vScreenHeight) return;
#endif

    c = GSU.vColorReg;
    
    if( !(GSU.vPlotOptionReg & 0x10) ) {
	    if( !(GSU.vPlotOptionReg & 0x01) && !(c & 0xf))
            return;
    }
    else
	    if( !(GSU.vPlotOptionReg & 0x01) && !c)
            return;

    a = GSU.apvScreen[y >> 3] + GSU.x[x >> 3] + ((y & 7) << 1);
    uint32 v = 128 >> (x&7);

    if(c & 0x01) a[0x00] |= v;
    else         a[0x00] &= ~v;
    if(c & 0x02) a[0x01] |= v;
    else         a[0x01] &= ~v;
    if(c & 0x04) a[0x10] |= v;
    else         a[0x10] &= ~v;
    if(c & 0x08) a[0x11] |= v;
    else         a[0x11] &= ~v;
    if(c & 0x10) a[0x20] |= v;
    else         a[0x20] &= ~v;
    if(c & 0x20) a[0x21] |= v;
    else         a[0x21] &= ~v;
    if(c & 0x40) a[0x30] |= v;
    else         a[0x30] &= ~v;
    if(c & 0x80) a[0x31] |= v;
    else         a[0x31] &= ~v;

    DEFEAT_TAIL_MERGE;
}

/* 4c(ALT1) - rpix - read color of the pixel with R1,R2 as x,y */
static inline void fx_rpix_8bit(uint8 unused)
{
    uint32 x = USEX8(R1);
    uint32 y = USEX8(R2);
    uint8 *a;
    uint8 v;

    R15++;
    CLRFLAGS;

#ifdef CHECK_LIMITS
    if(y >= GSU.vScreenHeight) return;
#endif
    a = GSU.apvScreen[y >> 3] + GSU.x[x >> 3] + ((y & 7) << 1);
    v = 128 >> (x&7);

    uint32 dReg = 0;
    TESTBIT(0x00, 0);
    TESTBIT(0x01, 1);
    TESTBIT(0x10, 2);
    TESTBIT(0x11, 3);
    TESTBIT(0x20, 4);
    TESTBIT(0x21, 5);
    TESTBIT(0x30, 6);
    TESTBIT(0x31, 7);
    DREG = dReg;

    ARMFLAGS &= ~ARM_ZERO;
    if (USEX16(DREG) == 0) ARMFLAGS |= ARM_ZERO;
    TESTR14;

    DEFEAT_TAIL_MERGE;
}

/* 4o - plot - plot pixel with R1,R2 as x,y and the color register as the color */
COLD static inline void fx_plot_obj(uint8 unused)
{
    printf ("ERROR fx_plot_obj called\n");
    DEFEAT_TAIL_MERGE;
}

/* 4c(ALT1) - rpix - read color of the pixel with R1,R2 as x,y */
COLD static inline void fx_rpix_obj(uint8 unused)
{
    printf ("ERROR fx_rpix_obj called\n");
    DEFEAT_TAIL_MERGE;
}

/* 4d - swap - swap upper and lower byte of a register */
static inline void fx_swap(uint8 unused)
{
    uint32 v;
    uint16 r15 = R15 + 1;
    asm ("rev16 %0, %1":"=r"(v):"r"(SREG));
    asm (
        "msr cpsr_f, %0\n\t"
        "movs %0, %1\n\t"
        "mrs %0, cpsr\n\t"
        : "+r" (ARMFLAGS)
        : "r" (v | (v << 16))
        : "cc"
    );

    R15 = r15;
    DREG = v;
    TESTR14;
    CLRFLAGS;
    
    DEFEAT_TAIL_MERGE;
}

/* 4e - color - copy source register to color register */
static inline void fx_color(uint8 unused)
{
    uint8 c = (uint8) SREG;
    if(GSU.vPlotOptionReg & 0x04)
	    c = (c & 0xf0) | (c >> 4);

    if(GSU.vPlotOptionReg & 0x08)
    {
        GSU.vColorReg &= 0xf0;
        GSU.vColorReg |= c & 0x0f;
    }
    else
	    GSU.vColorReg = USEX8(c);

    CLRFLAGS;
    R15++;
    
    DEFEAT_TAIL_MERGE;
}

/* 4e(ALT1) - cmode - set plot option register */
static inline void fx_cmode(uint8 unused)
{
    GSU.vPlotOptionReg = SREG;

    if(GSU.vPlotOptionReg & 0x10)
        GSU.vScreenHeight = 256; /* OBJ Mode (for drawing into sprites) */
    else
	    GSU.vScreenHeight = GSU.vScreenRealHeight;

    fx_computeScreenPointers(); // Moving this here increases register pressure too much. Leave it in the other file.
    CLRFLAGS;
    R15++;
    
    DEFEAT_TAIL_MERGE;
}

/* 4f - not - perform exclusive exor with 1 on all bits */
static inline void fx_not(uint8 unused)
{
    uint32 v;
    asm (
        "msr cpsr_f, %0\n\t"
        "mvns %1, %2\n\t"
        "mrs %0, cpsr\n\t"
        : "+r" (ARMFLAGS),
          "=r" (v)
        : "r" ((SREG << 16) | SREG)
        : "cc"
    );

    R15++;
    DREG = v;
    TESTR14;
    CLRFLAGS;
    
    DEFEAT_TAIL_MERGE;
}

/* 50-5f - add rn - add, register + register */
static inline void fx_add_r(uint8 reg) {
    ASSUME_REG(0, 15);
    
    uint32 s;
    asm (
        "adds %1, %2, %3, lsl #16\n\t"
        "mrs %0, cpsr"
        : "=r" (ARMFLAGS), "=r" (s)
        : "r" (SREG << 16), "r" (GSU.avReg[reg])
        : "cc"
    );
    s >>= 16;

    R15++;
    DREG = s;
    TESTR14;
    CLRFLAGS;
    
    DEFEAT_TAIL_MERGE;
}

/* 50-5f(ALT1) - adc rn - add with carry, register + register */
static inline void fx_adc_r(uint8 reg) {
    ASSUME_REG(0, 15);

    uint32 s = GSU.avReg[reg];
    asm (
        "msr cpsr_f, %0\n\t"
        "lsl %0, %2, #16\n\t"
        "orrcs %0, %0, %3\n\t"
        "orrcs %1, %1, %4\n\t"
        "adds %1, %0, %1, ror #16\n\t"
        "mrs %0, cpsr\n\t"
        : "+r" (ARMFLAGS),
          "+r" (s)
        : "r" (SREG),
          "i" (BIT(15)),
          "i" (BIT(31))
        : "cc"
    );
    s >>= 16;

    R15++;
    DREG = s;
    TESTR14;
    CLRFLAGS;
    
    DEFEAT_TAIL_MERGE;
}

/* 50-5f(ALT2) - add #n - add, register + immediate */
static inline void fx_add_i(uint8 imm) {
    ASSUME_IMM(0, 15);

    uint32 s;
    asm (
        "adds %1, %2, %3, lsl #16\n\t"
        "mrs %0, cpsr"
        : "=r" (ARMFLAGS), "=r" (s)
        : "r" (SREG << 16), "r" (imm)
        : "cc"
    );
    s >>= 16;

    R15++;
    DREG = s;
    TESTR14;
    CLRFLAGS;
    
    DEFEAT_TAIL_MERGE;
}

/* 50-5f(ALT3) - adc #n - add with carry, register + immediate */
static inline void fx_adc_i(uint8 imm) {
    ASSUME_IMM(0, 15);

    uint32 s = imm;
    asm (
        "msr cpsr_f, %0\n\t"
        "lsl %0, %2, #16\n\t"
        "orrcs %0, %0, %3\n\t"
        "orrcs %1, %1, %4\n\t"
        "adds %1, %0, %1, ror #16\n\t"
        "mrs %0, cpsr\n\t"
        : "+r" (ARMFLAGS),
          "+r" (s)
        : "r" (SREG),
          "i" (BIT(15)),
          "i" (BIT(31))
        : "cc"
    );
    s >>= 16;

    R15++;
    DREG = s;
    TESTR14;
    CLRFLAGS;
    
    DEFEAT_TAIL_MERGE;
}

/* 60-6f - sub rn - subtract, register - register */
static inline void fx_sub_r(uint8 reg) {
    ASSUME_REG(0, 15);

    uint32 s;
    asm (
        "subs %1, %2, %3, lsl #16\n\t"
        "mrs %0, cpsr"
        : "=r" (ARMFLAGS), "=r" (s)
        : "r" ((SREG << 16)), "r" (GSU.avReg[reg])
        : "cc"
    );
    s >>= 16;

    R15++;
    DREG = s;
    TESTR14;
    CLRFLAGS;
    
    DEFEAT_TAIL_MERGE;
}

/* 60-6f(ALT1) - sbc rn - subtract with carry, register - register */
static inline void fx_sbc_r(uint8 reg) {
    ASSUME_REG(0, 15);

    uint32 s;
    asm (
        "msr cpsr_f, %0\n\t" // Copy in the carry flag
        "sbcs %1, %2, %3, lsl #16\n\t" // Do the actual subtraction
        "mrs %0, cpsr\n\t"
        : "+r" (ARMFLAGS),
          "=r" (s)
        : "r" (SREG << 16),
          "r" (GSU.avReg[reg])
        : "cc"
    );
    s >>= 16;
    if (s == 0) ARMFLAGS |= ARM_ZERO;

    R15++;
    DREG = s;
    TESTR14;
    CLRFLAGS;
    
    DEFEAT_TAIL_MERGE;
}

/* 60-6f(ALT2) - sub #n - subtract, register - immediate */
static inline void fx_sub_i(uint8 imm) {
    ASSUME_IMM(0, 15);

    uint32 s;
    asm (
        "subs %1, %2, %3, lsl #16\n\t"
        "mrs %0, cpsr"
        : "=r" (ARMFLAGS), "=r" (s)
        : "r" ((SREG << 16)), "r" (imm)
        : "cc"
    );
    s >>= 16;

    R15++;
    DREG = s;
    TESTR14;
    CLRFLAGS;
    
    DEFEAT_TAIL_MERGE;
}

/* 60-6f(ALT3) - cmp rn - compare, register, register */
static inline void fx_cmp_r(uint8 reg) {
    ASSUME_REG(0, 15);

    asm (
        "cmp %1, %2, lsl #16\n\t"
        "mrs %0, cpsr"
        : "=r" (ARMFLAGS)
        : "r" ((SREG << 16)), "r" (GSU.avReg[reg])
        : "cc"
    );

    R15++;
    CLRFLAGS;
    
    DEFEAT_TAIL_MERGE;
}

/* 70 - merge - R7 as upper byte, R8 as lower byte (used for texture-mapping) */
static inline void fx_merge(uint8 unused)
{
    uint32 v = (R7 & 0xff00) | ((R8 & 0xff00) >> 8);
    uint32 offset = ((v >> 12) | (v >> 4)) & 0b1111;
    ARMFLAGS = GSU.mergeFlagLut[offset] << ARM_SHIFT;

    R15++;
    DREG = v;
    TESTR14;
    CLRFLAGS;
    
    DEFEAT_TAIL_MERGE;
}

/* 71-7f - and rn - reister & register */
static inline void fx_and_r(uint8 reg) {
    ASSUME_REG(1, 15);

    uint32 v;
    asm (
        "msr cpsr_f, %0\n\t"
        "ands %1, %2, %3\n\t"
        "mrs %0, cpsr\n\t"
        : "+r" (ARMFLAGS),
          "=r" (v)
        : "r" (SREG | (SREG << 16)),
          "r" (GSU.avReg[reg] | (GSU.avReg[reg] << 16))
        : "cc"
    );

    R15++;
    DREG = v;
    TESTR14;
    CLRFLAGS;
    
    DEFEAT_TAIL_MERGE;
}

/* 71-7f(ALT1) - bic rn - reister & ~register */
static inline void fx_bic_r(uint8 reg) {
    ASSUME_REG(1, 15);

    uint32 v;
    asm (
        "msr cpsr_f, %0\n\t"
        "bics %1, %2, %3\n\t"
        "mrs %0, cpsr\n\t"
        : "+r" (ARMFLAGS),
          "=r" (v)
        : "r" (SREG | (SREG << 16)),
          "r" (GSU.avReg[reg] | (GSU.avReg[reg] << 16))
        : "cc"
    );

    R15++;
    DREG = v;
    TESTR14;
    CLRFLAGS;
    
    DEFEAT_TAIL_MERGE;
}

/* 71-7f(ALT2) - and #n - reister & immediate */
static inline void fx_and_i(uint8 imm) {
    ASSUME_IMM(1, 15);

    uint32 v;
    asm (
        "msr cpsr_f, %0\n\t"
        "ands %1, %2, %3\n\t"
        "mrs %0, cpsr\n\t"
        : "+r" (ARMFLAGS),
          "=r" (v)
        : "r" (SREG),
          "r" (imm)
        : "cc"
    );

    R15++;
    DREG = v;
    TESTR14;
    CLRFLAGS;
    
    DEFEAT_TAIL_MERGE;
}

/* 71-7f(ALT3) - bic #n - reister & ~immediate */
static inline void fx_bic_i(uint8 imm) {
    ASSUME_IMM(1, 15);

    uint32 v;
    asm (
        "msr cpsr_f, %0\n\t"
        "bics %1, %2, %3\n\t"
        "mrs %0, cpsr\n\t"
        : "+r" (ARMFLAGS),
          "=r" (v)
        : "r" (SREG | (SREG << 16)),
          "r" (imm | (imm << 16))
        : "cc"
    );

    R15++;
    DREG = v;
    TESTR14;
    CLRFLAGS;
    
    DEFEAT_TAIL_MERGE;
}

/* 80-8f - mult rn - 8 bit to 16 bit signed multiply, register * register */
static inline void fx_mult_r(uint8 reg) {
    ASSUME_REG(0, 15);

    uint32 v = SEX8(SREG) * SEX8(GSU.avReg[reg]);
    asm (
        "msr cpsr_f, %0\n\t"
        "movs %0, %1\n\t"
        "mrs %0, cpsr\n\t"
        : "+r" (ARMFLAGS)
        : "r" (v)
        : "cc"
    );

    R15++;
    DREG = v;
    TESTR14;
    CLRFLAGS;
    
    DEFEAT_TAIL_MERGE;
}

/* 80-8f(ALT1) - umult rn - 8 bit to 16 bit unsigned multiply, register * register */
static inline void fx_umult_r(uint8 reg) {
    ASSUME_REG(0, 15);

    uint32 v = USEX8(SREG) * USEX8(GSU.avReg[reg]);
    asm (
        "msr cpsr_f, %0\n\t"
        "lsl %0, %1, #16\n\t"
        "movs %0, %0\n\t"
        "mrs %0, cpsr\n\t"
        : "+r" (ARMFLAGS)
        : "r" (v)
        : "cc"
    );

    R15++;
    DREG = v;
    TESTR14;
    CLRFLAGS;
    
    DEFEAT_TAIL_MERGE;
}
  
/* 80-8f(ALT2) - mult #n - 8 bit to 16 bit signed multiply, register * immediate */
static inline void fx_mult_i(uint8 imm) {
    ASSUME_IMM(0, 15);

    uint32 v = SEX8(SREG) * imm; // WYATT_TODO check that this promotion is correct, and change imm to a u8 globally
    asm (
        "msr cpsr_f, %0\n\t"
        "movs %0, %1\n\t"
        "mrs %0, cpsr\n\t"
        : "+r" (ARMFLAGS)
        : "r" (v)
        : "cc"
    );

    R15++;
    DREG = v;
    TESTR14;
    CLRFLAGS;
    
    DEFEAT_TAIL_MERGE;
}
  
/* 80-8f(ALT3) - umult #n - 8 bit to 16 bit unsigned multiply, register * immediate */
static inline void fx_umult_i(uint8 imm) {
    ASSUME_IMM(0, 15);

    uint32 v = USEX8(SREG) * imm;
    asm (
        "msr cpsr_f, %0\n\t"
        "movs %0, %1\n\t"
        "mrs %0, cpsr\n\t"
        : "+r" (ARMFLAGS)
        : "r" (v)
        : "cc"
    );

    R15++;
    DREG = v;
    TESTR14;
    CLRFLAGS;
    
    DEFEAT_TAIL_MERGE;
}
  
/* 90 - sbk - store word to last accessed RAM address */
static inline void fx_sbk(uint8 unused)
{
    uint16 sReg = SREG;
    RAM(GSU.vLastRamAdr) = (uint8)sReg;
    RAM(GSU.vLastRamAdr^1) = (uint8)(sReg>>8); // WYATT_TODO this RAM alignment can probably be optimized to a 16-bit store
    CLRFLAGS;
    R15++;
    
    DEFEAT_TAIL_MERGE;
}

/* 91-94 - link #n - R11 = R15 + immediate */
static inline void fx_link_i(uint8 lkn) {
    ASSUME_LKN(1, 4);
    R11 = R15 + lkn;
    CLRFLAGS;
    R15++;
    
    DEFEAT_TAIL_MERGE;
}

/* 95 - sex - sign extend 8 bit to 16 bit */
static inline void fx_sex(uint8 unused)
{
    // WYATT_TODO It may be faster to set v to SEX(SREG) and use %0 as a scratch, due to memory reordering
    uint32 v;
    asm (
        "msr cpsr_f, %0\n\t"
        "movs %1, %2\n\t"
        "mrs %0, cpsr\n\t"
        : "+r" (ARMFLAGS),
          "=r" (v)
        : "r" (SEX8(SREG))
        : "cc"
    );

    R15++;
    DREG = v;
    TESTR14;
    CLRFLAGS;
    
    DEFEAT_TAIL_MERGE;
}

/* 96 - asr - aritmetric shift right by one */
static inline void fx_asr(uint8 unused)
{
    uint32 v;
    asm (
        "msr cpsr_f, %0\n\t"
        "asrs %1, %2, #1\n\t" // Shift (sets NZC)
        "mrs %0, cpsr\n\t"
        : "+r" (ARMFLAGS),
          "=r" (v)
        : "r" (SEX16(SREG))
        : "cc"
    );

    R15++;
    DREG = v;
    TESTR14;
    CLRFLAGS;
    
    DEFEAT_TAIL_MERGE;
}

/* 96(ALT1) - div2 - aritmetric shift right by one */
static inline void fx_div2(uint8 unused)
{
    uint32 v;
    asm (
        "msr cpsr_f, %0\n\t"
        "asrs %1, %2, #1\n\t" // Shift (sets NZC)
        "mrs %0, cpsr\n\t"
        : "+r" (ARMFLAGS),
          "=r" (v)
        : "r" (SREG == GSU.const_u16Max ? 1 : SEX16(SREG))
        : "cc"
    );

    R15++;
    DREG = v;
    TESTR14;
    CLRFLAGS;
    
    DEFEAT_TAIL_MERGE;
}

/* 97 - ror - rotate right by one */
static inline void fx_ror(uint8 unused)
{
    uint32 v = SREG;
    asm (
        "msr cpsr_f, %0\n\t"
        "orrcs %1, %1, %2\n\t"
        "rrxs %1, %1\n\t"
        "mrs %0, cpsr\n\t"
        : "+r" (ARMFLAGS),
          "+r" (v)
        : "i" (BIT(16))
        : "cc"
    );

    R15++;
    DREG = v;
    TESTR14;
    CLRFLAGS;
    
    DEFEAT_TAIL_MERGE;
}

/* 98-9d - jmp rn - jump to address of register */
static inline void fx_jmp_r(uint8 reg) {
    ASSUME_REG(8, 13);
    R15 = GSU.avReg[reg];
    CLRFLAGS;
    
    DEFEAT_TAIL_MERGE;
}

/* 98-9d(ALT1) - ljmp rn - set program bank to source register and jump to address of register */
static inline void fx_ljmp_r(uint8 reg) {
    ASSUME_REG(8, 13);
    GSU.vPrgBankReg = GSU.avReg[reg] & 0x7f;
    GSU.pvPrgBank = GSU.apvRomBank[GSU.vPrgBankReg];
    R15 = SREG;
    GSU.bCacheActive = FALSE;
    fx_cache(reg);
    R15--;
    
    DEFEAT_TAIL_MERGE;
}

/* 9e - lob - set upper byte to zero (keep low byte) */
static inline void fx_lob(uint8 unused)
{
    uint32 v = USEX8(SREG);
    asm (
        "msr cpsr_f, %0\n\t"
        "lsl %0, %1, #24\n\t"
        "movs %0, %0\n\t"
        "mrs %0, cpsr\n\t"
        : "+r" (ARMFLAGS)
        : "r" (v)
        : "cc"
    );

    R15++;
    DREG = v;
    TESTR14;
    CLRFLAGS;
    
    DEFEAT_TAIL_MERGE;
}

/* 9f - fmult - 16 bit to 32 bit signed multiplication, upper 16 bits only */
static inline void fx_fmult(uint8 unused)
{
    uint32 v = SEX16(SREG) * SEX16(R6);
    asm (
        "msr cpsr_f, %0\n\t"
        "asrs %1, %1, #16\n\t"
        "mrs %0, cpsr\n\t"
        : "+r" (ARMFLAGS),
          "+r" (v)
        ::"cc"
    );

    R15++;
    DREG = v;
    TESTR14;
    CLRFLAGS;
    
    DEFEAT_TAIL_MERGE;
}

/* 9f(ALT1) - lmult - 16 bit to 32 bit signed multiplication */
static inline void fx_lmult(uint8 unused)
{
    uint32 full = SEX16(SREG) * SEX16(R6);
    uint16 resultHigh, resultLow = full;
    asm (
        "msr cpsr_f, %0\n\t"
        "asrs %1, %2, #16\n\t"
        "mrs %0, cpsr\n\t"
        : "+r" (ARMFLAGS),
          "=r" (resultHigh)
        : "r" (full)
        : "cc"
    );
    R4 = resultLow;

    R15++;
    DREG = resultHigh;
    TESTR14;
    CLRFLAGS;
    
    DEFEAT_TAIL_MERGE;
}

/* a0-af - ibt rn,#pp - immediate byte transfer */
static inline void fx_ibt_r(uint8 reg) {
    ASSUME_REG(0, 15);
    uint8 v = PIPE;
    R15++;
    FETCHPIPE;
    R15++;
    GSU.avReg[reg] = SEX8(v);
    CLRFLAGS;
    
    DEFEAT_TAIL_MERGE;
}

static inline void fx_ibt_r14(uint8 unused) {
    fx_ibt_r(14);
    READR14;
    
    DEFEAT_TAIL_MERGE;
}

/* a0-af(ALT1) - lms rn,(yy) - load word from RAM (short address) */
static inline void fx_lms_r(uint8 reg) {
    ASSUME_REG(0, 15);
    GSU.vLastRamAdr = PIPE << 1;
    uint32 r15 = R15 + 1;
    FETCHPIPE2(r15);
    R15 = r15 + 1;
    GSU.avReg[reg] =   (uint16) RAM(GSU.vLastRamAdr)
                   | (((uint16) RAM(GSU.vLastRamAdr + 1)) << 8);
    CLRFLAGS;
    
    DEFEAT_TAIL_MERGE;
}

static inline void fx_lms_r14(uint8 unused) {
    fx_lms_r(14);
    READR14;
    
    DEFEAT_TAIL_MERGE;
}

/* a0-af(ALT2) - sms (yy),rn - store word in RAM (short address) */
/* If rn == r15, is the value of r15 before or after the extra byte is read? */
static inline void fx_sms_r(uint8 reg) {
    ASSUME_REG(0, 15);
    uint16 v = GSU.avReg[reg];
    GSU.vLastRamAdr = PIPE << 1;
    R15++;
    FETCHPIPE;
    RAM(GSU.vLastRamAdr) = (uint8)v;
    RAM(GSU.vLastRamAdr+1) = (uint8)(v>>8);
    CLRFLAGS;
    R15++;
    
    DEFEAT_TAIL_MERGE;
}

/* b0-bf - from rn - set source register */
/* b0-bf(B) - moves rn - move register to register, and set flags, (if B flag is set) */
static inline void fx_from_r(uint8 reg) {
    ASSUME_REG(0, 15);
    if(TF(B)) {
        uint32 tmp, v = GSU.avReg[reg];
        ARMFLAGS &= ~(ARM_NEGATIVE | ARM_ZERO | ARM_OVERFLOW);
        asm (
            "lsls %1, %2, #24\n\t"
            "orrmi %0, %0, %5\n\t"
            "lsls %1, %2, #16\n\t"
            "orrmi %0, %0, %3\n\t"
            "orreq %0, %0, %4\n\t"
            : "+r" (ARMFLAGS),
              "=r" (tmp)
            : "r" (v),
              "i" (ARM_NEGATIVE),
              "i" (ARM_ZERO),
              "i" (ARM_OVERFLOW)
            : "cc"
        );

        R15++;
        DREG = v;
        TESTR14;
        CLRFLAGS;
    }
    else {
        SREG_PTR = &GSU.avReg[reg];
        R15++;
    }
    
    DEFEAT_TAIL_MERGE;
}

/* c0 - hib - move high-byte to low-byte */
static inline void fx_hib(uint8 unused)
{
    uint32 v = SREG >> 8;
    asm (
        "msr cpsr_f, %0\n\t"
        "movs %0, %1\n\t"
        "mrs %0, cpsr\n\t"
        : "+r" (ARMFLAGS)
        : "r" (SEX8(v))
        : "cc"
    );

    R15++;
    DREG = v;
    TESTR14;
    CLRFLAGS;
    
    DEFEAT_TAIL_MERGE;
}

/* c1-cf - or rn */
static inline void fx_or_r(uint8 reg) {
    ASSUME_REG(1, 15);

    uint32 v;
    asm (
        "msr cpsr_f, %0\n\t"
        "orrs %1, %2, %3\n\t"
        "mrs %0, cpsr\n\t"
        : "+r" (ARMFLAGS),
          "=r" (v)
        : "r" (SREG | (SREG << 16)),
          "r" (GSU.avReg[reg] | (GSU.avReg[reg] << 16)) // WYATT_TODO check this ASM
        : "cc"
    );

    R15++;
    DREG = v;
    TESTR14;
    CLRFLAGS;
    
    DEFEAT_TAIL_MERGE;
}

/* c1-cf(ALT1) - xor rn */
static inline void fx_xor_r(uint8 reg) {
    ASSUME_REG(1, 15);

    uint32 v;
    asm (
        "msr cpsr_f, %0\n\t"
        "eors %1, %2, %3\n\t"
        "mrs %0, cpsr\n\t"
        : "+r" (ARMFLAGS),
          "=r" (v)
        : "r" (SREG | (SREG << 16)),
          "r" (GSU.avReg[reg] | (GSU.avReg[reg] << 16))
        : "cc"
    );

    R15++;
    DREG = v;
    TESTR14;
    CLRFLAGS;
    
    DEFEAT_TAIL_MERGE;
}

/* c1-cf(ALT2) - or #n */
static inline void fx_or_i(uint8 imm) {
    ASSUME_IMM(1, 15);

    uint32 v;
    asm (
        "msr cpsr_f, %0\n\t"
        "orrs %1, %2, %3\n\t"
        "mrs %0, cpsr\n\t"
        : "+r" (ARMFLAGS),
          "=r" (v)
        : "r" (SREG | (SREG << 16)),
          "r" (imm) // Doesn't need shift because this can't change the sign
        : "cc"
    );

    R15++;
    DREG = v;
    TESTR14;
    CLRFLAGS;
    
    DEFEAT_TAIL_MERGE;
}

/* c1-cf(ALT3) - xor #n */
static inline void fx_xor_i(uint8 imm) {
    ASSUME_IMM(1, 15);

    uint32 v;
    asm (
        "msr cpsr_f, %0\n\t"
        "eors %1, %2, %3\n\t"
        "mrs %0, cpsr\n\t"
        : "+r" (ARMFLAGS),
          "=r" (v)
        : "r" (SREG | (SREG << 16)),
          "r" (imm | (imm << 16))
        : "cc"
    );

    R15++;
    DREG = v;
    TESTR14;
    CLRFLAGS;
    
    DEFEAT_TAIL_MERGE;
}

/* d0-de - inc rn - increase by one */
static inline void fx_inc_r(uint8 reg) {
    ASSUME_REG(0, 14);

    uint32 v = GSU.avReg[reg] + 1;
    asm (
        "msr cpsr_f, %0\n\t"
        "lsl %0, %1, #16\n\t"
        "movs %0, %0\n\t"
        "mrs %0, cpsr\n\t"
        : "+r" (ARMFLAGS)
        : "r" (v)
        : "cc"
    );
    GSU.avReg[reg] = v;

    CLRFLAGS;
    R15++;
    
    DEFEAT_TAIL_MERGE;
}

static inline void fx_inc_r14(uint8 unused) {
    fx_inc_r(14);
    READR14;
    
    DEFEAT_TAIL_MERGE;
}

/* df - getc - transfer ROM buffer to color register */
static inline void fx_getc(uint8 unused)
{
#ifndef FX_DO_ROMBUFFER
    uint8 c = ROM(R14);
#else
    uint8 c = GSU.vRomBuffer;
#endif
    if(GSU.vPlotOptionReg & 0x04)
	    c = (c & 0xf0) | (c >> 4);

    if(GSU.vPlotOptionReg & 0x08)
    {
        GSU.vColorReg &= 0xf0;
        GSU.vColorReg |= c & 0x0f;
    }
    else
	    GSU.vColorReg = USEX8(c);

    CLRFLAGS;
    R15++;
    
    DEFEAT_TAIL_MERGE;
}

/* df(ALT2) - ramb - set current RAM bank */
static inline void fx_ramb(uint8 unused)
{
    GSU.vRamBankReg = SREG & (FX_RAM_BANKS-1);
    GSU.pvRamBank = GSU.apvRamBank[GSU.vRamBankReg & (FX_RAM_BANKS-1)];
    CLRFLAGS;
    R15++;
    
    DEFEAT_TAIL_MERGE;
}

/* df(ALT3) - romb - set current ROM bank */
static inline void fx_romb(uint8 unused)
{
    GSU.vRomBankReg = USEX8(SREG) & 0x7f;
    GSU.pvRomBank = GSU.apvRomBank[GSU.vRomBankReg];
    CLRFLAGS;
    R15++;
    
    DEFEAT_TAIL_MERGE;
}

/* e0-ee - dec rn - decrement by one */
static inline void fx_dec_r(uint8 reg) {
    ASSUME_REG(0, 14);

    uint32 resultNew = GSU.avReg[reg] - 1;
    asm (
        "msr cpsr_f, %0\n\t"
        "lsl %0, %1, #16\n\t"
        "movs %0, %0\n\t"
        "mrs %0, cpsr\n\t"
        : "+r" (ARMFLAGS)
        : "r" (resultNew)
        : "cc"
    );
    GSU.avReg[reg] = resultNew;

    CLRFLAGS;
    R15++;
    
    DEFEAT_TAIL_MERGE;
}

static inline void fx_dec_r14(uint8 unused) {
    fx_dec_r(14);
    READR14;
    
    DEFEAT_TAIL_MERGE;
}

/* ef - getb - get byte from ROM at address R14 */
static inline void fx_getb(uint8 unused)
{
    uint32 v;
#ifndef FX_DO_ROMBUFFER
    v = (uint32)ROM(R14);
#else
    v = (uint32)GSU.vRomBuffer;
#endif
    R15++;
    DREG = v;
    TESTR14;
    CLRFLAGS;
    
    DEFEAT_TAIL_MERGE;
}

/* ef(ALT1) - getbh - get high-byte from ROM at address R14 */
static inline void fx_getbh(uint8 unused)
{
    uint32 v;
#ifndef FX_DO_ROMBUFFER
    uint32 c = (uint32) ROM(R14);
#else
    uint32 c = USEX8(GSU.vRomBuffer);
#endif
    v = USEX8(SREG) | (c<<8);
    R15++;
    DREG = v;
    TESTR14;
    CLRFLAGS;
    
    DEFEAT_TAIL_MERGE;
}

/* ef(ALT2) - getbl - get low-byte from ROM at address R14 */
static inline void fx_getbl(uint8 unused)
{
    uint32 v;
#ifndef FX_DO_ROMBUFFER
    uint32 c = (uint32) ROM(R14);
#else
    uint32 c = USEX8(GSU.vRomBuffer);
#endif
    v = (SREG & 0xff00) | c;
    R15++;
    DREG = v;
    TESTR14;
    CLRFLAGS;
    
    DEFEAT_TAIL_MERGE;
}

/* ef(ALT3) - getbs - get sign extended byte from ROM at address R14 */
static inline void fx_getbs(uint8 unused)
{
    uint32 v;
#ifndef FX_DO_ROMBUFFER
    int8 c = ROM(R14);
    v = SEX8(c);
#else
    v = SEX8(GSU.vRomBuffer);
#endif
    R15++;
    DREG = v;
    TESTR14;
    CLRFLAGS;
    
    DEFEAT_TAIL_MERGE;
}

/* f0-ff - iwt rn,#xx - immediate word transfer to register */
static inline void fx_iwt_r(uint8 reg) {
    ASSUME_REG(0, 15);
    uint16 v = PIPE;
    uint32 r15 = R15 + 1;
    FETCHPIPE2(r15);
    r15++;
    v |= USEX8(PIPE) << 8;
    FETCHPIPE2(r15);
    R15 = r15 + 1;
    GSU.avReg[reg] = v;
    CLRFLAGS;
    
    DEFEAT_TAIL_MERGE;
}

static inline void fx_iwt_r14(uint8 unused) {
    fx_iwt_r(14);
    READR14;
    
    DEFEAT_TAIL_MERGE;
}

/* f0-ff(ALT1) - lm rn,(xx) - load word from RAM */
static inline void fx_lm_r(uint8 reg) {
    ASSUME_REG(0, 15);
    GSU.vLastRamAdr = PIPE;
    uint32 r15 = R15 + 1;
    FETCHPIPE2(r15);
    r15++;
    GSU.vLastRamAdr |= PIPE << 8;
    FETCHPIPE2(r15);
    R15 = r15 + 1;
    GSU.avReg[reg] = RAM(GSU.vLastRamAdr)
                   | USEX8(RAM(GSU.vLastRamAdr^1)) << 8;
    CLRFLAGS;
    
    DEFEAT_TAIL_MERGE;
}

static inline void fx_lm_r14(uint8 unused) {
    fx_lm_r(14);
    READR14;
    
    DEFEAT_TAIL_MERGE;
}

/* f0-ff(ALT2) - sm (xx),rn - store word in RAM */
/* If rn == r15, is the value of r15 before or after the extra bytes are read? */
static inline void fx_sm_r(uint8 reg) {
    ASSUME_REG(0, 15);
    uint16 v = GSU.avReg[reg];
    GSU.vLastRamAdr = PIPE;
    R15++;
    FETCHPIPE;
    R15++;
    GSU.vLastRamAdr |= PIPE << 8;
    FETCHPIPE;
    RAM(GSU.vLastRamAdr) = (uint8)v;
    RAM(GSU.vLastRamAdr^1) = (uint8)(v>>8);
    CLRFLAGS;
    R15++;
    
    DEFEAT_TAIL_MERGE;
}

/*** GSU executions functions ***/

#define DISPATCH {                                         \
    if (UNLIKELY(--vCounter == 0)) goto loop_end;          \
    uint16 vOpcode = PIPE | (SFR & (FLG_ALT1 | FLG_ALT2)); \
    vLow = vOpcode & 0xf;                                  \
    FETCHPIPE;                                             \
    DEFEAT_TAIL_MERGE;                                     \
    goto *opcode_goto_table[vOpcode];                      \
}

#define HANDLER(func_)     \
    handle_ ## func_: {    \
        func_(vLow);       \
        DISPATCH;          \
    }

#define HANDLER_PTR(func_) &&handle_ ## func_

static uint32 fx_run(uint32 nInstructions)
{
    PUSH_RESERVED;
    fx_load_reserved();

    static void* opcode_goto_table[0x400] = {
        [0x000] = HANDLER_PTR(fx_stop),
        [0x001] = HANDLER_PTR(fx_nop),
        [0x002] = HANDLER_PTR(fx_cache),
        [0x003] = HANDLER_PTR(fx_lsr),
        [0x004] = HANDLER_PTR(fx_rol),
        [0x005] = HANDLER_PTR(fx_bra),
        [0x006] = HANDLER_PTR(fx_bge),
        [0x007] = HANDLER_PTR(fx_blt),
        [0x008] = HANDLER_PTR(fx_bne),
        [0x009] = HANDLER_PTR(fx_beq),
        [0x00a] = HANDLER_PTR(fx_bpl),
        [0x00b] = HANDLER_PTR(fx_bmi),
        [0x00c] = HANDLER_PTR(fx_bcc),
        [0x00d] = HANDLER_PTR(fx_bcs),
        [0x00e] = HANDLER_PTR(fx_bvc),
        [0x00f] = HANDLER_PTR(fx_bvs),
        [0x010] = HANDLER_PTR(fx_to_r),
        [0x011] = HANDLER_PTR(fx_to_r),
        [0x012] = HANDLER_PTR(fx_to_r),
        [0x013] = HANDLER_PTR(fx_to_r),
        [0x014] = HANDLER_PTR(fx_to_r),
        [0x015] = HANDLER_PTR(fx_to_r),
        [0x016] = HANDLER_PTR(fx_to_r),
        [0x017] = HANDLER_PTR(fx_to_r),
        [0x018] = HANDLER_PTR(fx_to_r),
        [0x019] = HANDLER_PTR(fx_to_r),
        [0x01a] = HANDLER_PTR(fx_to_r),
        [0x01b] = HANDLER_PTR(fx_to_r),
        [0x01c] = HANDLER_PTR(fx_to_r),
        [0x01d] = HANDLER_PTR(fx_to_r),
        [0x01e] = HANDLER_PTR(fx_to_r14),
        [0x01f] = HANDLER_PTR(fx_to_r15),
        [0x020] = HANDLER_PTR(fx_with),
        [0x021] = HANDLER_PTR(fx_with),
        [0x022] = HANDLER_PTR(fx_with),
        [0x023] = HANDLER_PTR(fx_with),
        [0x024] = HANDLER_PTR(fx_with),
        [0x025] = HANDLER_PTR(fx_with),
        [0x026] = HANDLER_PTR(fx_with),
        [0x027] = HANDLER_PTR(fx_with),
        [0x028] = HANDLER_PTR(fx_with),
        [0x029] = HANDLER_PTR(fx_with),
        [0x02a] = HANDLER_PTR(fx_with),
        [0x02b] = HANDLER_PTR(fx_with),
        [0x02c] = HANDLER_PTR(fx_with),
        [0x02d] = HANDLER_PTR(fx_with),
        [0x02e] = HANDLER_PTR(fx_with),
        [0x02f] = HANDLER_PTR(fx_with),
        [0x030] = HANDLER_PTR(fx_stw_r),
        [0x031] = HANDLER_PTR(fx_stw_r),
        [0x032] = HANDLER_PTR(fx_stw_r),
        [0x033] = HANDLER_PTR(fx_stw_r),
        [0x034] = HANDLER_PTR(fx_stw_r),
        [0x035] = HANDLER_PTR(fx_stw_r),
        [0x036] = HANDLER_PTR(fx_stw_r),
        [0x037] = HANDLER_PTR(fx_stw_r),
        [0x038] = HANDLER_PTR(fx_stw_r),
        [0x039] = HANDLER_PTR(fx_stw_r),
        [0x03a] = HANDLER_PTR(fx_stw_r),
        [0x03b] = HANDLER_PTR(fx_stw_r),
        [0x03c] = HANDLER_PTR(fx_loop),
        [0x03d] = HANDLER_PTR(fx_alt1),
        [0x03e] = HANDLER_PTR(fx_alt2),
        [0x03f] = HANDLER_PTR(fx_alt3),
        [0x040] = HANDLER_PTR(fx_ldw_r),
        [0x041] = HANDLER_PTR(fx_ldw_r),
        [0x042] = HANDLER_PTR(fx_ldw_r),
        [0x043] = HANDLER_PTR(fx_ldw_r),
        [0x044] = HANDLER_PTR(fx_ldw_r),
        [0x045] = HANDLER_PTR(fx_ldw_r),
        [0x046] = HANDLER_PTR(fx_ldw_r),
        [0x047] = HANDLER_PTR(fx_ldw_r),
        [0x048] = HANDLER_PTR(fx_ldw_r),
        [0x049] = HANDLER_PTR(fx_ldw_r),
        [0x04a] = HANDLER_PTR(fx_ldw_r),
        [0x04b] = HANDLER_PTR(fx_ldw_r),
        [0x04c] = HANDLER_PTR(fx_plot_2bit),
        [0x04d] = HANDLER_PTR(fx_swap),
        [0x04e] = HANDLER_PTR(fx_color),
        [0x04f] = HANDLER_PTR(fx_not),
        [0x050] = HANDLER_PTR(fx_add_r),
        [0x051] = HANDLER_PTR(fx_add_r),
        [0x052] = HANDLER_PTR(fx_add_r),
        [0x053] = HANDLER_PTR(fx_add_r),
        [0x054] = HANDLER_PTR(fx_add_r),
        [0x055] = HANDLER_PTR(fx_add_r),
        [0x056] = HANDLER_PTR(fx_add_r),
        [0x057] = HANDLER_PTR(fx_add_r),
        [0x058] = HANDLER_PTR(fx_add_r),
        [0x059] = HANDLER_PTR(fx_add_r),
        [0x05a] = HANDLER_PTR(fx_add_r),
        [0x05b] = HANDLER_PTR(fx_add_r),
        [0x05c] = HANDLER_PTR(fx_add_r),
        [0x05d] = HANDLER_PTR(fx_add_r),
        [0x05e] = HANDLER_PTR(fx_add_r),
        [0x05f] = HANDLER_PTR(fx_add_r),
        [0x060] = HANDLER_PTR(fx_sub_r),
        [0x061] = HANDLER_PTR(fx_sub_r),
        [0x062] = HANDLER_PTR(fx_sub_r),
        [0x063] = HANDLER_PTR(fx_sub_r),
        [0x064] = HANDLER_PTR(fx_sub_r),
        [0x065] = HANDLER_PTR(fx_sub_r),
        [0x066] = HANDLER_PTR(fx_sub_r),
        [0x067] = HANDLER_PTR(fx_sub_r),
        [0x068] = HANDLER_PTR(fx_sub_r),
        [0x069] = HANDLER_PTR(fx_sub_r),
        [0x06a] = HANDLER_PTR(fx_sub_r),
        [0x06b] = HANDLER_PTR(fx_sub_r),
        [0x06c] = HANDLER_PTR(fx_sub_r),
        [0x06d] = HANDLER_PTR(fx_sub_r),
        [0x06e] = HANDLER_PTR(fx_sub_r),
        [0x06f] = HANDLER_PTR(fx_sub_r),
        [0x070] = HANDLER_PTR(fx_merge),
        [0x071] = HANDLER_PTR(fx_and_r),
        [0x072] = HANDLER_PTR(fx_and_r),
        [0x073] = HANDLER_PTR(fx_and_r),
        [0x074] = HANDLER_PTR(fx_and_r),
        [0x075] = HANDLER_PTR(fx_and_r),
        [0x076] = HANDLER_PTR(fx_and_r),
        [0x077] = HANDLER_PTR(fx_and_r),
        [0x078] = HANDLER_PTR(fx_and_r),
        [0x079] = HANDLER_PTR(fx_and_r),
        [0x07a] = HANDLER_PTR(fx_and_r),
        [0x07b] = HANDLER_PTR(fx_and_r),
        [0x07c] = HANDLER_PTR(fx_and_r),
        [0x07d] = HANDLER_PTR(fx_and_r),
        [0x07e] = HANDLER_PTR(fx_and_r),
        [0x07f] = HANDLER_PTR(fx_and_r),
        [0x080] = HANDLER_PTR(fx_mult_r),
        [0x081] = HANDLER_PTR(fx_mult_r),
        [0x082] = HANDLER_PTR(fx_mult_r),
        [0x083] = HANDLER_PTR(fx_mult_r),
        [0x084] = HANDLER_PTR(fx_mult_r),
        [0x085] = HANDLER_PTR(fx_mult_r),
        [0x086] = HANDLER_PTR(fx_mult_r),
        [0x087] = HANDLER_PTR(fx_mult_r),
        [0x088] = HANDLER_PTR(fx_mult_r),
        [0x089] = HANDLER_PTR(fx_mult_r),
        [0x08a] = HANDLER_PTR(fx_mult_r),
        [0x08b] = HANDLER_PTR(fx_mult_r),
        [0x08c] = HANDLER_PTR(fx_mult_r),
        [0x08d] = HANDLER_PTR(fx_mult_r),
        [0x08e] = HANDLER_PTR(fx_mult_r),
        [0x08f] = HANDLER_PTR(fx_mult_r),
        [0x090] = HANDLER_PTR(fx_sbk),
        [0x091] = HANDLER_PTR(fx_link_i),
        [0x092] = HANDLER_PTR(fx_link_i),
        [0x093] = HANDLER_PTR(fx_link_i),
        [0x094] = HANDLER_PTR(fx_link_i),
        [0x095] = HANDLER_PTR(fx_sex),
        [0x096] = HANDLER_PTR(fx_asr),
        [0x097] = HANDLER_PTR(fx_ror),
        [0x098] = HANDLER_PTR(fx_jmp_r),
        [0x099] = HANDLER_PTR(fx_jmp_r),
        [0x09a] = HANDLER_PTR(fx_jmp_r),
        [0x09b] = HANDLER_PTR(fx_jmp_r),
        [0x09c] = HANDLER_PTR(fx_jmp_r),
        [0x09d] = HANDLER_PTR(fx_jmp_r),
        [0x09e] = HANDLER_PTR(fx_lob),
        [0x09f] = HANDLER_PTR(fx_fmult),
        [0x0a0] = HANDLER_PTR(fx_ibt_r),
        [0x0a1] = HANDLER_PTR(fx_ibt_r),
        [0x0a2] = HANDLER_PTR(fx_ibt_r),
        [0x0a3] = HANDLER_PTR(fx_ibt_r),
        [0x0a4] = HANDLER_PTR(fx_ibt_r),
        [0x0a5] = HANDLER_PTR(fx_ibt_r),
        [0x0a6] = HANDLER_PTR(fx_ibt_r),
        [0x0a7] = HANDLER_PTR(fx_ibt_r),
        [0x0a8] = HANDLER_PTR(fx_ibt_r),
        [0x0a9] = HANDLER_PTR(fx_ibt_r),
        [0x0aa] = HANDLER_PTR(fx_ibt_r),
        [0x0ab] = HANDLER_PTR(fx_ibt_r),
        [0x0ac] = HANDLER_PTR(fx_ibt_r),
        [0x0ad] = HANDLER_PTR(fx_ibt_r),
        [0x0ae] = HANDLER_PTR(fx_ibt_r14),
        [0x0af] = HANDLER_PTR(fx_ibt_r),
        [0x0b0] = HANDLER_PTR(fx_from_r),
        [0x0b1] = HANDLER_PTR(fx_from_r),
        [0x0b2] = HANDLER_PTR(fx_from_r),
        [0x0b3] = HANDLER_PTR(fx_from_r),
        [0x0b4] = HANDLER_PTR(fx_from_r),
        [0x0b5] = HANDLER_PTR(fx_from_r),
        [0x0b6] = HANDLER_PTR(fx_from_r),
        [0x0b7] = HANDLER_PTR(fx_from_r),
        [0x0b8] = HANDLER_PTR(fx_from_r),
        [0x0b9] = HANDLER_PTR(fx_from_r),
        [0x0ba] = HANDLER_PTR(fx_from_r),
        [0x0bb] = HANDLER_PTR(fx_from_r),
        [0x0bc] = HANDLER_PTR(fx_from_r),
        [0x0bd] = HANDLER_PTR(fx_from_r),
        [0x0be] = HANDLER_PTR(fx_from_r),
        [0x0bf] = HANDLER_PTR(fx_from_r),
        [0x0c0] = HANDLER_PTR(fx_hib),
        [0x0c1] = HANDLER_PTR(fx_or_r),
        [0x0c2] = HANDLER_PTR(fx_or_r),
        [0x0c3] = HANDLER_PTR(fx_or_r),
        [0x0c4] = HANDLER_PTR(fx_or_r),
        [0x0c5] = HANDLER_PTR(fx_or_r),
        [0x0c6] = HANDLER_PTR(fx_or_r),
        [0x0c7] = HANDLER_PTR(fx_or_r),
        [0x0c8] = HANDLER_PTR(fx_or_r),
        [0x0c9] = HANDLER_PTR(fx_or_r),
        [0x0ca] = HANDLER_PTR(fx_or_r),
        [0x0cb] = HANDLER_PTR(fx_or_r),
        [0x0cc] = HANDLER_PTR(fx_or_r),
        [0x0cd] = HANDLER_PTR(fx_or_r),
        [0x0ce] = HANDLER_PTR(fx_or_r),
        [0x0cf] = HANDLER_PTR(fx_or_r),
        [0x0d0] = HANDLER_PTR(fx_inc_r),
        [0x0d1] = HANDLER_PTR(fx_inc_r),
        [0x0d2] = HANDLER_PTR(fx_inc_r),
        [0x0d3] = HANDLER_PTR(fx_inc_r),
        [0x0d4] = HANDLER_PTR(fx_inc_r),
        [0x0d5] = HANDLER_PTR(fx_inc_r),
        [0x0d6] = HANDLER_PTR(fx_inc_r),
        [0x0d7] = HANDLER_PTR(fx_inc_r),
        [0x0d8] = HANDLER_PTR(fx_inc_r),
        [0x0d9] = HANDLER_PTR(fx_inc_r),
        [0x0da] = HANDLER_PTR(fx_inc_r),
        [0x0db] = HANDLER_PTR(fx_inc_r),
        [0x0dc] = HANDLER_PTR(fx_inc_r),
        [0x0dd] = HANDLER_PTR(fx_inc_r),
        [0x0de] = HANDLER_PTR(fx_inc_r14),
        [0x0df] = HANDLER_PTR(fx_getc),
        [0x0e0] = HANDLER_PTR(fx_dec_r),
        [0x0e1] = HANDLER_PTR(fx_dec_r),
        [0x0e2] = HANDLER_PTR(fx_dec_r),
        [0x0e3] = HANDLER_PTR(fx_dec_r),
        [0x0e4] = HANDLER_PTR(fx_dec_r),
        [0x0e5] = HANDLER_PTR(fx_dec_r),
        [0x0e6] = HANDLER_PTR(fx_dec_r),
        [0x0e7] = HANDLER_PTR(fx_dec_r),
        [0x0e8] = HANDLER_PTR(fx_dec_r),
        [0x0e9] = HANDLER_PTR(fx_dec_r),
        [0x0ea] = HANDLER_PTR(fx_dec_r),
        [0x0eb] = HANDLER_PTR(fx_dec_r),
        [0x0ec] = HANDLER_PTR(fx_dec_r),
        [0x0ed] = HANDLER_PTR(fx_dec_r),
        [0x0ee] = HANDLER_PTR(fx_dec_r14),
        [0x0ef] = HANDLER_PTR(fx_getb),
        [0x0f0] = HANDLER_PTR(fx_iwt_r),
        [0x0f1] = HANDLER_PTR(fx_iwt_r),
        [0x0f2] = HANDLER_PTR(fx_iwt_r),
        [0x0f3] = HANDLER_PTR(fx_iwt_r),
        [0x0f4] = HANDLER_PTR(fx_iwt_r),
        [0x0f5] = HANDLER_PTR(fx_iwt_r),
        [0x0f6] = HANDLER_PTR(fx_iwt_r),
        [0x0f7] = HANDLER_PTR(fx_iwt_r),
        [0x0f8] = HANDLER_PTR(fx_iwt_r),
        [0x0f9] = HANDLER_PTR(fx_iwt_r),
        [0x0fa] = HANDLER_PTR(fx_iwt_r),
        [0x0fb] = HANDLER_PTR(fx_iwt_r),
        [0x0fc] = HANDLER_PTR(fx_iwt_r),
        [0x0fd] = HANDLER_PTR(fx_iwt_r),
        [0x0fe] = HANDLER_PTR(fx_iwt_r14),
        [0x0ff] = HANDLER_PTR(fx_iwt_r),
        [0x100] = HANDLER_PTR(fx_stop),
        [0x101] = HANDLER_PTR(fx_nop),
        [0x102] = HANDLER_PTR(fx_cache),
        [0x103] = HANDLER_PTR(fx_lsr),
        [0x104] = HANDLER_PTR(fx_rol),
        [0x105] = HANDLER_PTR(fx_bra),
        [0x106] = HANDLER_PTR(fx_bge),
        [0x107] = HANDLER_PTR(fx_blt),
        [0x108] = HANDLER_PTR(fx_bne),
        [0x109] = HANDLER_PTR(fx_beq),
        [0x10a] = HANDLER_PTR(fx_bpl),
        [0x10b] = HANDLER_PTR(fx_bmi),
        [0x10c] = HANDLER_PTR(fx_bcc),
        [0x10d] = HANDLER_PTR(fx_bcs),
        [0x10e] = HANDLER_PTR(fx_bvc),
        [0x10f] = HANDLER_PTR(fx_bvs),
        [0x110] = HANDLER_PTR(fx_to_r),
        [0x111] = HANDLER_PTR(fx_to_r),
        [0x112] = HANDLER_PTR(fx_to_r),
        [0x113] = HANDLER_PTR(fx_to_r),
        [0x114] = HANDLER_PTR(fx_to_r),
        [0x115] = HANDLER_PTR(fx_to_r),
        [0x116] = HANDLER_PTR(fx_to_r),
        [0x117] = HANDLER_PTR(fx_to_r),
        [0x118] = HANDLER_PTR(fx_to_r),
        [0x119] = HANDLER_PTR(fx_to_r),
        [0x11a] = HANDLER_PTR(fx_to_r),
        [0x11b] = HANDLER_PTR(fx_to_r),
        [0x11c] = HANDLER_PTR(fx_to_r),
        [0x11d] = HANDLER_PTR(fx_to_r),
        [0x11e] = HANDLER_PTR(fx_to_r14),
        [0x11f] = HANDLER_PTR(fx_to_r15),
        [0x120] = HANDLER_PTR(fx_with),
        [0x121] = HANDLER_PTR(fx_with),
        [0x122] = HANDLER_PTR(fx_with),
        [0x123] = HANDLER_PTR(fx_with),
        [0x124] = HANDLER_PTR(fx_with),
        [0x125] = HANDLER_PTR(fx_with),
        [0x126] = HANDLER_PTR(fx_with),
        [0x127] = HANDLER_PTR(fx_with),
        [0x128] = HANDLER_PTR(fx_with),
        [0x129] = HANDLER_PTR(fx_with),
        [0x12a] = HANDLER_PTR(fx_with),
        [0x12b] = HANDLER_PTR(fx_with),
        [0x12c] = HANDLER_PTR(fx_with),
        [0x12d] = HANDLER_PTR(fx_with),
        [0x12e] = HANDLER_PTR(fx_with),
        [0x12f] = HANDLER_PTR(fx_with),
        [0x130] = HANDLER_PTR(fx_stb_r),
        [0x131] = HANDLER_PTR(fx_stb_r),
        [0x132] = HANDLER_PTR(fx_stb_r),
        [0x133] = HANDLER_PTR(fx_stb_r),
        [0x134] = HANDLER_PTR(fx_stb_r),
        [0x135] = HANDLER_PTR(fx_stb_r),
        [0x136] = HANDLER_PTR(fx_stb_r),
        [0x137] = HANDLER_PTR(fx_stb_r),
        [0x138] = HANDLER_PTR(fx_stb_r),
        [0x139] = HANDLER_PTR(fx_stb_r),
        [0x13a] = HANDLER_PTR(fx_stb_r),
        [0x13b] = HANDLER_PTR(fx_stb_r),
        [0x13c] = HANDLER_PTR(fx_loop),
        [0x13d] = HANDLER_PTR(fx_alt1),
        [0x13e] = HANDLER_PTR(fx_alt2),
        [0x13f] = HANDLER_PTR(fx_alt3),
        [0x140] = HANDLER_PTR(fx_ldb_r),
        [0x141] = HANDLER_PTR(fx_ldb_r),
        [0x142] = HANDLER_PTR(fx_ldb_r),
        [0x143] = HANDLER_PTR(fx_ldb_r),
        [0x144] = HANDLER_PTR(fx_ldb_r),
        [0x145] = HANDLER_PTR(fx_ldb_r),
        [0x146] = HANDLER_PTR(fx_ldb_r),
        [0x147] = HANDLER_PTR(fx_ldb_r),
        [0x148] = HANDLER_PTR(fx_ldb_r),
        [0x149] = HANDLER_PTR(fx_ldb_r),
        [0x14a] = HANDLER_PTR(fx_ldb_r),
        [0x14b] = HANDLER_PTR(fx_ldb_r),
        [0x14c] = HANDLER_PTR(fx_rpix_2bit),
        [0x14d] = HANDLER_PTR(fx_swap),
        [0x14e] = HANDLER_PTR(fx_cmode),
        [0x14f] = HANDLER_PTR(fx_not),
        [0x150] = HANDLER_PTR(fx_adc_r),
        [0x151] = HANDLER_PTR(fx_adc_r),
        [0x152] = HANDLER_PTR(fx_adc_r),
        [0x153] = HANDLER_PTR(fx_adc_r),
        [0x154] = HANDLER_PTR(fx_adc_r),
        [0x155] = HANDLER_PTR(fx_adc_r),
        [0x156] = HANDLER_PTR(fx_adc_r),
        [0x157] = HANDLER_PTR(fx_adc_r),
        [0x158] = HANDLER_PTR(fx_adc_r),
        [0x159] = HANDLER_PTR(fx_adc_r),
        [0x15a] = HANDLER_PTR(fx_adc_r),
        [0x15b] = HANDLER_PTR(fx_adc_r),
        [0x15c] = HANDLER_PTR(fx_adc_r),
        [0x15d] = HANDLER_PTR(fx_adc_r),
        [0x15e] = HANDLER_PTR(fx_adc_r),
        [0x15f] = HANDLER_PTR(fx_adc_r),
        [0x160] = HANDLER_PTR(fx_sbc_r),
        [0x161] = HANDLER_PTR(fx_sbc_r),
        [0x162] = HANDLER_PTR(fx_sbc_r),
        [0x163] = HANDLER_PTR(fx_sbc_r),
        [0x164] = HANDLER_PTR(fx_sbc_r),
        [0x165] = HANDLER_PTR(fx_sbc_r),
        [0x166] = HANDLER_PTR(fx_sbc_r),
        [0x167] = HANDLER_PTR(fx_sbc_r),
        [0x168] = HANDLER_PTR(fx_sbc_r),
        [0x169] = HANDLER_PTR(fx_sbc_r),
        [0x16a] = HANDLER_PTR(fx_sbc_r),
        [0x16b] = HANDLER_PTR(fx_sbc_r),
        [0x16c] = HANDLER_PTR(fx_sbc_r),
        [0x16d] = HANDLER_PTR(fx_sbc_r),
        [0x16e] = HANDLER_PTR(fx_sbc_r),
        [0x16f] = HANDLER_PTR(fx_sbc_r),
        [0x170] = HANDLER_PTR(fx_merge),
        [0x171] = HANDLER_PTR(fx_bic_r),
        [0x172] = HANDLER_PTR(fx_bic_r),
        [0x173] = HANDLER_PTR(fx_bic_r),
        [0x174] = HANDLER_PTR(fx_bic_r),
        [0x175] = HANDLER_PTR(fx_bic_r),
        [0x176] = HANDLER_PTR(fx_bic_r),
        [0x177] = HANDLER_PTR(fx_bic_r),
        [0x178] = HANDLER_PTR(fx_bic_r),
        [0x179] = HANDLER_PTR(fx_bic_r),
        [0x17a] = HANDLER_PTR(fx_bic_r),
        [0x17b] = HANDLER_PTR(fx_bic_r),
        [0x17c] = HANDLER_PTR(fx_bic_r),
        [0x17d] = HANDLER_PTR(fx_bic_r),
        [0x17e] = HANDLER_PTR(fx_bic_r),
        [0x17f] = HANDLER_PTR(fx_bic_r),
        [0x180] = HANDLER_PTR(fx_umult_r),
        [0x181] = HANDLER_PTR(fx_umult_r),
        [0x182] = HANDLER_PTR(fx_umult_r),
        [0x183] = HANDLER_PTR(fx_umult_r),
        [0x184] = HANDLER_PTR(fx_umult_r),
        [0x185] = HANDLER_PTR(fx_umult_r),
        [0x186] = HANDLER_PTR(fx_umult_r),
        [0x187] = HANDLER_PTR(fx_umult_r),
        [0x188] = HANDLER_PTR(fx_umult_r),
        [0x189] = HANDLER_PTR(fx_umult_r),
        [0x18a] = HANDLER_PTR(fx_umult_r),
        [0x18b] = HANDLER_PTR(fx_umult_r),
        [0x18c] = HANDLER_PTR(fx_umult_r),
        [0x18d] = HANDLER_PTR(fx_umult_r),
        [0x18e] = HANDLER_PTR(fx_umult_r),
        [0x18f] = HANDLER_PTR(fx_umult_r),
        [0x190] = HANDLER_PTR(fx_sbk),
        [0x191] = HANDLER_PTR(fx_link_i),
        [0x192] = HANDLER_PTR(fx_link_i),
        [0x193] = HANDLER_PTR(fx_link_i),
        [0x194] = HANDLER_PTR(fx_link_i),
        [0x195] = HANDLER_PTR(fx_sex),
        [0x196] = HANDLER_PTR(fx_div2),
        [0x197] = HANDLER_PTR(fx_ror),
        [0x198] = HANDLER_PTR(fx_ljmp_r),
        [0x199] = HANDLER_PTR(fx_ljmp_r),
        [0x19a] = HANDLER_PTR(fx_ljmp_r),
        [0x19b] = HANDLER_PTR(fx_ljmp_r),
        [0x19c] = HANDLER_PTR(fx_ljmp_r),
        [0x19d] = HANDLER_PTR(fx_ljmp_r),
        [0x19e] = HANDLER_PTR(fx_lob),
        [0x19f] = HANDLER_PTR(fx_lmult),
        [0x1a0] = HANDLER_PTR(fx_lms_r),
        [0x1a1] = HANDLER_PTR(fx_lms_r),
        [0x1a2] = HANDLER_PTR(fx_lms_r),
        [0x1a3] = HANDLER_PTR(fx_lms_r),
        [0x1a4] = HANDLER_PTR(fx_lms_r),
        [0x1a5] = HANDLER_PTR(fx_lms_r),
        [0x1a6] = HANDLER_PTR(fx_lms_r),
        [0x1a7] = HANDLER_PTR(fx_lms_r),
        [0x1a8] = HANDLER_PTR(fx_lms_r),
        [0x1a9] = HANDLER_PTR(fx_lms_r),
        [0x1aa] = HANDLER_PTR(fx_lms_r),
        [0x1ab] = HANDLER_PTR(fx_lms_r),
        [0x1ac] = HANDLER_PTR(fx_lms_r),
        [0x1ad] = HANDLER_PTR(fx_lms_r),
        [0x1ae] = HANDLER_PTR(fx_lms_r14),
        [0x1af] = HANDLER_PTR(fx_lms_r),
        [0x1b0] = HANDLER_PTR(fx_from_r),
        [0x1b1] = HANDLER_PTR(fx_from_r),
        [0x1b2] = HANDLER_PTR(fx_from_r),
        [0x1b3] = HANDLER_PTR(fx_from_r),
        [0x1b4] = HANDLER_PTR(fx_from_r),
        [0x1b5] = HANDLER_PTR(fx_from_r),
        [0x1b6] = HANDLER_PTR(fx_from_r),
        [0x1b7] = HANDLER_PTR(fx_from_r),
        [0x1b8] = HANDLER_PTR(fx_from_r),
        [0x1b9] = HANDLER_PTR(fx_from_r),
        [0x1ba] = HANDLER_PTR(fx_from_r),
        [0x1bb] = HANDLER_PTR(fx_from_r),
        [0x1bc] = HANDLER_PTR(fx_from_r),
        [0x1bd] = HANDLER_PTR(fx_from_r),
        [0x1be] = HANDLER_PTR(fx_from_r),
        [0x1bf] = HANDLER_PTR(fx_from_r),
        [0x1c0] = HANDLER_PTR(fx_hib),
        [0x1c1] = HANDLER_PTR(fx_xor_r),
        [0x1c2] = HANDLER_PTR(fx_xor_r),
        [0x1c3] = HANDLER_PTR(fx_xor_r),
        [0x1c4] = HANDLER_PTR(fx_xor_r),
        [0x1c5] = HANDLER_PTR(fx_xor_r),
        [0x1c6] = HANDLER_PTR(fx_xor_r),
        [0x1c7] = HANDLER_PTR(fx_xor_r),
        [0x1c8] = HANDLER_PTR(fx_xor_r),
        [0x1c9] = HANDLER_PTR(fx_xor_r),
        [0x1ca] = HANDLER_PTR(fx_xor_r),
        [0x1cb] = HANDLER_PTR(fx_xor_r),
        [0x1cc] = HANDLER_PTR(fx_xor_r),
        [0x1cd] = HANDLER_PTR(fx_xor_r),
        [0x1ce] = HANDLER_PTR(fx_xor_r),
        [0x1cf] = HANDLER_PTR(fx_xor_r),
        [0x1d0] = HANDLER_PTR(fx_inc_r),
        [0x1d1] = HANDLER_PTR(fx_inc_r),
        [0x1d2] = HANDLER_PTR(fx_inc_r),
        [0x1d3] = HANDLER_PTR(fx_inc_r),
        [0x1d4] = HANDLER_PTR(fx_inc_r),
        [0x1d5] = HANDLER_PTR(fx_inc_r),
        [0x1d6] = HANDLER_PTR(fx_inc_r),
        [0x1d7] = HANDLER_PTR(fx_inc_r),
        [0x1d8] = HANDLER_PTR(fx_inc_r),
        [0x1d9] = HANDLER_PTR(fx_inc_r),
        [0x1da] = HANDLER_PTR(fx_inc_r),
        [0x1db] = HANDLER_PTR(fx_inc_r),
        [0x1dc] = HANDLER_PTR(fx_inc_r),
        [0x1dd] = HANDLER_PTR(fx_inc_r),
        [0x1de] = HANDLER_PTR(fx_inc_r14),
        [0x1df] = HANDLER_PTR(fx_getc),
        [0x1e0] = HANDLER_PTR(fx_dec_r),
        [0x1e1] = HANDLER_PTR(fx_dec_r),
        [0x1e2] = HANDLER_PTR(fx_dec_r),
        [0x1e3] = HANDLER_PTR(fx_dec_r),
        [0x1e4] = HANDLER_PTR(fx_dec_r),
        [0x1e5] = HANDLER_PTR(fx_dec_r),
        [0x1e6] = HANDLER_PTR(fx_dec_r),
        [0x1e7] = HANDLER_PTR(fx_dec_r),
        [0x1e8] = HANDLER_PTR(fx_dec_r),
        [0x1e9] = HANDLER_PTR(fx_dec_r),
        [0x1ea] = HANDLER_PTR(fx_dec_r),
        [0x1eb] = HANDLER_PTR(fx_dec_r),
        [0x1ec] = HANDLER_PTR(fx_dec_r),
        [0x1ed] = HANDLER_PTR(fx_dec_r),
        [0x1ee] = HANDLER_PTR(fx_dec_r14),
        [0x1ef] = HANDLER_PTR(fx_getbh),
        [0x1f0] = HANDLER_PTR(fx_lm_r),
        [0x1f1] = HANDLER_PTR(fx_lm_r),
        [0x1f2] = HANDLER_PTR(fx_lm_r),
        [0x1f3] = HANDLER_PTR(fx_lm_r),
        [0x1f4] = HANDLER_PTR(fx_lm_r),
        [0x1f5] = HANDLER_PTR(fx_lm_r),
        [0x1f6] = HANDLER_PTR(fx_lm_r),
        [0x1f7] = HANDLER_PTR(fx_lm_r),
        [0x1f8] = HANDLER_PTR(fx_lm_r),
        [0x1f9] = HANDLER_PTR(fx_lm_r),
        [0x1fa] = HANDLER_PTR(fx_lm_r),
        [0x1fb] = HANDLER_PTR(fx_lm_r),
        [0x1fc] = HANDLER_PTR(fx_lm_r),
        [0x1fd] = HANDLER_PTR(fx_lm_r),
        [0x1fe] = HANDLER_PTR(fx_lm_r14),
        [0x1ff] = HANDLER_PTR(fx_lm_r),
        [0x200] = HANDLER_PTR(fx_stop),
        [0x201] = HANDLER_PTR(fx_nop),
        [0x202] = HANDLER_PTR(fx_cache),
        [0x203] = HANDLER_PTR(fx_lsr),
        [0x204] = HANDLER_PTR(fx_rol),
        [0x205] = HANDLER_PTR(fx_bra),
        [0x206] = HANDLER_PTR(fx_bge),
        [0x207] = HANDLER_PTR(fx_blt),
        [0x208] = HANDLER_PTR(fx_bne),
        [0x209] = HANDLER_PTR(fx_beq),
        [0x20a] = HANDLER_PTR(fx_bpl),
        [0x20b] = HANDLER_PTR(fx_bmi),
        [0x20c] = HANDLER_PTR(fx_bcc),
        [0x20d] = HANDLER_PTR(fx_bcs),
        [0x20e] = HANDLER_PTR(fx_bvc),
        [0x20f] = HANDLER_PTR(fx_bvs),
        [0x210] = HANDLER_PTR(fx_to_r),
        [0x211] = HANDLER_PTR(fx_to_r),
        [0x212] = HANDLER_PTR(fx_to_r),
        [0x213] = HANDLER_PTR(fx_to_r),
        [0x214] = HANDLER_PTR(fx_to_r),
        [0x215] = HANDLER_PTR(fx_to_r),
        [0x216] = HANDLER_PTR(fx_to_r),
        [0x217] = HANDLER_PTR(fx_to_r),
        [0x218] = HANDLER_PTR(fx_to_r),
        [0x219] = HANDLER_PTR(fx_to_r),
        [0x21a] = HANDLER_PTR(fx_to_r),
        [0x21b] = HANDLER_PTR(fx_to_r),
        [0x21c] = HANDLER_PTR(fx_to_r),
        [0x21d] = HANDLER_PTR(fx_to_r),
        [0x21e] = HANDLER_PTR(fx_to_r14),
        [0x21f] = HANDLER_PTR(fx_to_r15),
        [0x220] = HANDLER_PTR(fx_with),
        [0x221] = HANDLER_PTR(fx_with),
        [0x222] = HANDLER_PTR(fx_with),
        [0x223] = HANDLER_PTR(fx_with),
        [0x224] = HANDLER_PTR(fx_with),
        [0x225] = HANDLER_PTR(fx_with),
        [0x226] = HANDLER_PTR(fx_with),
        [0x227] = HANDLER_PTR(fx_with),
        [0x228] = HANDLER_PTR(fx_with),
        [0x229] = HANDLER_PTR(fx_with),
        [0x22a] = HANDLER_PTR(fx_with),
        [0x22b] = HANDLER_PTR(fx_with),
        [0x22c] = HANDLER_PTR(fx_with),
        [0x22d] = HANDLER_PTR(fx_with),
        [0x22e] = HANDLER_PTR(fx_with),
        [0x22f] = HANDLER_PTR(fx_with),
        [0x230] = HANDLER_PTR(fx_stw_r),
        [0x231] = HANDLER_PTR(fx_stw_r),
        [0x232] = HANDLER_PTR(fx_stw_r),
        [0x233] = HANDLER_PTR(fx_stw_r),
        [0x234] = HANDLER_PTR(fx_stw_r),
        [0x235] = HANDLER_PTR(fx_stw_r),
        [0x236] = HANDLER_PTR(fx_stw_r),
        [0x237] = HANDLER_PTR(fx_stw_r),
        [0x238] = HANDLER_PTR(fx_stw_r),
        [0x239] = HANDLER_PTR(fx_stw_r),
        [0x23a] = HANDLER_PTR(fx_stw_r),
        [0x23b] = HANDLER_PTR(fx_stw_r),
        [0x23c] = HANDLER_PTR(fx_loop),
        [0x23d] = HANDLER_PTR(fx_alt1),
        [0x23e] = HANDLER_PTR(fx_alt2),
        [0x23f] = HANDLER_PTR(fx_alt3),
        [0x240] = HANDLER_PTR(fx_ldw_r),
        [0x241] = HANDLER_PTR(fx_ldw_r),
        [0x242] = HANDLER_PTR(fx_ldw_r),
        [0x243] = HANDLER_PTR(fx_ldw_r),
        [0x244] = HANDLER_PTR(fx_ldw_r),
        [0x245] = HANDLER_PTR(fx_ldw_r),
        [0x246] = HANDLER_PTR(fx_ldw_r),
        [0x247] = HANDLER_PTR(fx_ldw_r),
        [0x248] = HANDLER_PTR(fx_ldw_r),
        [0x249] = HANDLER_PTR(fx_ldw_r),
        [0x24a] = HANDLER_PTR(fx_ldw_r),
        [0x24b] = HANDLER_PTR(fx_ldw_r),
        [0x24c] = HANDLER_PTR(fx_plot_2bit),
        [0x24d] = HANDLER_PTR(fx_swap),
        [0x24e] = HANDLER_PTR(fx_color),
        [0x24f] = HANDLER_PTR(fx_not),
        [0x250] = HANDLER_PTR(fx_add_i),
        [0x251] = HANDLER_PTR(fx_add_i),
        [0x252] = HANDLER_PTR(fx_add_i),
        [0x253] = HANDLER_PTR(fx_add_i),
        [0x254] = HANDLER_PTR(fx_add_i),
        [0x255] = HANDLER_PTR(fx_add_i),
        [0x256] = HANDLER_PTR(fx_add_i),
        [0x257] = HANDLER_PTR(fx_add_i),
        [0x258] = HANDLER_PTR(fx_add_i),
        [0x259] = HANDLER_PTR(fx_add_i),
        [0x25a] = HANDLER_PTR(fx_add_i),
        [0x25b] = HANDLER_PTR(fx_add_i),
        [0x25c] = HANDLER_PTR(fx_add_i),
        [0x25d] = HANDLER_PTR(fx_add_i),
        [0x25e] = HANDLER_PTR(fx_add_i),
        [0x25f] = HANDLER_PTR(fx_add_i),
        [0x260] = HANDLER_PTR(fx_sub_i),
        [0x261] = HANDLER_PTR(fx_sub_i),
        [0x262] = HANDLER_PTR(fx_sub_i),
        [0x263] = HANDLER_PTR(fx_sub_i),
        [0x264] = HANDLER_PTR(fx_sub_i),
        [0x265] = HANDLER_PTR(fx_sub_i),
        [0x266] = HANDLER_PTR(fx_sub_i),
        [0x267] = HANDLER_PTR(fx_sub_i),
        [0x268] = HANDLER_PTR(fx_sub_i),
        [0x269] = HANDLER_PTR(fx_sub_i),
        [0x26a] = HANDLER_PTR(fx_sub_i),
        [0x26b] = HANDLER_PTR(fx_sub_i),
        [0x26c] = HANDLER_PTR(fx_sub_i),
        [0x26d] = HANDLER_PTR(fx_sub_i),
        [0x26e] = HANDLER_PTR(fx_sub_i),
        [0x26f] = HANDLER_PTR(fx_sub_i),
        [0x270] = HANDLER_PTR(fx_merge),
        [0x271] = HANDLER_PTR(fx_and_i),
        [0x272] = HANDLER_PTR(fx_and_i),
        [0x273] = HANDLER_PTR(fx_and_i),
        [0x274] = HANDLER_PTR(fx_and_i),
        [0x275] = HANDLER_PTR(fx_and_i),
        [0x276] = HANDLER_PTR(fx_and_i),
        [0x277] = HANDLER_PTR(fx_and_i),
        [0x278] = HANDLER_PTR(fx_and_i),
        [0x279] = HANDLER_PTR(fx_and_i),
        [0x27a] = HANDLER_PTR(fx_and_i),
        [0x27b] = HANDLER_PTR(fx_and_i),
        [0x27c] = HANDLER_PTR(fx_and_i),
        [0x27d] = HANDLER_PTR(fx_and_i),
        [0x27e] = HANDLER_PTR(fx_and_i),
        [0x27f] = HANDLER_PTR(fx_and_i),
        [0x280] = HANDLER_PTR(fx_mult_i),
        [0x281] = HANDLER_PTR(fx_mult_i),
        [0x282] = HANDLER_PTR(fx_mult_i),
        [0x283] = HANDLER_PTR(fx_mult_i),
        [0x284] = HANDLER_PTR(fx_mult_i),
        [0x285] = HANDLER_PTR(fx_mult_i),
        [0x286] = HANDLER_PTR(fx_mult_i),
        [0x287] = HANDLER_PTR(fx_mult_i),
        [0x288] = HANDLER_PTR(fx_mult_i),
        [0x289] = HANDLER_PTR(fx_mult_i),
        [0x28a] = HANDLER_PTR(fx_mult_i),
        [0x28b] = HANDLER_PTR(fx_mult_i),
        [0x28c] = HANDLER_PTR(fx_mult_i),
        [0x28d] = HANDLER_PTR(fx_mult_i),
        [0x28e] = HANDLER_PTR(fx_mult_i),
        [0x28f] = HANDLER_PTR(fx_mult_i),
        [0x290] = HANDLER_PTR(fx_sbk),
        [0x291] = HANDLER_PTR(fx_link_i),
        [0x292] = HANDLER_PTR(fx_link_i),
        [0x293] = HANDLER_PTR(fx_link_i),
        [0x294] = HANDLER_PTR(fx_link_i),
        [0x295] = HANDLER_PTR(fx_sex),
        [0x296] = HANDLER_PTR(fx_asr),
        [0x297] = HANDLER_PTR(fx_ror),
        [0x298] = HANDLER_PTR(fx_jmp_r),
        [0x299] = HANDLER_PTR(fx_jmp_r),
        [0x29a] = HANDLER_PTR(fx_jmp_r),
        [0x29b] = HANDLER_PTR(fx_jmp_r),
        [0x29c] = HANDLER_PTR(fx_jmp_r),
        [0x29d] = HANDLER_PTR(fx_jmp_r),
        [0x29e] = HANDLER_PTR(fx_lob),
        [0x29f] = HANDLER_PTR(fx_fmult),
        [0x2a0] = HANDLER_PTR(fx_sms_r),
        [0x2a1] = HANDLER_PTR(fx_sms_r),
        [0x2a2] = HANDLER_PTR(fx_sms_r),
        [0x2a3] = HANDLER_PTR(fx_sms_r),
        [0x2a4] = HANDLER_PTR(fx_sms_r),
        [0x2a5] = HANDLER_PTR(fx_sms_r),
        [0x2a6] = HANDLER_PTR(fx_sms_r),
        [0x2a7] = HANDLER_PTR(fx_sms_r),
        [0x2a8] = HANDLER_PTR(fx_sms_r),
        [0x2a9] = HANDLER_PTR(fx_sms_r),
        [0x2aa] = HANDLER_PTR(fx_sms_r),
        [0x2ab] = HANDLER_PTR(fx_sms_r),
        [0x2ac] = HANDLER_PTR(fx_sms_r),
        [0x2ad] = HANDLER_PTR(fx_sms_r),
        [0x2ae] = HANDLER_PTR(fx_sms_r),
        [0x2af] = HANDLER_PTR(fx_sms_r),
        [0x2b0] = HANDLER_PTR(fx_from_r),
        [0x2b1] = HANDLER_PTR(fx_from_r),
        [0x2b2] = HANDLER_PTR(fx_from_r),
        [0x2b3] = HANDLER_PTR(fx_from_r),
        [0x2b4] = HANDLER_PTR(fx_from_r),
        [0x2b5] = HANDLER_PTR(fx_from_r),
        [0x2b6] = HANDLER_PTR(fx_from_r),
        [0x2b7] = HANDLER_PTR(fx_from_r),
        [0x2b8] = HANDLER_PTR(fx_from_r),
        [0x2b9] = HANDLER_PTR(fx_from_r),
        [0x2ba] = HANDLER_PTR(fx_from_r),
        [0x2bb] = HANDLER_PTR(fx_from_r),
        [0x2bc] = HANDLER_PTR(fx_from_r),
        [0x2bd] = HANDLER_PTR(fx_from_r),
        [0x2be] = HANDLER_PTR(fx_from_r),
        [0x2bf] = HANDLER_PTR(fx_from_r),
        [0x2c0] = HANDLER_PTR(fx_hib),
        [0x2c1] = HANDLER_PTR(fx_or_i),
        [0x2c2] = HANDLER_PTR(fx_or_i),
        [0x2c3] = HANDLER_PTR(fx_or_i),
        [0x2c4] = HANDLER_PTR(fx_or_i),
        [0x2c5] = HANDLER_PTR(fx_or_i),
        [0x2c6] = HANDLER_PTR(fx_or_i),
        [0x2c7] = HANDLER_PTR(fx_or_i),
        [0x2c8] = HANDLER_PTR(fx_or_i),
        [0x2c9] = HANDLER_PTR(fx_or_i),
        [0x2ca] = HANDLER_PTR(fx_or_i),
        [0x2cb] = HANDLER_PTR(fx_or_i),
        [0x2cc] = HANDLER_PTR(fx_or_i),
        [0x2cd] = HANDLER_PTR(fx_or_i),
        [0x2ce] = HANDLER_PTR(fx_or_i),
        [0x2cf] = HANDLER_PTR(fx_or_i),
        [0x2d0] = HANDLER_PTR(fx_inc_r),
        [0x2d1] = HANDLER_PTR(fx_inc_r),
        [0x2d2] = HANDLER_PTR(fx_inc_r),
        [0x2d3] = HANDLER_PTR(fx_inc_r),
        [0x2d4] = HANDLER_PTR(fx_inc_r),
        [0x2d5] = HANDLER_PTR(fx_inc_r),
        [0x2d6] = HANDLER_PTR(fx_inc_r),
        [0x2d7] = HANDLER_PTR(fx_inc_r),
        [0x2d8] = HANDLER_PTR(fx_inc_r),
        [0x2d9] = HANDLER_PTR(fx_inc_r),
        [0x2da] = HANDLER_PTR(fx_inc_r),
        [0x2db] = HANDLER_PTR(fx_inc_r),
        [0x2dc] = HANDLER_PTR(fx_inc_r),
        [0x2dd] = HANDLER_PTR(fx_inc_r),
        [0x2de] = HANDLER_PTR(fx_inc_r14),
        [0x2df] = HANDLER_PTR(fx_ramb),
        [0x2e0] = HANDLER_PTR(fx_dec_r),
        [0x2e1] = HANDLER_PTR(fx_dec_r),
        [0x2e2] = HANDLER_PTR(fx_dec_r),
        [0x2e3] = HANDLER_PTR(fx_dec_r),
        [0x2e4] = HANDLER_PTR(fx_dec_r),
        [0x2e5] = HANDLER_PTR(fx_dec_r),
        [0x2e6] = HANDLER_PTR(fx_dec_r),
        [0x2e7] = HANDLER_PTR(fx_dec_r),
        [0x2e8] = HANDLER_PTR(fx_dec_r),
        [0x2e9] = HANDLER_PTR(fx_dec_r),
        [0x2ea] = HANDLER_PTR(fx_dec_r),
        [0x2eb] = HANDLER_PTR(fx_dec_r),
        [0x2ec] = HANDLER_PTR(fx_dec_r),
        [0x2ed] = HANDLER_PTR(fx_dec_r),
        [0x2ee] = HANDLER_PTR(fx_dec_r14),
        [0x2ef] = HANDLER_PTR(fx_getbl),
        [0x2f0] = HANDLER_PTR(fx_sm_r),
        [0x2f1] = HANDLER_PTR(fx_sm_r),
        [0x2f2] = HANDLER_PTR(fx_sm_r),
        [0x2f3] = HANDLER_PTR(fx_sm_r),
        [0x2f4] = HANDLER_PTR(fx_sm_r),
        [0x2f5] = HANDLER_PTR(fx_sm_r),
        [0x2f6] = HANDLER_PTR(fx_sm_r),
        [0x2f7] = HANDLER_PTR(fx_sm_r),
        [0x2f8] = HANDLER_PTR(fx_sm_r),
        [0x2f9] = HANDLER_PTR(fx_sm_r),
        [0x2fa] = HANDLER_PTR(fx_sm_r),
        [0x2fb] = HANDLER_PTR(fx_sm_r),
        [0x2fc] = HANDLER_PTR(fx_sm_r),
        [0x2fd] = HANDLER_PTR(fx_sm_r),
        [0x2fe] = HANDLER_PTR(fx_sm_r),
        [0x2ff] = HANDLER_PTR(fx_sm_r),
        [0x300] = HANDLER_PTR(fx_stop),
        [0x301] = HANDLER_PTR(fx_nop),
        [0x302] = HANDLER_PTR(fx_cache),
        [0x303] = HANDLER_PTR(fx_lsr),
        [0x304] = HANDLER_PTR(fx_rol),
        [0x305] = HANDLER_PTR(fx_bra),
        [0x306] = HANDLER_PTR(fx_bge),
        [0x307] = HANDLER_PTR(fx_blt),
        [0x308] = HANDLER_PTR(fx_bne),
        [0x309] = HANDLER_PTR(fx_beq),
        [0x30a] = HANDLER_PTR(fx_bpl),
        [0x30b] = HANDLER_PTR(fx_bmi),
        [0x30c] = HANDLER_PTR(fx_bcc),
        [0x30d] = HANDLER_PTR(fx_bcs),
        [0x30e] = HANDLER_PTR(fx_bvc),
        [0x30f] = HANDLER_PTR(fx_bvs),
        [0x310] = HANDLER_PTR(fx_to_r),
        [0x311] = HANDLER_PTR(fx_to_r),
        [0x312] = HANDLER_PTR(fx_to_r),
        [0x313] = HANDLER_PTR(fx_to_r),
        [0x314] = HANDLER_PTR(fx_to_r),
        [0x315] = HANDLER_PTR(fx_to_r),
        [0x316] = HANDLER_PTR(fx_to_r),
        [0x317] = HANDLER_PTR(fx_to_r),
        [0x318] = HANDLER_PTR(fx_to_r),
        [0x319] = HANDLER_PTR(fx_to_r),
        [0x31a] = HANDLER_PTR(fx_to_r),
        [0x31b] = HANDLER_PTR(fx_to_r),
        [0x31c] = HANDLER_PTR(fx_to_r),
        [0x31d] = HANDLER_PTR(fx_to_r),
        [0x31e] = HANDLER_PTR(fx_to_r14),
        [0x31f] = HANDLER_PTR(fx_to_r15),
        [0x320] = HANDLER_PTR(fx_with),
        [0x321] = HANDLER_PTR(fx_with),
        [0x322] = HANDLER_PTR(fx_with),
        [0x323] = HANDLER_PTR(fx_with),
        [0x324] = HANDLER_PTR(fx_with),
        [0x325] = HANDLER_PTR(fx_with),
        [0x326] = HANDLER_PTR(fx_with),
        [0x327] = HANDLER_PTR(fx_with),
        [0x328] = HANDLER_PTR(fx_with),
        [0x329] = HANDLER_PTR(fx_with),
        [0x32a] = HANDLER_PTR(fx_with),
        [0x32b] = HANDLER_PTR(fx_with),
        [0x32c] = HANDLER_PTR(fx_with),
        [0x32d] = HANDLER_PTR(fx_with),
        [0x32e] = HANDLER_PTR(fx_with),
        [0x32f] = HANDLER_PTR(fx_with),
        [0x330] = HANDLER_PTR(fx_stb_r),
        [0x331] = HANDLER_PTR(fx_stb_r),
        [0x332] = HANDLER_PTR(fx_stb_r),
        [0x333] = HANDLER_PTR(fx_stb_r),
        [0x334] = HANDLER_PTR(fx_stb_r),
        [0x335] = HANDLER_PTR(fx_stb_r),
        [0x336] = HANDLER_PTR(fx_stb_r),
        [0x337] = HANDLER_PTR(fx_stb_r),
        [0x338] = HANDLER_PTR(fx_stb_r),
        [0x339] = HANDLER_PTR(fx_stb_r),
        [0x33a] = HANDLER_PTR(fx_stb_r),
        [0x33b] = HANDLER_PTR(fx_stb_r),
        [0x33c] = HANDLER_PTR(fx_loop),
        [0x33d] = HANDLER_PTR(fx_alt1),
        [0x33e] = HANDLER_PTR(fx_alt2),
        [0x33f] = HANDLER_PTR(fx_alt3),
        [0x340] = HANDLER_PTR(fx_ldb_r),
        [0x341] = HANDLER_PTR(fx_ldb_r),
        [0x342] = HANDLER_PTR(fx_ldb_r),
        [0x343] = HANDLER_PTR(fx_ldb_r),
        [0x344] = HANDLER_PTR(fx_ldb_r),
        [0x345] = HANDLER_PTR(fx_ldb_r),
        [0x346] = HANDLER_PTR(fx_ldb_r),
        [0x347] = HANDLER_PTR(fx_ldb_r),
        [0x348] = HANDLER_PTR(fx_ldb_r),
        [0x349] = HANDLER_PTR(fx_ldb_r),
        [0x34a] = HANDLER_PTR(fx_ldb_r),
        [0x34b] = HANDLER_PTR(fx_ldb_r),
        [0x34c] = HANDLER_PTR(fx_rpix_2bit),
        [0x34d] = HANDLER_PTR(fx_swap),
        [0x34e] = HANDLER_PTR(fx_cmode),
        [0x34f] = HANDLER_PTR(fx_not),
        [0x350] = HANDLER_PTR(fx_adc_i),
        [0x351] = HANDLER_PTR(fx_adc_i),
        [0x352] = HANDLER_PTR(fx_adc_i),
        [0x353] = HANDLER_PTR(fx_adc_i),
        [0x354] = HANDLER_PTR(fx_adc_i),
        [0x355] = HANDLER_PTR(fx_adc_i),
        [0x356] = HANDLER_PTR(fx_adc_i),
        [0x357] = HANDLER_PTR(fx_adc_i),
        [0x358] = HANDLER_PTR(fx_adc_i),
        [0x359] = HANDLER_PTR(fx_adc_i),
        [0x35a] = HANDLER_PTR(fx_adc_i),
        [0x35b] = HANDLER_PTR(fx_adc_i),
        [0x35c] = HANDLER_PTR(fx_adc_i),
        [0x35d] = HANDLER_PTR(fx_adc_i),
        [0x35e] = HANDLER_PTR(fx_adc_i),
        [0x35f] = HANDLER_PTR(fx_adc_i),
        [0x360] = HANDLER_PTR(fx_cmp_r),
        [0x361] = HANDLER_PTR(fx_cmp_r),
        [0x362] = HANDLER_PTR(fx_cmp_r),
        [0x363] = HANDLER_PTR(fx_cmp_r),
        [0x364] = HANDLER_PTR(fx_cmp_r),
        [0x365] = HANDLER_PTR(fx_cmp_r),
        [0x366] = HANDLER_PTR(fx_cmp_r),
        [0x367] = HANDLER_PTR(fx_cmp_r),
        [0x368] = HANDLER_PTR(fx_cmp_r),
        [0x369] = HANDLER_PTR(fx_cmp_r),
        [0x36a] = HANDLER_PTR(fx_cmp_r),
        [0x36b] = HANDLER_PTR(fx_cmp_r),
        [0x36c] = HANDLER_PTR(fx_cmp_r),
        [0x36d] = HANDLER_PTR(fx_cmp_r),
        [0x36e] = HANDLER_PTR(fx_cmp_r),
        [0x36f] = HANDLER_PTR(fx_cmp_r),
        [0x370] = HANDLER_PTR(fx_merge),
        [0x371] = HANDLER_PTR(fx_bic_i),
        [0x372] = HANDLER_PTR(fx_bic_i),
        [0x373] = HANDLER_PTR(fx_bic_i),
        [0x374] = HANDLER_PTR(fx_bic_i),
        [0x375] = HANDLER_PTR(fx_bic_i),
        [0x376] = HANDLER_PTR(fx_bic_i),
        [0x377] = HANDLER_PTR(fx_bic_i),
        [0x378] = HANDLER_PTR(fx_bic_i),
        [0x379] = HANDLER_PTR(fx_bic_i),
        [0x37a] = HANDLER_PTR(fx_bic_i),
        [0x37b] = HANDLER_PTR(fx_bic_i),
        [0x37c] = HANDLER_PTR(fx_bic_i),
        [0x37d] = HANDLER_PTR(fx_bic_i),
        [0x37e] = HANDLER_PTR(fx_bic_i),
        [0x37f] = HANDLER_PTR(fx_bic_i),
        [0x380] = HANDLER_PTR(fx_umult_i),
        [0x381] = HANDLER_PTR(fx_umult_i),
        [0x382] = HANDLER_PTR(fx_umult_i),
        [0x383] = HANDLER_PTR(fx_umult_i),
        [0x384] = HANDLER_PTR(fx_umult_i),
        [0x385] = HANDLER_PTR(fx_umult_i),
        [0x386] = HANDLER_PTR(fx_umult_i),
        [0x387] = HANDLER_PTR(fx_umult_i),
        [0x388] = HANDLER_PTR(fx_umult_i),
        [0x389] = HANDLER_PTR(fx_umult_i),
        [0x38a] = HANDLER_PTR(fx_umult_i),
        [0x38b] = HANDLER_PTR(fx_umult_i),
        [0x38c] = HANDLER_PTR(fx_umult_i),
        [0x38d] = HANDLER_PTR(fx_umult_i),
        [0x38e] = HANDLER_PTR(fx_umult_i),
        [0x38f] = HANDLER_PTR(fx_umult_i),
        [0x390] = HANDLER_PTR(fx_sbk),
        [0x391] = HANDLER_PTR(fx_link_i),
        [0x392] = HANDLER_PTR(fx_link_i),
        [0x393] = HANDLER_PTR(fx_link_i),
        [0x394] = HANDLER_PTR(fx_link_i),
        [0x395] = HANDLER_PTR(fx_sex),
        [0x396] = HANDLER_PTR(fx_div2),
        [0x397] = HANDLER_PTR(fx_ror),
        [0x398] = HANDLER_PTR(fx_ljmp_r),
        [0x399] = HANDLER_PTR(fx_ljmp_r),
        [0x39a] = HANDLER_PTR(fx_ljmp_r),
        [0x39b] = HANDLER_PTR(fx_ljmp_r),
        [0x39c] = HANDLER_PTR(fx_ljmp_r),
        [0x39d] = HANDLER_PTR(fx_ljmp_r),
        [0x39e] = HANDLER_PTR(fx_lob),
        [0x39f] = HANDLER_PTR(fx_lmult),
        [0x3a0] = HANDLER_PTR(fx_lms_r),
        [0x3a1] = HANDLER_PTR(fx_lms_r),
        [0x3a2] = HANDLER_PTR(fx_lms_r),
        [0x3a3] = HANDLER_PTR(fx_lms_r),
        [0x3a4] = HANDLER_PTR(fx_lms_r),
        [0x3a5] = HANDLER_PTR(fx_lms_r),
        [0x3a6] = HANDLER_PTR(fx_lms_r),
        [0x3a7] = HANDLER_PTR(fx_lms_r),
        [0x3a8] = HANDLER_PTR(fx_lms_r),
        [0x3a9] = HANDLER_PTR(fx_lms_r),
        [0x3aa] = HANDLER_PTR(fx_lms_r),
        [0x3ab] = HANDLER_PTR(fx_lms_r),
        [0x3ac] = HANDLER_PTR(fx_lms_r),
        [0x3ad] = HANDLER_PTR(fx_lms_r),
        [0x3ae] = HANDLER_PTR(fx_lms_r14),
        [0x3af] = HANDLER_PTR(fx_lms_r),
        [0x3b0] = HANDLER_PTR(fx_from_r),
        [0x3b1] = HANDLER_PTR(fx_from_r),
        [0x3b2] = HANDLER_PTR(fx_from_r),
        [0x3b3] = HANDLER_PTR(fx_from_r),
        [0x3b4] = HANDLER_PTR(fx_from_r),
        [0x3b5] = HANDLER_PTR(fx_from_r),
        [0x3b6] = HANDLER_PTR(fx_from_r),
        [0x3b7] = HANDLER_PTR(fx_from_r),
        [0x3b8] = HANDLER_PTR(fx_from_r),
        [0x3b9] = HANDLER_PTR(fx_from_r),
        [0x3ba] = HANDLER_PTR(fx_from_r),
        [0x3bb] = HANDLER_PTR(fx_from_r),
        [0x3bc] = HANDLER_PTR(fx_from_r),
        [0x3bd] = HANDLER_PTR(fx_from_r),
        [0x3be] = HANDLER_PTR(fx_from_r),
        [0x3bf] = HANDLER_PTR(fx_from_r),
        [0x3c0] = HANDLER_PTR(fx_hib),
        [0x3c1] = HANDLER_PTR(fx_xor_i),
        [0x3c2] = HANDLER_PTR(fx_xor_i),
        [0x3c3] = HANDLER_PTR(fx_xor_i),
        [0x3c4] = HANDLER_PTR(fx_xor_i),
        [0x3c5] = HANDLER_PTR(fx_xor_i),
        [0x3c6] = HANDLER_PTR(fx_xor_i),
        [0x3c7] = HANDLER_PTR(fx_xor_i),
        [0x3c8] = HANDLER_PTR(fx_xor_i),
        [0x3c9] = HANDLER_PTR(fx_xor_i),
        [0x3ca] = HANDLER_PTR(fx_xor_i),
        [0x3cb] = HANDLER_PTR(fx_xor_i),
        [0x3cc] = HANDLER_PTR(fx_xor_i),
        [0x3cd] = HANDLER_PTR(fx_xor_i),
        [0x3ce] = HANDLER_PTR(fx_xor_i),
        [0x3cf] = HANDLER_PTR(fx_xor_i),
        [0x3d0] = HANDLER_PTR(fx_inc_r),
        [0x3d1] = HANDLER_PTR(fx_inc_r),
        [0x3d2] = HANDLER_PTR(fx_inc_r),
        [0x3d3] = HANDLER_PTR(fx_inc_r),
        [0x3d4] = HANDLER_PTR(fx_inc_r),
        [0x3d5] = HANDLER_PTR(fx_inc_r),
        [0x3d6] = HANDLER_PTR(fx_inc_r),
        [0x3d7] = HANDLER_PTR(fx_inc_r),
        [0x3d8] = HANDLER_PTR(fx_inc_r),
        [0x3d9] = HANDLER_PTR(fx_inc_r),
        [0x3da] = HANDLER_PTR(fx_inc_r),
        [0x3db] = HANDLER_PTR(fx_inc_r),
        [0x3dc] = HANDLER_PTR(fx_inc_r),
        [0x3dd] = HANDLER_PTR(fx_inc_r),
        [0x3de] = HANDLER_PTR(fx_inc_r14),
        [0x3df] = HANDLER_PTR(fx_romb),
        [0x3e0] = HANDLER_PTR(fx_dec_r),
        [0x3e1] = HANDLER_PTR(fx_dec_r),
        [0x3e2] = HANDLER_PTR(fx_dec_r),
        [0x3e3] = HANDLER_PTR(fx_dec_r),
        [0x3e4] = HANDLER_PTR(fx_dec_r),
        [0x3e5] = HANDLER_PTR(fx_dec_r),
        [0x3e6] = HANDLER_PTR(fx_dec_r),
        [0x3e7] = HANDLER_PTR(fx_dec_r),
        [0x3e8] = HANDLER_PTR(fx_dec_r),
        [0x3e9] = HANDLER_PTR(fx_dec_r),
        [0x3ea] = HANDLER_PTR(fx_dec_r),
        [0x3eb] = HANDLER_PTR(fx_dec_r),
        [0x3ec] = HANDLER_PTR(fx_dec_r),
        [0x3ed] = HANDLER_PTR(fx_dec_r),
        [0x3ee] = HANDLER_PTR(fx_dec_r14),
        [0x3ef] = HANDLER_PTR(fx_getbs),
        [0x3f0] = HANDLER_PTR(fx_lm_r),
        [0x3f1] = HANDLER_PTR(fx_lm_r),
        [0x3f2] = HANDLER_PTR(fx_lm_r),
        [0x3f3] = HANDLER_PTR(fx_lm_r),
        [0x3f4] = HANDLER_PTR(fx_lm_r),
        [0x3f5] = HANDLER_PTR(fx_lm_r),
        [0x3f6] = HANDLER_PTR(fx_lm_r),
        [0x3f7] = HANDLER_PTR(fx_lm_r),
        [0x3f8] = HANDLER_PTR(fx_lm_r),
        [0x3f9] = HANDLER_PTR(fx_lm_r),
        [0x3fa] = HANDLER_PTR(fx_lm_r),
        [0x3fb] = HANDLER_PTR(fx_lm_r),
        [0x3fc] = HANDLER_PTR(fx_lm_r),
        [0x3fd] = HANDLER_PTR(fx_lm_r),
        [0x3fe] = HANDLER_PTR(fx_lm_r14),
        [0x3ff] = HANDLER_PTR(fx_lm_r),
    };
    
    // We need to update the goto table with the correct plot/rpix handlers
    void *plotHandler, *rpixHandler;
    switch (GSU.vMode) {
        default:
        case 0:  plotHandler = HANDLER_PTR(fx_plot_2bit); rpixHandler = HANDLER_PTR(fx_rpix_2bit); break;
        case 1:
        case 2:  plotHandler = HANDLER_PTR(fx_plot_4bit); rpixHandler = HANDLER_PTR(fx_rpix_4bit); break;
        case 3:  plotHandler = HANDLER_PTR(fx_plot_8bit); rpixHandler = HANDLER_PTR(fx_rpix_8bit); break;
    }

    opcode_goto_table[0x04c] = opcode_goto_table[0x24c] = plotHandler;
    opcode_goto_table[0x14c] = opcode_goto_table[0x34c] = rpixHandler;

    uint32 vCounter = nInstructions;
    uint8 vLow = 0;
    READR14;

    DISPATCH;

    handle_fx_stop:
        fx_stop(vLow);
        goto loop_end;

    HANDLER(fx_plot_2bit)
    HANDLER(fx_rpix_2bit)
    HANDLER(fx_plot_4bit)
    HANDLER(fx_rpix_4bit)
    HANDLER(fx_plot_8bit)
    HANDLER(fx_rpix_8bit)
    HANDLER(fx_nop)
    HANDLER(fx_cache)
    HANDLER(fx_lsr)
    HANDLER(fx_rol)
    HANDLER(fx_bra)
    HANDLER(fx_bge)
    HANDLER(fx_blt)
    HANDLER(fx_bne)
    HANDLER(fx_beq)
    HANDLER(fx_bpl)
    HANDLER(fx_bmi)
    HANDLER(fx_bcc)
    HANDLER(fx_bcs)
    HANDLER(fx_bvc)
    HANDLER(fx_bvs)
    HANDLER(fx_to_r)
    HANDLER(fx_to_r14)
    HANDLER(fx_to_r15)
    HANDLER(fx_with)
    HANDLER(fx_stw_r)
    HANDLER(fx_loop)
    HANDLER(fx_alt1)
    HANDLER(fx_alt2)
    HANDLER(fx_alt3)
    HANDLER(fx_ldw_r)
    HANDLER(fx_swap)
    HANDLER(fx_color)
    HANDLER(fx_not)
    HANDLER(fx_add_r)
    HANDLER(fx_sub_r)
    HANDLER(fx_merge)
    HANDLER(fx_and_r)
    HANDLER(fx_mult_r)
    HANDLER(fx_sbk)
    HANDLER(fx_link_i)
    HANDLER(fx_sex)
    HANDLER(fx_asr)
    HANDLER(fx_ror)
    HANDLER(fx_jmp_r)
    HANDLER(fx_lob)
    HANDLER(fx_fmult)
    HANDLER(fx_ibt_r)
    HANDLER(fx_ibt_r14)
    HANDLER(fx_from_r)
    HANDLER(fx_hib)
    HANDLER(fx_or_r)
    HANDLER(fx_inc_r)
    HANDLER(fx_inc_r14)
    HANDLER(fx_getc)
    HANDLER(fx_dec_r)
    HANDLER(fx_dec_r14)
    HANDLER(fx_getb)
    HANDLER(fx_iwt_r)
    HANDLER(fx_iwt_r14)
    HANDLER(fx_stb_r)
    HANDLER(fx_ldb_r)
    HANDLER(fx_cmode)
    HANDLER(fx_adc_r)
    HANDLER(fx_sbc_r)
    HANDLER(fx_bic_r)
    HANDLER(fx_umult_r)
    HANDLER(fx_div2)
    HANDLER(fx_ljmp_r)
    HANDLER(fx_lmult)
    HANDLER(fx_lms_r)
    HANDLER(fx_lms_r14)
    HANDLER(fx_xor_r)
    HANDLER(fx_getbh)
    HANDLER(fx_lm_r)
    HANDLER(fx_lm_r14)
    HANDLER(fx_add_i)
    HANDLER(fx_sub_i)
    HANDLER(fx_and_i)
    HANDLER(fx_mult_i)
    HANDLER(fx_sms_r)
    HANDLER(fx_or_i)
    HANDLER(fx_ramb)
    HANDLER(fx_getbl)
    HANDLER(fx_sm_r)
    HANDLER(fx_adc_i)
    HANDLER(fx_cmp_r)
    HANDLER(fx_bic_i)
    HANDLER(fx_umult_i)
    HANDLER(fx_xor_i)
    HANDLER(fx_romb)
    HANDLER(fx_getbs)

    loop_end:

 /*
#ifndef FX_ADDRESS_CHECK
    GSU.vPipeAdr = USEX16(R15-1) | (USEX8(GSU.vPrgBankReg)<<16);
#endif
*/

#if T3DS_COUNT_INSTRUCTIONS == 1
    t3dsCountN(&t3dsMain, Snx_GsuInstructions, nInstructions - vCounter);
#endif

    fx_save_reserved();
    POP_RESERVED;
    return nInstructions;
}

COLD static uint32 fx_run_to_breakpoint(uint32 nInstructions)
{
    printf ("run_to_bp\n");
    uint32 vCounter = 0;
    while(TF(G) && vCounter < nInstructions)
    {
		vCounter++;
        // FX_STEP; // WYATT_TODO fix this.
        if(USEX16(R15) == GSU.vBreakPoint)
        {
            GSU.vErrorCode = FX_BREAKPOINT;
            break;
        }
    }
    /*
#ifndef FX_ADDRESS_CHECK
    GSU.vPipeAdr = USEX16(R15-1) | (USEX8(GSU.vPrgBankReg)<<16);
#endif
*/
    return vCounter;
}

COLD static uint32 fx_step_over(uint32 nInstructions)
{
    printf ("run_step_over\n");
    
    uint32 vCounter = 0;
    while(TF(G) && vCounter < nInstructions)
    {
		vCounter++;
        // FX_STEP; // WYATT_TODO fix this.
        if(USEX16(R15) == GSU.vBreakPoint)
        {
            GSU.vErrorCode = FX_BREAKPOINT;
            break;
        }
        if(USEX16(R15) == GSU.vStepPoint)
            break;
        }
    /*
#ifndef FX_ADDRESS_CHECK
    GSU.vPipeAdr = USEX16(R15-1) | (USEX8(GSU.vPrgBankReg)<<16);
#endif
*/
    return vCounter;
}

#ifdef FX_FUNCTION_TABLE
uint32 (*FX_FUNCTION_TABLE[])(uint32) =
#else
uint32 (*fx_apfFunctionTable[])(uint32) =
#endif
{
    &fx_run,
    &fx_run_to_breakpoint,
    &fx_step_over,
};
