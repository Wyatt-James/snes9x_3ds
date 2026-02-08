#pragma once

// General macros
#define MAX(a_, b_) (((a_) > (b_)) ? (a_) : (b_)) // Returns the higher of a_ and b_.
#define MIN(a_, b_) (((a_) < (b_)) ? (a_) : (b_)) // Returns the lower of a_ and b_.
#define ROUND_UP(round_, val_) (((val_) + ((round_) - 1)) & ~((round_) - 1))  // Rounds a value up to the given power-of-2. Results with any other values are undefined.

// Attributes
#define COLD __attribute__ ((cold))
#define HOT __attribute__ ((hot))
#define NOINLINE __attribute__ ((noinline))
#define ALWAYS_INLINE __attribute__ ((always_inline)) inline
#define USED __attribute__((used))
#define ALIGNED(v_) __attribute__((aligned(v_)))

// Compiler hints
#define LIKELY(cond_) __builtin_expect(!!(cond_), 1)
#define UNLIKELY(cond_) __builtin_expect(!!(cond_), 0)
#define ASSUME(cond_) if (!(cond_)) __builtin_unreachable()
