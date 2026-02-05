#include "3dsopt.h"
#include "3dssnes9x.h"

#ifndef RELEASE

T3DS_Clock t3dsClocks[T3DS_NUM_CLOCKS];

void t3dsResetTimings(void)
{
	for (int i = 0; i < T3DS_NUM_CLOCKS; i++)
    {
        T3DS_Clock* clock = &t3dsClocks[i];
        clock->totalTicks = 0; 
        clock->count = 0;
        clock->name = "";
    }
}

void t3dsCount(int bucket, char *clockName)
{
    T3DS_Clock* clock = &t3dsClocks[bucket];
    clock->startTick = -1;
    clock->name = clockName;
    clock->count++;
}

// These are TOTAL timings, cumulative of all frames since the clocks were last reset.
void t3dsShowTotalTiming(int bucket)
{
    T3DS_Clock* clock = &t3dsClocks[bucket];

    if (clock->totalTicks > 0)
    {
        printf ("%-20s: %2d %4dms %d\n", clock->name, bucket, (int)(clock->totalTicks / (u64)CPU_TICKS_PER_MSEC), clock->count);
    }
    else if (clock->startTick == -1 && clock->count > 0)
    {
        printf ("%-20s: %2d %d\n", clock->name, bucket, clock->count);
    }
}

#endif // RELEASE
