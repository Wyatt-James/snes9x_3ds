#ifndef _3DSOPT_H_
#define _3DSOPT_H_

#include <stdint.h>

/*
 * Currently used clocks:
 * 1  - aptMainLoop (total)
 * 2  - SuperFX
 * 3  - CopyFB
 * 4  - Flush
 * 5  - Transfer
 * 6  - vMode SMC Swaps
 * 
 * 11 - S9xUpdateScreen
 * 
 * 20 - Read 214x (disabled)
 * 21 - DrawBG0, APU_EXECUTE (disabled), Write 214x (disabled)
 * 22 - DrawBG1
 * 23 - DrawBG2
 * 24 - DrawBG3
 * 25 - DrawBKClr
 * 26 - DrawOBJS
 * 27 - DrawBG0_M7
 * 28 - S9xSetupOBJ
 * 29 - Colormath
 * 30 - DrawWindowStencils, ComputeClipWindows (disabled)
 * 31 - RenderScnHW
 * 
 *  Audio Mixer (CPU1)
 * 41 - Mix-Timing
 * 42 - Mix-ApplyMstVol
 * 43 - Mix-Flush
 * 44 - Mix-Replay+S9xMix
 * 
 * 51 - APU
 * 70 - PrepM7
 * 71 - PrepM7-Palette
 * 72 - PrepM7-FullTile
 * 73 - PrepM7-CharFlag
*/

typedef struct
{
    char *name;
    int count;
    uint64_t startTick, totalTicks;
} T3DS_Clock;

#ifndef RELEASE

#define T3DS_NUM_CLOCKS 100
extern T3DS_Clock t3dsClocks[T3DS_NUM_CLOCKS];

void t3dsResetTimings(void);
void t3dsShowTotalTiming(int bucket);
void t3dsSetTotalForPercentage(uint64_t time);
void t3dsSetCountForPercentage(uint64_t count);
void t3dsCount(int bucket, char *clockName);
void t3dsStartTiming(int bucket, char *clockName);
void t3dsEndTiming(int bucket);

static inline uint64_t t3dsGetTime(int bucket) {return t3dsClocks[bucket].totalTicks;}
static inline uint64_t t3dsGetCount(int bucket) {return t3dsClocks[bucket].count;}

#else // RELEASE
#define T3DS_NUM_CLOCKS 0
static inline void t3dsResetTimings(void)                       {} // Stub
static inline void t3dsCount(int bucket, char *name)            {} // Stub
static inline void t3dsShowTotalTiming(int bucket)              {} // Stub
static inline void t3dsStartTiming(int bucket, char *clockName) {} // Stub
static inline void t3dsEndTiming(int bucket)                    {} // Stub
static inline void t3dsSetTotalForPercentage(uint64_t time)     {} // Stub
static inline uint64_t t3dsGetTime(int bucket)                  {return 0;} // Stub
static inline uint64_t t3dsGetCount(int bucket)                 {return 0;} // Stub
#endif // RELEASE

#endif
