# Writes a firmware image to the board over USB DFU. Run in script mode:
#   cmake -DRFX_DFU_UTIL=<dfu-util> -DRFX_IMAGE=<bin> -DRFX_FLASH_ORIGIN=<addr>
#         -P cmake/flash.cmake
#
# The board must be in DFU mode, where it enumerates as ST's ROM bootloader.
# Alternate setting 0 is internal flash. The image is a raw .bin and is written
# at the flash origin from the MCU's memory map.

cmake_minimum_required(VERSION 3.24)

foreach(var RFX_IMAGE RFX_FLASH_ORIGIN)
    if(NOT DEFINED ${var})
        message(FATAL_ERROR "flash.cmake: ${var} must be set")
    endif()
endforeach()

# ST's ROM bootloader. Naming it keeps the download off any other DFU device on
# the bus.
set(rfx_dfu_id 0483:df11)

if(NOT RFX_DFU_UTIL)
    message(FATAL_ERROR
        "dfu-util was not found. Flashing over USB needs it on PATH; install "
        "it and configure again.")
endif()

if(NOT EXISTS "${RFX_IMAGE}")
    message(FATAL_ERROR "flash.cmake: no image at ${RFX_IMAGE}")
endif()

get_filename_component(image "${RFX_IMAGE}" NAME)
message(STATUS "Flashing ${image} to ${RFX_FLASH_ORIGIN} over DFU")

execute_process(
    COMMAND "${RFX_DFU_UTIL}"
            -d "${rfx_dfu_id}"
            -a 0
            -s "${RFX_FLASH_ORIGIN}:leave"
            -D "${RFX_IMAGE}"
    RESULT_VARIABLE result
)

if(NOT result EQUAL 0)
    message(FATAL_ERROR
        "dfu-util failed (${result}). The board has to be in DFU mode and no "
        "other process holding it.\n"
        "A bootloader that enumerated badly reports LIBUSB_ERROR_OVERFLOW or "
        "unreadable descriptors; replug it and try again.")
endif()
