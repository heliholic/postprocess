# Wire the layer dependency check into the build, so a violation fails a normal
# `cmake --build` and not only CI.

function(rfx_add_layer_check)
    if(NOT RFX_LAYER_CHECK)
        return()
    endif()

    add_custom_target(rfx_layer_check ALL
        COMMAND ${CMAKE_COMMAND}
                -DRFX_SRC_DIR=${CMAKE_SOURCE_DIR}/src
                -P ${CMAKE_SOURCE_DIR}/cmake/check_layering.cmake
        COMMENT "Checking layer dependencies"
        VERBATIM
    )
endfunction()
