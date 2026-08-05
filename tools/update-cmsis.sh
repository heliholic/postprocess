#!/usr/bin/env bash
#
# Refreshes the vendored CMSIS headers under ext/cmsis.
#
# CMSIS is vendored rather than submoduled: the headers live in this repository
# and change only when ext/cmsis/cmsis.lock is edited, this script is run and
# the result committed. A clone needs no submodule step, and a build cannot
# pick up a revision other than the one reviewed.
#
# CMSIS arrives from two upstreams, because it is two things:
#
#   core    ARM's Cortex-M core support: core_cm7.h, the intrinsics, and the
#           cache and MPU helpers. Taken from ARM-software/CMSIS_6, where it is
#           developed, rather than the frozen CMSIS 5.9.0 copy ST ships with
#           Cube.
#   device  The register maps and the IRQn_Type list, per part. Only ST
#           publishes these, in one standalone repository per family.
#
# This script holds no versions of its own. The pins live in
# ext/cmsis/cmsis.lock, which is the file to edit to move CMSIS; everything
# here acts on it. Changing a version is a data change, not a code change — the
# same split as cmake/toolchain/arm-gnu-toolchain.lock.cmake and
# provision.cmake.
#
# Usage:
#   tools/update-cmsis.sh            vendor what ext/cmsis/cmsis.lock names
#   tools/update-cmsis.sh --check    verify the tree matches its digest

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cmsis_dir="$repo_root/ext/cmsis"
lock_file="$cmsis_dir/cmsis.lock"

# ---------------------------------------------------------------------------
# Reading the pins.
# ---------------------------------------------------------------------------

if [ ! -f "$lock_file" ]; then
    echo "ext/cmsis/cmsis.lock is missing — there is nothing to vendor from." >&2
    exit 1
fi

# rfx_lock_rows — the data lines of cmsis.lock, without comments or blanks.
rfx_lock_rows() {
    grep -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' "$lock_file"
}

# rfx_lock_pin <component> — echoes "<repo> <tag> <commit>" for a row of
# cmsis.lock. Fails if the component has no row, which catches an unpinned MCU
# family.
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
                echo "ext/cmsis/cmsis.lock: 'digest' row must be: digest <hash>" >&2
                bad=1
            fi
            continue
        fi

        if [ -z "$c" ] || [ -n "$extra" ]; then
            echo "ext/cmsis/cmsis.lock: row '$name' must be:" >&2
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

# rfx_write_digest <hash> — rewrite the digest row in place, leaving the pins
# and the surrounding commentary untouched. This is the only line of cmsis.lock
# the script owns.
rfx_write_digest() {
    local digest=$1 tmp
    tmp="$work/cmsis.lock"

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

# The list of parts to vendor headers for is read from cmake/mcu/, which
# already names the family and the part header for every supported MCU. Adding
# an MCU needs no edit here, nor in cmsis.lock unless it brings in a family
# with no row yet.
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

# rfx_mcu_files <family> <variable> — the value of <variable> for every MCU of
# that family, deduplicated. Parts of one family commonly share ST's system
# source while each has its own register map.
rfx_mcu_files() {
    local family=$1 var=$2 mcu

    for mcu in "$repo_root"/cmake/mcu/*.cmake; do
        if [ "$(rfx_mcu_field "$mcu" RFX_CMSIS_FAMILY)" = "$family" ]; then
            rfx_mcu_field "$mcu" "$var"
        fi
    done | sort -u
}

# rfx_family_headers <family> — the umbrella header, plus one part header per
# MCU of that family.
#
# ST's system header is not in this list. Every part header includes it by bare
# name, and the copy satisfying that include is this tree's, in
# src/core/platform/startup/. ST's goes to templates/ alongside the source it
# declares, off the include path.
rfx_family_headers() {
    local family=$1 lower
    lower=$(echo "$family" | tr '[:upper:]' '[:lower:]')

    echo "${lower}xx.h"

    rfx_mcu_files "$family" RFX_CMSIS_HEADER
}

# rfx_family_system_header <family> — ST's system header for a family. One per
# family, named after it, regardless of which system source a part selects.
rfx_family_system_header() {
    local lower
    lower=$(echo "$1" | tr '[:upper:]' '[:lower:]')

    echo "system_${lower}xx.h"
}

# rfx_take <component> <relative-path> <destination> — copy one file out of a
# fetched component, reporting the missing path rather than leaving cp's error
# unqualified.
rfx_take() {
    local component=$1 rel=$2 dest=$3

    if [ ! -f "$work/$component/$rel" ]; then
        echo "$component has no $rel." >&2
        echo "Check the RFX_CMSIS_* names in cmake/mcu/ against the package." >&2
        exit 1
    fi

    mkdir -p "$(dirname "$dest")"
    cp "$work/$component/$rel" "$dest"
}

# rfx_digest — a content hash over every vendored file, so a hand-edited
# upstream header is detected. Paths are relative and sorted, so the digest is
# stable across machines.
rfx_digest() {
    (cd "$cmsis_dir" && find core device -type f | LC_ALL=C sort | xargs sha256sum) \
        | sha256sum | cut -d' ' -f1
}

# rfx_fetch <name> <repo> <tag> <commit> — clone the tag into $work/<name> and
# fail if it does not resolve to the pinned commit. A tag can be moved and a
# commit cannot, so the commit is the pin.
rfx_fetch() {
    local name=$1 repo=$2 tag=$3 commit=$4 found

    echo "Fetching $name $tag"
    git -c advice.detachedHead=false clone --quiet --depth 1 \
        --branch "$tag" "$repo" "$work/$name"

    found=$(git -C "$work/$name" rev-parse HEAD)
    if [ "$found" != "$commit" ]; then
        echo "" >&2
        echo "$name $tag does not point at the pinned commit." >&2
        echo "  repo:     $repo" >&2
        echo "  expected: $commit" >&2
        echo "  found:    $found" >&2
        echo "The tag has been moved upstream. Review what changed before" >&2
        echo "updating its row in ext/cmsis/cmsis.lock." >&2
        exit 1
    fi
}

if [ "${1:-}" = "--check" ]; then
    expected=$(rfx_lock_digest)
    actual=$(rfx_digest)

    if [ -z "$expected" ]; then
        echo "ext/cmsis/cmsis.lock records no digest — run tools/update-cmsis.sh" >&2
        exit 1
    fi

    if [ "$expected" != "$actual" ]; then
        echo "Vendored CMSIS does not match ext/cmsis/cmsis.lock." >&2
        echo "  expected: $expected" >&2
        echo "  actual:   $actual" >&2
        echo "Vendored headers are unmodified upstream copies. Either a file" >&2
        echo "was edited by hand, or the tree was updated without re-running" >&2
        echo "tools/update-cmsis.sh." >&2
        exit 1
    fi

    echo "Vendored CMSIS matches ext/cmsis/cmsis.lock."
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

# Staged, then swapped in at the end, so an interrupted run leaves no
# half-updated tree that still looks complete.
staging="$work/staging"
mkdir -p "$staging/device"

if ! core_pin=$(rfx_lock_pin core); then
    echo "ext/cmsis/cmsis.lock has no 'core' row naming ARM's CMSIS." >&2
    exit 1
fi
read -r core_repo core_tag core_commit <<<"$core_pin"

rfx_fetch core "$core_repo" "$core_tag" "$core_commit"

# The whole Core include directory, verbatim, flattened into core/ so the
# include path is that directory. Its own subdirectories (m-profile/ and the
# rest) are taken as they are, since core_cm7.h includes through them by
# relative path. Taking only the Cortex-M7 headers would save 2 MB at the cost
# of a file list that breaks whenever ARM restructures the tree, as it did
# moving the M-profile headers into m-profile/ for CMSIS 6.
mkdir -p "$staging/core"
cp -r "$work/core/CMSIS/Core/Include/." "$staging/core/"
cp "$work/core/LICENSE" "$staging/core/LICENSE"

# Device headers are picked per part. Each family ships every part it covers in
# one directory — 19 MB for F7, 43 MB for H7 — of which this firmware runs on
# one.
for family in $families; do
    if ! pin=$(rfx_lock_pin "$family"); then
        echo "No CMSIS device package pinned for family '$family'." >&2
        echo "cmake/mcu/ names it, so it needs a row in ext/cmsis/cmsis.lock." >&2
        exit 1
    fi
    read -r repo tag commit <<<"$pin"

    rfx_fetch "$family" "$repo" "$tag" "$commit"

    dest="$staging/device/$family"
    rfx_take "$family" LICENSE.md "$dest/LICENSE.md"

    # Headers sit at the top of the family directory rather than under ST's
    # Include/, so the include path is the family directory itself.
    for header in $(rfx_family_headers "$family" | sort -u); do
        rfx_take "$family" "Include/$header" "$dest/$header"
    done

    # ST's system source and its header go to templates/, as the reference for
    # what the silicon expects at reset. Nothing in templates/ is compiled or
    # on the include path; see ext/cmsis/README.md. The startup files are not
    # taken: this tree's are its own, in src/core/platform/startup/.
    system_header=$(rfx_family_system_header "$family")
    rfx_take "$family" "Include/$system_header" "$dest/templates/$system_header"

    for system in $(rfx_mcu_files "$family" RFX_CMSIS_SYSTEM); do
        rfx_take "$family" "Source/Templates/$system" "$dest/templates/$system"
    done
done

mkdir -p "$cmsis_dir"
rm -rf "$cmsis_dir/core" "$cmsis_dir/device"
mv "$staging/core" "$cmsis_dir/core"
mv "$staging/device" "$cmsis_dir/device"

rfx_write_digest "$(rfx_digest)"

echo ""
echo "Vendored into ext/cmsis:"
rfx_lock_rows | sed 's/^/  /'
