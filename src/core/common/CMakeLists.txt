# core.h, the prelude the rest of the tree includes first: the standard
# headers, the firmware's types and the build identity.
#
# Header-only, included as "core/common/core.h". The include root is src/,
# carried by rfx::common.

target_sources(rfx_core INTERFACE
    # add .cpp files here
)
