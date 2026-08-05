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

/// The hook every board target implements.
///
/// Declared in core, defined by the board target and bound at link time, so
/// core includes no target header and the layering rule holds.
///
/// C linkage at file scope, so main() may be either language.
///
/// There is no early-init counterpart. Anything that must run before the C
/// runtime exists — clock tree, MPU regions, caches — belongs in SystemInit(),
/// in core/platform/startup/system_<part>.c, which the reset path calls before
/// copying .data. That path is per-part, and boards of the same part share it.

#ifdef __cplusplus
extern "C" {
#endif

/// Bring the board's hardware up and hand it to the drivers that need it.
/// Called from main(), with the C runtime up and static constructors already
/// run.
void boardInit(void);

#ifdef __cplusplus
}
#endif
