# Host unit tests.
#
# Links rfx::helios but not rfx::main: the test binary brings its own main().

include(FetchContent)

FetchContent_Declare(googletest
    GIT_REPOSITORY https://github.com/google/googletest.git
    GIT_TAG        v1.15.2
    GIT_SHALLOW    TRUE
    FIND_PACKAGE_ARGS NAMES GTest
)
FetchContent_MakeAvailable(googletest)

add_executable(rfx_tests)
add_subdirectory(unit)
add_subdirectory(mocks)

target_include_directories(rfx_tests PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}")
target_link_libraries(rfx_tests PRIVATE rfx::helios GTest::gtest_main GTest::gmock)
rfx_apply_warnings(rfx_tests)

include(GoogleTest)
gtest_discover_tests(rfx_tests)
