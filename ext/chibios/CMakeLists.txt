# ChibiOS/RT: the kernel, and nothing else.
#
# No HAL, no OSAL, no board files, no mcuconf.h. The HAL is the half of ChibiOS
# that drives peripherals, and this firmware drives its own. The two are
# separable by design — the HAL reaches the kernel through OSAL and the kernel
# reaches nothing — so the kernel alone is a supported configuration.
#
# What the kernel requires from the hardware is listed in
# ext/chibios/README.md: SysTick from src/core/rtos/, SVC from the port itself,
# and the process stack from src/core/platform/startup/.
#
# Vendored, not a submodule. See README.md for provenance and how to update.
#
# Board builds only. The ARMv7-M port is the only one vendored, so a host build
# compiles nothing here; core/ reaches the kernel through its own interface.

add_library(chibios STATIC)
add_library(chibios::rt ALIAS chibios)

# The file set is upstream's and is changed by tools/update-chibios.sh. Globbed
# for that reason: a release that adds a kernel source compiles it rather than
# linking an image silently missing it. Sources for subsystems chconf.h
# switches off are still compiled — they guard their whole contents and produce
# empty objects — so the list is independent of the configuration, unlike
# upstream's makefiles.
file(GLOB chibios_sources CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/rt/src/*.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/oslib/src/*.c"
)

target_sources(chibios PRIVATE
    ${chibios_sources}

    # The port: C where possible, plus the context switch, which cannot be.
    # chcoreasm.S is preprocessed — it includes chconf.h and chcore.h with
    # _FROM_ASM_ defined — so it needs the same include path as the C, which
    # target_include_directories supplies for every language.
    "${CMAKE_CURRENT_SOURCE_DIR}/port/chcore.c"
    "${CMAKE_CURRENT_SOURCE_DIR}/port/chcoreasm.S"
)

# All five directories are include roots rather than a tree to walk: ChibiOS
# headers include each other by bare name throughout, which is also why the
# port's three upstream directories are flattened into port/ here.
#
#   config/   chconf.h — hand-written, the one file here that is not vendored
#   license/  chlicense.h and the version headers ch.h opens with
#   rt/       the kernel API
#   oslib/    mailboxes, pools and the rest of the OS library
#   port/     the ARMv7-M port, plus cmparams.h for the family being built
#
# SYSTEM, as CMSIS's are: this firmware builds with -Wconversion,
# -Wsign-conversion, -Wundef and -Wcast-qual, which these headers do not
# compile cleanly under.
target_include_directories(chibios SYSTEM PUBLIC
    "${CMAKE_CURRENT_SOURCE_DIR}/config"
    "${CMAKE_CURRENT_SOURCE_DIR}/license"
    "${CMAKE_CURRENT_SOURCE_DIR}/rt/include"
    "${CMAKE_CURRENT_SOURCE_DIR}/oslib/include"
    "${CMAKE_CURRENT_SOURCE_DIR}/port"
    "${CMAKE_CURRENT_SOURCE_DIR}/port/${RFX_CMSIS_FAMILY}"
)

# cmparams.h describes the Cortex core — model, FPU, priority bits, MPU
# regions — and cross-checks each against the CMSIS part header it includes.
# The dependency reaches consumers of ch.h, so it is PUBLIC.
target_link_libraries(chibios PUBLIC cmsis::device)

# Not LTO'd. The kernel is assembly, naked functions and weak handlers intended
# to be overridden from other objects — the same arrangement as the vector
# table. The firmware image is still built with RFX_LTO; a static library of
# ordinary objects links into it unchanged.
set_target_properties(chibios PROPERTIES INTERPROCEDURAL_OPTIMIZATION FALSE)

# Warnings are not applied here: rfx_apply_warnings() is for first-party
# targets. Vendored code is compiled as it arrived.
