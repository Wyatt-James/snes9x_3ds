#pragma once
#include "macros.h"

// Function sizes. These are read from the .map file.
// These must be kept up-to-date or things will crash.
#define FX_PLOT_2BIT_SIZE 0xf0
#define FX_PLOT_4BIT_SIZE 0x110
#define FX_PLOT_8BIT_SIZE 0x16c
#define FX_PLOT_OBJ_SIZE  0xc
#define FX_RPIX_2BIT_SIZE 0xb0
#define FX_RPIX_4BIT_SIZE 0xdc
#define FX_RPIX_8BIT_SIZE 0x130
#define FX_RPIX_OBJ_SIZE  0xc

// The largest size of each function type
#define FX_PLOT_MAX_SIZE MAX(FX_PLOT_2BIT_SIZE, MAX(FX_PLOT_4BIT_SIZE, MAX(FX_PLOT_8BIT_SIZE, FX_PLOT_OBJ_SIZE)))
#define FX_RPIX_MAX_SIZE MAX(FX_RPIX_2BIT_SIZE, MAX(FX_RPIX_4BIT_SIZE, MAX(FX_RPIX_8BIT_SIZE, FX_RPIX_OBJ_SIZE)))

void fx_plot_current(void);
void fx_rpix_current(void);
