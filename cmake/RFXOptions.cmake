# Project-wide build options.

option(RFX_BUILD_TESTS "Build host unit tests" OFF)
option(RFX_WERROR "Treat compiler warnings as errors" OFF)
option(RFX_LTO "Enable link-time optimization for firmware builds" ON)
option(RFX_ASSERTS "Enable runtime assertions" ON)
option(RFX_LAYER_CHECK "Fail the build on a layer dependency violation" ON)

# Host builds take the startup code named for the machine and link no image.
if(NOT RFX_TARGET)
    set(RFX_MCU "host")
endif()

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "RelWithDebInfo" CACHE STRING "" FORCE)
endif()
