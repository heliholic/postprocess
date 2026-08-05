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

// NOLINTBEGIN(modernize-deprecated-headers,modernize-use-using)

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>
#include <limits.h>

#ifdef __cplusplus
#include <array>
#include <span>
#include <type_traits>
extern "C" {
#endif

/* Types in the spelling both languages accept. */

/// Short names for the built-in unsigned integer types.
typedef unsigned int uint;
typedef unsigned long ulong;

/// Fixed-width integers.
typedef uint8_t u8;
typedef uint16_t u16;
typedef uint32_t u32;
typedef uint64_t u64;

typedef int8_t i8;
typedef int16_t i16;
typedef int32_t i32;
typedef int64_t i64;

/// Signed sizes, counts and offsets. size_t comes from stddef.h.
typedef ptrdiff_t isize_t;

/// Firmware math is single precision.
typedef float f32;

#ifdef __cplusplus
}
#endif

// NOLINTEND(modernize-deprecated-headers,modernize-use-using)
