# Third-party code. Everything here is vendored or a git submodule and is built
# with its own warning settings; rfx_apply_warnings() is never applied to these
# targets.
#
# Add each as an INTERFACE or STATIC target so src/ can link it by name rather
# than by include path.
#
# CMSIS is vendored rather than submoduled: it is a small set of headers that
# moves a few times a year, and vendoring means a clone needs no submodule step
# and no build can pick up an unreviewed revision. It changes only when
# tools/update-cmsis.sh is run and the result committed.
#
# ChibiOS is vendored for the same reason. This firmware uses the RT kernel and
# the ARMv7-M port and nothing else, 1 MB out of a 445 MB repository. A
# submodule would put the other 444 MB — HAL ports, demos, testhal — in every
# clone, and leave the unused parts of ChibiOS in the tree.
# tools/update-chibios.sh owns that subset.

if(RFX_TARGET)
    add_subdirectory(cmsis)
    add_subdirectory(chibios)
endif()
