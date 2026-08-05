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
 * STM32H743 bring-up: everything between reset and the C runtime.
 *
 * The reset handler calls systemPreInit() before .data is copied and .bss
 * zeroed, so it may not read or write static storage: constants in flash are
 * fine, variables are not. SystemInit() runs after the copies and is under no
 * such rule, but has no state to keep either.
 *
 * Every wait here is unbounded. A crystal that fails to start or a PLL that
 * fails to lock halts bring-up: there is no console to report to and no
 * fallback clock worth running on.
 */

#include <stdint.h>
#include <string.h>

#include "stm32h7xx.h"

#include "system_stm32h7xx.h"

#include "core/common/macros.h"
#include "core/common/memory.h"

/*
 * Clock tree for this part: 480 MHz at voltage scale 0, which requires rev V
 * silicon or later. Rev X and rev Y stop at 400 MHz and their PLL VCO does not
 * reach 960 MHz, so systemPreInit() halts on them.
 *
 *                  ┌─ /P ─ sys_ck 480 ─┬─ /1 ── CPU              480
 *   HSE ─ /M ─ xN ─┤                   └─ /2 ── HCLK, AXI        240
 *                  │                            └─ /2 ── PCLK1..4 120
 *                  └─ /Q ─ pll1_q 120 ───────── kernel clock option
 *
 *   HSI48 ─────────────────────────────────────── USB             48
 *
 * HSE drives all of it with no fallback to HSI, so a crystal that does not
 * start halts systemPreInit(). USB is the exception: it needs exactly 48 MHz
 * and takes HSI48, trimmed against SOF by the CRS in its driver. Timers take
 * 2x PCLKx, which the /2 above makes 240 MHz on every APB.
 *
 * These are private to this file. Only sysClockHz() is exported; every other
 * clock is a fixed ratio of it that a driver derives.
 */
#define RFX_SYSCLK_HZ 480000000U
#define RFX_CPUCLK_HZ 480000000U
#define RFX_HCLK_HZ   240000000U
#define RFX_PCLK1_HZ  120000000U
#define RFX_PCLK2_HZ  120000000U
#define RFX_PCLK3_HZ  120000000U
#define RFX_PCLK4_HZ  120000000U
#define RFX_TIMCLK_HZ 240000000U
#define RFX_PLL1Q_HZ  120000000U
#define RFX_USBCLK_HZ 48000000U

/*
 * PLL1 settings per crystal frequency. M divides HSE down to the PLL input,
 * N multiplies that up to the 960 MHz VCO, and P and Q divide that down to
 * sys_ck and the pll1_q kernel clock. RGE declares the input range to
 * PLLCFGR: 1 is 2-4 MHz, 2 is 4-8 MHz.
 *
 * HSE_VALUE is the crystal the board fitted, from RFX_HSE_HZ in its
 * target.cmake. A board that names none, or one no branch below covers, fails
 * the build here rather than running on a clock this file cannot produce.
 */
#ifndef HSE_VALUE
#error "HSE_VALUE is not defined. The board must set RFX_HSE_HZ in its target.cmake."
#endif

#if HSE_VALUE == 8000000U
#define PLL1_M   4U
#define PLL1_N   480U
#define PLL1_RGE 1U
#elif HSE_VALUE == 25000000U
#define PLL1_M   5U
#define PLL1_N   192U
#define PLL1_RGE 2U
#else
#error "No PLL configuration for this HSE frequency."
#endif

#define PLL1_P 2U
#define PLL1_Q 8U
#define PLL1_R 2U

#define PLL1_VCO_HZ ((HSE_VALUE / PLL1_M) * PLL1_N)

_Static_assert(HSE_VALUE % PLL1_M == 0U, "PLL1 input is not a whole number of Hz");
_Static_assert(PLL1_VCO_HZ >= 192000000U && PLL1_VCO_HZ <= 960000000U,
               "PLL1 VCO outside the range rev V allows");
_Static_assert(PLL1_VCO_HZ / PLL1_P == RFX_SYSCLK_HZ, "PLL1 does not produce sys_ck");
_Static_assert(PLL1_VCO_HZ / PLL1_Q == RFX_PLL1Q_HZ, "PLL1 does not produce pll1_q");

/*
 * Rev V, as read from the top half of DBGMCU->IDCODE. Revision IDs do not sort
 * by speed grade — rev X is 0x2001 and rev Y is 0x1003, both 400 MHz parts —
 * so compare against this as a floor rather than masking.
 */
#define REV_ID_V 0x2003U

/* The vector table, from startup_stm32h743xx.s. */
extern uint32_t g_pfnVectors[];

/*
 * The only clock exported. The CPU runs at it as well, since D1CPRE is /1. A
 * part that divides the core clock below sys_ck needs a second accessor for
 * SysTick's users.
 */
uint32_t sysClockHz(void)
{
    return RFX_SYSCLK_HZ;
}

/*
 * Enable the parts of the memory system that are not available after reset.
 */
static void memoryInit(void)
{
    /*
     * D2 SRAM comes out of reset unclocked. The linker script places DMA
     * buffers there, so enable all three blocks before anything reaches them.
     * D3 SRAM has no clock gate.
     */
    RCC->AHB2ENR |= RCC_AHB2ENR_SRAM1EN | RCC_AHB2ENR_SRAM2EN | RCC_AHB2ENR_SRAM3EN;
    SYNCR(RCC->AHB2ENR);

    /*
     * FMC bank 1 is enabled out of reset, and speculative reads into it lock
     * the FMC out for 24 us at a time. No board fits external memory.
     */
    RCC->AHB3ENR |= RCC_AHB3ENR_FMCEN;
    SYNCR(RCC->AHB3ENR);
    FMC_Bank1_R->BTCR[0] = 0x000030D2U;
    RCC->AHB3ENR &= ~RCC_AHB3ENR_FMCEN;
}

/*
 * Leave Run* mode, the supply state the part comes out of reset in, where the
 * voltage scale cannot be raised.
 */
static void exitRun0Mode(void)
{
    /*
     * The core supply must be declared before the voltage scale may be
     * raised. This part has no SMPS: VCORE comes from the internal LDO, which
     * is also the reset state, so this write confirms rather than changes
     * it.
     */
    PWR->CR3 |= PWR_CR3_LDOEN;
    while ((PWR->CSR1 & PWR_CSR1_ACTVOSRDY) == 0U);
}

/*
 * Configure HSE, PLL1, the bus prescalers and the matching flash timing, and
 * with them the memory system.
 *
 * The only thing the reset path calls before the sections are brought up: the
 * copies that follow write RAM at the clock this programs, and a write into a
 * D2 pool is lost until memoryInit() has clocked that SRAM. Nothing here may
 * touch static storage.
 */
void systemPreInit(void)
{
    /*
     * Rev V raised the part maximum to 480 MHz, extended the PLL VCO to
     * 960 MHz and added voltage scale 0. This clock tree requires all three,
     * so older silicon halts here rather than running past its rating. First,
     * so nothing below is written on a part this image will not run on.
     */
    if ((DBGMCU->IDCODE >> 16U) < REV_ID_V) FOREVER;

    /* The core supply next: nothing below may raise the scale under Run*. */
    exitRun0Mode();

    /*
     * Return to the reset state first. The image may be entered from a
     * bootloader with a PLL already running, and the PLL registers are
     * read-only while it is.
     */
    RCC->CR |= RCC_CR_HSION;
    while ((RCC->CR & RCC_CR_HSIRDY) == 0U);

    RCC->CFGR = 0U;
    while ((RCC->CFGR & RCC_CFGR_SWS) != RCC_CFGR_SWS_HSI);

    RCC->CR &= ~(RCC_CR_HSEON | RCC_CR_HSEBYP | RCC_CR_CSSHSEON | RCC_CR_PLL1ON |
                 RCC_CR_PLL2ON | RCC_CR_PLL3ON);
    RCC->CIER = 0U;

    /*
     * SYSCFG is needed from here on: both voltage scale 0 and the I/O
     * compensation cell below are reached through it.
     */
    RCC->APB4ENR |= RCC_APB4ENR_SYSCFGEN;
    SYNCR(RCC->APB4ENR);

    /*
     * Scale 1, then scale 0 on top of it. Scale 0 is not a VOS encoding but
     * scale 1 plus the over-drive bit in SYSCFG, and VOSRDY must be waited on
     * again afterwards.
     */
    PWR->D3CR |= PWR_D3CR_VOS;
    while ((PWR->D3CR & PWR_D3CR_VOSRDY) == 0U);

    SYSCFG->PWRCR |= SYSCFG_PWRCR_ODEN;
    SYNCR(SYSCFG->PWRCR);
    while ((PWR->D3CR & PWR_D3CR_VOSRDY) == 0U);

    /*
     * A 240 MHz AXI clock at scale 0 needs 4 wait states, RM0433 table 17.
     * Raise the latency before the clock and read it back, since the flash
     * adopts it a few cycles after the write. The programming delay in the
     * same register applies to flash writes only.
     */
    FLASH->ACR = FLASH_ACR_LATENCY_4WS;
    while ((FLASH->ACR & FLASH_ACR_LATENCY) != FLASH_ACR_LATENCY_4WS);

    RCC->CR |= RCC_CR_HSEON;
    while ((RCC->CR & RCC_CR_HSERDY) == 0U);

    RCC->PLLCKSELR = (PLL1_M << RCC_PLLCKSELR_DIVM1_Pos) | RCC_PLLCKSELR_PLLSRC_HSE;

    /*
     * Integer mode, wide VCO range, P and Q enabled. R stays disabled, but
     * its divider is written anyway since all four share one register.
     */
    RCC->PLLCFGR = (PLL1_RGE << RCC_PLLCFGR_PLL1RGE_Pos) | RCC_PLLCFGR_DIVP1EN |
                   RCC_PLLCFGR_DIVQ1EN;
    RCC->PLL1DIVR = ((PLL1_N - 1U) << RCC_PLL1DIVR_N1_Pos) |
                    ((PLL1_P - 1U) << RCC_PLL1DIVR_P1_Pos) |
                    ((PLL1_Q - 1U) << RCC_PLL1DIVR_Q1_Pos) |
                    ((PLL1_R - 1U) << RCC_PLL1DIVR_R1_Pos);

    RCC->CR |= RCC_CR_PLL1ON;
    while ((RCC->CR & RCC_CR_PLL1RDY) == 0U);

    /*
     * Set the bus prescalers before the switch: halving sys_ck puts the AXI
     * and AHBs at their 240 MHz maximum and the APBs at their 120 MHz, both
     * of which must hold the instant sys_ck arrives. The CPU alone takes it
     * undivided.
     */
    RCC->D1CFGR = RCC_D1CFGR_D1CPRE_DIV1 | RCC_D1CFGR_HPRE_DIV2 | RCC_D1CFGR_D1PPRE_DIV2;
    RCC->D2CFGR = RCC_D2CFGR_D2PPRE1_DIV2 | RCC_D2CFGR_D2PPRE2_DIV2;
    RCC->D3CFGR = RCC_D3CFGR_D3PPRE_DIV2;

    RCC->CFGR |= RCC_CFGR_SW_PLL1;
    while ((RCC->CFGR & RCC_CFGR_SWS) != RCC_CFGR_SWS_PLL1);

    /*
     * USB needs exactly 48 MHz, which no divider off this VCO produces.
     * HSI48 does, to within ±1%. The CRS closes the remainder, trimmed
     * against USB SOF by the driver.
     */
    RCC->CR |= RCC_CR_HSI48ON;
    while ((RCC->CR & RCC_CR_HSI48RDY) == 0U);

    RCC->D2CCIP2R = (RCC->D2CCIP2R & ~RCC_D2CCIP2R_USBSEL) | RCC_D2CCIP2R_USBSEL;

    /*
     * The I/O compensation cell holds output slew within spec at these bus
     * speeds. It runs off CSI.
     */
    RCC->CR |= RCC_CR_CSION;
    while ((RCC->CR & RCC_CR_CSIRDY) == 0U);

    SYSCFG->CCCSR |= SYSCFG_CCCSR_EN;

    /* The memory system last: the reset path zeroes the D2 pools next. */
    memoryInit();
}

/*
 * The PERSISTENT pool, from core/platform/linker/sections_cm7.ld: where it
 * starts, and how long it is. Neither is storage — a linker symbol is an
 * address — so the size is the address of __persistent_size rather than
 * anything read out of it, and both are declared as arrays to keep that
 * visible at the use below.
 */
extern uint8_t __persistent_start[];
extern uint8_t __persistent_size[];

/*
 * Tells a warm reset from a cold one. Cold RAM holds whatever it powered up
 * with, so the region is cleared once. Any change to the layout of the region
 * — a new PERSISTENT definition, or a new image — moves this word and reads as
 * cold.
 */
#define PERSISTENT_MAGIC 0x52465831U    /* "RFX1" */

static PERSISTENT uint32_t persistentMagic;

/*
 * The one section the reset path does not bring up itself. PERSISTENT survives
 * a warm reset — nothing zeroes it — so the region is cleared only when the
 * magic word says the memory holds something else, and the word written back
 * afterwards because it sits in the region just cleared.
 */
static void persistentInit(void)
{
    if (persistentMagic != PERSISTENT_MAGIC) {
        memset(__persistent_start, 0, (size_t)(uintptr_t)__persistent_size);
        persistentMagic = PERSISTENT_MAGIC;
    }
}

/*
 * MPU regions overriding the default memory map. PRIVDEFENA retains the rest
 * of it: flash and AXI SRAM cached, DTCM outside the cache by construction,
 * peripherals Device.
 *
 * No region is Write-Through. Cortex-M7 erratum 1259864 is unfixed on the
 * r1p1 core this part carries, so every region is Write-Back or
 * non-cacheable.
 */
static void mpuInit(void)
{
    static const ARM_MPU_Region_t regions[] = {
        {
            /* ITCM, read-only: a write through a null pointer faults. */
            .RBAR = ARM_MPU_RBAR(0U, 0x00000000U),
            .RASR = ARM_MPU_RASR(0U, ARM_MPU_AP_RO, 1U, 0U, 0U, 0U, 0U,
                                 ARM_MPU_REGION_SIZE_64KB),
        },
        {
            /*
             * D2 SRAM, uncached and execute-never: the peripheral DMA
             * pool, the .dma_d2 section in the linker script. Coherent with
             * no cache maintenance. The region is the smallest power of two
             * covering the 288 KB fitted.
             */
            .RBAR = ARM_MPU_RBAR(1U, 0x30000000U),
            .RASR = ARM_MPU_RASR(1U, ARM_MPU_AP_FULL, 1U, 1U, 0U, 0U, 0U,
                                 ARM_MPU_REGION_SIZE_512KB),
        },
        {
            /* D3 SRAM, the same for BDMA: the .sram_d3 section. */
            .RBAR = ARM_MPU_RBAR(2U, 0x38000000U),
            .RASR = ARM_MPU_RASR(1U, ARM_MPU_AP_FULL, 1U, 1U, 0U, 0U, 0U,
                                 ARM_MPU_REGION_SIZE_64KB),
        },
    };

    const uint32_t implemented = (MPU->TYPE & MPU_TYPE_DREGION_Msk) >> MPU_TYPE_DREGION_Pos;

    ARM_MPU_Disable();

    for (uint32_t region = 0U; region < implemented; region++) {
        ARM_MPU_ClrRegion(region);
    }

    ARM_MPU_Load(regions, (uint32_t)(sizeof(regions) / sizeof(regions[0])));
    ARM_MPU_Enable(MPU_CTRL_PRIVDEFENA_Msk);
}

/*
 * The rest of bring-up, called from the reset path once RAM is up and before
 * the static constructors run.
 */
void SystemInit(void)
{
    /* Full access to CP10 and CP11, before any code that uses the FPU runs. */
    SCB->CPACR |= (3U << (10U * 2U)) | (3U << (11U * 2U));

    /*
     * Point VTOR at the table the linker placed rather than whatever the
     * boot mapping aliases at zero. Behind a bootloader these differ.
     */
    SCB->VTOR = (uint32_t)(uintptr_t)g_pfnVectors;

    persistentInit();
    mpuInit();

    /*
     * Caches last: the region attributes must be in place before anything
     * is cached under them.
     */
    SCB_EnableICache();
    SCB_EnableDCache();
}
