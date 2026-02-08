#include "3dsopt.h"

#include <3ds.h>
#include <stdio.h>

#ifndef RELEASE

T3DS_Clock t3dsClocks[T3DS_NUM_CLOCKS];
static uint64_t totalTime = 1;
static uint64_t totalCount = 1;


void t3dsCount(int bucket, char *clockName)
{
    T3DS_Clock* clock = &t3dsClocks[bucket];
    clock->startTick = -1;
    clock->name = clockName;
    clock->count++;
}

void t3dsStartTiming(int bucket, char *clockName)
{
    t3dsClocks[bucket].startTick = svcGetSystemTick();
    t3dsClocks[bucket].name = clockName;
}

void t3dsEndTiming(int bucket)
{
    T3DS_Clock* clock = &t3dsClocks[bucket];
    clock->totalTicks += (svcGetSystemTick() - clock->startTick);
    clock->count++;
}

void t3dsResetTimings(void)
{
    totalTime = 1;
    totalCount = 1;
	for (int i = 0; i < T3DS_NUM_CLOCKS; i++)
    {
        T3DS_Clock* clock = &t3dsClocks[i];
        clock->totalTicks = 0; 
        clock->count = 0;
        clock->name = "";
    }
}

static inline int t3dsCalculatePercentage(T3DS_Clock* clock)
{
    uint64_t percentage = (clock->totalTicks * 1000) / totalTime; 
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
        char timePrintBuf[6];
        snprintf(timePrintBuf, sizeof(timePrintBuf), "%lf", clock->totalTicks / ((double) CPU_TICKS_PER_MSEC * totalCount));
        printf ("%-20s:%3d%% %sms %d\n", clock->name, t3dsCalculatePercentage(clock), timePrintBuf, clock->count);
        // printf ("%-20s: %3d%% %4dms %d\n", clock->name, t3dsCalculatePercentage(clock), (int)(clock->totalTicks / (uint64_t)CPU_TICKS_PER_MSEC), clock->count);
    }
    else if (clock->startTick == -1 && clock->count > 0)
    {
        printf ("%-20s:        %d\n", clock->name, clock->count);
    }
}

void t3dsSetTotalForPercentage(uint64_t time)
{
    if (time != 0)
        totalTime = time;
    else
        time = 1;
}

void t3dsSetCountForPercentage(uint64_t count)
{
    if (count != 0)
        totalCount = count;
    else
        count = 1;
}

#endif // RELEASE
