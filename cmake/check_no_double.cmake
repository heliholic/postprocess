# Double-precision check. Run in script mode:
#   cmake -DRFX_NM=<nm> -DRFX_IMAGE=<elf> -P cmake/check_no_double.cmake
#
# No MCU enables the double-precision FPU, so every `double` operation compiles
# to a call into the soft-float routines in libgcc. A soft-float symbol in the
# image therefore means double arithmetic reached it: hundreds of cycles where
# a float costs one instruction.
#
# -Werror=double-promotion catches a float silently widened. This catches what
# it cannot: code that asks for double outright, and double arithmetic pulled
# in from a library.

cmake_minimum_required(VERSION 3.24)

foreach(var RFX_NM RFX_IMAGE)
    if(NOT DEFINED ${var})
        message(FATAL_ERROR "check_no_double.cmake: ${var} must be set")
    endif()
endforeach()

# Soft-float double routines, in the two naming schemes libgcc uses: the AEABI
# helpers (__aeabi_dadd, __aeabi_f2d) and the generic ones (__muldf3,
# __extendsfdf2, __fixdfsi, __floatsidf). Single-precision names end in `sf`
# and never match.
set(rfx_double_symbols
    "^__aeabi_(d[a-z0-9_]*|[a-z]+2d)$"
    "^__(add|sub|mul|div|neg|eq|ne|lt|le|gt|ge|unord|cmp|powi)df[23]$"
    "^__(extendsfdf2|truncdfsf2)$"
    "^__fix(uns)?df[a-z]+$"
    "^__float[a-z]*df$"
)

execute_process(
    COMMAND "${RFX_NM}" --format=posix "${RFX_IMAGE}"
    OUTPUT_VARIABLE symbols
    RESULT_VARIABLE result
    ERROR_VARIABLE error
)

if(NOT result EQUAL 0)
    message(FATAL_ERROR "check_no_double.cmake: nm failed on ${RFX_IMAGE}:\n${error}")
endif()

string(REPLACE "\n" ";" lines "${symbols}")

set(found "")
foreach(line IN LISTS lines)
    # posix format: "<name> <type> [value] [size]"
    string(REGEX MATCH "^[^ ]+" name "${line}")

    foreach(pattern IN LISTS rfx_double_symbols)
        if(name MATCHES "${pattern}")
            list(APPEND found "  ${name}")
            break()
        endif()
    endforeach()
endforeach()

if(found)
    list(REMOVE_DUPLICATES found)
    list(SORT found)
    list(JOIN found "\n" report)
    get_filename_component(image "${RFX_IMAGE}" NAME)
    message(FATAL_ERROR
        "${image} contains double-precision arithmetic. Firmware math is "
        "float:\n${report}\n"
        "Use float literals (1.0f), the float math functions (sqrtf, sinf, "
        "cosf) and float parameters. The map file names the caller.")
endif()
