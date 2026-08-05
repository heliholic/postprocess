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

/*
 * STM32F722xE memory map.
 *
 * Shared by every board carrying this part. The xE in the name is the 512K
 * flash below; the 256K xC part is a separate MCU with its own memory map.
 *
 * The image is linked at the start of flash. A bootloader requires ORIGIN
 * moved forward and a header section added.
 *
 * The section layout is in sections_cm7.ld, shared by every Cortex-M7 MCU.
 */

ENTRY(Reset_Handler)

MEMORY
{
    FLASH  (rx)  : ORIGIN = 0x08000000, LENGTH = 512K
    ITCM   (rwx) : ORIGIN = 0x00000000, LENGTH = 16K
    DTCM   (rwx) : ORIGIN = 0x20000000, LENGTH = 64K
    SRAM1  (rwx) : ORIGIN = 0x20010000, LENGTH = 176K
    SRAM2  (rwx) : ORIGIN = 0x2003C000, LENGTH = 16K
}

/*
 * SRAM1 is the bulk pool and holds .data/.bss, cached. The tightly-coupled
 * memories are opt-in: ITCM takes FAST_CODE, DTCM takes FAST_DATA, PERSISTENT
 * and both stacks. DTCM is 64K on this part, so the DTCM overflow ASSERT in
 * sections_cm7.ld is the first limit reached.
 *
 * SRAM2 is the DMA pool: SystemInit() gives it a non-cacheable MPU region, so
 * buffers there need no cache maintenance. The part has one such pool rather
 * than the H7's two, so BDMA_DATA lands in it alongside DMA_DATA.
 */

REGION_ALIAS("BULK",     SRAM1)
REGION_ALIAS("DMAPOOL",  SRAM2)
REGION_ALIAS("BDMAPOOL", SRAM2)

INCLUDE sections_cm7.ld
