# MCU-selected code: the reset path and the memory map.
# Board resolution picks the set matching the board being built.
#
#   startup/  ST's startup_<part>.s, vendored from ext/cmsis/, and this
#             firmware's system_<part>.[ch]; both named by cmake/mcu/<mcu>.cmake
#   linker/   <mcu>.ld, one per MCU, named after the part
#
# The part's architecture flags are build settings rather than source and live
# in cmake/mcu/<mcu>.cmake, under the same name.
#
# Only startup/ is a subdirectory of the build. Nothing in linker/ is compiled:
# board resolution resolves the script by path and passes it to the firmware
# image target. Host builds link no image and use none of them.

add_subdirectory(startup)
