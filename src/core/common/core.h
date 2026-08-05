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

/// Prelude for every first-party translation unit: the universally used
/// standard headers, the firmware's integer and float types, and the memory
/// placement macros. Everything here reaches every object, so the bar for
/// adding to it is "needed nearly everywhere".
///
/// C and C++ both, from one set of typedefs at file scope. <stdint.h> puts the
/// fixed-width names in the global namespace for these to alias; <cstdint>
/// only guarantees them in std.
///
/// No hardware. Files that touch registers include the CMSIS register
/// map themselves.

#include "core/common/memory.h"
#include "core/common/macros.h"
#include "core/common/types.h"
