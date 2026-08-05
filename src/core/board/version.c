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

#include "core/board/version.h"

#if !defined(RFX_TARGET_NAME) || !defined(RFX_MCU_NAME)
#error "RFX_TARGET_NAME and RFX_MCU_NAME are missing; this file needs rfx::common"
#endif

#if !defined(RFX_VERSION_MAJOR) || !defined(RFX_VERSION_MINOR) || !defined(RFX_VERSION_PATCH)
#error "the RFX_VERSION_* defines are missing; this file needs rfx::common"
#endif

const char TargetName[] = RFX_TARGET_NAME;
const char McuName[] = RFX_MCU_NAME;

const unsigned int VersionMajor = RFX_VERSION_MAJOR;
const unsigned int VersionMinor = RFX_VERSION_MINOR;
const unsigned int VersionPatch = RFX_VERSION_PATCH;
