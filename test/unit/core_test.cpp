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

/// Covers core/common/core.h. Every guarantee the header makes is a
/// compile-time property, so the checks are static_assert; the test case gives
/// the suite something to report.

#include "core/common/core.h"

#include <gtest/gtest.h>

namespace {

static_assert(sizeof(u8) == 1);
static_assert(sizeof(u16) == 2);
static_assert(sizeof(u32) == 4);
static_assert(sizeof(u64) == 8);

static_assert(sizeof(i8) == 1);
static_assert(sizeof(i16) == 2);
static_assert(sizeof(i32) == 4);
static_assert(sizeof(i64) == 8);

static_assert(std::is_unsigned_v<size_t>);
static_assert(std::is_signed_v<isize_t>);
static_assert(sizeof(size_t) == sizeof(isize_t));

/// Firmware math is single precision. There is no f64.
static_assert(sizeof(f32) == 4);
static_assert(std::is_same_v<f32, float>);

TEST(Core, TypesAreTheWidthsTheyClaim)
{
    SUCCEED();  // The static_asserts above ran at compile time.
}

}  // namespace
