# Fetches the pinned Arm GNU Toolchain into tools/ on demand.
#
# Called from the toolchain file, which runs before project(), so a fresh clone
# needs no bootstrap step: `cmake --preset stm32h743-release` provisions the
# compiler and builds. Downloads are hash-verified and land in tools/.cache.
# Extraction is atomic, so an interrupted run leaves no half-unpacked tree that
# later looks complete.
#
# Overrides (cache variables):
#   RFX_TOOLCHAIN_DIR  use this toolchain instead, skipping the download
#                      entirely. Still version-checked.
#   RFX_TOOLCHAIN_URL  full URL to the archive. Points at a mirror when ARM
#                      changes its download paths, without a code change.

include_guard(GLOBAL)

# rfx_provision_toolchain(<out-var>) — sets <out-var> to the toolchain root
# (the directory containing bin/).
function(rfx_provision_toolchain out_var)
    if(RFX_TOOLCHAIN_DIR)
        set(${out_var} "${RFX_TOOLCHAIN_DIR}" PARENT_SCOPE)
        return()
    endif()

    # Derived from this file's location, never CMAKE_SOURCE_DIR: during
    # try_compile that points at a scratch project and would provision a second
    # copy there.
    get_filename_component(repo_root "${CMAKE_CURRENT_LIST_DIR}/../.." ABSOLUTE)
    set(tools_dir "${repo_root}/tools")
    set(cache_dir "${tools_dir}/.cache")

    cmake_host_system_information(RESULT host_arch QUERY OS_PLATFORM)
    set(key "${CMAKE_HOST_SYSTEM_NAME}_${host_arch}")

    if(NOT DEFINED RFX_TOOLCHAIN_ARCHIVE_${key})
        if(key STREQUAL "Darwin_x86_64")
            message(FATAL_ERROR
                "Arm GNU Toolchain ${RFX_TOOLCHAIN_VERSION} has no Intel macOS "
                "build — ARM stopped publishing darwin-x86_64 after 13.3.rel1.\n"
                "Install GCC ${RFX_TOOLCHAIN_GCC_VERSION} yourself and configure "
                "with -DRFX_TOOLCHAIN_DIR=<path>.")
        endif()
        message(FATAL_ERROR
            "No pinned Arm GNU Toolchain for host '${key}'.\n"
            "Add it to cmake/toolchain/arm-gnu-toolchain.lock.cmake, or "
            "configure with -DRFX_TOOLCHAIN_DIR=<path>.")
    endif()

    set(archive "${RFX_TOOLCHAIN_ARCHIVE_${key}}")
    set(sha256 "${RFX_TOOLCHAIN_SHA256_${key}}")

    # Archives unpack to a directory named after themselves, minus suffix.
    string(REGEX REPLACE "\\.(tar\\.xz|zip)$" "" install_name "${archive}")
    set(install_dir "${tools_dir}/${install_name}")

    if(EXISTS "${install_dir}/bin")
        set(${out_var} "${install_dir}" PARENT_SCOPE)
        return()
    endif()

    if(RFX_TOOLCHAIN_URL)
        set(url "${RFX_TOOLCHAIN_URL}")
    else()
        set(url "${RFX_TOOLCHAIN_DEFAULT_BASE_URL}/${archive}")
    endif()

    set(archive_path "${cache_dir}/${archive}")

    if(NOT EXISTS "${archive_path}")
        message(STATUS "Fetching Arm GNU Toolchain ${RFX_TOOLCHAIN_VERSION} for ${key}")
        message(STATUS "  ${url}")

        file(DOWNLOAD "${url}" "${archive_path}.part"
             EXPECTED_HASH SHA256=${sha256}
             SHOW_PROGRESS
             STATUS status)

        list(GET status 0 code)
        if(NOT code EQUAL 0)
            list(GET status 1 reason)
            file(REMOVE "${archive_path}.part")
            message(FATAL_ERROR
                "Toolchain download failed (${reason}).\n"
                "  url: ${url}\n"
                "If ARM has moved this file, pass -DRFX_TOOLCHAIN_URL=<mirror>.")
        endif()

        file(RENAME "${archive_path}.part" "${archive_path}")
    endif()

    # The cache persists across runs and machines, so verify before every
    # extraction rather than only after a download.
    file(SHA256 "${archive_path}" actual_sha)
    if(NOT actual_sha STREQUAL sha256)
        file(REMOVE "${archive_path}")
        message(FATAL_ERROR
            "Toolchain archive failed hash verification and was deleted.\n"
            "  file:     ${archive_path}\n"
            "  expected: ${sha256}\n"
            "  actual:   ${actual_sha}\n"
            "Re-run to fetch it again.")
    endif()

    message(STATUS "Extracting ${archive}")
    set(staging "${tools_dir}/.staging-${install_name}")
    file(REMOVE_RECURSE "${staging}")
    file(ARCHIVE_EXTRACT INPUT "${archive_path}" DESTINATION "${staging}")

    if(NOT EXISTS "${staging}/${install_name}/bin")
        message(FATAL_ERROR
            "Unexpected archive layout: ${staging}/${install_name}/bin missing")
    endif()

    file(RENAME "${staging}/${install_name}" "${install_dir}")
    file(REMOVE_RECURSE "${staging}")

    set(${out_var} "${install_dir}" PARENT_SCOPE)
endfunction()

# rfx_verify_toolchain_version(<compiler>) — fails on any version mismatch.
function(rfx_verify_toolchain_version compiler)
    execute_process(
        COMMAND "${compiler}" -dumpversion
        OUTPUT_VARIABLE found
        OUTPUT_STRIP_TRAILING_WHITESPACE
        RESULT_VARIABLE result
        ERROR_QUIET
    )

    if(NOT result EQUAL 0)
        message(FATAL_ERROR "Could not run ${compiler} to check its version")
    endif()

    if(NOT found VERSION_EQUAL RFX_TOOLCHAIN_GCC_VERSION)
        message(FATAL_ERROR
            "Toolchain version mismatch: found GCC ${found}, "
            "require ${RFX_TOOLCHAIN_GCC_VERSION}.\n"
            "  compiler: ${compiler}\n"
            "This build pins its compiler so every machine produces the same "
            "firmware. Fix the pin in cmake/toolchain/arm-gnu-toolchain.lock.cmake "
            "or drop the RFX_TOOLCHAIN_DIR override.")
    endif()
endfunction()
