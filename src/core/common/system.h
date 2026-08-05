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

/// The MCU register map, and with it the clock tree and reset entry points
/// declared by core/platform/startup/.
///
/// Everything under that path is C and declares no C++ linkage of its own.
/// This header states the linkage once and maps the part define onto its
/// family header, so board and driver code needs neither an `extern "C"` nor
/// an `#ifdef`.
///
/// Board builds only. A host build has no register map, and nothing that
/// compiles there includes this.

#ifdef __cplusplus
extern "C" {
#endif

#if defined(STM32H743xx) || defined(STM32H723xx)
#include "stm32h7xx.h"
#elif defined(STM32F722xx) || defined(STM32F745xx)
#include "stm32f7xx.h"
#else
#error "No register map for this MCU."
#endif

#ifdef __cplusplus
}
#endif
