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
 * STM32H723xG memory map.
 *
 * Shared by every board carrying this part. The xG in the name is the 1M flash
 * below; the 512K xE part is a separate MCU with its own memory map.
 *
 * The image is linked at the start of flash. A bootloader requires ORIGIN
 * moved forward and a header section added.
 *
 * The section layout is in sections_cm7.ld, shared by every Cortex-M7 MCU.
 */

ENTRY(Reset_Handler)

MEMORY
{
    FLASH  (rx)  : ORIGIN = 0x08000000, LENGTH = 1024K
    ITCM   (rwx) : ORIGIN = 0x00000000, LENGTH = 64K
    DTCM   (rwx) : ORIGIN = 0x20000000, LENGTH = 128K
    SRAM   (rwx) : ORIGIN = 0x24000000, LENGTH = 320K   /* AXI SRAM, D1 */
    SRAM_D2(rwx) : ORIGIN = 0x30000000, LENGTH = 32K    /* peripheral DMA */
    SRAM_D3(rwx) : ORIGIN = 0x38000000, LENGTH = 16K    /* BDMA */
}

/*
 * AXI SRAM is the bulk pool and holds .data/.bss, cached. The tightly-coupled
 * memories are opt-in: ITCM takes FAST_CODE, DTCM takes FAST_DATA, PERSISTENT
 * and both stacks.
 *
 * D2 and D3 SRAM are the DMA pools, each sitting in the domain of the
 * controllers that reach it: SystemInit() gives both a non-cacheable MPU
 * region, so buffers there need no cache maintenance. D3 is the domain BDMA
 * reaches, and is what BDMA_DATA targets.
 *
 * D2 is SRAM1 and SRAM2 back to back, 16K each; ST numbers them separately
 * because they are separately clock-gated, but they are one address range.
 */

REGION_ALIAS("BULK",     SRAM)
REGION_ALIAS("DMAPOOL",  SRAM_D2)
REGION_ALIAS("BDMAPOOL", SRAM_D3)

INCLUDE sections_cm7.ld
