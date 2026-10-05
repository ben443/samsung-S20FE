#!/bin/bash
set -euo pipefail

repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT
mkdir -p "$fixture/tools" "$fixture/work/tmp/partitions" "$fixture/out"
modules="$fixture/work/tmp/system/lib/modules/test-release/kernel/drivers"
mkdir -p "$modules"
printf 'module fixture\n' > "$modules/test.ko"
cp "$modules/test.ko" "$fixture/test.ko"
ln -s /nonexistent/kernel/source "$modules/../../build"
ln -s /nonexistent/kernel/source "$modules/../../source"
printf 'r8q boot fixture\n' > "$fixture/work/tmp/partitions/boot.img"

# Model only the inspected packager's overlay copy, usrmerge and archive contract.
cat > "$fixture/tools/build-tarball-mainline.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
[[ "$1" == r8q && "$4" == usrmerge && -f deviceinfo ]]
cp -a overlay/. "$3/"
mkdir -p "$3/system/usr"
if [[ -d "$3/system/lib" ]]; then
    cp -a "$3/system/lib" "$3/system/usr/"
    rm -rf "$3/system/lib"
fi
tar -cJf "$2/device_r8q.tar.xz" --owner=0 --group=0 -C "$3" system partitions
EOF
chmod +x "$fixture/tools/build-tarball-mainline.sh"
cd /tmp
bash "$repo/package-device.sh" "${PACKAGING_TOOLS:-"$fixture/tools"}" "$fixture/work" "$fixture/out"
system="$fixture/work/tmp/system"
cmp "$fixture/test.ko" "$system/usr/lib/modules/test-release/kernel/drivers/test.ko"
for partition in system vendor; do
    android="$system/usr/share/halium-overlay/android/$partition/lib/modules"
    cmp "$android/test.ko" "$system/usr/lib/modules/test-release/kernel/drivers/test.ko"
    [[ "$(readlink "$android/test.ko")" == test-release/kernel/drivers/test.ko ]]
    [[ ! -L "$android/test-release/build" && ! -L "$android/test-release/source" ]]
done
[[ -f "$system/usr/share/halium-overlay/android/system/lib/.halium-overlay-dir" ]]
[[ -f "$system/usr/share/halium-overlay/android/vendor/lib/.halium-overlay-dir" ]]

base="$fixture/base"
generic="$fixture/generic"
mkdir -p "$base/etc" "$base/usr/libexec/lxc-android-config" "$base/usr/lib" \
    "$generic/system/var/lib/lxc/android" "$generic/partitions"
ln -s usr/lib "$base/lib"
printf 'VERSION_ID="20.04"\n' > "$base/etc/os-release"
cat > "$base/usr/libexec/lxc-android-config/mount-halium-overlay" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$base/usr/libexec/lxc-android-config/mount-halium-overlay"
printf 'preserved Focal rootfs\n' > "$base/etc/base-file"
printf 'preserved service ownership\n' > "$base/etc/service-file"
python3 - "$base/etc/base-file" <<'PY'
import os
import sys
os.setxattr(sys.argv[1], "user.r8q-test", b"preserved")
PY
printf 'Halium 13 Android rootfs fixture\n' > "$generic/system/var/lib/lxc/android/system.img"
printf 'must be replaced by device boot\n' > "$generic/partitions/boot.img"
tar --xattrs --acls -cf "$fixture/rootfs.tar" --owner=0 --group=0 -C "$base" .
tar -rf "$fixture/rootfs.tar" --owner=42 --group=42 -C "$base" etc/service-file
gzip "$fixture/rootfs.tar"
tar -cJf "$fixture/halium.tar.xz" --owner=0 --group=0 -C "$generic" system partitions
export ROOTFS_ARCHIVE="$fixture/rootfs.tar.gz" HALIUM_ARCHIVE="$fixture/halium.tar.xz" ROOTFS_SIZE=32M
ROOTFS_SHA256="$(sha256sum "$ROOTFS_ARCHIVE" | cut -d' ' -f1)"
HALIUM_SHA256="$(sha256sum "$HALIUM_ARCHIVE" | cut -d' ' -f1)"
export ROOTFS_SHA256 HALIUM_SHA256
bash "$repo/build-rootfs.sh" "$fixture/out"
cmp "$fixture/out/boot.img" "$fixture/work/tmp/partitions/boot.img"
for path in /etc/base-file /etc/gbinder.conf \
    /usr/libexec/lxc-android-config/mount-halium-overlay \
    /usr/libexec/lxc-android-config/mount-halium-overlay.generic \
    /usr/lib/modules/test-release/kernel/drivers/test.ko \
    /usr/share/halium-overlay/android/vendor/etc/init/vndservicemanager.rc \
    /var/lib/lxc/android/android-rootfs.img; do
    debugfs -R "stat $path" "$fixture/out/ubuntu.img" 2>/dev/null | grep -q 'User: *0'
done
debugfs -R 'stat /etc/service-file' "$fixture/out/ubuntu.img" 2>/dev/null | grep -q 'User: *42'
debugfs -R 'ea_list /etc/base-file' "$fixture/out/ubuntu.img" 2>/dev/null | grep -q 'user.r8q-test'
(cd "$fixture/out" && sha256sum --check SHA256SUMS)
debugfs -R "dump /usr/libexec/lxc-android-config/mount-halium-overlay.generic $fixture/original-consumer" \
    "$fixture/out/ubuntu.img" 2>/dev/null
cmp "$base/usr/libexec/lxc-android-config/mount-halium-overlay" "$fixture/original-consumer"
if ROOTFS_SHA256="$(printf '%064d' 0)" bash "$repo/build-rootfs.sh" "$fixture/out"; then
    echo "Incorrect checksum was accepted!" >&2
    exit 1
fi
mkdir -p "$modules/other"
printf 'original fixture\n' > "$modules/test.ko"
printf 'duplicate fixture\n' > "$modules/other/test.ko"
rm -rf "$system/usr/share/halium-overlay/android/system/lib/modules"
if bash "$repo/package-device.sh" "$fixture/tools" "$fixture/work" "$fixture/out"; then
    echo "Duplicate Android module basenames were accepted!" >&2
    exit 1
fi
mkdir -p "$fixture/no-modules/tmp/system" "$fixture/no-modules/tmp/partitions" "$fixture/no-modules-out"
cp "$fixture/work/tmp/partitions/boot.img" "$fixture/no-modules/tmp/partitions/"
bash "$repo/package-device.sh" "$fixture/tools" "$fixture/no-modules" "$fixture/no-modules-out"
[[ ! -d "$fixture/no-modules/tmp/system/usr/lib/modules" ]]
"$repo/build.sh" --help
if "$repo/build.sh" positional-output || "$repo/build.sh" -b || "$repo/build.sh" -c -k ||
    "$repo/build.sh" -b / || "$repo/build.sh" -b "$repo/build"; then
    echo "Invalid build arguments were accepted!" >&2
    exit 1
fi
echo "Build-flow fixtures passed"
