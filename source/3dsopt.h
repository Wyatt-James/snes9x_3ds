
#ifndef _3DSOPT_H_
#define _3DSOPT_H_

#include <3ds.h>

#include "snes9x.h"
#include "port.h"
#include "memmap.h"
#include "3dssnes9x.h"

typedef struct
{
    char *name;
    int count;
    u64 startTick, totalTick;
} T3DS_Clock;

#ifndef RELEASE

#define T3DS_NUM_CLOCKS 100
extern T3DS_Clock t3dsClocks[T3DS_NUM_CLOCKS];

void t3dsResetTimings(void);
void t3dsCount(int bucket, char *name);
void t3dsShowTotalTiming(int bucket);

static inline void t3dsStartTiming(int bucket, char *clockName)
{
    t3dsClocks[bucket].startTick = svcGetSystemTick();
    t3dsClocks[bucket].name = clockName;
}

static inline void t3dsEndTiming(int bucket)
{
    T3DS_Clock* clock = &t3dsClocks[bucket];
    clock->totalTick += (svcGetSystemTick() - clock->startTick);
    clock->count++;
}

#else // RELEASE
#define T3DS_NUM_CLOCKS 0
static inline void t3dsResetTimings(void)                       {} // Stub
static inline void t3dsCount(int bucket, char *name)            {} // Stub
static inline void t3dsShowTotalTiming(int bucket)              {} // Stub
static inline void t3dsStartTiming(int bucket, char *clockName) {} // Stub
static inline void t3dsEndTiming(int bucket)                    {} // Stub
#endif // RELEASE

#endif
