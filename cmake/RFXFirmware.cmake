# Helpers for producing a flashable firmware image.

# dfu-util is needed only by the `flash` target, so a missing one is not a
# configure error: the target is still created and cmake/flash.cmake reports
# the absence, with installation advice, when flashing is attempted. Cached, so
# a build outside PATH can be selected with -D.
find_program(RFX_DFU_UTIL dfu-util
    DOC "dfu-util, used by the `flash` target to write images over USB")

# rfx_flash_origin(<linker script> <out var>)
#
# The address a raw .bin is written to. This is ORIGIN(FLASH) in the memory
# map, read back out of the linker script rather than restated in
# cmake/mcu/<mcu>.cmake, so there is one definition of it.
function(rfx_flash_origin script out)
    file(READ "${script}" contents)

    if(NOT contents MATCHES "FLASH[ \t]*\\([^)]*\\)[ \t]*:[ \t]*ORIGIN[ \t]*=[ \t]*(0[xX][0-9a-fA-F]+)")
        message(FATAL_ERROR
            "${script} declares no FLASH region this build can read an ORIGIN "
            "from. The `flash` target needs it: a .bin carries no addresses, "
            "so the origin has to come from the memory map. Expected a MEMORY "
            "entry of the form:\n"
            "  FLASH (rx) : ORIGIN = 0x08000000, LENGTH = ...")
    endif()

    set(${out} "${CMAKE_MATCH_1}" PARENT_SCOPE)
endfunction()

# rfx_add_firmware(<name> SOURCES ... LINKER_SCRIPT <path> [LIBS ...])
#
# Build an ELF, emit .hex/.bin beside it, and print the section sizes so flash
# and RAM pressure are visible on every build.
function(rfx_add_firmware name)
    cmake_parse_arguments(ARG "" "LINKER_SCRIPT" "SOURCES;LIBS" ${ARGN})

    if(NOT ARG_LINKER_SCRIPT)
        message(FATAL_ERROR "rfx_add_firmware(${name}): LINKER_SCRIPT is required")
    endif()

    add_executable(${name} ${ARG_SOURCES})
    set_target_properties(${name} PROPERTIES SUFFIX ".elf")

    target_link_libraries(${name} PRIVATE rfx::main ${ARG_LIBS})
    rfx_apply_warnings(${name})

    # <mcu>.ld pulls in the shared section layout with INCLUDE, which searches
    # the -L paths rather than the including script's directory.
    get_filename_component(linker_dir "${ARG_LINKER_SCRIPT}" DIRECTORY)

    target_link_options(${name} PRIVATE
        -T${ARG_LINKER_SCRIPT}
        -L${linker_dir}
        -Wl,--gc-sections
        -Wl,--print-memory-usage
        # .RamFunc places executable code in RAM, which requires an RWX
        # segment.
        -Wl,--no-warn-rwx-segments
        -Wl,-Map=$<TARGET_FILE_DIR:${name}>/${name}.map
        --specs=nano.specs
        --specs=nosys.specs
    )

    set_target_properties(${name} PROPERTIES
        LINK_DEPENDS "${ARG_LINKER_SCRIPT};${linker_dir}/sections_cm7.ld")

    if(RFX_LTO)
        set_target_properties(${name} PROPERTIES INTERPROCEDURAL_OPTIMIZATION TRUE)
    endif()

    # Reject the image if double arithmetic reached it. Registered first, so a
    # rejected image produces no .hex/.bin.
    add_custom_command(TARGET ${name} POST_BUILD
        COMMAND ${CMAKE_COMMAND}
                -DRFX_NM=${CMAKE_NM}
                -DRFX_IMAGE=$<TARGET_FILE:${name}>
                -P ${CMAKE_SOURCE_DIR}/cmake/check_no_double.cmake
        COMMENT "Checking ${name}.elf for double-precision arithmetic"
        VERBATIM
    )

    add_custom_command(TARGET ${name} POST_BUILD
        COMMAND ${CMAKE_OBJCOPY} -O ihex   $<TARGET_FILE:${name}> $<TARGET_FILE_DIR:${name}>/${name}.hex
        COMMAND ${CMAKE_OBJCOPY} -O binary $<TARGET_FILE:${name}> $<TARGET_FILE_DIR:${name}>/${name}.bin
        COMMAND ${CMAKE_SIZE} --format=berkeley $<TARGET_FILE:${name}>
        COMMENT "Generating ${name}.hex / ${name}.bin"
        VERBATIM
    )

    # `cmake --build --preset <board>-build --target flash` writes the image
    # over USB DFU. Kept out of ALL: it touches hardware, so it runs only when
    # named.
    #
    # One image per build tree, so the target is `flash` rather than named
    # after the board.
    if(TARGET flash)
        message(FATAL_ERROR
            "rfx_add_firmware(${name}): a `flash` target already exists. "
            "Flashing assumes one image per build tree; a tree building two "
            "would need per-image target names.")
    endif()

    # The origin is read at configure time, so an edited memory map requires a
    # re-configure to take effect.
    set_property(DIRECTORY APPEND PROPERTY
        CMAKE_CONFIGURE_DEPENDS "${ARG_LINKER_SCRIPT}")

    rfx_flash_origin("${ARG_LINKER_SCRIPT}" flash_origin)

    add_custom_target(flash
        COMMAND ${CMAKE_COMMAND}
                -DRFX_DFU_UTIL=${RFX_DFU_UTIL}
                -DRFX_IMAGE=$<TARGET_FILE_DIR:${name}>/${name}.bin
                -DRFX_FLASH_ORIGIN=${flash_origin}
                -P ${CMAKE_SOURCE_DIR}/cmake/flash.cmake
        DEPENDS ${name}
        COMMENT "Flashing ${name}.bin over DFU"
        USES_TERMINAL
        VERBATIM
    )
endfunction()
