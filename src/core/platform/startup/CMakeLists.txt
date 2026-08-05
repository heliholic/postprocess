# The reset path: everything that runs before the C runtime exists. C and
# assembly only, never C++, and none of it declares C++ linkage — a common
# header states that once and C++ reaches these headers through it.
#
#   startup_<part>.s    vector table, reset entry, and the bring-up of every
#                       section the linker script places: ITCM, .data, .bss and
#                       the placement pools. It calls systemPreInit() before
#                       them and SystemInit() after, then __libc_init_array()
#                       and main().
#   system_<part>.c     systemPreInit() — the core supply on the H7, the clock
#                       tree, flash timing, and the SRAM clocks — and
#                       SystemInit() — FPU, VTOR, PERSISTENT, MPU, caches. The
#                       frequencies they program stay private to the file;
#                       sysClockHz() is what the rest of the image reads.
#   system_<family>.h   the name ST's part headers include, with no path.
#                       Declares what every part of the family provides, and
#                       holds no value of its own. This is why the directory is
#                       on the include path.
#
# All of it is first-party. The startup files began as the GCC templates in
# ST's CMSIS device package and keep their vector tables, which name the
# part's interrupts in the order the NVIC takes them; the reset path above the
# table is this tree's. ST's system sources stay in
# ext/cmsis/device/<family>/templates/ as a reference for what the silicon
# expects at reset.
#
# A part is named for itself rather than for its family because its contents
# are the part's: one clock tree, one voltage scale, one set of MPU regions.
# Adding a part to a family already present is one startup_<part>.s, one
# system_<part>.c and a line in cmake/mcu/<mcu>.cmake; the family header needs
# no edit.
#
# Taking over an interrupt needs no registration and no edit to a table: every
# vector is weak and resolves to a spinning Default_Handler, so defining a
# function with the CMSIS name — SysTick_Handler, TIM2_IRQHandler — anywhere in
# the image replaces it. The full list for a part is the .weak block at the
# bottom of its startup file.
#
# Both filenames come from cmake/mcu/<mcu>.cmake. Host builds compile none of
# this: it links against section bounds only a board's linker script defines.

if(RFX_TARGET)
    # List the assembly first so the object defining the weak handlers precedes
    # those that override them. The reverse order is a documented failure mode
    # for weak ISR symbols under LTO.
    target_sources(rfx_core INTERFACE
        "${CMAKE_CURRENT_SOURCE_DIR}/${RFX_MCU_STARTUP}"
        "${CMAKE_CURRENT_SOURCE_DIR}/${RFX_MCU_SYSTEM}"
    )

    target_include_directories(rfx_core INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}")
endif()
