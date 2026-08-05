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

/* Common attributes */

#define NORETURN        __attribute__((noreturn))

#define ALIGN(n)        __attribute__((aligned(n)))
#define PACKED          __attribute__((packed))

#define FORMAT(m, n)    __attribute__((format(printf, (m), (n))))


/* Common macros */

#define UNUSED(x)       ((void)(x))
#define IGNORE(x)       UNUSED(x)

#define SYNCR(x)        ((void)(x))

#define FOREVER         for(;;)


/* Bit manipulation */

#define BIT(n)           (1U << (n))
#define BITL(n)          (1UL << (n))
#define BITLL(n)         (1ULL << (n))

#define BITMASK(n)       (BIT(n) - 1U)
#define BITMASKL(n)      (BITL(n) - 1UL)
#define BITMASKLL(n)     (BITLL(n) - 1ULL)

#define SETBIT(x, b)     ((x) | BIT(b))
#define CLEARBIT(x, b)   ((x) & ~BIT(b))

#define SETMASK(x, b)    ((x) | (b))
#define CLEARMASK(x, b)  ((x) & ~(b))

