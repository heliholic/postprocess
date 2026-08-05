# Project-wide build options.
#
# The board is the only hardware knob. The MCU, the architecture flags, the
# startup code and the link layout all follow from it and cannot be
# overridden.

set(RFX_TARGET "" CACHE STRING "Board to build, from src/targets/ (empty = host build)")

option(RFX_BUILD_TESTS "Build host unit tests" OFF)
option(RFX_WERROR "Treat compiler warnings as errors" OFF)
option(RFX_LTO "Enable link-time optimization for firmware builds" ON)
option(RFX_ASSERTS "Enable runtime assertions" ON)
option(RFX_LAYER_CHECK "Fail the build on a layer dependency violation" ON)

# RFX_MCU is derived, never chosen: the board declares the part it carries.
# Reject any attempt to set it from outside, so a stale cache entry cannot pair
# a board with the wrong architecture or link layout.
if(DEFINED CACHE{RFX_MCU})
    message(WARNING
        "RFX_MCU is derived from the selected board and cannot be set "
        "directly — ignoring the value passed in.")
    unset(RFX_MCU CACHE)
endif()

# Host builds take the startup code named for the machine and link no image.
if(NOT RFX_TARGET)
    set(RFX_MCU "host")
endif()

if(RFX_BUILD_TESTS AND RFX_TARGET)
    message(FATAL_ERROR
        "RFX_BUILD_TESTS is a host build — leave RFX_TARGET empty "
        "(currently '${RFX_TARGET}')")
endif()

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "RelWithDebInfo" CACHE STRING "" FORCE)
endif()
