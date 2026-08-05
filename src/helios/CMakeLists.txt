# Helios: the helicopter firmware. Flight control and everything that knows
# what a helicopter is. Builds on rfx::core and never the reverse.

target_sources(rfx_helios INTERFACE
    # add .cpp files here
)

# main() goes to rfx::main, not rfx::helios: the test binary links rfx::helios
# and supplies its own main() from GoogleTest.
target_sources(rfx_main INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}/main.cpp")
