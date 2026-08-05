# STM32F722xE — Cortex-M7, single-precision FPU, 512 KB flash.
#
# ST's xE suffix is the flash size, 512K; the 256K part is xC and is a separate
# MCU with its own two files, since the memory map differs. The x denotes
# pinout, package and temperature grade, none of which affect the build.
#
# Architecture flags and part-wide defines. Read at top-level scope by board
# resolution before any target exists, so it sets variables only.
#
# The part's code lives elsewhere: the reset path in
# src/core/platform/startup/, named by RFX_MCU_STARTUP and RFX_MCU_SYSTEM
# below, and the memory map in src/core/platform/linker/STM32F722xE.ld.

# The FPU is single-precision only, which is all the firmware uses. `double`
# has no hardware behind it and compiles to a soft-float library call the link
# check rejects.
set(RFX_MCU_FLAGS
    -mcpu=cortex-m7
    -mthumb
    -mfpu=fpv5-sp-d16
    -mfloat-abi=hard
)

set(RFX_MCU_DEFINES
    # Selects the register headers in the CMSIS device package. ST's xx is
    # flash-agnostic — the register map is the same on xC and xE — so this is
    # broader than the MCU name above, which names the memory map.
    STM32F722xx
)

# What this part takes from the vendored CMSIS device package, under
# ext/cmsis/device/<family>/. All three are read by tools/update-cmsis.sh. Each
# is named explicitly rather than derived from the define above: ST's naming is
# a convention rather than a rule, and the H7 ships several system sources.
#
#   HEADER   <family>/            register map and IRQn_Type list
#   SYSTEM   <family>/templates/  ST's SystemInit(), reference only
set(RFX_CMSIS_FAMILY STM32F7)
set(RFX_CMSIS_HEADER stm32f722xx.h)
set(RFX_CMSIS_SYSTEM system_stm32f7xx.c)

# This part's reset path, in src/core/platform/startup/. Both files are this
# firmware's own and named for the part rather than the family: the vector
# table, the clock tree, the flash timing and the MPU regions are the part's and
# stay private to it. What the pair exports is declared once per family, in
# system_stm32f7xx.h.
set(RFX_MCU_STARTUP startup_stm32f722xx.s)
set(RFX_MCU_SYSTEM  system_stm32f722xx.c)
