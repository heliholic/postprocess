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
 * Section layout shared by every Cortex-M7 MCU, included by <mcu>.ld once that
 * file has declared its memory map. It names no part and no address: it is
 * written against FLASH, ITCM and DTCM, which every part declares under those
 * names, and against BULK, DMAPOOL and BDMAPOOL, which each part aliases onto
 * whichever of its SRAMs serves that role.
 *
 * Named for the core because the shape is the core's. A Cortex-M4 offers CCM,
 * which is on the data bus only and cannot hold code, and a Cortex-M33 has
 * neither TCM; either needs a layout of its own beside this one.
 *
 * Ordinary data goes to BULK, the part's largest RAM, which is cached. The
 * tightly-coupled memories are a budget: FAST_CODE places code in ITCM and
 * FAST_DATA places data in DTCM, both at the expense of other users of that
 * memory.
 *
 * Every bound exported here is __<section>_start and __<section>_end, with a
 * load address __<section>_load where there is one — the spelling the
 * toolchain's own __exidx_start and __exidx_end already arrive in. The two
 * exceptions carry trailing underscores because they are not this file's names
 * to choose: ChibiOS declares __main_thread_stack_base__ and
 * __main_thread_stack_end__ extern and links against them.
 */

/*
 * Two stacks. Exceptions run on the main stack (MSP); main() and every thread
 * run on a process stack (PSP), which is what ChibiOS/RT's context switch
 * swaps and what its SVC handler reads directly. The reset path in
 * startup_<part>.s makes the switch before calling main().
 */
__main_stack_size    = 2K;
__process_stack_size = 2K;

/*
 * The symbols the kernel links against. chsys.c takes the main thread's bounds
 * for its stack check, and the reset path loads PSP from its end. In ChibiOS
 * terms the PSP stack is the main thread's and the MSP one is the main stack.
 */
__main_stack_end           = ORIGIN(DTCM) + LENGTH(DTCM);
__main_stack_base          = __main_stack_end - __main_stack_size;
__main_thread_stack_end__  = __main_stack_base;
__main_thread_stack_base__ = __main_thread_stack_end__ - __process_stack_size;

SECTIONS
{
    .isr_vector :
    {
        KEEP(*(.isr_vector))
    } > FLASH

    .text :
    {
        *(.text .text.*)
        *(.glue_7 .glue_7t)
        KEEP(*(.init))
        KEEP(*(.fini))
    } > FLASH

    .rodata :
    {
        *(.rodata .rodata.*)
    } > FLASH

    .ARM.extab :
    {
        *(.ARM.extab*)
    } > FLASH

    .ARM.exidx :
    {
        __exidx_start = .;
        *(.ARM.exidx*)
        __exidx_end = .;
    } > FLASH

    /*
     * crtbegin.o's frame_dummy and __do_global_dtors_aux reference .eh_frame,
     * so it must be placed rather than discarded. Firmware code emits none
     * (-fno-exceptions, -fno-asynchronous-unwind-tables), leaving only a few
     * bytes of C runtime.
     */
    .eh_frame :
    {
        *(.eh_frame)
    } > FLASH

    .preinit_array :
    {
        PROVIDE_HIDDEN(__preinit_array_start = .);
        KEEP(*(.preinit_array*))
        PROVIDE_HIDDEN(__preinit_array_end = .);
    } > FLASH

    .init_array :
    {
        PROVIDE_HIDDEN(__init_array_start = .);
        KEEP(*(SORT(.init_array.*)))
        KEEP(*(.init_array*))
        PROVIDE_HIDDEN(__init_array_end = .);
    } > FLASH

    .fini_array :
    {
        PROVIDE_HIDDEN(__fini_array_start = .);
        KEEP(*(SORT(.fini_array.*)))
        KEEP(*(.fini_array*))
        PROVIDE_HIDDEN(__fini_array_end = .);
    } > FLASH

    /*
     * FAST_CODE, running from ITCM. Instructions come off a bus of their own,
     * so a function here neither waits on flash nor competes with data for the
     * AXI, and needs no instruction cache. The reset path copies it out of
     * flash before SystemInit() enables the MPU, the last point at which ITCM
     * is writable.
     *
     * The first 32 bytes hold 0xDEDE, a permanently undefined instruction, so
     * a call through a null function pointer faults instead of executing
     * whatever was placed at address zero. Written with LONG() rather than as
     * a filled gap: a gap leaves the section NOBITS while no FAST_CODE exists,
     * and a NOBITS section has nothing in flash to copy out of.
     */
    __itcm_load = LOADADDR(.itcm_code);

    .itcm_code : ALIGN(8)
    {
        __itcm_start = .;
        LONG(0xDEDEDEDE); LONG(0xDEDEDEDE); LONG(0xDEDEDEDE); LONG(0xDEDEDEDE);
        LONG(0xDEDEDEDE); LONG(0xDEDEDEDE); LONG(0xDEDEDEDE); LONG(0xDEDEDEDE);
        *(.itcm_code .itcm_code.*)
        . = ALIGN(4);
        __itcm_end = .;
    } > ITCM AT> FLASH

    __data_load = LOADADDR(.data);

    .data : ALIGN(4)
    {
        __data_start = .;
        *(.data .data.*)
        *(.RamFunc .RamFunc.*)      /* flash-write routines must not run from flash */
        . = ALIGN(4);
        __data_end = .;
    } > BULK AT> FLASH

    /*
     * The placement pools. Each name begins with ".bss.", which makes the
     * compiler emit the section NOBITS and reject an initialiser with the
     * offending line named.
     *
     * These must stay ahead of .bss below. Input section matching takes the
     * first pattern that fits and *(.bss.*) there matches every one of these,
     * so moving them after it places all of the pooled data in BULK.
     *
     * "pool" sits in the middle of each name so it cannot collide with the
     * .bss.<name> sections -fdata-sections generates for ordinary variables; a
     * dot cannot appear in a C identifier.
     */

    /*
     * PERSISTENT: survives a warm reset, so nothing zeroes it. Placed first
     * in DTCM, out of reach of both the reset path's .bss loop and the pools
     * below. DTCM rather than BULK because BULK is cached, and a value stored
     * just before a reset can still be in a dirty line when the cache is
     * discarded. SystemInit() validates it against a magic word it keeps in
     * this region and clears the region once, on a cold boot.
     *
     * Its size is worked out here rather than in C: the two bounds are
     * addresses and not storage, so subtracting them there reads as pointer
     * arithmetic over an object that does not exist. __persistent_size is an
     * absolute symbol — its address is the byte count.
     */
    .bss.pool.persistent (NOLOAD) : ALIGN(8)
    {
        __persistent_start = .;
        *(.bss.pool.persistent .bss.pool.persistent.*)
        . = ALIGN(8);
        __persistent_end = .;
    } > DTCM

    __persistent_size = __persistent_end - __persistent_start;

    /* FAST_DATA: DTCM, single-cycle and never cached. */
    .bss.pool.fast (NOLOAD) : ALIGN(4)
    {
        __fast_start = .;
        *(.bss.pool.fast .bss.pool.fast.*)
        . = ALIGN(4);
        __fast_end = .;
    } > DTCM

    /*
     * DMA_DATA and BDMA_DATA. Each pool sits in the domain of the controllers
     * that reach it, and SystemInit() gives each a non-cacheable MPU region,
     * so a buffer here is coherent with no cache maintenance. Cache-line
     * aligned, so a neighbouring pool made cacheable cannot share a line.
     */
    .bss.pool.dma (NOLOAD) : ALIGN(32)
    {
        __dma_start = .;
        *(.bss.pool.dma .bss.pool.dma.*)
        . = ALIGN(32);
        __dma_end = .;
    } > DMAPOOL

    .bss.pool.bdma (NOLOAD) : ALIGN(32)
    {
        __bdma_start = .;
        *(.bss.pool.bdma .bss.pool.bdma.*)
        . = ALIGN(32);
        __bdma_end = .;
    } > BDMAPOOL

    .bss (NOLOAD) : ALIGN(4)
    {
        __bss_start = .;
        *(.bss .bss.*)
        *(COMMON)
        . = ALIGN(4);
        __bss_end = .;
    } > BULK

    /*
     * The symbols above address the stacks from the top of DTCM. Reserve
     * their bytes in the region so the allocator reports what is actually
     * left for FAST_DATA.
     */
    ._stack (NOLOAD) : ALIGN(8)
    {
        . = . + __main_stack_size + __process_stack_size;
        . = ALIGN(8);
    } > DTCM

    .ARM.attributes 0 :
    {
        *(.ARM.attributes)
    }
}

/*
 * The stacks are placed by address arithmetic rather than by the region
 * allocator, so ld does not report a collision with what grows up from the
 * bottom of DTCM. Every other region overflow is reported by name.
 */
ASSERT(__main_thread_stack_base__ >= __fast_end,
       "DTCM overflow: stacks collide with FAST_DATA")
