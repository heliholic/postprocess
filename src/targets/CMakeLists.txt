# Board targets.
#
# cmake/RFXBoard.cmake has already resolved the board, derived its MCU and
# applied the architecture flags to every directory, and has set
# RFX_LINKER_SCRIPT and RFX_TARGET_SOURCES.
#
# Application sources arrive through rfx::main. Only board-specific files
# belong here.

rfx_add_firmware(rfx_${RFX_TARGET}
    SOURCES       ${RFX_TARGET_SOURCES}
    LINKER_SCRIPT "${RFX_LINKER_SCRIPT}"
)
