#include <stdio.h>
#include <string.h>

#include "3dslog.h"
#include "3dstimer.h"

T3dsTimer t3dsTimers[TIMER_COUNT];
ProfilingMode t3dsProfilingMode;
#ifndef PROFILING_DISABLED
static const bool writeToLogFile = false;
#endif

TimerConfig TimerConfigs[TIMER_COUNT] = {
    [TIMER_S9X_MAIN_LOOP]       = { "S9xMainLoop     ", true },
    [TIMER_S9X_SUPER_FX]        = { "S9xSuperFX      ", true },
    [TIMER_S9X_UPDATE_SCREEN]   = { "S9xUpdateScreen ", true },
    [TIMER_DRAW]                = { "gpu3dsDraw      ", true },
    [TIMER_DRAW_M7_TEXTURE]     = { "draw M7 texture ", true },
    [TIMER_DRAW_SNES_SCREEN]    = { "draw SNES screen", true },
    [TIMER_DRAW_SCENE]          = { "draw scene      ", true },
    [TIMER_GPU_WAIT]            = { "gpuWait         ", true },
    [TIMER_FLUSH]               = { "flush           ", true },
    [TIMER_SKIPPED_FRAMES]      = { "skipped frames  ", true },
    [TIMER_DRAWN_FRAMES]        = { "drawn frames    ", true },
    [TIMER_RUN_ONE_FRAME]       = { "runOneFrame     ", true }
};

static const TimerBucket coreTimers[] = {
    TIMER_S9X_MAIN_LOOP,
    TIMER_S9X_SUPER_FX,
    TIMER_S9X_UPDATE_SCREEN,
    TIMER_SKIPPED_FRAMES,
    TIMER_DRAWN_FRAMES,
};

double t3dsTicksToMs(u64 ticks) {
    return (double)ticks / (SYSCLOCK_ARM11 / 1000.0);
}

void t3dsResetTimers() {
    #ifndef PROFILING_DISABLED
        for (int i = 0; i < TIMER_COUNT; ++i) {
            t3dsTimers[i].calls = 0;
            t3dsTimers[i].totalTicks = 0;
            t3dsTimers[i].startTick = 0;
            t3dsTimers[i].name = TimerConfigs[i].name;
            t3dsTimers[i].isEnabled = false;
        }

        switch (t3dsProfilingMode) {
            case PROFILING_ALL:
                for (int i = 0; i < TIMER_COUNT; ++i)
                    t3dsTimers[i].isEnabled = TimerConfigs[i].isEnabled;
                break;
            case PROFILING_CORE:
                for (int i = 0; i < (int)(sizeof(coreTimers) / sizeof(coreTimers[0])); ++i)
                    t3dsTimers[coreTimers[i]].isEnabled = TimerConfigs[coreTimers[i]].isEnabled;
                break;
            default: break;
        }
    #endif
}

void t3dsPrintTimer(TimerBucket bucket, int totalFrames) {
    #ifndef PROFILING_DISABLED
        if (bucket >= TIMER_COUNT || !t3dsTimers[bucket].isEnabled) return;

        char logBuffer[256];

        if (t3dsTimers[bucket].calls == 0)
        {
            snprintf(logBuffer, sizeof(logBuffer), "%s: calls:0 ", t3dsTimers[bucket].name);
        }
        else
        {
            if (totalFrames <= 0) totalFrames = 1;

            int calls = t3dsTimers[bucket].calls;
            double totalMs = t3dsTicksToMs(t3dsTimers[bucket].totalTicks);
            double avg = totalMs / calls;
            double msPerFrame = totalMs / totalFrames;

            if (bucket == TIMER_RUN_ONE_FRAME) {
                // paceFrame() is called after t3dsStopTimer(TIMER_RUN_ONE_FRAME)
                // so TIMER_RUN_ONE_FRAME represents the max potential fps here
                snprintf(logBuffer, sizeof(logBuffer),
                    "%s: %.2fmaxfps, %.3fms",
                    t3dsTimers[bucket].name, 1000.0 / avg, avg);
            } else if (totalMs == 0) {
                snprintf(logBuffer, sizeof(logBuffer),
                    "%s: calls:%d",
                    t3dsTimers[bucket].name, calls);
            } else {
                snprintf(logBuffer, sizeof(logBuffer),
                    "%s: %.2fms/f calls:%d",
                    t3dsTimers[bucket].name, msPerFrame, calls);
            }
        }

        if (writeToLogFile)
            log3dsWrite("%s", logBuffer);
        else
            printf("%s\n", logBuffer);
    #endif
}

void t3dsPrintTimers(int totalFrames) {
    #ifndef PROFILING_DISABLED
        printf("\n");
        for (int i = 0; i < TIMER_COUNT; ++i) {
            t3dsPrintTimer((TimerBucket)i, totalFrames);
        }
    #endif
}
