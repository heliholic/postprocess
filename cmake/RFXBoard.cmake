# Resolves the selected board and applies the settings of the MCU it carries.
#
#   board  declares RFX_MCU — the part fitted, e.g. STM32H743xI
#   MCU    supplies architecture flags, startup code and link layout
#
# Included from the top level before any add_subdirectory(). MCU flags apply at
# directory scope so every object in the image is built with the same -mcpu,
# FPU and float ABI, including third-party code under ext/ that links no
# first-party target.
#
# The architecture flags live in cmake/mcu/<mcu>.cmake: build settings rather
# than source, read here before any target exists. The MCU's code stays in
# src/core/platform/.

set(RFX_PLATFORM_DIR "${CMAKE_SOURCE_DIR}/src/core/platform")
set(RFX_DEBUG_DIR "${CMAKE_SOURCE_DIR}/src/debug")
set(RFX_MCU_DIR "${CMAKE_CURRENT_LIST_DIR}/mcu")
set(RFX_TARGETS_DIR "${CMAKE_SOURCE_DIR}/src/targets")
set(RFX_TARGET_DIR "${RFX_TARGETS_DIR}/${RFX_TARGET}")

if(NOT EXISTS "${RFX_TARGET_DIR}/target.cmake")
    file(GLOB boards RELATIVE "${RFX_TARGETS_DIR}" "${RFX_TARGETS_DIR}/*")
    list(REMOVE_ITEM boards CMakeLists.txt)
    message(FATAL_ERROR "Unknown RFX_TARGET '${RFX_TARGET}'. Available: ${boards}")
endif()

include("${RFX_TARGET_DIR}/target.cmake")

if(NOT RFX_MCU)
    message(FATAL_ERROR
        "${RFX_TARGET}/target.cmake must set RFX_MCU to the part fitted on the "
        "board, e.g. set(RFX_MCU STM32H743xI)")
endif()

# The HSE crystal. Every clock in the image derives from it, and a wrong value
# fails silently: the PLL locks either way and everything downstream — SysTick,
# baud rates, timer periods — is off by the ratio. There is no default; the
# board states the frequency and a build without one does not compile.
#
# The list below is what SystemInit() has PLL settings for. Adding a crystal
# means adding those settings; the static assertions beside them check that the
# result is still the SYSCLK the header declares.
set(RFX_HSE_SUPPORTED 8000000 25000000)
list(JOIN RFX_HSE_SUPPORTED ", " RFX_HSE_SUPPORTED_TEXT)

if(NOT RFX_HSE_HZ)
    message(FATAL_ERROR
        "${RFX_TARGET}/target.cmake must set RFX_HSE_HZ to the HSE crystal "
        "frequency fitted on the board, in Hz, e.g. set(RFX_HSE_HZ 8000000).\n"
        "Supported: ${RFX_HSE_SUPPORTED_TEXT}")
endif()

if(NOT RFX_HSE_HZ IN_LIST RFX_HSE_SUPPORTED)
    message(FATAL_ERROR
        "Board '${RFX_TARGET}' sets RFX_HSE_HZ to ${RFX_HSE_HZ}, which this "
        "firmware has no clock configuration for.\n"
        "Supported: ${RFX_HSE_SUPPORTED_TEXT}")
endif()

# What a debugger needs to attach to this board, cached so
# .vscode/launch.json can read them back per active preset with
# `${command:cmake.cacheVariable}` instead of hardcoding one board's values.
# Missing values are a warning, not a build failure: the firmware still
# builds and flashes fine without them, debugging from VS Code just won't
# work until target.cmake sets them.

# Every board provides its own openocd.cfg alongside target.cmake, rather
# than target.cmake naming a stock OpenOCD board file — that keeps the probe
# config next to the board it's wired to, and lets it `source [find ...]` a
# stock file or replace it outright.
set(RFX_OPENOCD_CONFIG "${RFX_TARGET_DIR}/openocd.cfg" CACHE FILEPATH "OpenOCD config for this board" FORCE)

set(RFX_SVD_PATH "${RFX_DEBUG_DIR}/svd/${RFX_SVD_FILE}" CACHE FILEPATH "SVD file for this part" FORCE)
set(RFX_MCU_HZ "${RFX_MCU_HZ}" CACHE STRING "Core clock (SYSCLK), in Hz" FORCE)
set(RFX_SWO_HZ "${RFX_SWO_HZ}" CACHE STRING "SWO trace clock, in Hz" FORCE)

# Two of an MCU's hand-written files share its name. Check both up front so a
# half-added MCU fails here rather than at link time. ST's register map and
# startup file, and this firmware's system source, are named for the part and
# are checked further down, once cmake/mcu/<mcu>.cmake has named them.
set(RFX_MCU_CMAKE     "${RFX_MCU_DIR}/${RFX_MCU}.cmake")
set(RFX_LINKER_SCRIPT "${RFX_PLATFORM_DIR}/linker/${RFX_MCU}.ld")

string(CONCAT RFX_MCU_PIECES
    "cmake/mcu/<mcu>.cmake and src/core/platform/linker/<mcu>.ld")

if(NOT EXISTS "${RFX_MCU_CMAKE}")
    file(GLOB known "${RFX_MCU_DIR}/*.cmake")
    set(supported "")
    foreach(candidate IN LISTS known)
        get_filename_component(name "${candidate}" NAME_WE)
        list(APPEND supported "${name}")
    endforeach()
    message(FATAL_ERROR
        "Unsupported MCU '${RFX_MCU}' (board '${RFX_TARGET}').\n"
        "Adding one means writing both of ${RFX_MCU_PIECES}.\n"
        "Supported MCUs: ${supported}")
endif()

if(NOT EXISTS "${RFX_LINKER_SCRIPT}")
    message(FATAL_ERROR
        "MCU '${RFX_MCU}' is incomplete: ${RFX_LINKER_SCRIPT} is missing.\n"
        "An MCU needs both of ${RFX_MCU_PIECES}.")
endif()

include("${RFX_MCU_CMAKE}")

if(NOT RFX_MCU_FLAGS)
    message(FATAL_ERROR
        "cmake/mcu/${RFX_MCU}.cmake must set RFX_MCU_FLAGS")
endif()

# The part's register map comes from the vendored CMSIS device package, which
# holds headers only for the parts listed in cmake/mcu/. Adding an MCU requires
# re-running tools/update-cmsis.sh to fetch its header. Check that here, so a
# missed run fails the configure rather than the compile.
foreach(piece FAMILY HEADER SYSTEM)
    if(NOT RFX_CMSIS_${piece})
        message(FATAL_ERROR
            "cmake/mcu/${RFX_MCU}.cmake must set RFX_CMSIS_${piece}, naming "
            "what this part takes from the CMSIS device package.")
    endif()
endforeach()

set(RFX_CMSIS_DIR "${CMAKE_SOURCE_DIR}/ext/cmsis/device/${RFX_CMSIS_FAMILY}")

set(RFX_CMSIS_HEADER_PATH "${RFX_CMSIS_DIR}/${RFX_CMSIS_HEADER}")
set(RFX_CMSIS_SYSTEM_PATH "${RFX_CMSIS_DIR}/templates/${RFX_CMSIS_SYSTEM}")

foreach(piece HEADER SYSTEM)
    if(NOT EXISTS "${RFX_CMSIS_${piece}_PATH}")
        message(FATAL_ERROR
            "MCU '${RFX_MCU}' has no vendored CMSIS device file:\n"
            "  ${RFX_CMSIS_${piece}_PATH}\n"
            "Run tools/update-cmsis.sh and commit the result. A family this "
            "firmware has not used before also needs a row in "
            "ext/cmsis/cmsis.lock.")
    endif()
endforeach()

# The reset path itself is this firmware's own: one startup file and one system
# source, both named for the part in cmake/mcu/<mcu>.cmake and both in
# src/core/platform/startup/. Nothing under ext/cmsis/ is compiled into it;
# ST's system source there is a reference for what the silicon expects at
# reset.
#
# Neither has a header of its own: what the pair provides is declared once per
# family, in the header ST's part headers include by bare name.
foreach(piece STARTUP SYSTEM)
    if(NOT RFX_MCU_${piece})
        message(FATAL_ERROR
            "cmake/mcu/${RFX_MCU}.cmake must set RFX_MCU_${piece}, naming "
            "that half of this part's reset path in "
            "src/core/platform/startup/.")
    endif()

    set(RFX_MCU_${piece}_PATH "${RFX_PLATFORM_DIR}/startup/${RFX_MCU_${piece}}")

    if(NOT EXISTS "${RFX_MCU_${piece}_PATH}")
        message(FATAL_ERROR
            "MCU '${RFX_MCU}' has no reset path to compile:\n"
            "  ${RFX_MCU_${piece}_PATH}\n"
            "A part needs both a startup_<part>.s and a system_<part>.c, "
            "written for it. Start from the nearest part's pair and check the "
            "clock tree, the voltage scale, the flash latency and the MPU "
            "regions against the new part.")
    endif()
endforeach()

# No part enables the double-precision FPU, whether or not the silicon has one.
# Firmware math is float, and with the DP instructions out of reach a `double`
# compiles to a soft-float library call that cmake/check_no_double.cmake
# rejects at link time. With a DP FPU enabled that check cannot see anything:
# the arithmetic compiles to VFP instructions and emits no symbol.
foreach(flag IN LISTS RFX_MCU_FLAGS)
    if(flag MATCHES "^-mfpu=" AND NOT flag MATCHES "-sp-")
        message(FATAL_ERROR
            "cmake/mcu/${RFX_MCU}.cmake selects a double-precision FPU "
            "(${flag}). Use the single-precision variant, e.g. "
            "-mfpu=fpv5-sp-d16.")
    endif()
endforeach()

message(STATUS "Board '${RFX_TARGET}' -> MCU ${RFX_MCU}")

add_compile_options(${RFX_MCU_FLAGS})
add_link_options(${RFX_MCU_FLAGS})
add_compile_definitions(
    ${RFX_MCU_DEFINES}
    ${RFX_TARGET_DEFINES}
    RFX_MCU_NAME="${RFX_MCU}"
    RFX_TARGET_NAME="${RFX_TARGET}"

    # ST's name for it, read by system_<part>.c and by any HAL code in the
    # image. The U suffix keeps the divisions in SystemCoreClockUpdate()
    # unsigned, matching ST's own default.
    HSE_VALUE=${RFX_HSE_HZ}U
)
