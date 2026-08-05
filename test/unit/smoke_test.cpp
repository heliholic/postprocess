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

/// Placeholder keeping the test harness wired up until there is real code to
/// test. Remove once the first real unit test lands.

#include <gtest/gtest.h>

namespace {

TEST(Smoke, BuildDefinesArePresent)
{
    EXPECT_GE(RFX_VERSION_MAJOR + RFX_VERSION_MINOR + RFX_VERSION_PATCH, 0);
}

}  // namespace
