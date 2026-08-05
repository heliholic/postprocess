cmake_minimum_required(VERSION 3.24)

# Configure with e.g.:
#   cmake --preset host-test

project(rfx-firmware
    VERSION 0.1.0
    DESCRIPTION "Rotorflight X flight control firmware"
    LANGUAGES C CXX ASM
)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")

include(RFXOptions)
include(RFXWarnings)
include(RFXLayering)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

add_subdirectory(ext)
add_subdirectory(src)

if(RFX_BUILD_TESTS)
    enable_testing()
    add_subdirectory(test)
endif()

message(STATUS "----------------------------------------------------------")
message(STATUS "  ${PROJECT_NAME} ${PROJECT_VERSION}")
message(STATUS "  build  : ${CMAKE_BUILD_TYPE}")
message(STATUS "  tests  : ${RFX_BUILD_TESTS}")
message(STATUS "----------------------------------------------------------")
