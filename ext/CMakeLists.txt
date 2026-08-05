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

if(RFX_TARGET)
    add_subdirectory(cmsis)
endif()
