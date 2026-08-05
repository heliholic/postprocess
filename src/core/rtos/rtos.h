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

/// Binding between the kernel and this tree.
///
/// The kernel is ChibiOS/RT, vendored under ext/chibios/ without ChibiOS's
/// HAL. Its hardware requirements are supplied here and by
/// core/platform/startup/:
///
///   SysTick        the periodic tick, configured and handled below
///   SVC            the context switch, taken by the port's own handler
///   process stack  established by the reset path before it calls main()
///
/// Board builds only. The port is ARMv7-M and compiles on no host, so a host
/// build would reach concurrency through this interface rather than through
/// ch.h.
///
/// C linkage at file scope, so main() may be either language.

#ifdef __cplusplus
extern "C" {
#endif

/// Start the kernel and the system tick. Returns with the caller running as
/// the main thread at NORMALPRIO and able to spawn threads; the idle thread
/// exists by then.
///
/// Call from main() after the static constructors and before anything that
/// blocks, sleeps or synchronises.
void rtosStart(void);

/// Park the calling thread permanently. Does not return, and the scheduler
/// never selects the thread again, so the CPU goes to whatever else is
/// runnable and to the idle thread when nothing is.
///
/// For a thread that has finished its work and has nothing to wait on, such as
/// main() once it has started the firmware's threads.
void rtosPark(void);

#ifdef __cplusplus
}
#endif
