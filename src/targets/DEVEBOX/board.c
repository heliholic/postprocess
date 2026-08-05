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

#include "core/board/board.h"
#include "core/rtos/rtos.h"

#include <ch.h>

#include "core/common/core.h"
#include "core/common/system.h"

/*
 * Temporary: the blink demo lives entirely here rather than behind a driver
 * layer, to exercise the kernel end to end (SysTick, thread creation, sleep)
 * on real silicon. DevEBox has one status LED, PA1.
 *
 * boardInit() starts the kernel itself and parks here, so it never returns —
 * main() calling rtosStart() and rtosPark() again is dead code for this
 * board.
 */

static FAST_DATA THD_WORKING_AREA(BlinkWorkArea, 128);

static THD_FUNCTION(blinkThread, arg)
{
    UNUSED(arg);

    chRegSetThreadName("blink");

    FOREVER {
        GPIOA->ODR ^= (1U << 1);
        chThdSleepMilliseconds(500U);
    }
}

void boardInit(void)
{
    rtosStart();

    /* GPIO hangs off AHB4 on the H7. The clock reaches the port a cycle
       after the write, so read the register back before configuring the
       pin. */
    RCC->AHB4ENR |= RCC_AHB4ENR_GPIOAEN;
    SYNCR(RCC->AHB4ENR);

    GPIOA->MODER = (GPIOA->MODER & ~(3U << 2U)) | (1U << 2U);
    GPIOA->OTYPER &= ~(1U << 1U);
    GPIOA->PUPDR &= ~(3U << 2U);

    chThdCreateStatic(BlinkWorkArea, sizeof(BlinkWorkArea), NORMALPRIO + 1, blinkThread, NULL);

    rtosPark();
}
