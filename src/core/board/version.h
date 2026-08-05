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

/// Image identity: the board built for, the part that board carries, and the
/// firmware version. Fixed at compile time from the build defines on
/// rfx::common.
///
/// C linkage at file scope. version.c defines these and core/common/core.h
/// makes them available everywhere.

#ifdef __cplusplus
extern "C" {
#endif

/// Board and MCU names, NUL-terminated and never empty.
extern const char TargetName[];
extern const char McuName[];

extern const unsigned int VersionMajor;
extern const unsigned int VersionMinor;
extern const unsigned int VersionPatch;

#ifdef __cplusplus
}
#endif
