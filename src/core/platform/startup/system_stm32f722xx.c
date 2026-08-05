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
 * STM32F722 bring-up: everything between reset and the C runtime.
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

#include "stm32f7xx.h"

#include "system_stm32f7xx.h"

#include "core/common/macros.h"
#include "core/common/memory.h"

/*
 * Clock tree for this part. SYSCLK is the part maximum. HSE drives all of it
 * with no fallback to HSI, so a crystal that does not start halts
 * systemPreInit().
 *
 *                  ┌─ /P ─ SYSCLK 216 ─┬─ /1 ── CPU, HCLK  216
 *   HSE ─ /M ─ xN ─┤                   ├─ /4 ── PCLK1       54
 *                  │                   └─ /2 ── PCLK2      108
 *                  └─ /Q ─ CK48M    48 ──────── USB, SDMMC
 *
 * Timers take HCLK rather than 2x PCLKx, so every timer counts at 216 MHz
 * whichever bus it sits on.
 *
 * These are private to this file. Only sysClockHz() is exported; every other
 * clock is a fixed ratio of it that a driver derives.
 */
#define RFX_SYSCLK_HZ 216000000U
#define RFX_CPUCLK_HZ 216000000U
#define RFX_HCLK_HZ   216000000U
#define RFX_PCLK1_HZ  54000000U
#define RFX_PCLK2_HZ  108000000U
#define RFX_TIMCLK_HZ 216000000U
#define RFX_USBCLK_HZ 48000000U

/*
 * PLL settings per crystal frequency. M divides HSE down to the 1-2 MHz PLL
 * input, N multiplies that up to the VCO, and P and Q divide the VCO down to
 * SYSCLK and CK48M.
 *
 * HSE_VALUE is the crystal the board fitted, from RFX_HSE_HZ in its
 * target.cmake. A board that names none, or one no branch below covers, fails
 * the build here rather than running on a clock this file cannot produce.
 */
#ifndef HSE_VALUE
#error "HSE_VALUE is not defined. The board must set RFX_HSE_HZ in its target.cmake."
#endif

#if HSE_VALUE == 8000000U
#define PLL_M 4U
#define PLL_N 216U
#elif HSE_VALUE == 25000000U
#define PLL_M 25U
#define PLL_N 432U
#else
#error "No PLL configuration for this HSE frequency."
#endif

#define PLL_P 2U
#define PLL_Q 9U

#define PLL_VCO_HZ ((HSE_VALUE / PLL_M) * PLL_N)

_Static_assert(HSE_VALUE % PLL_M == 0U, "PLL input is not a whole number of Hz");
_Static_assert(PLL_VCO_HZ >= 100000000U && PLL_VCO_HZ <= 432000000U, "PLL VCO out of range");
_Static_assert(PLL_VCO_HZ / PLL_P == RFX_SYSCLK_HZ, "PLL does not produce SYSCLK");
_Static_assert(PLL_VCO_HZ / PLL_Q == RFX_USBCLK_HZ, "PLL does not produce CK48M");

/* The vector table, from startup_stm32f722xx.s. */
extern uint32_t g_pfnVectors[];

/*
 * The only clock exported. SYSCLK, the core clock and HCLK are one clock on
 * this part, so SysTick and the CPU run at it as well.
 */
uint32_t sysClockHz(void)
{
    return RFX_SYSCLK_HZ;
}

/*
 * Configure HSE, the PLL, the bus prescalers and the matching flash timing.
 *
 * The first thing the reset path calls, and the only one it calls before the
 * sections are brought up: the copies that follow write RAM at the clock this
 * programs. Nothing here may touch static storage.
 */
void systemPreInit(void)
{
    /*
     * Return to the reset state first. The image may be entered from a
     * bootloader with the PLL already running, and PLLCFGR is read-only while
     * it is.
     */
    RCC->CR |= RCC_CR_HSION;
    while ((RCC->CR & RCC_CR_HSIRDY) == 0U);

    RCC->CFGR = 0U;
    while ((RCC->CFGR & RCC_CFGR_SWS) != RCC_CFGR_SWS_HSI);

    RCC->CR &= ~(RCC_CR_HSEON | RCC_CR_HSEBYP | RCC_CR_CSSON | RCC_CR_PLLON);
    RCC->CIR = 0U;

    /* Scale 1 is the only voltage scale that reaches 216 MHz. */
    RCC->APB1ENR |= RCC_APB1ENR_PWREN;
    SYNCR(RCC->APB1ENR);
    PWR->CR1 |= PWR_CR1_VOS;

    RCC->CR |= RCC_CR_HSEON;
    while ((RCC->CR & RCC_CR_HSERDY) == 0U);

    RCC->PLLCFGR = (PLL_M << RCC_PLLCFGR_PLLM_Pos) | (PLL_N << RCC_PLLCFGR_PLLN_Pos) |
                   (((PLL_P / 2U) - 1U) << RCC_PLLCFGR_PLLP_Pos) |
                   (PLL_Q << RCC_PLLCFGR_PLLQ_Pos) | RCC_PLLCFGR_PLLSRC_HSE;

    RCC->CR |= RCC_CR_PLLON;
    while ((RCC->CR & RCC_CR_PLLRDY) == 0U);

    /*
     * Over-drive is required above 180 MHz, and the switch may only be made
     * while the CPU is still on HSI.
     */
    PWR->CR1 |= PWR_CR1_ODEN;
    while ((PWR->CSR1 & PWR_CSR1_ODRDY) == 0U);

    PWR->CR1 |= PWR_CR1_ODSWEN;
    while ((PWR->CSR1 & PWR_CSR1_ODSWRDY) == 0U);

    /*
     * 216 MHz at scale 1 needs 7 wait states, RM0431 table 7. The flash
     * adopts the new latency a few cycles after the write, so read it back
     * before raising the clock.
     */
    FLASH->ACR = FLASH_ACR_ARTEN | FLASH_ACR_PRFTEN | FLASH_ACR_LATENCY_7WS;
    while ((FLASH->ACR & FLASH_ACR_LATENCY) != FLASH_ACR_LATENCY_7WS);

    /*
     * Set the bus prescalers before the switch: 54 MHz on APB1 and 108 MHz
     * on APB2 are the maxima, and both must hold the instant SYSCLK reaches
     * 216 MHz. TIMPRE then clocks the timers from HCLK instead of 2x PCLKx.
     */
    RCC->CFGR = RCC_CFGR_HPRE_DIV1 | RCC_CFGR_PPRE1_DIV4 | RCC_CFGR_PPRE2_DIV2;
    RCC->DCKCFGR1 |= RCC_DCKCFGR1_TIMPRE;

    /* USB and SDMMC take their 48 MHz from PLLQ, not from PLLSAI. */
    RCC->DCKCFGR2 &= ~RCC_DCKCFGR2_CK48MSEL;

    RCC->CFGR |= RCC_CFGR_SW_PLL;
    while ((RCC->CFGR & RCC_CFGR_SWS) != RCC_CFGR_SWS_PLL);
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
 * of it: flash and SRAM1 cached, DTCM and ITCM outside the cache by
 * construction, peripherals Device.
 *
 * No region is Write-Through. Cortex-M7 erratum 1259864 makes that unsafe, so
 * every region is Write-Back or non-cacheable.
 */
static void mpuInit(void)
{
    static const ARM_MPU_Region_t regions[] = {
        {
            /* ITCM, read-only: a write through a null pointer faults. */
            .RBAR = ARM_MPU_RBAR(0U, 0x00000000U),
            .RASR = ARM_MPU_RASR(0U, ARM_MPU_AP_RO, 1U, 0U, 0U, 0U, 0U,
                                 ARM_MPU_REGION_SIZE_16KB),
        },
        {
            /*
             * SRAM2, uncached and execute-never: the DMA buffer pool, the
             * .sram2 section in the linker script. Coherent with no cache
             * maintenance.
             */
            .RBAR = ARM_MPU_RBAR(1U, 0x2003C000U),
            .RASR = ARM_MPU_RASR(1U, ARM_MPU_AP_FULL, 1U, 1U, 0U, 0U, 0U,
                                 ARM_MPU_REGION_SIZE_16KB),
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
