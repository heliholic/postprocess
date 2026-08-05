# STM32H723xG — Cortex-M7, 1 MB flash.
#
# ST's xG suffix is the flash size, 1M; the 512K part is xE and is a separate
# MCU with its own two files, since the memory map differs. The x denotes
# pinout, package and temperature grade, none of which affect the build.
#
# Architecture flags and part-wide defines. Read at top-level scope by board
# resolution before any target exists, so it sets variables only.
#
# The part's code lives elsewhere: the reset path in
# src/core/platform/startup/, named by RFX_MCU_STARTUP and RFX_MCU_SYSTEM
# below, and the memory map in src/core/platform/linker/STM32H723xG.ld.

# The part has a double-precision FPU; the build selects its single-precision
# subset. Firmware math is `float`, and with the DP instructions out of reach
# any `double` compiles to a soft-float call the link check rejects. This also
# avoids GCC PR 102018, which requires `+fp.dp`.
set(RFX_MCU_FLAGS
    -mcpu=cortex-m7
    -mthumb
    -mfpu=fpv5-sp-d16
    -mfloat-abi=hard
)

set(RFX_MCU_DEFINES
    # Selects the register headers in the CMSIS device package. ST's xx is
    # flash-agnostic — the register map is the same on xE and xG — so this is
    # broader than the MCU name above, which names the memory map.
    STM32H723xx
)

# What this part takes from the vendored CMSIS device package, under
# ext/cmsis/device/<family>/. All three are read by tools/update-cmsis.sh. Each
# is named explicitly rather than derived from the define above: ST's naming is
# a convention rather than a rule, and the H7 ships several system sources.
#
#   HEADER   <family>/            register map and IRQn_Type list
#   SYSTEM   <family>/templates/  ST's SystemInit(), reference only
set(RFX_CMSIS_FAMILY STM32H7)
set(RFX_CMSIS_HEADER stm32h723xx.h)
set(RFX_CMSIS_SYSTEM system_stm32h7xx.c)

# This part's reset path, in src/core/platform/startup/. Both files are this
# firmware's own and named for the part rather than the family: the vector
# table, the clock tree, the voltage scale and the MPU regions are the part's
# and stay private to it. What the pair exports is declared once per family,
# in system_stm32h7xx.h.
set(RFX_MCU_STARTUP startup_stm32h723xx.s)
set(RFX_MCU_SYSTEM  system_stm32h723xx.c)
