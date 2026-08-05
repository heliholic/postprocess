# CMSIS: ARM's Cortex-M core support, and ST's register map for the part.
#
# Two upstreams, so two targets. Link cmsis::device: the ST headers include
# core_cm7.h, so the dependency points this way.
#
# Vendored, not a submodule. See README.md for provenance and how to update.
#
# Include paths are SYSTEM. The firmware compiles with -Wconversion,
# -Wsign-conversion, -Wundef and -Wcast-qual, which vendor register maps do not
# compile cleanly under.

add_library(cmsis_core INTERFACE)
add_library(cmsis::core ALIAS cmsis_core)

target_include_directories(cmsis_core SYSTEM INTERFACE
    "${CMAKE_CURRENT_SOURCE_DIR}/core"
)

add_library(cmsis_device INTERFACE)
add_library(cmsis::device ALIAS cmsis_device)

target_link_libraries(cmsis_device INTERFACE cmsis::core)

target_include_directories(cmsis_device SYSTEM INTERFACE
    "${CMAKE_CURRENT_SOURCE_DIR}/device/${RFX_CMSIS_FAMILY}"

    # Every ST part header includes system_<family>.h by bare name. The copy
    # satisfying it is this firmware's and sits with the rest of the reset
    # path. Carried here rather than by rfx::core because the requirement
    # belongs to these headers: anything linking cmsis::device needs it as
    # well.
    "${CMAKE_SOURCE_DIR}/src/core/platform/startup"
)

# Headers only. The vendored templates/ files — ST's system_<family>.c and
# startup_<part>.s — are sources of no target. The compiled reset path lives in
# core/platform/startup/, and these copies define the same Reset_Handler,
# Default_Handler and core exception handlers, so adding them to a target fails
# the link. See README.md.
