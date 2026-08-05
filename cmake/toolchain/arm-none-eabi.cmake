# Bare-metal ARM Cortex-M toolchain file.
#
# The compiler is pinned and provisioned automatically: see
# arm-gnu-toolchain.lock.cmake for the version and hashes, provision.cmake for
# the fetch. Compilers are referenced by absolute path inside tools/, so a
# stray arm-none-eabi-gcc earlier on PATH is never picked up.
#
# The MCU-specific flags (-mcpu, FPU) come from the selected board. This file
# establishes the cross-compiler only.

set(CMAKE_SYSTEM_NAME Generic)
set(CMAKE_SYSTEM_PROCESSOR arm)

include("${CMAKE_CURRENT_LIST_DIR}/arm-gnu-toolchain.lock.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/provision.cmake")

rfx_provision_toolchain(RFX_TOOLCHAIN_ROOT)

set(_bin "${RFX_TOOLCHAIN_ROOT}/bin")
if(CMAKE_HOST_SYSTEM_NAME STREQUAL "Windows")
    set(_exe ".exe")
else()
    set(_exe "")
endif()

set(CMAKE_C_COMPILER   "${_bin}/arm-none-eabi-gcc${_exe}"         CACHE FILEPATH "")
set(CMAKE_CXX_COMPILER "${_bin}/arm-none-eabi-g++${_exe}"         CACHE FILEPATH "")
set(CMAKE_ASM_COMPILER "${_bin}/arm-none-eabi-gcc${_exe}"         CACHE FILEPATH "")
set(CMAKE_AR           "${_bin}/arm-none-eabi-gcc-ar${_exe}"      CACHE FILEPATH "")
set(CMAKE_RANLIB       "${_bin}/arm-none-eabi-gcc-ranlib${_exe}"  CACHE FILEPATH "")
set(CMAKE_NM           "${_bin}/arm-none-eabi-nm${_exe}"          CACHE FILEPATH "")
set(CMAKE_OBJCOPY      "${_bin}/arm-none-eabi-objcopy${_exe}"     CACHE FILEPATH "")
set(CMAKE_OBJDUMP      "${_bin}/arm-none-eabi-objdump${_exe}"     CACHE FILEPATH "")
set(CMAKE_SIZE         "${_bin}/arm-none-eabi-size${_exe}"        CACHE FILEPATH "")
set(CMAKE_GDB          "${_bin}/arm-none-eabi-gdb${_exe}"         CACHE FILEPATH "")

if(NOT EXISTS "${CMAKE_C_COMPILER}")
    message(FATAL_ERROR "Provisioned toolchain is missing ${CMAKE_C_COMPILER}")
endif()

rfx_verify_toolchain_version("${CMAKE_C_COMPILER}")

# The cross-compiler cannot produce runnable host executables. Building a
# static library is sufficient to validate it.
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)

set(CMAKE_FIND_ROOT_PATH "${RFX_TOOLCHAIN_ROOT}")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# Freestanding C++: no exceptions, no RTTI, no static-init guards, and one
# section per function and datum so --gc-sections can drop what is unused.
add_compile_options(
    -ffunction-sections
    -fdata-sections
    -fno-common
    -fmessage-length=0
    -fno-unwind-tables
    -fno-asynchronous-unwind-tables
    $<$<COMPILE_LANGUAGE:CXX>:-fno-exceptions>
    $<$<COMPILE_LANGUAGE:CXX>:-fno-rtti>
    $<$<COMPILE_LANGUAGE:CXX>:-fno-threadsafe-statics>
    $<$<COMPILE_LANGUAGE:CXX>:-fno-use-cxa-atexit>
)

set(CMAKE_C_FLAGS_DEBUG            "-Og -g3" CACHE STRING "")
set(CMAKE_CXX_FLAGS_DEBUG          "-Og -g3" CACHE STRING "")
set(CMAKE_C_FLAGS_RELWITHDEBINFO   "-O2 -g3 -DNDEBUG" CACHE STRING "")
set(CMAKE_CXX_FLAGS_RELWITHDEBINFO "-O2 -g3 -DNDEBUG" CACHE STRING "")
set(CMAKE_C_FLAGS_RELEASE          "-O2 -DNDEBUG" CACHE STRING "")
set(CMAKE_CXX_FLAGS_RELEASE        "-O2 -DNDEBUG" CACHE STRING "")
set(CMAKE_C_FLAGS_MINSIZEREL       "-Os -DNDEBUG" CACHE STRING "")
set(CMAKE_CXX_FLAGS_MINSIZEREL     "-Os -DNDEBUG" CACHE STRING "")
