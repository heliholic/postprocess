# Pinned Arm GNU Toolchain.
#
# The single source of truth for which compiler builds this firmware. Every
# developer and every CI run uses these exact bytes, verified by hash,
# regardless of what the host distribution ships.
#
# To move to a new release:
#   1. Bump RFX_TOOLCHAIN_VERSION and RFX_TOOLCHAIN_GCC_VERSION.
#   2. Refresh every hash below from ARM's published .sha256asc sidecars:
#        curl -sL <base-url>/<archive>.sha256asc
#   3. Rebuild on each host you support before committing.
#
# Policy: track one major version behind the newest release.

set(RFX_TOOLCHAIN_VERSION     "14.3.rel1")
set(RFX_TOOLCHAIN_GCC_VERSION "14.3.1")

set(RFX_TOOLCHAIN_DEFAULT_BASE_URL
    "https://developer.arm.com/-/media/Files/downloads/gnu/${RFX_TOOLCHAIN_VERSION}/binrel")

# rfx_toolchain_host(<key> <archive-suffix> <sha256>)
macro(rfx_toolchain_host key suffix sha)
    set(RFX_TOOLCHAIN_ARCHIVE_${key}
        "arm-gnu-toolchain-${RFX_TOOLCHAIN_VERSION}-${suffix}")
    set(RFX_TOOLCHAIN_SHA256_${key} "${sha}")
endmacro()

rfx_toolchain_host(Linux_x86_64   "x86_64-arm-none-eabi.tar.xz"
                   "8f6903f8ceb084d9227b9ef991490413014d991874a1e34074443c2a72b14dbd")
rfx_toolchain_host(Linux_aarch64  "aarch64-arm-none-eabi.tar.xz"
                   "2d465847eb1d05f876270494f51034de9ace9abe87a4222d079f3360240184d3")
rfx_toolchain_host(Darwin_arm64   "darwin-arm64-arm-none-eabi.tar.xz"
                   "30f4d08b219190a37cded6aa796f4549504902c53cfc3c7e044a8490b6eba1f7")
rfx_toolchain_host(Windows_AMD64  "mingw-w64-x86_64-arm-none-eabi.zip"
                   "864c0c8815857d68a1bbba2e5e2782255bb922845c71c97636004a3d74f60986")

# ARM publishes no Intel macOS build at 14.3.rel1; 13.3.rel1 was the last
# release with a darwin-x86_64 archive. Intel Macs need RFX_TOOLCHAIN_DIR
# pointing at a local 14.3.1 build, or Rosetta with the arm64 archive. Handled
# explicitly in provision.cmake, so the failure is a clear message rather than
# a 404.
