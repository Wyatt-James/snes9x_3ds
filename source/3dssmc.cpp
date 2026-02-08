#include "3dssmc.h"
#include "Snes9x/macros.h"
#include "Snes9x/fxinst_smc.h"
#include <3ds.h>

static Handle getCurrentProcessHandle(void) {
    Handle h;
    u32 process;

    svcGetProcessId(&process, CUR_PROCESS_HANDLE);
    if (!R_SUCCEEDED(svcOpenProcess(&h, process)))
        return 0;

    return h;
}

static Result makeRegionRWX(Handle handle, void* addr, size_t max_size)
{
    u32 baseAddr = (u32) addr;
    u32 baseAddrAdj = baseAddr & ~0xfff;
    u32 size = ROUND_UP(0x1000, max_size + (baseAddr - baseAddrAdj));

    return svcControlProcessMemory(handle, baseAddrAdj, baseAddrAdj, size, MEMOP_PROT, MEMPERM_READWRITE | MEMPERM_EXECUTE);
}

bool n3dsInitSmcRegion(void)
{
    static bool initialized = false;
    bool success = true;
    
    if (!initialized) {
        initialized = true;

        Handle handle = getCurrentProcessHandle();
        if (handle == 0)
            return false;

        if (!R_SUCCEEDED(makeRegionRWX(handle, (void*) &fx_plot_current, FX_PLOT_MAX_SIZE)))
            success = false;
            
        if (!R_SUCCEEDED(makeRegionRWX(handle, (void*) &fx_rpix_current, FX_RPIX_MAX_SIZE)))
            success = false;

        svcCloseHandle(handle);
    }
    return success;
}
