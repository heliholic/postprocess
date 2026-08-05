#!/usr/bin/env bash
#
# Refreshes the vendored ChibiOS sources under ext/chibios.
#
# ChibiOS is vendored rather than submoduled for the same reason CMSIS is. This
# firmware uses the RT kernel and the ARMv7-M port and nothing else — no HAL,
# no OSAL, no board files — which is 928 KB out of a 445 MB repository. A
# submodule would put that 445 MB in every clone and every CI job, and would
# leave the unused parts of ChibiOS in the tree.
#
# This script holds no versions of its own. The pin lives in
# ext/chibios/chibios.lock, which is the file to edit to move ChibiOS;
# everything here acts on it. The same data/logic split as
# tools/update-cmsis.sh and cmake/toolchain/arm-gnu-toolchain.lock.cmake.
#
# Usage:
#   tools/update-chibios.sh            vendor what ext/chibios/chibios.lock names
#   tools/update-chibios.sh --check    verify the tree matches its digest

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
chibios_dir="$repo_root/ext/chibios"
lock_file="$chibios_dir/chibios.lock"

# ---------------------------------------------------------------------------
# Reading the pin.
# ---------------------------------------------------------------------------

if [ ! -f "$lock_file" ]; then
    echo "ext/chibios/chibios.lock is missing — there is nothing to vendor from." >&2
    exit 1
fi

# rfx_lock_rows — the data lines of chibios.lock, without comments or
# blanks.
rfx_lock_rows() {
    grep -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' "$lock_file"
}

# rfx_lock_pin <component> — echoes "<repo> <tag> <commit>" for a row of
# chibios.lock. Fails if the component has no row.
rfx_lock_pin() {
    local want=$1 name repo tag commit

    while read -r name repo tag commit _; do
        [ "$name" = "$want" ] || continue
        echo "$repo $tag $commit"
        return 0
    done < <(rfx_lock_rows)

    return 1
}

# rfx_lock_validate — check every row is well formed. Run once up front rather
# than during lookup: a lookup runs in a subshell and cannot fail the script
# from there, and a typo must be reported before anything is fetched.
rfx_lock_validate() {
    local name a b c extra bad=0

    while read -r name a b c extra; do
        if [ "$name" = "digest" ]; then
            if [ -z "$a" ] || [ -n "$b" ]; then
                echo "ext/chibios/chibios.lock: 'digest' row must be: digest <hash>" >&2
                bad=1
            fi
            continue
        fi

        if [ -z "$c" ] || [ -n "$extra" ]; then
            echo "ext/chibios/chibios.lock: row '$name' must be:" >&2
            echo "  <component> <repo> <tag> <commit>" >&2
            bad=1
        fi
    done < <(rfx_lock_rows)

    [ "$bad" -eq 0 ]
}

# rfx_lock_digest — the recorded content hash, empty if there is no row yet.
rfx_lock_digest() {
    local name value
    while read -r name value _; do
        if [ "$name" = "digest" ]; then
            echo "$value"
            return 0
        fi
    done < <(rfx_lock_rows)
}

# rfx_write_digest <hash> — rewrite the digest row in place, leaving the pin
# and the surrounding commentary untouched. This is the only line of
# chibios.lock the script owns.
rfx_write_digest() {
    local digest=$1 tmp
    tmp="$work/chibios.lock"

    if grep -q '^digest[[:space:]]' "$lock_file"; then
        awk -v d="$digest" \
            '/^digest[[:space:]]/ { printf "digest   %s\n", d; next } { print }' \
            "$lock_file" >"$tmp"
    else
        cat "$lock_file" >"$tmp"
        printf '\ndigest   %s\n' "$digest" >>"$tmp"
    fi

    cp "$tmp" "$lock_file"
}

rfx_lock_validate || exit 1

# ---------------------------------------------------------------------------
# What gets vendored.
# ---------------------------------------------------------------------------

# The directories fetched out of the repository. Everything the build compiles
# or includes comes from one of these. The rest of ChibiOS — HAL, OSAL, the
# demos, testhal, the documentation — is never fetched.
sparse_paths=(
    os/license
    os/rt/include
    os/rt/src
    os/rt/templates
    os/oslib/include
    os/oslib/src
    os/common/ports/ARMv7-M
    os/common/ports/ARM-common
    os/common/portability/GCC
    os/common/startup/ARMCMx/devices
    /license.txt
)

# The port's headers arrive from three upstream directories and are flattened
# into one here, so the include path is that directory. They include each other
# by bare name, which the flat layout satisfies.
port_files=(
    "os/common/ports/ARMv7-M/chcore.h"
    "os/common/ports/ARMv7-M/chcore.c"
    "os/common/ports/ARMv7-M/mpu.h"
    "os/common/ports/ARMv7-M/compilers/GCC/chcoreasm.S"
    "os/common/ports/ARM-common/chtypes.h"
    "os/common/portability/GCC/ccportab.h"
)

# The list of MCU families needing a cmparams.h is read from cmake/mcu/, which
# already names the family for every supported MCU. ChibiOS names its device
# directories with an `xx` suffix that RFX_CMSIS_FAMILY does not carry.
#
# rfx_mcu_field <file> <variable> — the value of a `set(<variable> <value>)`.
rfx_mcu_field() {
    sed -n "s/^set($2[ \t]\+\([A-Za-z0-9_.]\+\)).*/\1/p" "$1"
}

# rfx_families — every family named by cmake/mcu/, deduplicated.
rfx_families() {
    local mcu
    for mcu in "$repo_root"/cmake/mcu/*.cmake; do
        rfx_mcu_field "$mcu" RFX_CMSIS_FAMILY
    done | sort -u
}

# rfx_take <relative-path> <destination> — copy one file out of the fetched
# tree, reporting the missing path rather than leaving cp's error unqualified.
rfx_take() {
    local rel=$1 dest=$2

    if [ ! -f "$work/chibios/$rel" ]; then
        echo "ChibiOS has no $rel." >&2
        echo "The layout changed upstream; update the file lists in this script." >&2
        exit 1
    fi

    mkdir -p "$(dirname "$dest")"
    cp "$work/chibios/$rel" "$dest"
}

# rfx_digest — a content hash over every vendored file, so a hand-edited
# upstream source is detected. config/ is excluded: chconf.h is this firmware's
# and is meant to be edited. Paths are relative and sorted, so the digest is
# stable across machines.
rfx_digest() {
    (cd "$chibios_dir" \
        && find license rt oslib port templates LICENSE -type f \
        | LC_ALL=C sort | xargs sha256sum) \
        | sha256sum | cut -d' ' -f1
}

# rfx_fetch <repo> <tag> <commit> — clone the tag into $work/chibios and fail
# if it does not resolve to the pinned commit. A tag can be moved and a commit
# cannot, so the commit is the pin.
#
# Sparse and blobless: the working tree this needs is under a megabyte and the
# repository is 445 MB, nearly all of it HAL ports, demos and documentation
# for hardware this firmware does not run on.
rfx_fetch() {
    local repo=$1 tag=$2 commit=$3 found

    echo "Fetching ChibiOS $tag"
    git -c advice.detachedHead=false clone --quiet --depth 1 \
        --filter=blob:none --sparse --branch "$tag" "$repo" "$work/chibios"

    git -C "$work/chibios" sparse-checkout set --no-cone "${sparse_paths[@]}" \
        >/dev/null

    found=$(git -C "$work/chibios" rev-parse HEAD)
    if [ "$found" != "$commit" ]; then
        echo "" >&2
        echo "ChibiOS $tag does not point at the pinned commit." >&2
        echo "  repo:     $repo" >&2
        echo "  expected: $commit" >&2
        echo "  found:    $found" >&2
        echo "The tag has been moved upstream. Review what changed before" >&2
        echo "updating its row in ext/chibios/chibios.lock." >&2
        exit 1
    fi
}

if [ "${1:-}" = "--check" ]; then
    expected=$(rfx_lock_digest)
    actual=$(rfx_digest)

    if [ -z "$expected" ]; then
        echo "ext/chibios/chibios.lock records no digest — run tools/update-chibios.sh" >&2
        exit 1
    fi

    if [ "$expected" != "$actual" ]; then
        echo "Vendored ChibiOS does not match ext/chibios/chibios.lock." >&2
        echo "  expected: $expected" >&2
        echo "  actual:   $actual" >&2
        echo "Vendored sources are unmodified upstream copies. Either a file" >&2
        echo "was edited by hand, or the tree was updated without re-running" >&2
        echo "tools/update-chibios.sh. Kernel settings belong in" >&2
        echo "ext/chibios/config/chconf.h, which this digest excludes." >&2
        exit 1
    fi

    echo "Vendored ChibiOS matches ext/chibios/chibios.lock."
    exit 0
elif [ $# -ne 0 ]; then
    echo "usage: ${BASH_SOURCE[0]} [--check]" >&2
    exit 2
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

families=$(rfx_families)
if [ -z "$families" ]; then
    echo "No cmake/mcu/*.cmake sets RFX_CMSIS_FAMILY — nothing to vendor." >&2
    exit 1
fi

if ! pin=$(rfx_lock_pin chibios); then
    echo "ext/chibios/chibios.lock has no 'chibios' row." >&2
    exit 1
fi
read -r repo tag commit <<<"$pin"

rfx_fetch "$repo" "$tag" "$commit"

# Staged, then swapped in at the end, so an interrupted run leaves no
# half-updated tree that still looks complete.
staging="$work/staging"
mkdir -p "$staging/rt" "$staging/oslib"

# The kernel, the OS library and the licence headers ch.h includes, each copied
# whole. Sources for subsystems chconf.h disables compile to empty translation
# units, so the file list is independent of the configuration, unlike
# upstream's makefiles.
cp -r "$work/chibios/os/license"       "$staging/license"
cp -r "$work/chibios/os/rt/include"    "$staging/rt/include"
cp -r "$work/chibios/os/rt/src"        "$staging/rt/src"
cp -r "$work/chibios/os/oslib/include" "$staging/oslib/include"
cp -r "$work/chibios/os/oslib/src"     "$staging/oslib/src"

# license.dox and the makefile fragment are documentation and glue for a build
# system this firmware does not use.
rm -f "$staging/license/license.dox" "$staging/license/license.mk"

for file in "${port_files[@]}"; do
    rfx_take "$file" "$staging/port/$(basename "$file")"
done

# cmparams.h describes the Cortex core rather than the peripherals: model, FPU
# presence, priority bits, MPU regions. One per family, each in its own
# directory because both families use the same filename and the include path
# selects between them.
for family in $families; do
    rfx_take "os/common/startup/ARMCMx/devices/${family}xx/cmparams.h" \
             "$staging/port/$family/cmparams.h"
done

# Upstream's chconf.h, kept as the reference the configured copy is diffed
# against on an update. Not compiled and not on any include path; the build
# uses config/chconf.h.
rfx_take "os/rt/templates/chconf.h" "$staging/templates/chconf.h"

rfx_take "license.txt" "$staging/LICENSE"

mkdir -p "$chibios_dir"
rm -rf "$chibios_dir/license" "$chibios_dir/rt" "$chibios_dir/oslib" \
       "$chibios_dir/port" "$chibios_dir/templates" "$chibios_dir/LICENSE"
for item in license rt oslib port templates LICENSE; do
    mv "$staging/$item" "$chibios_dir/$item"
done

rfx_write_digest "$(rfx_digest)"

echo ""
echo "Vendored into ext/chibios:"
rfx_lock_rows | sed 's/^/  /'
