#!/bin/bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
out="$(realpath -- "$1")"
rootfs="$(realpath -- "${ROOTFS_ARCHIVE:?Set ROOTFS_ARCHIVE}")"
halium="$(realpath -- "${HALIUM_ARCHIVE:?Set HALIUM_ARCHIVE}")"

verify_input() {
    local file="$1" hash="$2"
    [[ "$hash" =~ ^[[:xdigit:]]{64}$ ]]
    printf '%s  %s\n' "$hash" "$file" | sha256sum --check --status
}
verify_input "$rootfs" "${ROOTFS_SHA256:?Set ROOTFS_SHA256}"
verify_input "$halium" "${HALIUM_SHA256:?Set HALIUM_SHA256}"

# Real privilege is needed for security.capability xattrs; fakeroot loses them.
if ((EUID != 0)); then
    exec sudo --preserve-env=ROOTFS_ARCHIVE,ROOTFS_SHA256,HALIUM_ARCHIVE,HALIUM_SHA256,ROOTFS_SIZE \
        "$repo_root/build-rootfs.sh" "$out"
fi

stage="$(mktemp -d)"
trap 'rm -rf -- "$stage"' EXIT
mkdir "$stage/system"
tar --extract --gzip --file "$rootfs" --numeric-owner --xattrs --xattrs-include='*' --acls -C "$stage/system"
grep -q '^VERSION_ID="20.04"$' "$stage/system/etc/os-release"
[[ "$(readlink "$stage/system/lib")" == usr/lib &&
    -x "$stage/system/usr/libexec/lxc-android-config/mount-halium-overlay" ]] || {
    echo "Expected a usrmerged Focal hybris rootfs with mount-halium-overlay support." >&2
    exit 1
}
# Generic Halium and device archives use system/ and partitions/ OTA prefixes.
tar --extract --xz --file "$halium" --numeric-owner --keep-directory-symlink \
    --xattrs --xattrs-include='*' --acls -C "$stage"
consumer="$stage/system/usr/libexec/lxc-android-config/mount-halium-overlay"
[[ -x "$consumer" && ! -e "$consumer.generic" ]] || {
    echo "Expected an unwrapped Focal mount-halium-overlay consumer." >&2
    exit 1
}
mv "$consumer" "$stage/generic-consumer"
tar --extract --xz --file "$out/device_r8q.tar.xz" --numeric-owner --keep-directory-symlink \
    --xattrs --xattrs-include='*' --acls -C "$stage"
cp -a "$stage/generic-consumer" "$consumer.generic"
cmp "$repo_root/overlay/system/usr/libexec/lxc-android-config/mount-halium-overlay" "$consumer"
# Export a self-contained adaptation archive for this exact Focal input too.
mkdir "$stage/device"
tar --extract --xz --file "$out/device_r8q.tar.xz" --numeric-owner -C "$stage/device"
cp -a "$stage/generic-consumer" \
    "$stage/device/system/usr/libexec/lxc-android-config/mount-halium-overlay.generic"
tar --create --xz --file "$out/device_r8q.tar.xz" --owner=0 --group=0 --xattrs --acls \
    -C "$stage/device" system partitions
android="$stage/system/var/lib/lxc/android"
if [[ -f "$android/system.img" && ! -e "$android/android-rootfs.img" ]]; then
    mv "$android/system.img" "$android/android-rootfs.img"
fi
[[ -s "$android/android-rootfs.img" ]] || {
    echo "The generic Halium archive did not provide an Android rootfs image." >&2
    exit 1
}
cmp "$repo_root/overlay/system/etc/gbinder.conf" "$stage/system/etc/gbinder.conf"
cmp "$repo_root/overlay/system/usr/share/halium-overlay/android/vendor/etc/init/vndservicemanager.rc" \
    "$stage/system/usr/share/halium-overlay/android/vendor/etc/init/vndservicemanager.rc"

# Populate ext4 without loop mounts; disable features unsupported by Focal recovery.
truncate -s "${ROOTFS_SIZE:-4G}" "$out/ubuntu.img"
mke2fs -q -t ext4 -b 4096 -O '^metadata_csum,^64bit' \
    -F -d "$stage/system" "$out/ubuntu.img"
if dumpe2fs -h "$out/ubuntu.img" 2>/dev/null | grep 'orphan_file' >/dev/null; then
    tune2fs -O '^orphan_file' "$out/ubuntu.img"
fi
e2fsck -fn "$out/ubuntu.img"
cp "$stage/partitions/"*.img "$out/"
(
    cd "$out"
    sha256sum ./*.img device_r8q.tar.xz > SHA256SUMS
)
chown "${SUDO_UID:-0}:${SUDO_GID:-0}" "$out/"*.img "$out/SHA256SUMS" "$out/device_r8q.tar.xz"
