Development scripts: flashing, debugging, config generation.

The pinned Arm GNU Toolchain is also provisioned into this directory on the
first ARM configure — `arm-gnu-toolchain-<version>-<host>/`, with downloads
cached in `.cache/`. Both are gitignored; delete them to force a re-fetch.
The version and hashes live in
[../cmake/toolchain/arm-gnu-toolchain.lock.cmake](../cmake/toolchain/arm-gnu-toolchain.lock.cmake).
