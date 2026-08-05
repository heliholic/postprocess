# The board interface core requires from whichever target is being built.
# Header-only: board targets supply the definitions, bound at link time so
# core never depends on a target directory.
#
# version.c turns the build defines carried by rfx::common into linkable
# constants naming the board and the part. It is C, so the code below main()
# reads the same constants the firmware does.

target_sources(rfx_core INTERFACE
    "${CMAKE_CURRENT_SOURCE_DIR}/version.c"
)
