# Third-party code. Everything here is vendored or a git submodule and is built
# with its own warning settings; rfx_apply_warnings() is never applied to these
# targets.
#
# Add each as an INTERFACE or STATIC target so src/ can link it by name rather
# than by include path.
