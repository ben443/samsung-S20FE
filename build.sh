#!/bin/bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
build_tools="${repo_root}/build"
tools_source="https://github.com/Talustus/halium-generic-adaptation-build-tools.git"
tools_revision="a1099f7fff34620f66b1efb690de6e7ce1ee5002"
kernel_revision="d222ac7454ee1e3bf728fbba1347b76397ad5702"
workdir="${repo_root}/workdir"
out="${repo_root}/out"
mode=""
menuconfig=()

usage() {
    echo "Usage: $0 [-b workdir] [-o output] [-c | -k] [-m]"
    echo "Full builds require ROOTFS_ARCHIVE, HALIUM_ARCHIVE and their *_SHA256 values."
    echo "All builds require RAMDISK_ARCHIVE and RAMDISK_SHA256."
}

while (($#)); do
    case "$1" in
        -b|-o)
            [[ $# -ge 2 && -n "$2" && "$2" != -* ]] || { usage >&2; exit 2; }
            path="$(realpath -m -- "$2")"
            if [[ "$1" == -b ]]; then workdir="$path"; else out="$path"; fi
            shift 2 ;;
        -c|-k)
            [[ -z "$mode" ]] || { usage >&2; exit 2; }
            mode="$1"; shift ;;
        -m) menuconfig=(-m); shift ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done

if [[ "$workdir" == / || "$workdir" == "$build_tools" || "$workdir" == "$build_tools/"* ]]; then
    echo "The build workspace must not be / or inside build/." >&2
    exit 2
fi

verify_input() {
    local file="$1" hash="$2"
    [[ -f "$file" && "$hash" =~ ^[[:xdigit:]]{64}$ ]] || {
        echo "A local archive and its SHA256 are required: $file" >&2
        exit 1
    }
    printf '%s  %s\n' "$hash" "$file" | sha256sum --check --status
}

ramdisk="$(realpath -m -- "${RAMDISK_ARCHIVE:?Set RAMDISK_ARCHIVE to a Halium arm64 gzip initrd}")"
verify_input "$ramdisk" "${RAMDISK_SHA256:?Set RAMDISK_SHA256}"
gzip -t "$ramdisk"
if [[ -z "$mode" ]]; then
    ROOTFS_ARCHIVE="$(realpath -m -- "${ROOTFS_ARCHIVE:?Set ROOTFS_ARCHIVE to a Focal arm64 rootfs tar.gz}")"
    HALIUM_ARCHIVE="$(realpath -m -- "${HALIUM_ARCHIVE:?Set HALIUM_ARCHIVE to the Halium 11 arm64 generic tar.xz}")"
    export ROOTFS_ARCHIVE HALIUM_ARCHIVE
    verify_input "$ROOTFS_ARCHIVE" "${ROOTFS_SHA256:?Set ROOTFS_SHA256}"
    verify_input "$HALIUM_ARCHIVE" "${HALIUM_SHA256:?Set HALIUM_SHA256}"
fi

for path in "$repo_root" "$out" "$ramdisk" "${ROOTFS_ARCHIVE:-}" "${HALIUM_ARCHIVE:-}"; do
    if [[ "$path/" == "$workdir/tmp/"* ]]; then
        echo "Inputs, source and output must be outside the workspace's disposable tmp/: $path" >&2
        exit 2
    fi
done

if [[ ! -e "$build_tools" ]]; then
    git init "$build_tools"
    git -C "$build_tools" remote add origin "$tools_source"
    git -C "$build_tools" fetch --depth=1 origin "$tools_revision"
    git -C "$build_tools" checkout --detach FETCH_HEAD
fi
if [[ "$(git -C "$build_tools" rev-parse HEAD)" != "$tools_revision" ]] ||
    [[ -n "$(git -C "$build_tools" status --porcelain)" ]]; then
    echo "build/ must be a clean checkout of $tools_source at $tools_revision; move the old directory aside." >&2
    exit 1
fi

mkdir -p "$workdir/downloads" "$out"
# setup_repositories.sh reuses existing dependencies without checking their revision.
kernel="$workdir/downloads/android_kernel_samsung_sm8250"
if [[ ! -e "$kernel" ]]; then
    git init "$kernel"
    git -C "$kernel" remote add origin "https://github.com/droidian-S20FE/android_kernel_samsung_sm8250.git"
    git -C "$kernel" fetch --depth=1 origin "$kernel_revision"
    git -C "$kernel" checkout --detach FETCH_HEAD
fi
if [[ "$(git -C "$kernel" rev-parse HEAD)" != "$kernel_revision" ]] ||
    [[ -n "$(git -C "$kernel" status --porcelain)" ]]; then
    echo "Cached kernel must be clean and at $kernel_revision; move the old directory aside." >&2
    exit 1
fi
cp "$ramdisk" "$workdir/downloads/halium-boot-ramdisk.img"

cd "${repo_root}"
if [[ "$mode" == -c ]]; then
    exec "$build_tools/build.sh" -b "$workdir" -o "$out" -c
fi
"$build_tools/build.sh" -b "$workdir" -o "$out" -k "${menuconfig[@]}"
cp "$workdir/tmp/partitions/"*.img "$out/"
{
    printf 'build-tools %s\nkernel %s\nramdisk-sha256 %s\n' \
        "$tools_revision" "$kernel_revision" "$RAMDISK_SHA256"
    if [[ -z "$mode" ]]; then
        printf 'rootfs-sha256 %s\nhalium-sha256 %s\n' "$ROOTFS_SHA256" "$HALIUM_SHA256"
    fi
    for dependency in "$workdir/downloads/"*; do
        if [[ -d "$dependency/.git" ]]; then
            printf '%s %s\n' "$(basename "$dependency")" "$(git -C "$dependency" rev-parse HEAD)"
        fi
    done
    for compiler in "$workdir/downloads/linux-x86/"*/bin/clang; do
        [[ ! -f "$compiler" ]] || sha256sum "$compiler"
    done
} > "$out/build-info.txt"
[[ "$mode" == -k ]] && exit 0

"$repo_root/package-device.sh" "$build_tools" "$workdir" "$out"
"$repo_root/build-rootfs.sh" "$out"
