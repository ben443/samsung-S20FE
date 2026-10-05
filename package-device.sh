#!/bin/bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
tools="$(realpath -- "$1")"
workdir="$(realpath -- "$2")"
out="$(realpath -- "$3")"
system="$workdir/tmp/system"

# Keep the versioned Linux module tree, and expose flat Android insmod paths too.
if [[ -d "$system/lib/modules" ]]; then
    find "$system/lib/modules" -type l \( -name build -o -name source \) -delete
    modules="$system/usr/share/halium-overlay/android/system/lib/modules"
    mkdir -p "$modules"
    cp -a "$system/lib/modules/." "$modules/"
    while IFS= read -r -d '' module; do
        name="$(basename "$module")"
        [[ ! -e "$modules/$name" && ! -L "$modules/$name" ]] || {
            echo "Duplicate Android module name: $name" >&2
            exit 1
        }
        ln -s "${module#"$modules/"}" "$modules/$name"
    done < <(find "$modules" -type f -name '*.ko' -print0)
    # Merge at lib/ so modules/ can be added even when absent in the GSI.
    touch "$modules/../.halium-overlay-dir"
    vendor="$system/usr/share/halium-overlay/android/vendor/lib/modules"
    mkdir -p "$vendor"
    cp -a "$modules/." "$vendor/"
    # Merge with vendor modules rather than hiding firmware-supplied drivers.
    touch "$vendor/../.halium-overlay-dir"
fi

cd "$repo_root"
"$tools/build-tarball-mainline.sh" r8q "$out" "$workdir/tmp" usrmerge
