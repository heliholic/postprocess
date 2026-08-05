# The kernel's binding to this tree: what ChibiOS/RT needs from the hardware
# that its own HAL would otherwise supply, which is the system tick and nothing
# else.
#
# Board builds only. The vendored port is ARMv7-M and compiles on no host; a
# host build would reach concurrency through core's own interface instead.

if(RFX_TARGET)
    target_sources(rfx_core INTERFACE
        "${CMAKE_CURRENT_SOURCE_DIR}/rtos.c"
    )
endif()
