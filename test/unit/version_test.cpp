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

/// Covers core/board/version.h: the build identity reaches the image intact
/// rather than arriving empty or from the wrong define.

#include "core/board/version.h"

#include <cstring>

#include <gtest/gtest.h>

namespace {

TEST(Version, TargetNameIsPresent)
{
    EXPECT_GT(std::strlen(TargetName), 0u);
}

TEST(Version, McuNameIsPresent)
{
    EXPECT_GT(std::strlen(McuName), 0u);
}

/// A version that never reached the build defines arrives as 0.0.0.
TEST(Version, VersionNumbersArePresent)
{
    EXPECT_GT(VersionMajor + VersionMinor + VersionPatch, 0u);
}

TEST(Version, MatchesTheBuildDefines)
{
    EXPECT_EQ(VersionMajor, RFX_VERSION_MAJOR);
    EXPECT_EQ(VersionMinor, RFX_VERSION_MINOR);
    EXPECT_EQ(VersionPatch, RFX_VERSION_PATCH);
}

}  // namespace
