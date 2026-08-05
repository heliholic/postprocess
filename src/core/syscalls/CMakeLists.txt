# The syscalls newlib expects an operating system to provide. All of them fail.
#
# Board builds only. A host build runs under a real kernel and takes the real
# syscalls; defining these there would replace them.
#
# Without these the toolchain links its own stubs from libnosys, four of which
# carry a .gnu.warning section the linker prints on every build.

if(RFX_TARGET)
    target_sources(rfx_core INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}/syscalls.c")
endif()
