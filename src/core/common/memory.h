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

/// Memory placement macros. An undecorated definition lands in the part's bulk
/// SRAM, which is cached; these move it to a pool the default cannot serve.
///
///   FAST_CODE   ITCM. Off the flash bus and out of the instruction cache.
///   FAST_DATA   DTCM. Single-cycle, never cached.
///   DMA_DATA    The pool a peripheral DMA controller reaches, MPU-marked
///               non-cacheable. Required for any buffer hardware reads or
///               writes: the default is cached and nothing here does cache
///               maintenance.
///   BDMA_DATA   The same for the BDMA controller, which reaches only its own
///               domain. Parts with a single DMA pool map this onto it.
///   PERSISTENT  Survives a warm reset. Nothing zeroes it.
///
/// Each macro places the definition in a bss section, so an initialiser is a
/// compile error; initialise from a function instead, and put read-only tables
/// in flash as `const`. PERSISTENT additionally requires a trivially
/// constructible type, since __libc_init_array() would run a C++ constructor
/// over the retained value on every boot.
///
/// core/platform/linker/sections_cm7.ld lays out the sections and the reset
/// path in core/platform/startup/startup_<part>.s brings them up before it
/// reaches main(). See docs/memory.md.
///
/// Only the Cortex-M7 parts have these memories. A Cortex-M4 part offers CCM
/// instead, which is on the data bus only, and a Cortex-M33 part has neither.
/// Such a part needs its own layout; until it has one, every macro here
/// expands to nothing for it.
///
/// No hardware dependency, so this reaches every translation unit through
/// core.h. Placement is selected by the compile definitions naming the part,
/// and a part with no such memory — including a host build — gets empty
/// macros, so decorated code still compiles.

#if defined(STM32H743xx) || defined(STM32H723xx) || \
    defined(STM32F722xx) || defined(STM32F745xx)

/*
 * noinline: the section attribute places the function, and an inlined function
 * is placed nowhere. LTO is on by default.
 */
#define FAST_CODE   __attribute__((section(".itcm_code"), noinline))

#define FAST_DATA   __attribute__((section(".bss.pool.fast")))
#define DMA_DATA    __attribute__((section(".bss.pool.dma")))
#define BDMA_DATA   __attribute__((section(".bss.pool.bdma")))
#define PERSISTENT  __attribute__((section(".bss.pool.persistent")))

#endif

/* Placements the part has no memory for expand to nothing. */

#ifndef INIT_CODE
#define INIT_CODE
#endif

#ifndef FAST_CODE
#define FAST_CODE
#endif

#ifndef FAST_DATA
#define FAST_DATA
#endif

#ifndef DMA_DATA
#define DMA_DATA
#endif

#ifndef BDMA_DATA
#define BDMA_DATA
#endif

#ifndef PERSISTENT
#define PERSISTENT
#endif

