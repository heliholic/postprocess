/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * This file is part of RFX Firmware.
 *
 * Copyright (C) 2026 Rotorflight Project.
 *
 * RFX Firmware is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the Free
 * Software Foundation, either version 3 of the License, or (at your option)
 * any later version.
 *
 * RFX Firmware is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
 * more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program. If not, see <https://www.gnu.org/licenses/>.
 */

#include "core/common/core.h"
#include "core/common/system.h"

#include "core/rtos/rtos.h"

#include <ch.h>

/*
 * Start SysTick at CH_CFG_ST_FREQUENCY off the processor clock. RT alone ships
 * no tick driver; ChibiOS would otherwise take one from its HAL.
 */
static void tickStart(void)
{
    /*
     * Kernel priority, so the handler may call chSysTimerHandlerI(). An ISR
     * above CORTEX_MAX_KERNEL_PRIORITY is never masked by chSysLock() and may
     * call no kernel function at all.
     */
    NVIC_SetPriority(SysTick_IRQn, CORTEX_MAX_KERNEL_PRIORITY);

    SysTick->LOAD = (sysClockHz() / CH_CFG_ST_FREQUENCY) - 1U;
    SysTick->VAL = 0U;
    SysTick->CTRL = SysTick_CTRL_CLKSOURCE_Msk | SysTick_CTRL_TICKINT_Msk | SysTick_CTRL_ENABLE_Msk;
}

void rtosStart(void)
{
    chSysInit();
    tickStart();
}

void rtosPark(void)
{
    /* TIME_INFINITE sleeps with no timer behind it, so nothing makes the
       thread ready again. Looped to guarantee this never returns. */
    FOREVER {
        chThdSleep(TIME_INFINITE);
    }
}

/*
 * Overrides the weak SysTick_Handler in the part's startup assembly.
 */

FAST_CODE CH_IRQ_HANDLER(SysTick_Handler)
{
    CH_IRQ_PROLOGUE();

    chSysLockFromISR();
    chSysTimerHandlerI();
    chSysUnlockFromISR();

    CH_IRQ_EPILOGUE();
}
