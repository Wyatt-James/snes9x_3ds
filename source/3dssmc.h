#pragma once

/*
 * Utilities for self-modifying code
 */

#include <stdbool.h>
#include <stddef.h>
#include "macros.h"

#define SMC_SOURCE  HOT NOINLINE USED
#define SMC_DEST  NOINLINE USED

// Adds n_ nops to a function. Cap of 65534.
// Loop unrolling optimizations must be enabled!
// It is recommended to enable -O3 with pragmas.
#define EMIT_NOPS(n_)                       \
_Pragma("GCC unroll 65534")                 \
for (int i = 0; i < n_; i++)                \
    __asm__ inline("nop" :::)               \

typedef struct
{
    void* ptr;
    size_t size;
} FunctionAttrib;

bool n3dsInitSmcRegion(void);
