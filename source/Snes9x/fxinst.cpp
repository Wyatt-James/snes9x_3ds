#include "copyright.h"


#define FX_DO_ROMBUFFER

#include "fxemu.h"
#include "fxinst.h"
#include <string.h>
#include <stdio.h>

extern struct FxRegs_s GSU;
int gsu_bank [512] = {0};

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
static inline void fx_stop()
{
    CF(G);
    GSU.vCounter = 0;
    GSU.vInstCount = GSU.vCounter;

    /* Check if we need to generate an IRQ */
    if(!(GSU.pvRegisters[GSU_CFGR] & 0x80))
	SF(IRQ);

    GSU.vPlotOptionReg = 0;
    GSU.vPipe = 1;
    CLRFLAGS;
    R15++;
}

/* 01 - nop - no operation */
static inline void fx_nop() { CLRFLAGS; R15++; }

extern void fx_flushCache();

/* 02 - cache - reintialize GSU cache */
static inline void fx_cache()
{
    uint32 c = R15 & 0xfff0;
    if(GSU.vCacheBaseReg != c || !GSU.bCacheActive)
    {
	fx_flushCache();
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
}

/* 03 - lsr - logic shift right */
static inline void fx_lsr()
{
    uint32 v;
    GSU.vCarry = SREG & 1;
    v = USEX16(SREG) >> 1;
    R15++; DREG = v;
    GSU.vSign = v;
    GSU.vZero = v;
    TESTR14;
    CLRFLAGS;
}

/* 04 - rol - rotate left */
static inline void fx_rol()
{
    uint32 v = USEX16((SREG << 1) + GSU.vCarry);
    GSU.vCarry = (SREG >> 15) & 1;
    R15++; DREG = v;
    GSU.vSign = v;
    GSU.vZero = v;
    TESTR14;
    CLRFLAGS;
}

/* 05 - bra - branch always */
static inline void fx_bra() { uint8 v = PIPE; R15++; FETCHPIPE; R15 += SEX8(v); }

/* Branch on condition */
#define BRA_COND(cond) uint8 v = PIPE; R15++; FETCHPIPE; if(cond) R15 += SEX8(v); else R15++;

#define TEST_S (GSU.vSign & 0x8000)
#define TEST_Z (USEX16(GSU.vZero) == 0)
#define TEST_OV (GSU.vOverflow >= 0x8000 || GSU.vOverflow < -0x8000)
#define TEST_CY (GSU.vCarry & 1)

/* 06 - blt - branch on less than */
static inline void fx_blt() { BRA_COND( (TEST_S!=0) != (TEST_OV!=0) ); }

/* 07 - bge - branch on greater or equals */
static inline void fx_bge() { BRA_COND( (TEST_S!=0) == (TEST_OV!=0)); }

/* 08 - bne - branch on not equal */
static inline void fx_bne() { BRA_COND( !TEST_Z ); }

/* 09 - beq - branch on equal */
static inline void fx_beq() { BRA_COND( TEST_Z ); }

/* 0a - bpl - branch on plus */
static inline void fx_bpl() { BRA_COND( !TEST_S ); }

/* 0b - bmi - branch on minus */
static inline void fx_bmi() { BRA_COND( TEST_S ); }

/* 0c - bcc - branch on carry clear */
static inline void fx_bcc() { BRA_COND( !TEST_CY ); }

/* 0d - bcs - branch on carry set */
static inline void fx_bcs() { BRA_COND( TEST_CY ); }

/* 0e - bvc - branch on overflow clear */
static inline void fx_bvc() { BRA_COND( !TEST_OV ); }

/* 0f - bvs - branch on overflow set */
static inline void fx_bvs() { BRA_COND( TEST_OV ); }

/* 10-1f - to rn - set register n as destination register */
/* 10-1f(B) - move rn - move one register to another (if B flag is set) */
#define FX_TO(reg) \
if(TF(B)) { GSU.avReg[(reg)] = SREG; CLRFLAGS; } \
else { GSU.pvDreg = &GSU.avReg[reg]; } R15++;
#define FX_TO_R14(reg) \
if(TF(B)) { GSU.avReg[(reg)] = SREG; CLRFLAGS; READR14; } \
else { GSU.pvDreg = &GSU.avReg[reg]; } R15++;
#define FX_TO_R15(reg) \
if(TF(B)) { GSU.avReg[(reg)] = SREG; CLRFLAGS; } \
else { GSU.pvDreg = &GSU.avReg[reg]; R15++; }
static inline void fx_to_r0() { FX_TO(0); }
static inline void fx_to_r1() { FX_TO(1); }
static inline void fx_to_r2() { FX_TO(2); }
static inline void fx_to_r3() { FX_TO(3); }
static inline void fx_to_r4() { FX_TO(4); }
static inline void fx_to_r5() { FX_TO(5); }
static inline void fx_to_r6() { FX_TO(6); }
static inline void fx_to_r7() { FX_TO(7); }
static inline void fx_to_r8() { FX_TO(8); }
static inline void fx_to_r9() { FX_TO(9); }
static inline void fx_to_r10() { FX_TO(10); }
static inline void fx_to_r11() { FX_TO(11); }
static inline void fx_to_r12() { FX_TO(12); }
static inline void fx_to_r13() { FX_TO(13); }
static inline void fx_to_r14() { FX_TO_R14(14); }
static inline void fx_to_r15() { FX_TO_R15(15); }

/* 20-2f - to rn - set register n as source and destination register */
#define FX_WITH(reg) SF(B); GSU.pvSreg = GSU.pvDreg = &GSU.avReg[reg]; R15++;
static inline void fx_with_r0() { FX_WITH(0); }
static inline void fx_with_r1() { FX_WITH(1); }
static inline void fx_with_r2() { FX_WITH(2); }
static inline void fx_with_r3() { FX_WITH(3); }
static inline void fx_with_r4() { FX_WITH(4); }
static inline void fx_with_r5() { FX_WITH(5); }
static inline void fx_with_r6() { FX_WITH(6); }
static inline void fx_with_r7() { FX_WITH(7); }
static inline void fx_with_r8() { FX_WITH(8); }
static inline void fx_with_r9() { FX_WITH(9); }
static inline void fx_with_r10() { FX_WITH(10); }
static inline void fx_with_r11() { FX_WITH(11); }
static inline void fx_with_r12() { FX_WITH(12); }
static inline void fx_with_r13() { FX_WITH(13); }
static inline void fx_with_r14() { FX_WITH(14); }
static inline void fx_with_r15() { FX_WITH(15); }

/* 30-3b - stw (rn) - store word */
#define FX_STW(reg) \
GSU.vLastRamAdr = GSU.avReg[reg]; \
RAM(GSU.avReg[reg]) = (uint8)SREG; \
RAM(GSU.avReg[reg]^1) = (uint8)(SREG>>8); \
CLRFLAGS; R15++
static inline void fx_stw_r0() { FX_STW(0); }
static inline void fx_stw_r1() { FX_STW(1); }
static inline void fx_stw_r2() { FX_STW(2); }
static inline void fx_stw_r3() { FX_STW(3); }
static inline void fx_stw_r4() { FX_STW(4); }
static inline void fx_stw_r5() { FX_STW(5); }
static inline void fx_stw_r6() { FX_STW(6); }
static inline void fx_stw_r7() { FX_STW(7); }
static inline void fx_stw_r8() { FX_STW(8); }
static inline void fx_stw_r9() { FX_STW(9); }
static inline void fx_stw_r10() { FX_STW(10); }
static inline void fx_stw_r11() { FX_STW(11); }

/* 30-3b(ALT1) - stb (rn) - store byte */
#define FX_STB(reg) \
GSU.vLastRamAdr = GSU.avReg[reg]; \
RAM(GSU.avReg[reg]) = (uint8)SREG; \
CLRFLAGS; R15++
static inline void fx_stb_r0() { FX_STB(0); }
static inline void fx_stb_r1() { FX_STB(1); }
static inline void fx_stb_r2() { FX_STB(2); }
static inline void fx_stb_r3() { FX_STB(3); }
static inline void fx_stb_r4() { FX_STB(4); }
static inline void fx_stb_r5() { FX_STB(5); }
static inline void fx_stb_r6() { FX_STB(6); }
static inline void fx_stb_r7() { FX_STB(7); }
static inline void fx_stb_r8() { FX_STB(8); }
static inline void fx_stb_r9() { FX_STB(9); }
static inline void fx_stb_r10() { FX_STB(10); }
static inline void fx_stb_r11() { FX_STB(11); }

/* 3c - loop - decrement loop counter, and branch on not zero */
static inline void fx_loop()
{
    GSU.vSign = GSU.vZero = --R12;
    if( (uint16) R12 != 0 )
	R15 = R13;
    else
	R15++;

    CLRFLAGS;
}

/* 3d - alt1 - set alt1 mode */
static inline void fx_alt1() { SF(ALT1); CF(B); R15++; }

/* 3e - alt2 - set alt2 mode */
static inline void fx_alt2() { SF(ALT2); CF(B); R15++; }

/* 3f - alt3 - set alt3 mode */
static inline void fx_alt3() { SF(ALT1); SF(ALT2); CF(B); R15++; }
    
/* 40-4b - ldw (rn) - load word from RAM */
#define FX_LDW(reg) uint32 v; \
GSU.vLastRamAdr = GSU.avReg[reg]; \
v = (uint32)RAM(GSU.avReg[reg]); \
v |= ((uint32)RAM(GSU.avReg[reg]^1))<<8; \
R15++; DREG = v; \
TESTR14; \
CLRFLAGS
static inline void fx_ldw_r0() { FX_LDW(0); }
static inline void fx_ldw_r1() { FX_LDW(1); }
static inline void fx_ldw_r2() { FX_LDW(2); }
static inline void fx_ldw_r3() { FX_LDW(3); }
static inline void fx_ldw_r4() { FX_LDW(4); }
static inline void fx_ldw_r5() { FX_LDW(5); }
static inline void fx_ldw_r6() { FX_LDW(6); }
static inline void fx_ldw_r7() { FX_LDW(7); }
static inline void fx_ldw_r8() { FX_LDW(8); }
static inline void fx_ldw_r9() { FX_LDW(9); }
static inline void fx_ldw_r10() { FX_LDW(10); }
static inline void fx_ldw_r11() { FX_LDW(11); }

/* 40-4b(ALT1) - ldb (rn) - load byte */
#define FX_LDB(reg) uint32 v; \
GSU.vLastRamAdr = GSU.avReg[reg]; \
v = (uint32)RAM(GSU.avReg[reg]); \
R15++; DREG = v; \
TESTR14; \
CLRFLAGS
static inline void fx_ldb_r0() { FX_LDB(0); }
static inline void fx_ldb_r1() { FX_LDB(1); }
static inline void fx_ldb_r2() { FX_LDB(2); }
static inline void fx_ldb_r3() { FX_LDB(3); }
static inline void fx_ldb_r4() { FX_LDB(4); }
static inline void fx_ldb_r5() { FX_LDB(5); }
static inline void fx_ldb_r6() { FX_LDB(6); }
static inline void fx_ldb_r7() { FX_LDB(7); }
static inline void fx_ldb_r8() { FX_LDB(8); }
static inline void fx_ldb_r9() { FX_LDB(9); }
static inline void fx_ldb_r10() { FX_LDB(10); }
static inline void fx_ldb_r11() { FX_LDB(11); }

/* 4c - plot - plot pixel with R1,R2 as x,y and the color register as the color */
static inline void fx_plot_2bit()
{
    uint32 x = USEX8(R1);
    uint32 y = USEX8(R2);
    uint8 *a;
    uint8 v,c;

    R15++;
    CLRFLAGS;
    R1++;

#ifdef CHECK_LIMITS
    if(y >= GSU.vScreenHeight) return;
#endif
    if(GSU.vPlotOptionReg & 0x02)
	c = (x^y)&1 ? (uint8)(GSU.vColorReg>>4) : (uint8)GSU.vColorReg;
    else
	c = (uint8)GSU.vColorReg;
    
    if( !(GSU.vPlotOptionReg & 0x01) && !(c & 0xf)) return;
    a = GSU.apvScreen[y >> 3] + GSU.x[x >> 3] + ((y & 7) << 1);
    v = 128 >> (x&7);

    if(c & 0x01) a[0] |= v;
    else a[0] &= ~v;
    if(c & 0x02) a[1] |= v;
    else a[1] &= ~v;
}

/* 2c(ALT1) - rpix - read color of the pixel with R1,R2 as x,y */
static inline void fx_rpix_2bit()
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

    DREG = 0;
    DREG |= ((uint32)((a[0] & v) != 0)) << 0;
    DREG |= ((uint32)((a[1] & v) != 0)) << 1;
    TESTR14;
}

/* 4c - plot - plot pixel with R1,R2 as x,y and the color register as the color */
static inline void fx_plot_4bit()
{
    uint32 x = USEX8(R1);
    uint32 y = USEX8(R2);
    uint8 *a;
    uint8 v,c;

    R15++;
    CLRFLAGS;
    R1++;
    
#ifdef CHECK_LIMITS
    if(y >= GSU.vScreenHeight) return;
#endif
    if(GSU.vPlotOptionReg & 0x02)
	c = (x^y)&1 ? (uint8)(GSU.vColorReg>>4) : (uint8)GSU.vColorReg;
    else
	c = (uint8)GSU.vColorReg;

    if( !(GSU.vPlotOptionReg & 0x01) && !(c & 0xf)) return;

    a = GSU.apvScreen[y >> 3] + GSU.x[x >> 3] + ((y & 7) << 1);
    v = 128 >> (x&7);

    if(c & 0x01) a[0x00] |= v;
    else a[0x00] &= ~v;
    if(c & 0x02) a[0x01] |= v;
    else a[0x01] &= ~v;
    if(c & 0x04) a[0x10] |= v;
    else a[0x10] &= ~v;
    if(c & 0x08) a[0x11] |= v;
    else a[0x11] &= ~v;
}

/* 4c(ALT1) - rpix - read color of the pixel with R1,R2 as x,y */
static inline void fx_rpix_4bit()
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

    DREG = 0;
    DREG |= ((uint32)((a[0x00] & v) != 0)) << 0;
    DREG |= ((uint32)((a[0x01] & v) != 0)) << 1;
    DREG |= ((uint32)((a[0x10] & v) != 0)) << 2;
    DREG |= ((uint32)((a[0x11] & v) != 0)) << 3;
    TESTR14;
}

/* 8c - plot - plot pixel with R1,R2 as x,y and the color register as the color */
static inline void fx_plot_8bit()
{
    uint32 x = USEX8(R1);
    uint32 y = USEX8(R2);
    uint8 *a;
    uint8 v,c;

    R15++;
    CLRFLAGS;
    R1++;
    
#ifdef CHECK_LIMITS
    if(y >= GSU.vScreenHeight) return;
#endif
    c = (uint8)GSU.vColorReg;
    if( !(GSU.vPlotOptionReg & 0x10) )
    {
	if( !(GSU.vPlotOptionReg & 0x01) && !(c&0xf)) return;
    }
    else
	if( !(GSU.vPlotOptionReg & 0x01) && !c) return;

    a = GSU.apvScreen[y >> 3] + GSU.x[x >> 3] + ((y & 7) << 1);
    v = 128 >> (x&7);

    if(c & 0x01) a[0x00] |= v;
    else a[0x00] &= ~v;
    if(c & 0x02) a[0x01] |= v;
    else a[0x01] &= ~v;
    if(c & 0x04) a[0x10] |= v;
    else a[0x10] &= ~v;
    if(c & 0x08) a[0x11] |= v;
    else a[0x11] &= ~v;
    if(c & 0x10) a[0x20] |= v;
    else a[0x20] &= ~v;
    if(c & 0x20) a[0x21] |= v;
    else a[0x21] &= ~v;
    if(c & 0x40) a[0x30] |= v;
    else a[0x30] &= ~v;
    if(c & 0x80) a[0x31] |= v;
    else a[0x31] &= ~v;
}

/* 4c(ALT1) - rpix - read color of the pixel with R1,R2 as x,y */
static inline void fx_rpix_8bit()
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

    DREG = 0;
    DREG |= ((uint32)((a[0x00] & v) != 0)) << 0;
    DREG |= ((uint32)((a[0x01] & v) != 0)) << 1;
    DREG |= ((uint32)((a[0x10] & v) != 0)) << 2;
    DREG |= ((uint32)((a[0x11] & v) != 0)) << 3;
    DREG |= ((uint32)((a[0x20] & v) != 0)) << 4;
    DREG |= ((uint32)((a[0x21] & v) != 0)) << 5;
    DREG |= ((uint32)((a[0x30] & v) != 0)) << 6;
    DREG |= ((uint32)((a[0x31] & v) != 0)) << 7;
    GSU.vZero = DREG;
    TESTR14;
}

/* 4o - plot - plot pixel with R1,R2 as x,y and the color register as the color */
static inline void fx_plot_obj()
{
    printf ("ERROR fx_plot_obj called\n");
}

/* 4c(ALT1) - rpix - read color of the pixel with R1,R2 as x,y */
static inline void fx_rpix_obj()
{
    printf ("ERROR fx_rpix_obj called\n");
}

/* 4d - swap - swap upper and lower byte of a register */
static inline void fx_swap()
{
    uint8 c = (uint8)SREG;
    uint8 d = (uint8)(SREG>>8);
    uint32 v = (((uint32)c)<<8)|((uint32)d);
    R15++; DREG = v;
    GSU.vSign = v;
    GSU.vZero = v;
    TESTR14;
    CLRFLAGS;
}

/* 4e - color - copy source register to color register */
static inline void fx_color()
{
    uint8 c = (uint8)SREG;
    if(GSU.vPlotOptionReg & 0x04)
	c = (c&0xf0) | (c>>4);
    if(GSU.vPlotOptionReg & 0x08)
    {
	GSU.vColorReg &= 0xf0;
	GSU.vColorReg |= c & 0x0f;
    }
    else
	GSU.vColorReg = USEX8(c);
    CLRFLAGS;
    R15++;
}

/* 4e(ALT1) - cmode - set plot option register */
static inline void fx_cmode()
{
    GSU.vPlotOptionReg = SREG;

    if(GSU.vPlotOptionReg & 0x10)
    {
	/* OBJ Mode (for drawing into sprites) */
	GSU.vScreenHeight = 256;
    }
    else
	GSU.vScreenHeight = GSU.vScreenRealHeight;

    fx_computeScreenPointers ();
    CLRFLAGS;
    R15++;
}

/* 4f - not - perform exclusive exor with 1 on all bits */
static inline void fx_not()
{
    uint32 v = ~SREG;
    R15++; DREG = v;
    GSU.vSign = v;
    GSU.vZero = v;
    TESTR14;
    CLRFLAGS;
}

/* 50-5f - add rn - add, register + register */
#define FX_ADD(reg) \
int32 s = SUSEX16(SREG) + SUSEX16(GSU.avReg[reg]); \
GSU.vCarry = s >= 0x10000; \
GSU.vOverflow = ~(SREG ^ GSU.avReg[reg]) & (GSU.avReg[reg] ^ s) & 0x8000; \
GSU.vSign = s; \
GSU.vZero = s; \
R15++; DREG = s; \
TESTR14; \
CLRFLAGS
static inline void fx_add_r0() { FX_ADD(0); }
static inline void fx_add_r1() { FX_ADD(1); }
static inline void fx_add_r2() { FX_ADD(2); }
static inline void fx_add_r3() { FX_ADD(3); }
static inline void fx_add_r4() { FX_ADD(4); }
static inline void fx_add_r5() { FX_ADD(5); }
static inline void fx_add_r6() { FX_ADD(6); }
static inline void fx_add_r7() { FX_ADD(7); }
static inline void fx_add_r8() { FX_ADD(8); }
static inline void fx_add_r9() { FX_ADD(9); }
static inline void fx_add_r10() { FX_ADD(10); }
static inline void fx_add_r11() { FX_ADD(11); }
static inline void fx_add_r12() { FX_ADD(12); }
static inline void fx_add_r13() { FX_ADD(13); }
static inline void fx_add_r14() { FX_ADD(14); }
static inline void fx_add_r15() { FX_ADD(15); }

/* 50-5f(ALT1) - adc rn - add with carry, register + register */
#define FX_ADC(reg) \
int32 s = SUSEX16(SREG) + SUSEX16(GSU.avReg[reg]) + SEX16(GSU.vCarry); \
GSU.vCarry = s >= 0x10000; \
GSU.vOverflow = ~(SREG ^ GSU.avReg[reg]) & (GSU.avReg[reg] ^ s) & 0x8000; \
GSU.vSign = s; \
GSU.vZero = s; \
R15++; DREG = s; \
TESTR14; \
CLRFLAGS
static inline void fx_adc_r0() { FX_ADC(0); }
static inline void fx_adc_r1() { FX_ADC(1); }
static inline void fx_adc_r2() { FX_ADC(2); }
static inline void fx_adc_r3() { FX_ADC(3); }
static inline void fx_adc_r4() { FX_ADC(4); }
static inline void fx_adc_r5() { FX_ADC(5); }
static inline void fx_adc_r6() { FX_ADC(6); }
static inline void fx_adc_r7() { FX_ADC(7); }
static inline void fx_adc_r8() { FX_ADC(8); }
static inline void fx_adc_r9() { FX_ADC(9); }
static inline void fx_adc_r10() { FX_ADC(10); }
static inline void fx_adc_r11() { FX_ADC(11); }
static inline void fx_adc_r12() { FX_ADC(12); }
static inline void fx_adc_r13() { FX_ADC(13); }
static inline void fx_adc_r14() { FX_ADC(14); }
static inline void fx_adc_r15() { FX_ADC(15); }

/* 50-5f(ALT2) - add #n - add, register + immediate */
#define FX_ADD_I(imm) \
int32 s = SUSEX16(SREG) + imm; \
GSU.vCarry = s >= 0x10000; \
GSU.vOverflow = ~(SREG ^ imm) & (imm ^ s) & 0x8000; \
GSU.vSign = s; \
GSU.vZero = s; \
R15++; DREG = s; \
TESTR14; \
CLRFLAGS
static inline void fx_add_i0() { FX_ADD_I(0); }
static inline void fx_add_i1() { FX_ADD_I(1); }
static inline void fx_add_i2() { FX_ADD_I(2); }
static inline void fx_add_i3() { FX_ADD_I(3); }
static inline void fx_add_i4() { FX_ADD_I(4); }
static inline void fx_add_i5() { FX_ADD_I(5); }
static inline void fx_add_i6() { FX_ADD_I(6); }
static inline void fx_add_i7() { FX_ADD_I(7); }
static inline void fx_add_i8() { FX_ADD_I(8); }
static inline void fx_add_i9() { FX_ADD_I(9); }
static inline void fx_add_i10() { FX_ADD_I(10); }
static inline void fx_add_i11() { FX_ADD_I(11); }
static inline void fx_add_i12() { FX_ADD_I(12); }
static inline void fx_add_i13() { FX_ADD_I(13); }
static inline void fx_add_i14() { FX_ADD_I(14); }
static inline void fx_add_i15() { FX_ADD_I(15); }

/* 50-5f(ALT3) - adc #n - add with carry, register + immediate */
#define FX_ADC_I(imm) \
int32 s = SUSEX16(SREG) + imm + SUSEX16(GSU.vCarry); \
GSU.vCarry = s >= 0x10000; \
GSU.vOverflow = ~(SREG ^ imm) & (imm ^ s) & 0x8000; \
GSU.vSign = s; \
GSU.vZero = s; \
R15++; DREG = s; \
TESTR14; \
CLRFLAGS
static inline void fx_adc_i0() { FX_ADC_I(0); }
static inline void fx_adc_i1() { FX_ADC_I(1); }
static inline void fx_adc_i2() { FX_ADC_I(2); }
static inline void fx_adc_i3() { FX_ADC_I(3); }
static inline void fx_adc_i4() { FX_ADC_I(4); }
static inline void fx_adc_i5() { FX_ADC_I(5); }
static inline void fx_adc_i6() { FX_ADC_I(6); }
static inline void fx_adc_i7() { FX_ADC_I(7); }
static inline void fx_adc_i8() { FX_ADC_I(8); }
static inline void fx_adc_i9() { FX_ADC_I(9); }
static inline void fx_adc_i10() { FX_ADC_I(10); }
static inline void fx_adc_i11() { FX_ADC_I(11); }
static inline void fx_adc_i12() { FX_ADC_I(12); }
static inline void fx_adc_i13() { FX_ADC_I(13); }
static inline void fx_adc_i14() { FX_ADC_I(14); }
static inline void fx_adc_i15() { FX_ADC_I(15); }

/* 60-6f - sub rn - subtract, register - register */
#define FX_SUB(reg) \
int32 s = SUSEX16(SREG) - SUSEX16(GSU.avReg[reg]); \
GSU.vCarry = s >= 0; \
GSU.vOverflow = (SREG ^ GSU.avReg[reg]) & (SREG ^ s) & 0x8000; \
GSU.vSign = s; \
GSU.vZero = s; \
R15++; DREG = s; \
TESTR14; \
CLRFLAGS
static inline void fx_sub_r0() { FX_SUB(0); }
static inline void fx_sub_r1() { FX_SUB(1); }
static inline void fx_sub_r2() { FX_SUB(2); }
static inline void fx_sub_r3() { FX_SUB(3); }
static inline void fx_sub_r4() { FX_SUB(4); }
static inline void fx_sub_r5() { FX_SUB(5); }
static inline void fx_sub_r6() { FX_SUB(6); }
static inline void fx_sub_r7() { FX_SUB(7); }
static inline void fx_sub_r8() { FX_SUB(8); }
static inline void fx_sub_r9() { FX_SUB(9); }
static inline void fx_sub_r10() { FX_SUB(10); }
static inline void fx_sub_r11() { FX_SUB(11); }
static inline void fx_sub_r12() { FX_SUB(12); }
static inline void fx_sub_r13() { FX_SUB(13); }
static inline void fx_sub_r14() { FX_SUB(14); }
static inline void fx_sub_r15() { FX_SUB(15); }

/* 60-6f(ALT1) - sbc rn - subtract with carry, register - register */
#define FX_SBC(reg) \
int32 s = SUSEX16(SREG) - SUSEX16(GSU.avReg[reg]) - (SUSEX16(GSU.vCarry^1)); \
GSU.vCarry = s >= 0; \
GSU.vOverflow = (SREG ^ GSU.avReg[reg]) & (SREG ^ s) & 0x8000; \
GSU.vSign = s; \
GSU.vZero = s; \
R15++; DREG = s; \
TESTR14; \
CLRFLAGS
static inline void fx_sbc_r0() { FX_SBC(0); }
static inline void fx_sbc_r1() { FX_SBC(1); }
static inline void fx_sbc_r2() { FX_SBC(2); }
static inline void fx_sbc_r3() { FX_SBC(3); }
static inline void fx_sbc_r4() { FX_SBC(4); }
static inline void fx_sbc_r5() { FX_SBC(5); }
static inline void fx_sbc_r6() { FX_SBC(6); }
static inline void fx_sbc_r7() { FX_SBC(7); }
static inline void fx_sbc_r8() { FX_SBC(8); }
static inline void fx_sbc_r9() { FX_SBC(9); }
static inline void fx_sbc_r10() { FX_SBC(10); }
static inline void fx_sbc_r11() { FX_SBC(11); }
static inline void fx_sbc_r12() { FX_SBC(12); }
static inline void fx_sbc_r13() { FX_SBC(13); }
static inline void fx_sbc_r14() { FX_SBC(14); }
static inline void fx_sbc_r15() { FX_SBC(15); }

/* 60-6f(ALT2) - sub #n - subtract, register - immediate */
#define FX_SUB_I(imm) \
int32 s = SUSEX16(SREG) - imm; \
GSU.vCarry = s >= 0; \
GSU.vOverflow = (SREG ^ imm) & (SREG ^ s) & 0x8000; \
GSU.vSign = s; \
GSU.vZero = s; \
R15++; DREG = s; \
TESTR14; \
CLRFLAGS
static inline void fx_sub_i0() { FX_SUB_I(0); }
static inline void fx_sub_i1() { FX_SUB_I(1); }
static inline void fx_sub_i2() { FX_SUB_I(2); }
static inline void fx_sub_i3() { FX_SUB_I(3); }
static inline void fx_sub_i4() { FX_SUB_I(4); }
static inline void fx_sub_i5() { FX_SUB_I(5); }
static inline void fx_sub_i6() { FX_SUB_I(6); }
static inline void fx_sub_i7() { FX_SUB_I(7); }
static inline void fx_sub_i8() { FX_SUB_I(8); }
static inline void fx_sub_i9() { FX_SUB_I(9); }
static inline void fx_sub_i10() { FX_SUB_I(10); }
static inline void fx_sub_i11() { FX_SUB_I(11); }
static inline void fx_sub_i12() { FX_SUB_I(12); }
static inline void fx_sub_i13() { FX_SUB_I(13); }
static inline void fx_sub_i14() { FX_SUB_I(14); }
static inline void fx_sub_i15() { FX_SUB_I(15); }

/* 60-6f(ALT3) - cmp rn - compare, register, register */
#define FX_CMP(reg) \
int32 s = SUSEX16(SREG) - SUSEX16(GSU.avReg[reg]); \
GSU.vCarry = s >= 0; \
GSU.vOverflow = (SREG ^ GSU.avReg[reg]) & (SREG ^ s) & 0x8000; \
GSU.vSign = s; \
GSU.vZero = s; \
R15++; \
CLRFLAGS;
static inline void fx_cmp_r0() { FX_CMP(0); }
static inline void fx_cmp_r1() { FX_CMP(1); }
static inline void fx_cmp_r2() { FX_CMP(2); }
static inline void fx_cmp_r3() { FX_CMP(3); }
static inline void fx_cmp_r4() { FX_CMP(4); }
static inline void fx_cmp_r5() { FX_CMP(5); }
static inline void fx_cmp_r6() { FX_CMP(6); }
static inline void fx_cmp_r7() { FX_CMP(7); }
static inline void fx_cmp_r8() { FX_CMP(8); }
static inline void fx_cmp_r9() { FX_CMP(9); }
static inline void fx_cmp_r10() { FX_CMP(10); }
static inline void fx_cmp_r11() { FX_CMP(11); }
static inline void fx_cmp_r12() { FX_CMP(12); }
static inline void fx_cmp_r13() { FX_CMP(13); }
static inline void fx_cmp_r14() { FX_CMP(14); }
static inline void fx_cmp_r15() { FX_CMP(15); }

/* 70 - merge - R7 as upper byte, R8 as lower byte (used for texture-mapping) */
static inline void fx_merge()
{
    uint32 v = (R7&0xff00) | ((R8&0xff00)>>8);
    R15++; DREG = v;
    GSU.vOverflow = (v & 0xc0c0) << 16;
    GSU.vZero = !(v & 0xf0f0);
    GSU.vSign = ((v | (v<<8)) & 0x8000);
    GSU.vCarry = (v & 0xe0e0) != 0;
    TESTR14;
    CLRFLAGS;
}

/* 71-7f - and rn - reister & register */
#define FX_AND(reg) \
uint32 v = SREG & GSU.avReg[reg]; \
R15++; DREG = v; \
GSU.vSign = v; \
GSU.vZero = v; \
TESTR14; \
CLRFLAGS;
static inline void fx_and_r1() { FX_AND(1); }
static inline void fx_and_r2() { FX_AND(2); }
static inline void fx_and_r3() { FX_AND(3); }
static inline void fx_and_r4() { FX_AND(4); }
static inline void fx_and_r5() { FX_AND(5); }
static inline void fx_and_r6() { FX_AND(6); }
static inline void fx_and_r7() { FX_AND(7); }
static inline void fx_and_r8() { FX_AND(8); }
static inline void fx_and_r9() { FX_AND(9); }
static inline void fx_and_r10() { FX_AND(10); }
static inline void fx_and_r11() { FX_AND(11); }
static inline void fx_and_r12() { FX_AND(12); }
static inline void fx_and_r13() { FX_AND(13); }
static inline void fx_and_r14() { FX_AND(14); }
static inline void fx_and_r15() { FX_AND(15); }

/* 71-7f(ALT1) - bic rn - reister & ~register */
#define FX_BIC(reg) \
uint32 v = SREG & ~GSU.avReg[reg];	\
R15++; DREG = v; \
GSU.vSign = v; \
GSU.vZero = v; \
TESTR14; \
CLRFLAGS;
static inline void fx_bic_r1() { FX_BIC(1); }
static inline void fx_bic_r2() { FX_BIC(2); }
static inline void fx_bic_r3() { FX_BIC(3); }
static inline void fx_bic_r4() { FX_BIC(4); }
static inline void fx_bic_r5() { FX_BIC(5); }
static inline void fx_bic_r6() { FX_BIC(6); }
static inline void fx_bic_r7() { FX_BIC(7); }
static inline void fx_bic_r8() { FX_BIC(8); }
static inline void fx_bic_r9() { FX_BIC(9); }
static inline void fx_bic_r10() { FX_BIC(10); }
static inline void fx_bic_r11() { FX_BIC(11); }
static inline void fx_bic_r12() { FX_BIC(12); }
static inline void fx_bic_r13() { FX_BIC(13); }
static inline void fx_bic_r14() { FX_BIC(14); }
static inline void fx_bic_r15() { FX_BIC(15); }

/* 71-7f(ALT2) - and #n - reister & immediate */
#define FX_AND_I(imm) \
uint32 v = SREG & imm; \
R15++; DREG = v; \
GSU.vSign = v; \
GSU.vZero = v; \
TESTR14; \
CLRFLAGS;
static inline void fx_and_i1() { FX_AND_I(1); }
static inline void fx_and_i2() { FX_AND_I(2); }
static inline void fx_and_i3() { FX_AND_I(3); }
static inline void fx_and_i4() { FX_AND_I(4); }
static inline void fx_and_i5() { FX_AND_I(5); }
static inline void fx_and_i6() { FX_AND_I(6); }
static inline void fx_and_i7() { FX_AND_I(7); }
static inline void fx_and_i8() { FX_AND_I(8); }
static inline void fx_and_i9() { FX_AND_I(9); }
static inline void fx_and_i10() { FX_AND_I(10); }
static inline void fx_and_i11() { FX_AND_I(11); }
static inline void fx_and_i12() { FX_AND_I(12); }
static inline void fx_and_i13() { FX_AND_I(13); }
static inline void fx_and_i14() { FX_AND_I(14); }
static inline void fx_and_i15() { FX_AND_I(15); }

/* 71-7f(ALT3) - bic #n - reister & ~immediate */
#define FX_BIC_I(imm) \
uint32 v = SREG & ~imm; \
R15++; DREG = v; \
GSU.vSign = v; \
GSU.vZero = v; \
TESTR14; \
CLRFLAGS;
static inline void fx_bic_i1() { FX_BIC_I(1); }
static inline void fx_bic_i2() { FX_BIC_I(2); }
static inline void fx_bic_i3() { FX_BIC_I(3); }
static inline void fx_bic_i4() { FX_BIC_I(4); }
static inline void fx_bic_i5() { FX_BIC_I(5); }
static inline void fx_bic_i6() { FX_BIC_I(6); }
static inline void fx_bic_i7() { FX_BIC_I(7); }
static inline void fx_bic_i8() { FX_BIC_I(8); }
static inline void fx_bic_i9() { FX_BIC_I(9); }
static inline void fx_bic_i10() { FX_BIC_I(10); }
static inline void fx_bic_i11() { FX_BIC_I(11); }
static inline void fx_bic_i12() { FX_BIC_I(12); }
static inline void fx_bic_i13() { FX_BIC_I(13); }
static inline void fx_bic_i14() { FX_BIC_I(14); }
static inline void fx_bic_i15() { FX_BIC_I(15); }

/* 80-8f - mult rn - 8 bit to 16 bit signed multiply, register * register */
#define FX_MULT(reg) \
uint32 v = (uint32)(SEX8(SREG) * SEX8(GSU.avReg[reg])); \
R15++; DREG = v; \
GSU.vSign = v; \
GSU.vZero = v; \
TESTR14; \
CLRFLAGS;
static inline void fx_mult_r0() { FX_MULT(0); }
static inline void fx_mult_r1() { FX_MULT(1); }
static inline void fx_mult_r2() { FX_MULT(2); }
static inline void fx_mult_r3() { FX_MULT(3); }
static inline void fx_mult_r4() { FX_MULT(4); }
static inline void fx_mult_r5() { FX_MULT(5); }
static inline void fx_mult_r6() { FX_MULT(6); }
static inline void fx_mult_r7() { FX_MULT(7); }
static inline void fx_mult_r8() { FX_MULT(8); }
static inline void fx_mult_r9() { FX_MULT(9); }
static inline void fx_mult_r10() { FX_MULT(10); }
static inline void fx_mult_r11() { FX_MULT(11); }
static inline void fx_mult_r12() { FX_MULT(12); }
static inline void fx_mult_r13() { FX_MULT(13); }
static inline void fx_mult_r14() { FX_MULT(14); }
static inline void fx_mult_r15() { FX_MULT(15); }

/* 80-8f(ALT1) - umult rn - 8 bit to 16 bit unsigned multiply, register * register */
#define FX_UMULT(reg) \
uint32 v = USEX8(SREG) * USEX8(GSU.avReg[reg]); \
R15++; DREG = v; \
GSU.vSign = v; \
GSU.vZero = v; \
TESTR14; \
CLRFLAGS;
static inline void fx_umult_r0() { FX_UMULT(0); }
static inline void fx_umult_r1() { FX_UMULT(1); }
static inline void fx_umult_r2() { FX_UMULT(2); }
static inline void fx_umult_r3() { FX_UMULT(3); }
static inline void fx_umult_r4() { FX_UMULT(4); }
static inline void fx_umult_r5() { FX_UMULT(5); }
static inline void fx_umult_r6() { FX_UMULT(6); }
static inline void fx_umult_r7() { FX_UMULT(7); }
static inline void fx_umult_r8() { FX_UMULT(8); }
static inline void fx_umult_r9() { FX_UMULT(9); }
static inline void fx_umult_r10() { FX_UMULT(10); }
static inline void fx_umult_r11() { FX_UMULT(11); }
static inline void fx_umult_r12() { FX_UMULT(12); }
static inline void fx_umult_r13() { FX_UMULT(13); }
static inline void fx_umult_r14() { FX_UMULT(14); }
static inline void fx_umult_r15() { FX_UMULT(15); }
  
/* 80-8f(ALT2) - mult #n - 8 bit to 16 bit signed multiply, register * immediate */
#define FX_MULT_I(imm) \
uint32 v = (uint32) (SEX8(SREG) * ((int32)imm)); \
R15++; DREG = v; \
GSU.vSign = v; \
GSU.vZero = v; \
TESTR14; \
CLRFLAGS;
static inline void fx_mult_i0() { FX_MULT_I(0); }
static inline void fx_mult_i1() { FX_MULT_I(1); }
static inline void fx_mult_i2() { FX_MULT_I(2); }
static inline void fx_mult_i3() { FX_MULT_I(3); }
static inline void fx_mult_i4() { FX_MULT_I(4); }
static inline void fx_mult_i5() { FX_MULT_I(5); }
static inline void fx_mult_i6() { FX_MULT_I(6); }
static inline void fx_mult_i7() { FX_MULT_I(7); }
static inline void fx_mult_i8() { FX_MULT_I(8); }
static inline void fx_mult_i9() { FX_MULT_I(9); }
static inline void fx_mult_i10() { FX_MULT_I(10); }
static inline void fx_mult_i11() { FX_MULT_I(11); }
static inline void fx_mult_i12() { FX_MULT_I(12); }
static inline void fx_mult_i13() { FX_MULT_I(13); }
static inline void fx_mult_i14() { FX_MULT_I(14); }
static inline void fx_mult_i15() { FX_MULT_I(15); }
  
/* 80-8f(ALT3) - umult #n - 8 bit to 16 bit unsigned multiply, register * immediate */
#define FX_UMULT_I(imm) \
uint32 v = USEX8(SREG) * ((uint32)imm); \
R15++; DREG = v; \
GSU.vSign = v; \
GSU.vZero = v; \
TESTR14; \
CLRFLAGS;
static inline void fx_umult_i0() { FX_UMULT_I(0); }
static inline void fx_umult_i1() { FX_UMULT_I(1); }
static inline void fx_umult_i2() { FX_UMULT_I(2); }
static inline void fx_umult_i3() { FX_UMULT_I(3); }
static inline void fx_umult_i4() { FX_UMULT_I(4); }
static inline void fx_umult_i5() { FX_UMULT_I(5); }
static inline void fx_umult_i6() { FX_UMULT_I(6); }
static inline void fx_umult_i7() { FX_UMULT_I(7); }
static inline void fx_umult_i8() { FX_UMULT_I(8); }
static inline void fx_umult_i9() { FX_UMULT_I(9); }
static inline void fx_umult_i10() { FX_UMULT_I(10); }
static inline void fx_umult_i11() { FX_UMULT_I(11); }
static inline void fx_umult_i12() { FX_UMULT_I(12); }
static inline void fx_umult_i13() { FX_UMULT_I(13); }
static inline void fx_umult_i14() { FX_UMULT_I(14); }
static inline void fx_umult_i15() { FX_UMULT_I(15); }
  
/* 90 - sbk - store word to last accessed RAM address */
static inline void fx_sbk()
{
    RAM(GSU.vLastRamAdr) = (uint8)SREG;
    RAM(GSU.vLastRamAdr^1) = (uint8)(SREG>>8);
    CLRFLAGS;
    R15++;
}

/* 91-94 - link #n - R11 = R15 + immediate */
#define FX_LINK_I(lkn) R11 = R15 + lkn; CLRFLAGS; R15++
static inline void fx_link_i1() { FX_LINK_I(1); }
static inline void fx_link_i2() { FX_LINK_I(2); }
static inline void fx_link_i3() { FX_LINK_I(3); }
static inline void fx_link_i4() { FX_LINK_I(4); }

/* 95 - sex - sign extend 8 bit to 16 bit */
static inline void fx_sex()
{
    uint32 v = (uint32)SEX8(SREG);
    R15++; DREG = v;
    GSU.vSign = v;
    GSU.vZero = v;
    TESTR14;
    CLRFLAGS;
}

/* 96 - asr - aritmetric shift right by one */
static inline void fx_asr()
{
    uint32 v;
    GSU.vCarry = SREG & 1;
    v = (uint32)(SEX16(SREG)>>1);
    R15++; DREG = v;
    GSU.vSign = v;
    GSU.vZero = v;
    TESTR14;
    CLRFLAGS;
}

/* 96(ALT1) - div2 - aritmetric shift right by one */
static inline void fx_div2()
{
    uint32 v;
    int32 s = SEX16(SREG);
    GSU.vCarry = s & 1;
    if(s == -1)
	v = 0;
    else
	v = (uint32)(s>>1);
    R15++; DREG = v;
    GSU.vSign = v;
    GSU.vZero = v;
    TESTR14;
    CLRFLAGS;
}

/* 97 - ror - rotate right by one */
static inline void fx_ror()
{
    uint32 v = (USEX16(SREG)>>1) | (GSU.vCarry<<15);
    GSU.vCarry = SREG & 1;
    R15++; DREG = v;
    GSU.vSign = v;
    GSU.vZero = v;
    TESTR14;
    CLRFLAGS;
}

/* 98-9d - jmp rn - jump to address of register */
#define FX_JMP(reg) \
R15 = GSU.avReg[reg]; \
CLRFLAGS;
static inline void fx_jmp_r8() { FX_JMP(8); }
static inline void fx_jmp_r9() { FX_JMP(9); }
static inline void fx_jmp_r10() { FX_JMP(10); }
static inline void fx_jmp_r11() { FX_JMP(11); }
static inline void fx_jmp_r12() { FX_JMP(12); }
static inline void fx_jmp_r13() { FX_JMP(13); }

/* 98-9d(ALT1) - ljmp rn - set program bank to source register and jump to address of register */
#define FX_LJMP(reg) \
GSU.vPrgBankReg = GSU.avReg[reg] & 0x7f; \
GSU.pvPrgBank = GSU.apvRomBank[GSU.vPrgBankReg]; \
R15 = SREG; \
GSU.bCacheActive = FALSE; fx_cache(); R15--;
static inline void fx_ljmp_r8() { FX_LJMP(8); }
static inline void fx_ljmp_r9() { FX_LJMP(9); }
static inline void fx_ljmp_r10() { FX_LJMP(10); }
static inline void fx_ljmp_r11() { FX_LJMP(11); }
static inline void fx_ljmp_r12() { FX_LJMP(12); }
static inline void fx_ljmp_r13() { FX_LJMP(13); }

/* 9e - lob - set upper byte to zero (keep low byte) */
static inline void fx_lob()
{
    uint32 v = USEX8(SREG);
    R15++; DREG = v;
    GSU.vSign = v<<8;
    GSU.vZero = v<<8;
    TESTR14;
    CLRFLAGS;
}

/* 9f - fmult - 16 bit to 32 bit signed multiplication, upper 16 bits only */
static inline void fx_fmult()
{
    uint32 v;
    uint32 c = (uint32) (SEX16(SREG) * SEX16(R6));
    v = c >> 16;
    R15++; DREG = v;
    GSU.vSign = v;
    GSU.vZero = v;
    GSU.vCarry = (c >> 15) & 1;
    TESTR14;
    CLRFLAGS;
}

/* 9f(ALT1) - lmult - 16 bit to 32 bit signed multiplication */
static inline void fx_lmult()
{
    uint32 v;
    uint32 c = (uint32) (SEX16(SREG) * SEX16(R6));
    R4 = c;
    v = c >> 16;
    R15++; DREG = v;
    GSU.vSign = v;
    GSU.vZero = v;
    /* XXX R6 or R4? */
    GSU.vCarry = (R4 >> 15) & 1;	/* should it be bit 15 of R4 instead? */
    TESTR14;
    CLRFLAGS;
}

/* a0-af - ibt rn,#pp - immediate byte transfer */
#define FX_IBT(reg) \
uint8 v = PIPE; R15++; \
FETCHPIPE; R15++; \
GSU.avReg[reg] = SEX8(v); \
CLRFLAGS;
static inline void fx_ibt_r0() { FX_IBT(0); }
static inline void fx_ibt_r1() { FX_IBT(1); }
static inline void fx_ibt_r2() { FX_IBT(2); }
static inline void fx_ibt_r3() { FX_IBT(3); }
static inline void fx_ibt_r4() { FX_IBT(4); }
static inline void fx_ibt_r5() { FX_IBT(5); }
static inline void fx_ibt_r6() { FX_IBT(6); }
static inline void fx_ibt_r7() { FX_IBT(7); }
static inline void fx_ibt_r8() { FX_IBT(8); }
static inline void fx_ibt_r9() { FX_IBT(9); }
static inline void fx_ibt_r10() { FX_IBT(10); }
static inline void fx_ibt_r11() { FX_IBT(11); }
static inline void fx_ibt_r12() { FX_IBT(12); }
static inline void fx_ibt_r13() { FX_IBT(13); }
static inline void fx_ibt_r14() { FX_IBT(14); READR14; }
static inline void fx_ibt_r15() { FX_IBT(15); }

/* a0-af(ALT1) - lms rn,(yy) - load word from RAM (short address) */
#define FX_LMS(reg) \
GSU.vLastRamAdr = ((uint32)PIPE) << 1; \
R15++; FETCHPIPE; R15++; \
GSU.avReg[reg] = (uint32)RAM(GSU.vLastRamAdr); \
GSU.avReg[reg] |= ((uint32)RAM(GSU.vLastRamAdr+1))<<8; \
CLRFLAGS;
static inline void fx_lms_r0() { FX_LMS(0); }
static inline void fx_lms_r1() { FX_LMS(1); }
static inline void fx_lms_r2() { FX_LMS(2); }
static inline void fx_lms_r3() { FX_LMS(3); }
static inline void fx_lms_r4() { FX_LMS(4); }
static inline void fx_lms_r5() { FX_LMS(5); }
static inline void fx_lms_r6() { FX_LMS(6); }
static inline void fx_lms_r7() { FX_LMS(7); }
static inline void fx_lms_r8() { FX_LMS(8); }
static inline void fx_lms_r9() { FX_LMS(9); }
static inline void fx_lms_r10() { FX_LMS(10); }
static inline void fx_lms_r11() { FX_LMS(11); }
static inline void fx_lms_r12() { FX_LMS(12); }
static inline void fx_lms_r13() { FX_LMS(13); }
static inline void fx_lms_r14() { FX_LMS(14); READR14; }
static inline void fx_lms_r15() { FX_LMS(15); }

/* a0-af(ALT2) - sms (yy),rn - store word in RAM (short address) */
/* If rn == r15, is the value of r15 before or after the extra byte is read? */
#define FX_SMS(reg) \
uint32 v = GSU.avReg[reg]; \
GSU.vLastRamAdr = ((uint32)PIPE) << 1; \
R15++; FETCHPIPE; \
RAM(GSU.vLastRamAdr) = (uint8)v; \
RAM(GSU.vLastRamAdr+1) = (uint8)(v>>8); \
CLRFLAGS; R15++;
static inline void fx_sms_r0() { FX_SMS(0); }
static inline void fx_sms_r1() { FX_SMS(1); }
static inline void fx_sms_r2() { FX_SMS(2); }
static inline void fx_sms_r3() { FX_SMS(3); }
static inline void fx_sms_r4() { FX_SMS(4); }
static inline void fx_sms_r5() { FX_SMS(5); }
static inline void fx_sms_r6() { FX_SMS(6); }
static inline void fx_sms_r7() { FX_SMS(7); }
static inline void fx_sms_r8() { FX_SMS(8); }
static inline void fx_sms_r9() { FX_SMS(9); }
static inline void fx_sms_r10() { FX_SMS(10); }
static inline void fx_sms_r11() { FX_SMS(11); }
static inline void fx_sms_r12() { FX_SMS(12); }
static inline void fx_sms_r13() { FX_SMS(13); }
static inline void fx_sms_r14() { FX_SMS(14); }
static inline void fx_sms_r15() { FX_SMS(15); }

/* b0-bf - from rn - set source register */
/* b0-bf(B) - moves rn - move register to register, and set flags, (if B flag is set) */
#define FX_FROM(reg) \
if(TF(B)) { uint32 v = GSU.avReg[reg]; R15++; DREG = v; \
GSU.vOverflow = (v&0x80) << 16; GSU.vSign = v; GSU.vZero = v; TESTR14; CLRFLAGS; } \
else { GSU.pvSreg = &GSU.avReg[reg]; R15++; }
static inline void fx_from_r0() { FX_FROM(0); }
static inline void fx_from_r1() { FX_FROM(1); }
static inline void fx_from_r2() { FX_FROM(2); }
static inline void fx_from_r3() { FX_FROM(3); }
static inline void fx_from_r4() { FX_FROM(4); }
static inline void fx_from_r5() { FX_FROM(5); }
static inline void fx_from_r6() { FX_FROM(6); }
static inline void fx_from_r7() { FX_FROM(7); }
static inline void fx_from_r8() { FX_FROM(8); }
static inline void fx_from_r9() { FX_FROM(9); }
static inline void fx_from_r10() { FX_FROM(10); }
static inline void fx_from_r11() { FX_FROM(11); }
static inline void fx_from_r12() { FX_FROM(12); }
static inline void fx_from_r13() { FX_FROM(13); }
static inline void fx_from_r14() { FX_FROM(14); }
static inline void fx_from_r15() { FX_FROM(15); }

/* c0 - hib - move high-byte to low-byte */
static inline void fx_hib()
{
    uint32 v = USEX8(SREG>>8);
    R15++; DREG = v;
    GSU.vSign = v<<8;
    GSU.vZero = v<<8;
    TESTR14;
    CLRFLAGS;
}

/* c1-cf - or rn */
#define FX_OR(reg) \
uint32 v = SREG | GSU.avReg[reg]; R15++; DREG = v; \
GSU.vSign = v; \
GSU.vZero = v; \
TESTR14; \
CLRFLAGS;
static inline void fx_or_r1() { FX_OR(1); }
static inline void fx_or_r2() { FX_OR(2); }
static inline void fx_or_r3() { FX_OR(3); }
static inline void fx_or_r4() { FX_OR(4); }
static inline void fx_or_r5() { FX_OR(5); }
static inline void fx_or_r6() { FX_OR(6); }
static inline void fx_or_r7() { FX_OR(7); }
static inline void fx_or_r8() { FX_OR(8); }
static inline void fx_or_r9() { FX_OR(9); }
static inline void fx_or_r10() { FX_OR(10); }
static inline void fx_or_r11() { FX_OR(11); }
static inline void fx_or_r12() { FX_OR(12); }
static inline void fx_or_r13() { FX_OR(13); }
static inline void fx_or_r14() { FX_OR(14); }
static inline void fx_or_r15() { FX_OR(15); }

/* c1-cf(ALT1) - xor rn */
#define FX_XOR(reg) \
uint32 v = SREG ^ GSU.avReg[reg]; R15++; DREG = v; \
GSU.vSign = v; \
GSU.vZero = v; \
TESTR14; \
CLRFLAGS;
static inline void fx_xor_r1() { FX_XOR(1); }
static inline void fx_xor_r2() { FX_XOR(2); }
static inline void fx_xor_r3() { FX_XOR(3); }
static inline void fx_xor_r4() { FX_XOR(4); }
static inline void fx_xor_r5() { FX_XOR(5); }
static inline void fx_xor_r6() { FX_XOR(6); }
static inline void fx_xor_r7() { FX_XOR(7); }
static inline void fx_xor_r8() { FX_XOR(8); }
static inline void fx_xor_r9() { FX_XOR(9); }
static inline void fx_xor_r10() { FX_XOR(10); }
static inline void fx_xor_r11() { FX_XOR(11); }
static inline void fx_xor_r12() { FX_XOR(12); }
static inline void fx_xor_r13() { FX_XOR(13); }
static inline void fx_xor_r14() { FX_XOR(14); }
static inline void fx_xor_r15() { FX_XOR(15); }

/* c1-cf(ALT2) - or #n */
#define FX_OR_I(imm) \
uint32 v = SREG | imm; R15++; DREG = v; \
GSU.vSign = v; \
GSU.vZero = v; \
TESTR14; \
CLRFLAGS;
static inline void fx_or_i1() { FX_OR_I(1); }
static inline void fx_or_i2() { FX_OR_I(2); }
static inline void fx_or_i3() { FX_OR_I(3); }
static inline void fx_or_i4() { FX_OR_I(4); }
static inline void fx_or_i5() { FX_OR_I(5); }
static inline void fx_or_i6() { FX_OR_I(6); }
static inline void fx_or_i7() { FX_OR_I(7); }
static inline void fx_or_i8() { FX_OR_I(8); }
static inline void fx_or_i9() { FX_OR_I(9); }
static inline void fx_or_i10() { FX_OR_I(10); }
static inline void fx_or_i11() { FX_OR_I(11); }
static inline void fx_or_i12() { FX_OR_I(12); }
static inline void fx_or_i13() { FX_OR_I(13); }
static inline void fx_or_i14() { FX_OR_I(14); }
static inline void fx_or_i15() { FX_OR_I(15); }

/* c1-cf(ALT3) - xor #n */
#define FX_XOR_I(imm) \
uint32 v = SREG ^ imm; R15++; DREG = v; \
GSU.vSign = v; \
GSU.vZero = v; \
TESTR14; \
CLRFLAGS;
static inline void fx_xor_i1() { FX_XOR_I(1); }
static inline void fx_xor_i2() { FX_XOR_I(2); }
static inline void fx_xor_i3() { FX_XOR_I(3); }
static inline void fx_xor_i4() { FX_XOR_I(4); }
static inline void fx_xor_i5() { FX_XOR_I(5); }
static inline void fx_xor_i6() { FX_XOR_I(6); }
static inline void fx_xor_i7() { FX_XOR_I(7); }
static inline void fx_xor_i8() { FX_XOR_I(8); }
static inline void fx_xor_i9() { FX_XOR_I(9); }
static inline void fx_xor_i10() { FX_XOR_I(10); }
static inline void fx_xor_i11() { FX_XOR_I(11); }
static inline void fx_xor_i12() { FX_XOR_I(12); }
static inline void fx_xor_i13() { FX_XOR_I(13); }
static inline void fx_xor_i14() { FX_XOR_I(14); }
static inline void fx_xor_i15() { FX_XOR_I(15); }

/* d0-de - inc rn - increase by one */
#define FX_INC(reg) \
GSU.avReg[reg] += 1; \
GSU.vSign = GSU.avReg[reg]; \
GSU.vZero = GSU.avReg[reg]; \
CLRFLAGS; R15++;
static inline void fx_inc_r0() { FX_INC(0); }
static inline void fx_inc_r1() { FX_INC(1); }
static inline void fx_inc_r2() { FX_INC(2); }
static inline void fx_inc_r3() { FX_INC(3); }
static inline void fx_inc_r4() { FX_INC(4); }
static inline void fx_inc_r5() { FX_INC(5); }
static inline void fx_inc_r6() { FX_INC(6); }
static inline void fx_inc_r7() { FX_INC(7); }
static inline void fx_inc_r8() { FX_INC(8); }
static inline void fx_inc_r9() { FX_INC(9); }
static inline void fx_inc_r10() { FX_INC(10); }
static inline void fx_inc_r11() { FX_INC(11); }
static inline void fx_inc_r12() { FX_INC(12); }
static inline void fx_inc_r13() { FX_INC(13); }
static inline void fx_inc_r14() { FX_INC(14); READR14; }

/* df - getc - transfer ROM buffer to color register */
static inline void fx_getc()
{
#ifndef FX_DO_ROMBUFFER
    uint8 c;
    c = ROM(R14);
#else
    uint8 c = GSU.vRomBuffer;
#endif
    if(GSU.vPlotOptionReg & 0x04)
	c = (c&0xf0) | (c>>4);
    if(GSU.vPlotOptionReg & 0x08)
    {
	GSU.vColorReg &= 0xf0;
	GSU.vColorReg |= c & 0x0f;
    }
    else
	GSU.vColorReg = USEX8(c);
    CLRFLAGS;
    R15++;
}

/* df(ALT2) - ramb - set current RAM bank */
static inline void fx_ramb()
{
    GSU.vRamBankReg = SREG & (FX_RAM_BANKS-1);
    GSU.pvRamBank = GSU.apvRamBank[GSU.vRamBankReg & 0x3];
    CLRFLAGS;
    R15++;
}

/* df(ALT3) - romb - set current ROM bank */
static inline void fx_romb()
{
    GSU.vRomBankReg = USEX8(SREG) & 0x7f;
    GSU.pvRomBank = GSU.apvRomBank[GSU.vRomBankReg];
    CLRFLAGS;
    R15++;
}

/* e0-ee - dec rn - decrement by one */
#define FX_DEC(reg) \
GSU.avReg[reg] -= 1; \
GSU.vSign = GSU.avReg[reg]; \
GSU.vZero = GSU.avReg[reg]; \
CLRFLAGS; R15++;
static inline void fx_dec_r0() { FX_DEC(0); }
static inline void fx_dec_r1() { FX_DEC(1); }
static inline void fx_dec_r2() { FX_DEC(2); }
static inline void fx_dec_r3() { FX_DEC(3); }
static inline void fx_dec_r4() { FX_DEC(4); }
static inline void fx_dec_r5() { FX_DEC(5); }
static inline void fx_dec_r6() { FX_DEC(6); }
static inline void fx_dec_r7() { FX_DEC(7); }
static inline void fx_dec_r8() { FX_DEC(8); }
static inline void fx_dec_r9() { FX_DEC(9); }
static inline void fx_dec_r10() { FX_DEC(10); }
static inline void fx_dec_r11() { FX_DEC(11); }
static inline void fx_dec_r12() { FX_DEC(12); }
static inline void fx_dec_r13() { FX_DEC(13); }
static inline void fx_dec_r14() { FX_DEC(14); READR14; }

/* ef - getb - get byte from ROM at address R14 */
static inline void fx_getb()
{
    uint32 v;
#ifndef FX_DO_ROMBUFFER
    v = (uint32)ROM(R14);
#else
    v = (uint32)GSU.vRomBuffer;
#endif
    R15++; DREG = v;
    TESTR14;
    CLRFLAGS;
}

/* ef(ALT1) - getbh - get high-byte from ROM at address R14 */
static inline void fx_getbh()
{
    uint32 v;
#ifndef FX_DO_ROMBUFFER
    uint32 c;
    c = (uint32)ROM(R14);
#else
    uint32 c = USEX8(GSU.vRomBuffer);
#endif
    v = USEX8(SREG) | (c<<8);
    R15++; DREG = v;
    TESTR14;
    CLRFLAGS;
}

/* ef(ALT2) - getbl - get low-byte from ROM at address R14 */
static inline void fx_getbl()
{
    uint32 v;
#ifndef FX_DO_ROMBUFFER
    uint32 c;
    c = (uint32)ROM(R14);
#else
    uint32 c = USEX8(GSU.vRomBuffer);
#endif
    v = (SREG & 0xff00) | c;
    R15++; DREG = v;
    TESTR14;
    CLRFLAGS;
}

/* ef(ALT3) - getbs - get sign extended byte from ROM at address R14 */
static inline void fx_getbs()
{
    uint32 v;
#ifndef FX_DO_ROMBUFFER
    int8 c;
    c = ROM(R14);
    v = SEX8(c);
#else
    v = SEX8(GSU.vRomBuffer);
#endif
    R15++; DREG = v;
    TESTR14;
    CLRFLAGS;
}

/* f0-ff - iwt rn,#xx - immediate word transfer to register */
#define FX_IWT(reg) \
uint32 v = PIPE; R15++; FETCHPIPE; R15++; \
v |= USEX8(PIPE) << 8; FETCHPIPE; R15++; \
GSU.avReg[reg] = v; \
CLRFLAGS;
static inline void fx_iwt_r0() { FX_IWT(0); }
static inline void fx_iwt_r1() { FX_IWT(1); }
static inline void fx_iwt_r2() { FX_IWT(2); }
static inline void fx_iwt_r3() { FX_IWT(3); }
static inline void fx_iwt_r4() { FX_IWT(4); }
static inline void fx_iwt_r5() { FX_IWT(5); }
static inline void fx_iwt_r6() { FX_IWT(6); }
static inline void fx_iwt_r7() { FX_IWT(7); }
static inline void fx_iwt_r8() { FX_IWT(8); }
static inline void fx_iwt_r9() { FX_IWT(9); }
static inline void fx_iwt_r10() { FX_IWT(10); }
static inline void fx_iwt_r11() { FX_IWT(11); }
static inline void fx_iwt_r12() { FX_IWT(12); }
static inline void fx_iwt_r13() { FX_IWT(13); }
static inline void fx_iwt_r14() { FX_IWT(14); READR14; }
static inline void fx_iwt_r15() { FX_IWT(15); }

/* f0-ff(ALT1) - lm rn,(xx) - load word from RAM */
#define FX_LM(reg) \
GSU.vLastRamAdr = PIPE; R15++; FETCHPIPE; R15++; \
GSU.vLastRamAdr |= USEX8(PIPE) << 8; FETCHPIPE; R15++; \
GSU.avReg[reg] = RAM(GSU.vLastRamAdr); \
GSU.avReg[reg] |= USEX8(RAM(GSU.vLastRamAdr^1)) << 8; \
CLRFLAGS;
static inline void fx_lm_r0() { FX_LM(0); }
static inline void fx_lm_r1() { FX_LM(1); }
static inline void fx_lm_r2() { FX_LM(2); }
static inline void fx_lm_r3() { FX_LM(3); }
static inline void fx_lm_r4() { FX_LM(4); }
static inline void fx_lm_r5() { FX_LM(5); }
static inline void fx_lm_r6() { FX_LM(6); }
static inline void fx_lm_r7() { FX_LM(7); }
static inline void fx_lm_r8() { FX_LM(8); }
static inline void fx_lm_r9() { FX_LM(9); }
static inline void fx_lm_r10() { FX_LM(10); }
static inline void fx_lm_r11() { FX_LM(11); }
static inline void fx_lm_r12() { FX_LM(12); }
static inline void fx_lm_r13() { FX_LM(13); }
static inline void fx_lm_r14() { FX_LM(14); READR14; }
static inline void fx_lm_r15() { FX_LM(15); }

/* f0-ff(ALT2) - sm (xx),rn - store word in RAM */
/* If rn == r15, is the value of r15 before or after the extra bytes are read? */
#define FX_SM(reg) \
uint32 v = GSU.avReg[reg]; \
GSU.vLastRamAdr = PIPE; R15++; FETCHPIPE; R15++; \
GSU.vLastRamAdr |= USEX8(PIPE) << 8; FETCHPIPE; \
RAM(GSU.vLastRamAdr) = (uint8)v; \
RAM(GSU.vLastRamAdr^1) = (uint8)(v>>8); \
CLRFLAGS; R15++;
static inline void fx_sm_r0() { FX_SM(0); }
static inline void fx_sm_r1() { FX_SM(1); }
static inline void fx_sm_r2() { FX_SM(2); }
static inline void fx_sm_r3() { FX_SM(3); }
static inline void fx_sm_r4() { FX_SM(4); }
static inline void fx_sm_r5() { FX_SM(5); }
static inline void fx_sm_r6() { FX_SM(6); }
static inline void fx_sm_r7() { FX_SM(7); }
static inline void fx_sm_r8() { FX_SM(8); }
static inline void fx_sm_r9() { FX_SM(9); }
static inline void fx_sm_r10() { FX_SM(10); }
static inline void fx_sm_r11() { FX_SM(11); }
static inline void fx_sm_r12() { FX_SM(12); }
static inline void fx_sm_r13() { FX_SM(13); }
static inline void fx_sm_r14() { FX_SM(14); }
static inline void fx_sm_r15() { FX_SM(15); }

#define ASSUME(cond_) if (!(cond_)) __builtin_unreachable()

/*** GSU executions functions ***/

static uint32 fx_run(uint32 nInstructions)
{
    //printf ("fx: %d\n", nInstructions);

#define LIKELY(cond_) __builtin_expect(!!(cond_), 1)
#define UNLIKELY(cond_) __builtin_expect(!!(cond_), 0)
    GSU.vCounter = nInstructions;
    READR14;
    while(LIKELY(GSU.vCounter-- > 0))
    {
        uint32 vOpcode = (uint32)GSU.vPipe | (GSU.vStatusReg & 0x300);
        GSU.vPipe = GSU.pvPrgBank[((uint32)((uint16)(GSU.avReg[15])))];

        ASSUME(vOpcode < 0x400);

		// If you replace this, you must:
		// - Replace fx_stop's break with goto loop_end or equivalent
		// - Replace 0x04c and 0x24c with GSU.pfPlot
		// - Replace 0x14c and 0x34c with GSU.pfRpix
		switch (vOpcode) {
            case 0x000: case 0x100: case 0x200: case 0x300: fx_stop(); goto loop_end;
            case 0x001: case 0x101: case 0x201: case 0x301: fx_nop(); break;
            case 0x002: case 0x102: case 0x202: case 0x302: fx_cache(); break;
            case 0x003: case 0x103: case 0x203: case 0x303: fx_lsr(); break;
            case 0x004: case 0x104: case 0x204: case 0x304: fx_rol(); break;
            case 0x005: case 0x105: case 0x205: case 0x305: fx_bra(); break;
            case 0x006: case 0x106: case 0x206: case 0x306: fx_bge(); break;
            case 0x007: case 0x107: case 0x207: case 0x307: fx_blt(); break;
            case 0x008: case 0x108: case 0x208: case 0x308: fx_bne(); break;
            case 0x009: case 0x109: case 0x209: case 0x309: fx_beq(); break;
            case 0x00a: case 0x10a: case 0x20a: case 0x30a: fx_bpl(); break;
            case 0x00b: case 0x10b: case 0x20b: case 0x30b: fx_bmi(); break;
            case 0x00c: case 0x10c: case 0x20c: case 0x30c: fx_bcc(); break;
            case 0x00d: case 0x10d: case 0x20d: case 0x30d: fx_bcs(); break;
            case 0x00e: case 0x10e: case 0x20e: case 0x30e: fx_bvc(); break;
            case 0x00f: case 0x10f: case 0x20f: case 0x30f: fx_bvs(); break;
            case 0x010: case 0x110: case 0x210: case 0x310: fx_to_r0(); break;
            case 0x011: case 0x111: case 0x211: case 0x311: fx_to_r1(); break;
            case 0x012: case 0x112: case 0x212: case 0x312: fx_to_r2(); break;
            case 0x013: case 0x113: case 0x213: case 0x313: fx_to_r3(); break;
            case 0x014: case 0x114: case 0x214: case 0x314: fx_to_r4(); break;
            case 0x015: case 0x115: case 0x215: case 0x315: fx_to_r5(); break;
            case 0x016: case 0x116: case 0x216: case 0x316: fx_to_r6(); break;
            case 0x017: case 0x117: case 0x217: case 0x317: fx_to_r7(); break;
            case 0x018: case 0x118: case 0x218: case 0x318: fx_to_r8(); break;
            case 0x019: case 0x119: case 0x219: case 0x319: fx_to_r9(); break;
            case 0x01a: case 0x11a: case 0x21a: case 0x31a: fx_to_r10(); break;
            case 0x01b: case 0x11b: case 0x21b: case 0x31b: fx_to_r11(); break;
            case 0x01c: case 0x11c: case 0x21c: case 0x31c: fx_to_r12(); break;
            case 0x01d: case 0x11d: case 0x21d: case 0x31d: fx_to_r13(); break;
            case 0x01e: case 0x11e: case 0x21e: case 0x31e: fx_to_r14(); break;
            case 0x01f: case 0x11f: case 0x21f: case 0x31f: fx_to_r15(); break;
            case 0x020: case 0x120: case 0x220: case 0x320: fx_with_r0(); break;
            case 0x021: case 0x121: case 0x221: case 0x321: fx_with_r1(); break;
            case 0x022: case 0x122: case 0x222: case 0x322: fx_with_r2(); break;
            case 0x023: case 0x123: case 0x223: case 0x323: fx_with_r3(); break;
            case 0x024: case 0x124: case 0x224: case 0x324: fx_with_r4(); break;
            case 0x025: case 0x125: case 0x225: case 0x325: fx_with_r5(); break;
            case 0x026: case 0x126: case 0x226: case 0x326: fx_with_r6(); break;
            case 0x027: case 0x127: case 0x227: case 0x327: fx_with_r7(); break;
            case 0x028: case 0x128: case 0x228: case 0x328: fx_with_r8(); break;
            case 0x029: case 0x129: case 0x229: case 0x329: fx_with_r9(); break;
            case 0x02a: case 0x12a: case 0x22a: case 0x32a: fx_with_r10(); break;
            case 0x02b: case 0x12b: case 0x22b: case 0x32b: fx_with_r11(); break;
            case 0x02c: case 0x12c: case 0x22c: case 0x32c: fx_with_r12(); break;
            case 0x02d: case 0x12d: case 0x22d: case 0x32d: fx_with_r13(); break;
            case 0x02e: case 0x12e: case 0x22e: case 0x32e: fx_with_r14(); break;
            case 0x02f: case 0x12f: case 0x22f: case 0x32f: fx_with_r15(); break;
            case 0x030: case 0x230: fx_stw_r0(); break;
            case 0x031: case 0x231: fx_stw_r1(); break;
            case 0x032: case 0x232: fx_stw_r2(); break;
            case 0x033: case 0x233: fx_stw_r3(); break;
            case 0x034: case 0x234: fx_stw_r4(); break;
            case 0x035: case 0x235: fx_stw_r5(); break;
            case 0x036: case 0x236: fx_stw_r6(); break;
            case 0x037: case 0x237: fx_stw_r7(); break;
            case 0x038: case 0x238: fx_stw_r8(); break;
            case 0x039: case 0x239: fx_stw_r9(); break;
            case 0x03a: case 0x23a: fx_stw_r10(); break;
            case 0x03b: case 0x23b: fx_stw_r11(); break;
            case 0x03c: case 0x13c: case 0x23c: case 0x33c: fx_loop(); break;
            case 0x03d: case 0x13d: case 0x23d: case 0x33d: fx_alt1(); break;
            case 0x03e: case 0x13e: case 0x23e: case 0x33e: fx_alt2(); break;
            case 0x03f: case 0x13f: case 0x23f: case 0x33f: fx_alt3(); break;
            case 0x040: case 0x240: fx_ldw_r0(); break;
            case 0x041: case 0x241: fx_ldw_r1(); break;
            case 0x042: case 0x242: fx_ldw_r2(); break;
            case 0x043: case 0x243: fx_ldw_r3(); break;
            case 0x044: case 0x244: fx_ldw_r4(); break;
            case 0x045: case 0x245: fx_ldw_r5(); break;
            case 0x046: case 0x246: fx_ldw_r6(); break;
            case 0x047: case 0x247: fx_ldw_r7(); break;
            case 0x048: case 0x248: fx_ldw_r8(); break;
            case 0x049: case 0x249: fx_ldw_r9(); break;
            case 0x04a: case 0x24a: fx_ldw_r10(); break;
            case 0x04b: case 0x24b: fx_ldw_r11(); break;
            case 0x04c: case 0x24c: GSU.pfPlot(); break;
            case 0x04d: case 0x14d: case 0x24d: case 0x34d: fx_swap(); break;
            case 0x04e: case 0x24e: fx_color(); break;
            case 0x04f: case 0x14f: case 0x24f: case 0x34f: fx_not(); break;
            case 0x050: fx_add_r0(); break;
            case 0x051: fx_add_r1(); break;
            case 0x052: fx_add_r2(); break;
            case 0x053: fx_add_r3(); break;
            case 0x054: fx_add_r4(); break;
            case 0x055: fx_add_r5(); break;
            case 0x056: fx_add_r6(); break;
            case 0x057: fx_add_r7(); break;
            case 0x058: fx_add_r8(); break;
            case 0x059: fx_add_r9(); break;
            case 0x05a: fx_add_r10(); break;
            case 0x05b: fx_add_r11(); break;
            case 0x05c: fx_add_r12(); break;
            case 0x05d: fx_add_r13(); break;
            case 0x05e: fx_add_r14(); break;
            case 0x05f: fx_add_r15(); break;
            case 0x060: fx_sub_r0(); break;
            case 0x061: fx_sub_r1(); break;
            case 0x062: fx_sub_r2(); break;
            case 0x063: fx_sub_r3(); break;
            case 0x064: fx_sub_r4(); break;
            case 0x065: fx_sub_r5(); break;
            case 0x066: fx_sub_r6(); break;
            case 0x067: fx_sub_r7(); break;
            case 0x068: fx_sub_r8(); break;
            case 0x069: fx_sub_r9(); break;
            case 0x06a: fx_sub_r10(); break;
            case 0x06b: fx_sub_r11(); break;
            case 0x06c: fx_sub_r12(); break;
            case 0x06d: fx_sub_r13(); break;
            case 0x06e: fx_sub_r14(); break;
            case 0x06f: fx_sub_r15(); break;
            case 0x070: case 0x170: case 0x270: case 0x370: fx_merge(); break;
            case 0x071: fx_and_r1(); break;
            case 0x072: fx_and_r2(); break;
            case 0x073: fx_and_r3(); break;
            case 0x074: fx_and_r4(); break;
            case 0x075: fx_and_r5(); break;
            case 0x076: fx_and_r6(); break;
            case 0x077: fx_and_r7(); break;
            case 0x078: fx_and_r8(); break;
            case 0x079: fx_and_r9(); break;
            case 0x07a: fx_and_r10(); break;
            case 0x07b: fx_and_r11(); break;
            case 0x07c: fx_and_r12(); break;
            case 0x07d: fx_and_r13(); break;
            case 0x07e: fx_and_r14(); break;
            case 0x07f: fx_and_r15(); break;
            case 0x080: fx_mult_r0(); break;
            case 0x081: fx_mult_r1(); break;
            case 0x082: fx_mult_r2(); break;
            case 0x083: fx_mult_r3(); break;
            case 0x084: fx_mult_r4(); break;
            case 0x085: fx_mult_r5(); break;
            case 0x086: fx_mult_r6(); break;
            case 0x087: fx_mult_r7(); break;
            case 0x088: fx_mult_r8(); break;
            case 0x089: fx_mult_r9(); break;
            case 0x08a: fx_mult_r10(); break;
            case 0x08b: fx_mult_r11(); break;
            case 0x08c: fx_mult_r12(); break;
            case 0x08d: fx_mult_r13(); break;
            case 0x08e: fx_mult_r14(); break;
            case 0x08f: fx_mult_r15(); break;
            case 0x090: case 0x190: case 0x290: case 0x390: fx_sbk(); break;
            case 0x091: case 0x191: case 0x291: case 0x391: fx_link_i1(); break;
            case 0x092: case 0x192: case 0x292: case 0x392: fx_link_i2(); break;
            case 0x093: case 0x193: case 0x293: case 0x393: fx_link_i3(); break;
            case 0x094: case 0x194: case 0x294: case 0x394: fx_link_i4(); break;
            case 0x095: case 0x195: case 0x295: case 0x395: fx_sex(); break;
            case 0x096: case 0x296: fx_asr(); break;
            case 0x097: case 0x197: case 0x297: case 0x397: fx_ror(); break;
            case 0x098: case 0x298: fx_jmp_r8(); break;
            case 0x099: case 0x299: fx_jmp_r9(); break;
            case 0x09a: case 0x29a: fx_jmp_r10(); break;
            case 0x09b: case 0x29b: fx_jmp_r11(); break;
            case 0x09c: case 0x29c: fx_jmp_r12(); break;
            case 0x09d: case 0x29d: fx_jmp_r13(); break;
            case 0x09e: case 0x19e: case 0x29e: case 0x39e: fx_lob(); break;
            case 0x09f: case 0x29f: fx_fmult(); break;
            case 0x0a0: fx_ibt_r0(); break;
            case 0x0a1: fx_ibt_r1(); break;
            case 0x0a2: fx_ibt_r2(); break;
            case 0x0a3: fx_ibt_r3(); break;
            case 0x0a4: fx_ibt_r4(); break;
            case 0x0a5: fx_ibt_r5(); break;
            case 0x0a6: fx_ibt_r6(); break;
            case 0x0a7: fx_ibt_r7(); break;
            case 0x0a8: fx_ibt_r8(); break;
            case 0x0a9: fx_ibt_r9(); break;
            case 0x0aa: fx_ibt_r10(); break;
            case 0x0ab: fx_ibt_r11(); break;
            case 0x0ac: fx_ibt_r12(); break;
            case 0x0ad: fx_ibt_r13(); break;
            case 0x0ae: fx_ibt_r14(); break;
            case 0x0af: fx_ibt_r15(); break;
            case 0x0b0: case 0x1b0: case 0x2b0: case 0x3b0: fx_from_r0(); break;
            case 0x0b1: case 0x1b1: case 0x2b1: case 0x3b1: fx_from_r1(); break;
            case 0x0b2: case 0x1b2: case 0x2b2: case 0x3b2: fx_from_r2(); break;
            case 0x0b3: case 0x1b3: case 0x2b3: case 0x3b3: fx_from_r3(); break;
            case 0x0b4: case 0x1b4: case 0x2b4: case 0x3b4: fx_from_r4(); break;
            case 0x0b5: case 0x1b5: case 0x2b5: case 0x3b5: fx_from_r5(); break;
            case 0x0b6: case 0x1b6: case 0x2b6: case 0x3b6: fx_from_r6(); break;
            case 0x0b7: case 0x1b7: case 0x2b7: case 0x3b7: fx_from_r7(); break;
            case 0x0b8: case 0x1b8: case 0x2b8: case 0x3b8: fx_from_r8(); break;
            case 0x0b9: case 0x1b9: case 0x2b9: case 0x3b9: fx_from_r9(); break;
            case 0x0ba: case 0x1ba: case 0x2ba: case 0x3ba: fx_from_r10(); break;
            case 0x0bb: case 0x1bb: case 0x2bb: case 0x3bb: fx_from_r11(); break;
            case 0x0bc: case 0x1bc: case 0x2bc: case 0x3bc: fx_from_r12(); break;
            case 0x0bd: case 0x1bd: case 0x2bd: case 0x3bd: fx_from_r13(); break;
            case 0x0be: case 0x1be: case 0x2be: case 0x3be: fx_from_r14(); break;
            case 0x0bf: case 0x1bf: case 0x2bf: case 0x3bf: fx_from_r15(); break;
            case 0x0c0: case 0x1c0: case 0x2c0: case 0x3c0: fx_hib(); break;
            case 0x0c1: fx_or_r1(); break;
            case 0x0c2: fx_or_r2(); break;
            case 0x0c3: fx_or_r3(); break;
            case 0x0c4: fx_or_r4(); break;
            case 0x0c5: fx_or_r5(); break;
            case 0x0c6: fx_or_r6(); break;
            case 0x0c7: fx_or_r7(); break;
            case 0x0c8: fx_or_r8(); break;
            case 0x0c9: fx_or_r9(); break;
            case 0x0ca: fx_or_r10(); break;
            case 0x0cb: fx_or_r11(); break;
            case 0x0cc: fx_or_r12(); break;
            case 0x0cd: fx_or_r13(); break;
            case 0x0ce: fx_or_r14(); break;
            case 0x0cf: fx_or_r15(); break;
            case 0x0d0: case 0x1d0: case 0x2d0: case 0x3d0: fx_inc_r0(); break;
            case 0x0d1: case 0x1d1: case 0x2d1: case 0x3d1: fx_inc_r1(); break;
            case 0x0d2: case 0x1d2: case 0x2d2: case 0x3d2: fx_inc_r2(); break;
            case 0x0d3: case 0x1d3: case 0x2d3: case 0x3d3: fx_inc_r3(); break;
            case 0x0d4: case 0x1d4: case 0x2d4: case 0x3d4: fx_inc_r4(); break;
            case 0x0d5: case 0x1d5: case 0x2d5: case 0x3d5: fx_inc_r5(); break;
            case 0x0d6: case 0x1d6: case 0x2d6: case 0x3d6: fx_inc_r6(); break;
            case 0x0d7: case 0x1d7: case 0x2d7: case 0x3d7: fx_inc_r7(); break;
            case 0x0d8: case 0x1d8: case 0x2d8: case 0x3d8: fx_inc_r8(); break;
            case 0x0d9: case 0x1d9: case 0x2d9: case 0x3d9: fx_inc_r9(); break;
            case 0x0da: case 0x1da: case 0x2da: case 0x3da: fx_inc_r10(); break;
            case 0x0db: case 0x1db: case 0x2db: case 0x3db: fx_inc_r11(); break;
            case 0x0dc: case 0x1dc: case 0x2dc: case 0x3dc: fx_inc_r12(); break;
            case 0x0dd: case 0x1dd: case 0x2dd: case 0x3dd: fx_inc_r13(); break;
            case 0x0de: case 0x1de: case 0x2de: case 0x3de: fx_inc_r14(); break;
            case 0x0df: case 0x1df: fx_getc(); break;
            case 0x0e0: case 0x1e0: case 0x2e0: case 0x3e0: fx_dec_r0(); break;
            case 0x0e1: case 0x1e1: case 0x2e1: case 0x3e1: fx_dec_r1(); break;
            case 0x0e2: case 0x1e2: case 0x2e2: case 0x3e2: fx_dec_r2(); break;
            case 0x0e3: case 0x1e3: case 0x2e3: case 0x3e3: fx_dec_r3(); break;
            case 0x0e4: case 0x1e4: case 0x2e4: case 0x3e4: fx_dec_r4(); break;
            case 0x0e5: case 0x1e5: case 0x2e5: case 0x3e5: fx_dec_r5(); break;
            case 0x0e6: case 0x1e6: case 0x2e6: case 0x3e6: fx_dec_r6(); break;
            case 0x0e7: case 0x1e7: case 0x2e7: case 0x3e7: fx_dec_r7(); break;
            case 0x0e8: case 0x1e8: case 0x2e8: case 0x3e8: fx_dec_r8(); break;
            case 0x0e9: case 0x1e9: case 0x2e9: case 0x3e9: fx_dec_r9(); break;
            case 0x0ea: case 0x1ea: case 0x2ea: case 0x3ea: fx_dec_r10(); break;
            case 0x0eb: case 0x1eb: case 0x2eb: case 0x3eb: fx_dec_r11(); break;
            case 0x0ec: case 0x1ec: case 0x2ec: case 0x3ec: fx_dec_r12(); break;
            case 0x0ed: case 0x1ed: case 0x2ed: case 0x3ed: fx_dec_r13(); break;
            case 0x0ee: case 0x1ee: case 0x2ee: case 0x3ee: fx_dec_r14(); break;
            case 0x0ef: fx_getb(); break;
            case 0x0f0: fx_iwt_r0(); break;
            case 0x0f1: fx_iwt_r1(); break;
            case 0x0f2: fx_iwt_r2(); break;
            case 0x0f3: fx_iwt_r3(); break;
            case 0x0f4: fx_iwt_r4(); break;
            case 0x0f5: fx_iwt_r5(); break;
            case 0x0f6: fx_iwt_r6(); break;
            case 0x0f7: fx_iwt_r7(); break;
            case 0x0f8: fx_iwt_r8(); break;
            case 0x0f9: fx_iwt_r9(); break;
            case 0x0fa: fx_iwt_r10(); break;
            case 0x0fb: fx_iwt_r11(); break;
            case 0x0fc: fx_iwt_r12(); break;
            case 0x0fd: fx_iwt_r13(); break;
            case 0x0fe: fx_iwt_r14(); break;
            case 0x0ff: fx_iwt_r15(); break;
            case 0x130: case 0x330: fx_stb_r0(); break;
            case 0x131: case 0x331: fx_stb_r1(); break;
            case 0x132: case 0x332: fx_stb_r2(); break;
            case 0x133: case 0x333: fx_stb_r3(); break;
            case 0x134: case 0x334: fx_stb_r4(); break;
            case 0x135: case 0x335: fx_stb_r5(); break;
            case 0x136: case 0x336: fx_stb_r6(); break;
            case 0x137: case 0x337: fx_stb_r7(); break;
            case 0x138: case 0x338: fx_stb_r8(); break;
            case 0x139: case 0x339: fx_stb_r9(); break;
            case 0x13a: case 0x33a: fx_stb_r10(); break;
            case 0x13b: case 0x33b: fx_stb_r11(); break;
            case 0x140: case 0x340: fx_ldb_r0(); break;
            case 0x141: case 0x341: fx_ldb_r1(); break;
            case 0x142: case 0x342: fx_ldb_r2(); break;
            case 0x143: case 0x343: fx_ldb_r3(); break;
            case 0x144: case 0x344: fx_ldb_r4(); break;
            case 0x145: case 0x345: fx_ldb_r5(); break;
            case 0x146: case 0x346: fx_ldb_r6(); break;
            case 0x147: case 0x347: fx_ldb_r7(); break;
            case 0x148: case 0x348: fx_ldb_r8(); break;
            case 0x149: case 0x349: fx_ldb_r9(); break;
            case 0x14a: case 0x34a: fx_ldb_r10(); break;
            case 0x14b: case 0x34b: fx_ldb_r11(); break;
            case 0x14c: case 0x34c: GSU.pfRpix(); break;
            case 0x14e: case 0x34e: fx_cmode(); break;
            case 0x150: fx_adc_r0(); break;
            case 0x151: fx_adc_r1(); break;
            case 0x152: fx_adc_r2(); break;
            case 0x153: fx_adc_r3(); break;
            case 0x154: fx_adc_r4(); break;
            case 0x155: fx_adc_r5(); break;
            case 0x156: fx_adc_r6(); break;
            case 0x157: fx_adc_r7(); break;
            case 0x158: fx_adc_r8(); break;
            case 0x159: fx_adc_r9(); break;
            case 0x15a: fx_adc_r10(); break;
            case 0x15b: fx_adc_r11(); break;
            case 0x15c: fx_adc_r12(); break;
            case 0x15d: fx_adc_r13(); break;
            case 0x15e: fx_adc_r14(); break;
            case 0x15f: fx_adc_r15(); break;
            case 0x160: fx_sbc_r0(); break;
            case 0x161: fx_sbc_r1(); break;
            case 0x162: fx_sbc_r2(); break;
            case 0x163: fx_sbc_r3(); break;
            case 0x164: fx_sbc_r4(); break;
            case 0x165: fx_sbc_r5(); break;
            case 0x166: fx_sbc_r6(); break;
            case 0x167: fx_sbc_r7(); break;
            case 0x168: fx_sbc_r8(); break;
            case 0x169: fx_sbc_r9(); break;
            case 0x16a: fx_sbc_r10(); break;
            case 0x16b: fx_sbc_r11(); break;
            case 0x16c: fx_sbc_r12(); break;
            case 0x16d: fx_sbc_r13(); break;
            case 0x16e: fx_sbc_r14(); break;
            case 0x16f: fx_sbc_r15(); break;
            case 0x171: fx_bic_r1(); break;
            case 0x172: fx_bic_r2(); break;
            case 0x173: fx_bic_r3(); break;
            case 0x174: fx_bic_r4(); break;
            case 0x175: fx_bic_r5(); break;
            case 0x176: fx_bic_r6(); break;
            case 0x177: fx_bic_r7(); break;
            case 0x178: fx_bic_r8(); break;
            case 0x179: fx_bic_r9(); break;
            case 0x17a: fx_bic_r10(); break;
            case 0x17b: fx_bic_r11(); break;
            case 0x17c: fx_bic_r12(); break;
            case 0x17d: fx_bic_r13(); break;
            case 0x17e: fx_bic_r14(); break;
            case 0x17f: fx_bic_r15(); break;
            case 0x180: fx_umult_r0(); break;
            case 0x181: fx_umult_r1(); break;
            case 0x182: fx_umult_r2(); break;
            case 0x183: fx_umult_r3(); break;
            case 0x184: fx_umult_r4(); break;
            case 0x185: fx_umult_r5(); break;
            case 0x186: fx_umult_r6(); break;
            case 0x187: fx_umult_r7(); break;
            case 0x188: fx_umult_r8(); break;
            case 0x189: fx_umult_r9(); break;
            case 0x18a: fx_umult_r10(); break;
            case 0x18b: fx_umult_r11(); break;
            case 0x18c: fx_umult_r12(); break;
            case 0x18d: fx_umult_r13(); break;
            case 0x18e: fx_umult_r14(); break;
            case 0x18f: fx_umult_r15(); break;
            case 0x196: case 0x396: fx_div2(); break;
            case 0x198: case 0x398: fx_ljmp_r8(); break;
            case 0x199: case 0x399: fx_ljmp_r9(); break;
            case 0x19a: case 0x39a: fx_ljmp_r10(); break;
            case 0x19b: case 0x39b: fx_ljmp_r11(); break;
            case 0x19c: case 0x39c: fx_ljmp_r12(); break;
            case 0x19d: case 0x39d: fx_ljmp_r13(); break;
            case 0x19f: case 0x39f: fx_lmult(); break;
            case 0x1a0: case 0x3a0: fx_lms_r0(); break;
            case 0x1a1: case 0x3a1: fx_lms_r1(); break;
            case 0x1a2: case 0x3a2: fx_lms_r2(); break;
            case 0x1a3: case 0x3a3: fx_lms_r3(); break;
            case 0x1a4: case 0x3a4: fx_lms_r4(); break;
            case 0x1a5: case 0x3a5: fx_lms_r5(); break;
            case 0x1a6: case 0x3a6: fx_lms_r6(); break;
            case 0x1a7: case 0x3a7: fx_lms_r7(); break;
            case 0x1a8: case 0x3a8: fx_lms_r8(); break;
            case 0x1a9: case 0x3a9: fx_lms_r9(); break;
            case 0x1aa: case 0x3aa: fx_lms_r10(); break;
            case 0x1ab: case 0x3ab: fx_lms_r11(); break;
            case 0x1ac: case 0x3ac: fx_lms_r12(); break;
            case 0x1ad: case 0x3ad: fx_lms_r13(); break;
            case 0x1ae: case 0x3ae: fx_lms_r14(); break;
            case 0x1af: case 0x3af: fx_lms_r15(); break;
            case 0x1c1: fx_xor_r1(); break;
            case 0x1c2: fx_xor_r2(); break;
            case 0x1c3: fx_xor_r3(); break;
            case 0x1c4: fx_xor_r4(); break;
            case 0x1c5: fx_xor_r5(); break;
            case 0x1c6: fx_xor_r6(); break;
            case 0x1c7: fx_xor_r7(); break;
            case 0x1c8: fx_xor_r8(); break;
            case 0x1c9: fx_xor_r9(); break;
            case 0x1ca: fx_xor_r10(); break;
            case 0x1cb: fx_xor_r11(); break;
            case 0x1cc: fx_xor_r12(); break;
            case 0x1cd: fx_xor_r13(); break;
            case 0x1ce: fx_xor_r14(); break;
            case 0x1cf: fx_xor_r15(); break;
            case 0x1ef: fx_getbh(); break;
            case 0x1f0: case 0x3f0: fx_lm_r0(); break;
            case 0x1f1: case 0x3f1: fx_lm_r1(); break;
            case 0x1f2: case 0x3f2: fx_lm_r2(); break;
            case 0x1f3: case 0x3f3: fx_lm_r3(); break;
            case 0x1f4: case 0x3f4: fx_lm_r4(); break;
            case 0x1f5: case 0x3f5: fx_lm_r5(); break;
            case 0x1f6: case 0x3f6: fx_lm_r6(); break;
            case 0x1f7: case 0x3f7: fx_lm_r7(); break;
            case 0x1f8: case 0x3f8: fx_lm_r8(); break;
            case 0x1f9: case 0x3f9: fx_lm_r9(); break;
            case 0x1fa: case 0x3fa: fx_lm_r10(); break;
            case 0x1fb: case 0x3fb: fx_lm_r11(); break;
            case 0x1fc: case 0x3fc: fx_lm_r12(); break;
            case 0x1fd: case 0x3fd: fx_lm_r13(); break;
            case 0x1fe: case 0x3fe: fx_lm_r14(); break;
            case 0x1ff: case 0x3ff: fx_lm_r15(); break;
            case 0x250: fx_add_i0(); break;
            case 0x251: fx_add_i1(); break;
            case 0x252: fx_add_i2(); break;
            case 0x253: fx_add_i3(); break;
            case 0x254: fx_add_i4(); break;
            case 0x255: fx_add_i5(); break;
            case 0x256: fx_add_i6(); break;
            case 0x257: fx_add_i7(); break;
            case 0x258: fx_add_i8(); break;
            case 0x259: fx_add_i9(); break;
            case 0x25a: fx_add_i10(); break;
            case 0x25b: fx_add_i11(); break;
            case 0x25c: fx_add_i12(); break;
            case 0x25d: fx_add_i13(); break;
            case 0x25e: fx_add_i14(); break;
            case 0x25f: fx_add_i15(); break;
            case 0x260: fx_sub_i0(); break;
            case 0x261: fx_sub_i1(); break;
            case 0x262: fx_sub_i2(); break;
            case 0x263: fx_sub_i3(); break;
            case 0x264: fx_sub_i4(); break;
            case 0x265: fx_sub_i5(); break;
            case 0x266: fx_sub_i6(); break;
            case 0x267: fx_sub_i7(); break;
            case 0x268: fx_sub_i8(); break;
            case 0x269: fx_sub_i9(); break;
            case 0x26a: fx_sub_i10(); break;
            case 0x26b: fx_sub_i11(); break;
            case 0x26c: fx_sub_i12(); break;
            case 0x26d: fx_sub_i13(); break;
            case 0x26e: fx_sub_i14(); break;
            case 0x26f: fx_sub_i15(); break;
            case 0x271: fx_and_i1(); break;
            case 0x272: fx_and_i2(); break;
            case 0x273: fx_and_i3(); break;
            case 0x274: fx_and_i4(); break;
            case 0x275: fx_and_i5(); break;
            case 0x276: fx_and_i6(); break;
            case 0x277: fx_and_i7(); break;
            case 0x278: fx_and_i8(); break;
            case 0x279: fx_and_i9(); break;
            case 0x27a: fx_and_i10(); break;
            case 0x27b: fx_and_i11(); break;
            case 0x27c: fx_and_i12(); break;
            case 0x27d: fx_and_i13(); break;
            case 0x27e: fx_and_i14(); break;
            case 0x27f: fx_and_i15(); break;
            case 0x280: fx_mult_i0(); break;
            case 0x281: fx_mult_i1(); break;
            case 0x282: fx_mult_i2(); break;
            case 0x283: fx_mult_i3(); break;
            case 0x284: fx_mult_i4(); break;
            case 0x285: fx_mult_i5(); break;
            case 0x286: fx_mult_i6(); break;
            case 0x287: fx_mult_i7(); break;
            case 0x288: fx_mult_i8(); break;
            case 0x289: fx_mult_i9(); break;
            case 0x28a: fx_mult_i10(); break;
            case 0x28b: fx_mult_i11(); break;
            case 0x28c: fx_mult_i12(); break;
            case 0x28d: fx_mult_i13(); break;
            case 0x28e: fx_mult_i14(); break;
            case 0x28f: fx_mult_i15(); break;
            case 0x2a0: fx_sms_r0(); break;
            case 0x2a1: fx_sms_r1(); break;
            case 0x2a2: fx_sms_r2(); break;
            case 0x2a3: fx_sms_r3(); break;
            case 0x2a4: fx_sms_r4(); break;
            case 0x2a5: fx_sms_r5(); break;
            case 0x2a6: fx_sms_r6(); break;
            case 0x2a7: fx_sms_r7(); break;
            case 0x2a8: fx_sms_r8(); break;
            case 0x2a9: fx_sms_r9(); break;
            case 0x2aa: fx_sms_r10(); break;
            case 0x2ab: fx_sms_r11(); break;
            case 0x2ac: fx_sms_r12(); break;
            case 0x2ad: fx_sms_r13(); break;
            case 0x2ae: fx_sms_r14(); break;
            case 0x2af: fx_sms_r15(); break;
            case 0x2c1: fx_or_i1(); break;
            case 0x2c2: fx_or_i2(); break;
            case 0x2c3: fx_or_i3(); break;
            case 0x2c4: fx_or_i4(); break;
            case 0x2c5: fx_or_i5(); break;
            case 0x2c6: fx_or_i6(); break;
            case 0x2c7: fx_or_i7(); break;
            case 0x2c8: fx_or_i8(); break;
            case 0x2c9: fx_or_i9(); break;
            case 0x2ca: fx_or_i10(); break;
            case 0x2cb: fx_or_i11(); break;
            case 0x2cc: fx_or_i12(); break;
            case 0x2cd: fx_or_i13(); break;
            case 0x2ce: fx_or_i14(); break;
            case 0x2cf: fx_or_i15(); break;
            case 0x2df: fx_ramb(); break;
            case 0x2ef: fx_getbl(); break;
            case 0x2f0: fx_sm_r0(); break;
            case 0x2f1: fx_sm_r1(); break;
            case 0x2f2: fx_sm_r2(); break;
            case 0x2f3: fx_sm_r3(); break;
            case 0x2f4: fx_sm_r4(); break;
            case 0x2f5: fx_sm_r5(); break;
            case 0x2f6: fx_sm_r6(); break;
            case 0x2f7: fx_sm_r7(); break;
            case 0x2f8: fx_sm_r8(); break;
            case 0x2f9: fx_sm_r9(); break;
            case 0x2fa: fx_sm_r10(); break;
            case 0x2fb: fx_sm_r11(); break;
            case 0x2fc: fx_sm_r12(); break;
            case 0x2fd: fx_sm_r13(); break;
            case 0x2fe: fx_sm_r14(); break;
            case 0x2ff: fx_sm_r15(); break;
            case 0x350: fx_adc_i0(); break;
            case 0x351: fx_adc_i1(); break;
            case 0x352: fx_adc_i2(); break;
            case 0x353: fx_adc_i3(); break;
            case 0x354: fx_adc_i4(); break;
            case 0x355: fx_adc_i5(); break;
            case 0x356: fx_adc_i6(); break;
            case 0x357: fx_adc_i7(); break;
            case 0x358: fx_adc_i8(); break;
            case 0x359: fx_adc_i9(); break;
            case 0x35a: fx_adc_i10(); break;
            case 0x35b: fx_adc_i11(); break;
            case 0x35c: fx_adc_i12(); break;
            case 0x35d: fx_adc_i13(); break;
            case 0x35e: fx_adc_i14(); break;
            case 0x35f: fx_adc_i15(); break;
            case 0x360: fx_cmp_r0(); break;
            case 0x361: fx_cmp_r1(); break;
            case 0x362: fx_cmp_r2(); break;
            case 0x363: fx_cmp_r3(); break;
            case 0x364: fx_cmp_r4(); break;
            case 0x365: fx_cmp_r5(); break;
            case 0x366: fx_cmp_r6(); break;
            case 0x367: fx_cmp_r7(); break;
            case 0x368: fx_cmp_r8(); break;
            case 0x369: fx_cmp_r9(); break;
            case 0x36a: fx_cmp_r10(); break;
            case 0x36b: fx_cmp_r11(); break;
            case 0x36c: fx_cmp_r12(); break;
            case 0x36d: fx_cmp_r13(); break;
            case 0x36e: fx_cmp_r14(); break;
            case 0x36f: fx_cmp_r15(); break;
            case 0x371: fx_bic_i1(); break;
            case 0x372: fx_bic_i2(); break;
            case 0x373: fx_bic_i3(); break;
            case 0x374: fx_bic_i4(); break;
            case 0x375: fx_bic_i5(); break;
            case 0x376: fx_bic_i6(); break;
            case 0x377: fx_bic_i7(); break;
            case 0x378: fx_bic_i8(); break;
            case 0x379: fx_bic_i9(); break;
            case 0x37a: fx_bic_i10(); break;
            case 0x37b: fx_bic_i11(); break;
            case 0x37c: fx_bic_i12(); break;
            case 0x37d: fx_bic_i13(); break;
            case 0x37e: fx_bic_i14(); break;
            case 0x37f: fx_bic_i15(); break;
            case 0x380: fx_umult_i0(); break;
            case 0x381: fx_umult_i1(); break;
            case 0x382: fx_umult_i2(); break;
            case 0x383: fx_umult_i3(); break;
            case 0x384: fx_umult_i4(); break;
            case 0x385: fx_umult_i5(); break;
            case 0x386: fx_umult_i6(); break;
            case 0x387: fx_umult_i7(); break;
            case 0x388: fx_umult_i8(); break;
            case 0x389: fx_umult_i9(); break;
            case 0x38a: fx_umult_i10(); break;
            case 0x38b: fx_umult_i11(); break;
            case 0x38c: fx_umult_i12(); break;
            case 0x38d: fx_umult_i13(); break;
            case 0x38e: fx_umult_i14(); break;
            case 0x38f: fx_umult_i15(); break;
            case 0x3c1: fx_xor_i1(); break;
            case 0x3c2: fx_xor_i2(); break;
            case 0x3c3: fx_xor_i3(); break;
            case 0x3c4: fx_xor_i4(); break;
            case 0x3c5: fx_xor_i5(); break;
            case 0x3c6: fx_xor_i6(); break;
            case 0x3c7: fx_xor_i7(); break;
            case 0x3c8: fx_xor_i8(); break;
            case 0x3c9: fx_xor_i9(); break;
            case 0x3ca: fx_xor_i10(); break;
            case 0x3cb: fx_xor_i11(); break;
            case 0x3cc: fx_xor_i12(); break;
            case 0x3cd: fx_xor_i13(); break;
            case 0x3ce: fx_xor_i14(); break;
            case 0x3cf: fx_xor_i15(); break;
            case 0x3df: fx_romb(); break;
            case 0x3ef: fx_getbs(); break;
		}
	}

    loop_end:

 /*
#ifndef FX_ADDRESS_CHECK
    GSU.vPipeAdr = USEX16(R15-1) | (USEX8(GSU.vPrgBankReg)<<16);
#endif
*/
    return (nInstructions - GSU.vInstCount);
}

static uint32 fx_run_to_breakpoint(uint32 nInstructions)
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

static uint32 fx_step_over(uint32 nInstructions)
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

/*** Special table for the different plot configurations ***/

#ifdef FX_PLOT_TABLE
void (*FX_PLOT_TABLE[])() =
#else
void (*fx_apfPlotTable[])() =
#endif
{
    &fx_plot_2bit,    &fx_plot_4bit,	&fx_plot_4bit,	&fx_plot_8bit,	&fx_plot_obj,
    &fx_rpix_2bit,    &fx_rpix_4bit,    &fx_rpix_4bit,	&fx_rpix_8bit,	&fx_rpix_obj,
};
