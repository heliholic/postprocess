# The layer stack. Link direction is one-way:
#
#   main  ->  helios  ->  core  ->  common
#
#   common  Settings every compiled unit needs: include root, build defines.
#   core    The "operating system" layer — scheduling, time, memory, sync,
#           and hardware access. Knows nothing about flight control.
#   helios  The helicopter firmware. Built on core, never the reverse.
#   main    main() and startup glue.
#
# The direction is checked on every build by cmake/check_layering.cmake; see
# rfx_add_layer_check() at the bottom of this file.
#
# core and helios are INTERFACE targets while they have no sources. Make them
# STATIC once they do.

add_library(rfx_common INTERFACE)
add_library(rfx::common ALIAS rfx_common)

target_include_directories(rfx_common INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}")

target_compile_definitions(rfx_common INTERFACE
    RFX_VERSION_MAJOR=${PROJECT_VERSION_MAJOR}
    RFX_VERSION_MINOR=${PROJECT_VERSION_MINOR}
    RFX_VERSION_PATCH=${PROJECT_VERSION_PATCH}
    $<$<NOT:$<BOOL:${RFX_ASSERTS}>>:RFX_NO_ASSERT>
)

# On a board build RFX_TARGET_NAME and RFX_MCU_NAME come from board
# resolution at top-level scope.
if(NOT RFX_TARGET)
    target_compile_definitions(rfx_common INTERFACE
        RFX_TARGET_NAME="${RFX_MCU}"
        RFX_MCU_NAME="${RFX_MCU}"
    )
endif()

add_library(rfx_core INTERFACE)
add_library(rfx::core ALIAS rfx_core)
target_link_libraries(rfx_core INTERFACE rfx::common)

# Hardware access and scheduling belong to core, so CMSIS and the kernel attach
# here and reach the layers above, including src/targets/, whose board code
# needs the same register map. Board builds only: the host has no register map.
#
# Both ride the INTERFACE link until core has sources of its own. Once core is
# STATIC, make chibios::rt PRIVATE to it so ch.h stops being reachable from
# helios/ and targets/ and core/rtos/ becomes the only route to the kernel.
# cmake/check_layering.cmake scans first-party includes only and does not catch
# this.
if(RFX_TARGET)
    target_link_libraries(rfx_core INTERFACE cmsis::device chibios::rt)
endif()

add_library(rfx_helios INTERFACE)
add_library(rfx::helios ALIAS rfx_helios)
target_link_libraries(rfx_helios INTERFACE rfx::core)

# main() stays out of rfx::helios so the test binary can link the code under
# test without colliding with GoogleTest's own main(). The source lives in
# helios/ and attaches itself to this target from there.
add_library(rfx_main INTERFACE)
add_library(rfx::main ALIAS rfx_main)
target_link_libraries(rfx_main INTERFACE rfx::helios)

add_subdirectory(core)
add_subdirectory(helios)

if(RFX_TARGET)
    add_subdirectory(targets)
endif()

rfx_add_layer_check()
