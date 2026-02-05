#include "3dsopt.h"
#include "3dssnes9x.h"

#ifndef RELEASE

T3DS_Clock t3dsClocks[T3DS_NUM_CLOCKS];
static u64 totalTime = 1;

void t3dsResetTimings(void)
{
    totalTime = 1;
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

static inline int t3dsCalculatePercentage(T3DS_Clock* clock)
{
    u64 percentage = (clock->totalTicks * 1000) / totalTime; 
    int percentageRemainder = percentage % 10;
    percentage /= 10;

    // Round with a precision of 1 decimal place
    if (percentageRemainder >= 5)
        percentage++;
    
    return percentage;
}

// These are TOTAL timings, cumulative of all frames since the clocks were last reset.
void t3dsShowTotalTiming(int bucket)
{
    T3DS_Clock* clock = &t3dsClocks[bucket];

    if (clock->totalTicks > 0)
    {
        printf ("%-20s: %3d%% %4dms %d\n", clock->name, t3dsCalculatePercentage(clock), (int)(clock->totalTicks / (u64)CPU_TICKS_PER_MSEC), clock->count);
    }
    else if (clock->startTick == -1 && clock->count > 0)
    {
        printf ("%-20s: %d\n", clock->name, clock->count);
    }
}

void t3dsSetTotalForPercentage(u64 time)
{
    if (time != 0)
        totalTime = time;
    else
        time = 1;
}

#endif // RELEASE
