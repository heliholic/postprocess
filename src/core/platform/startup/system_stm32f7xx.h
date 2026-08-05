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

#pragma once

/*
 * What every STM32F7 part in this tree provides out of its reset path. The
 * name is ST's: each part header includes it by bare name with no path, so a
 * file of this name must exist and be on the include path.
 *
 * The clock tree behind sysClockHz() is not declared here. It is one set of
 * numbers per part, private to that part's system_<part>.c, where the
 * registers that produce it are written.
 *
 * C only. ST's part header includes this from inside its own extern "C", and
 * C++ reaches it through core/common/system.h, which states the linkage.
 */

#include <stdint.h>

/*
 * Bring-up, in the two halves the reset handler in startup_<part>.s calls it
 * in. Everything between them is the sections: ITCM, .data, .bss and the
 * placement pools, which the reset path brings up itself.
 *
 *   systemPreInit()  the clock tree and the flash timing that goes with it.
 *                    Runs before .data is copied and .bss zeroed, so nothing
 *                    it reaches may touch static storage.
 *   SystemInit()     the FPU, VTOR, the MPU regions and the caches. Runs after
 *                    the sections, because the MPU makes ITCM read-only, and
 *                    before the static constructors.
 */
void systemPreInit(void);
void SystemInit(void);

/*
 * SYSCLK, in Hz: the PLL output the whole tree derives from. Every other clock
 * is a fixed ratio of it, so a driver divides this down by the prescaler its
 * part's system_<part>.c programmed.
 */
uint32_t sysClockHz(void);
