# NEXUS board.
#
# Data only: sets variables and nothing else. Read at top-level scope before
# any target exists.
#
# The board declares the part it is built around. Everything downstream is
# derived and cannot be overridden. RFX_MCU selects:
#
#   cmake/mcu/<mcu>.cmake                  -mcpu, FPU, float ABI, part defines,
#                                          and which CMSIS files the part takes
#   src/core/platform/startup/             ST's startup and system sources,
#                                          named by that .cmake file
#   src/core/platform/linker/<mcu>.ld      memory map and section layout
#
# Only board-level facts belong here: the sources describing this hardware, and
# defines specific to the board rather than to the part.

# MCU fitted on this board.
set(RFX_MCU STM32F722xE)

# The clock speeds on this platform.
set(RFX_MCU_HZ 216000000)
set(RFX_HSE_HZ 8000000)
set(RFX_SWO_HZ 2000000)

# System View Description for the debugger
set(RFX_SVD_FILE "stm32f722.svd")


## Files and defines specific to this board

set(RFX_TARGET_SOURCES
    "${CMAKE_CURRENT_LIST_DIR}/board.c"
)

set(RFX_TARGET_DEFINES
    # Board-specific defines go here; part-wide ones come from the MCU.
)
