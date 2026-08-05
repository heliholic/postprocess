# The "operating system" layer: scheduling, time, memory, synchronisation and
# hardware access. Nothing here may know what a helicopter is.
#
# Holds no sources of its own. Every component gets a subdirectory.

add_subdirectory(common)
add_subdirectory(platform)
