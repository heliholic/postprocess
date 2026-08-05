# Layer dependency check. Run in script mode:
#   cmake -DRFX_SRC_DIR=<path> -P cmake/check_layering.cmake
#
# Scans includes rather than relying on the link graph: CMake permits
# dependency cycles between STATIC libraries, so a wrong-direction #include
# still links.

cmake_minimum_required(VERSION 3.24)

if(NOT DEFINED RFX_SRC_DIR)
    message(FATAL_ERROR "check_layering.cmake: RFX_SRC_DIR must be set")
endif()

set(violations "")

# rfx_scan_layer(<layer> <forbidden>...) — report any include of a forbidden
# layer from within <layer>.
function(rfx_scan_layer layer)
    file(GLOB_RECURSE sources
        "${RFX_SRC_DIR}/${layer}/*.c"
        "${RFX_SRC_DIR}/${layer}/*.cpp"
        "${RFX_SRC_DIR}/${layer}/*.h"
        "${RFX_SRC_DIR}/${layer}/*.hpp"
    )

    foreach(forbidden IN LISTS ARGN)
        foreach(source IN LISTS sources)
            file(STRINGS "${source}" hits
                 REGEX "^[ \t]*#[ \t]*include[ \t]*[\"<]${forbidden}/")

            foreach(hit IN LISTS hits)
                file(RELATIVE_PATH rel "${RFX_SRC_DIR}" "${source}")
                string(STRIP "${hit}" hit)
                list(APPEND violations "  ${rel}\n      ${hit}")
            endforeach()
        endforeach()
    endforeach()

    set(violations "${violations}" PARENT_SCOPE)
endfunction()

rfx_scan_layer(core helios targets)
rfx_scan_layer(helios targets)

if(violations)
    list(JOIN violations "\n" report)
    message(FATAL_ERROR
        "Layer violation — dependencies must point downward "
        "(main -> helios -> core -> common):\n${report}")
endif()
