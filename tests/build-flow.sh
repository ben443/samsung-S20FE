#!/bin/bash
set -euo pipefail

repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
grep -q '^deviceinfo_halium_version="11"$' "$repo/deviceinfo"
grep -q '^deviceinfo_bootimg_os_version="11"$' "$repo/deviceinfo"
grep -q '^deviceinfo_kernel_source_branch="Halium-latest"$' "$repo/deviceinfo"
grep -q '^deviceinfo_kernel_defconfig="vendor/samsung-rq8-halium_defconfig"$' "$repo/deviceinfo"
grep -q '^deviceinfo_kernel_clang_branch="android11-gsi"$' "$repo/deviceinfo"
grep -q '^deviceinfo_kernel_clang_revision="r383902"$' "$repo/deviceinfo"
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
    "$generic/system/var/lib/lxc/android" "$generic/system/lib" "$generic/partitions"
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
printf 'Halium 11 Android rootfs fixture\n' > "$generic/system/var/lib/lxc/android/system.img"
printf 'must be replaced by device boot\n' > "$generic/partitions/boot.img"
printf 'preserved generic lib file\n' > "$generic/system/lib/generic-file"
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
    /usr/lib/generic-file \
    /usr/libexec/lxc-android-config/mount-halium-overlay \
    /usr/libexec/lxc-android-config/mount-halium-overlay.generic \
    /usr/lib/modules/test-release/kernel/drivers/test.ko \
    /usr/share/halium-overlay/android/vendor/etc/init/vndservicemanager.rc \
    /var/lib/lxc/android/android-rootfs.img; do
    debugfs -R "stat $path" "$fixture/out/ubuntu.img" 2>/dev/null | grep 'User: *0' >/dev/null
done
debugfs -R 'stat /lib' "$fixture/out/ubuntu.img" 2>/dev/null | grep 'Type: symlink' >/dev/null
debugfs -R 'stat /etc/service-file' "$fixture/out/ubuntu.img" 2>/dev/null | grep 'User: *42' >/dev/null
debugfs -R 'ea_list /etc/base-file' "$fixture/out/ubuntu.img" 2>/dev/null | grep 'user.r8q-test' >/dev/null
(cd "$fixture/out" && sha256sum --check SHA256SUMS)
debugfs -R "dump /usr/libexec/lxc-android-config/mount-halium-overlay.generic $fixture/original-consumer" \
    "$fixture/out/ubuntu.img" 2>/dev/null
cmp "$base/usr/libexec/lxc-android-config/mount-halium-overlay" "$fixture/original-consumer"
tar -tJf "$fixture/out/device_r8q.tar.xz" | grep 'mount-halium-overlay.generic' >/dev/null
for exported in "$fixture/out/"*.img "$fixture/out/SHA256SUMS" "$fixture/out/device_r8q.tar.xz"; do
    [[ "$(stat -c %u "$exported")" == "${SUDO_UID:-$(id -u)}" ]]
done
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

wrapper="$fixture/wrapper source"
workspace="$fixture/wrapper work"
output="$fixture/wrapper out"
mkdir -p "$wrapper/build" "$workspace/downloads/android_kernel_samsung_sm8250/.git" "$fixture/bin"
cp "$repo/build.sh" "$wrapper/build.sh"
cat > "$fixture/bin/git" <<'EOF'
#!/bin/bash
set -euo pipefail
[[ "$1" == -C ]]
case "$3" in
    status) exit 0 ;;
    rev-parse)
        if [[ "$2" == */build ]]; then
            echo a1099f7fff34620f66b1efb690de6e7ce1ee5002
        else
            echo d222ac7454ee1e3bf728fbba1347b76397ad5702
        fi ;;
    *) exit 1 ;;
esac
EOF
cat > "$wrapper/build/build.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
[[ "$PWD" == "$WRAPPER_REPO" ]]
[[ "$1" == -b && "$3" == -o && "$5" == -k && "$6" == -m ]]
[[ "$2" == "$WRAPPER_WORK" && "$4" == "$WRAPPER_OUT" ]]
mkdir -p "$2/tmp/partitions"
printf 'wrapper boot fixture\n' > "$2/tmp/partitions/boot.img"
EOF
chmod +x "$fixture/bin/git" "$wrapper/build/build.sh"
printf 'initrd fixture\n' | gzip > "$fixture/initrd.gz"
RAMDISK_SHA256="$(sha256sum "$fixture/initrd.gz" | cut -d' ' -f1)"
PATH="$fixture/bin:$PATH" WRAPPER_REPO="$wrapper" WRAPPER_WORK="$workspace" WRAPPER_OUT="$output" \
    RAMDISK_ARCHIVE="$fixture/initrd.gz" RAMDISK_SHA256="$RAMDISK_SHA256" \
    bash "$wrapper/build.sh" -b "$workspace" -o "$output" -k -m
cmp "$workspace/tmp/partitions/boot.img" "$output/boot.img"
grep -q '^kernel d222ac7454ee1e3bf728fbba1347b76397ad5702$' "$output/build-info.txt"

runtime="$fixture/runtime"
mkdir -p "$runtime/bin" "$runtime/usr/bin" "$runtime/usr/libexec/lxc-android-config" \
    "$runtime/android/system/lib" "$runtime/android/vendor/lib" "$runtime/android/vendor/etc/init" \
    "$runtime/usr/share/halium-overlay/android/system/lib/modules" \
    "$runtime/usr/share/halium-overlay/android/vendor/lib/modules" \
    "$runtime/usr/share/halium-overlay/android/vendor/etc/init"
cp /bin/bash "$runtime/bin/"
while IFS= read -r library; do
    cp -L --parents "$library" "$runtime/"
done < <(ldd /bin/bash | awk '$2 == "=>" {print $3} /ld-linux/ {print $1}')
cp "$repo/overlay/system/usr/libexec/lxc-android-config/mount-halium-overlay" \
    "$runtime/usr/libexec/lxc-android-config/"
cat > "$runtime/usr/libexec/lxc-android-config/mount-halium-overlay.generic" <<'EOF'
#!/bin/bash
echo generic >> /mount.log
EOF
cat > "$runtime/usr/bin/mount" <<'EOF'
#!/bin/bash
printf 'mount %s\n' "$*" >> /mount.log
EOF
printf '#!/bin/bash\nexit 0\n' > "$runtime/usr/bin/mountpoint"
chmod +x "$runtime/usr/bin/"* "$runtime/usr/libexec/lxc-android-config/"*
sudo chroot "$runtime" /usr/libexec/lxc-android-config/mount-halium-overlay
mapfile -t mounts < "$runtime/mount.log"
[[ "${mounts[0]}" == generic && "${#mounts[@]}" == 8 ]]
grep -Fq 'mount --bind /android/vendor/lib /var/lib/lxc/android/rootfs/vendor/lib' "$runtime/mount.log"
grep -Fq 'mount --bind /android/system/lib/modules /usr/lib/modules' "$runtime/mount.log"
rm -rf "$runtime/android/vendor/lib"
if sudo chroot "$runtime" /usr/libexec/lxc-android-config/mount-halium-overlay 2>"$fixture/missing-target"; then
    echo "Missing vendor overlay target was silently accepted!" >&2
    exit 1
fi
grep -q 'r8q overlay target is missing' "$fixture/missing-target"

"$repo/build.sh" --help
if "$repo/build.sh" positional-output || "$repo/build.sh" -b || "$repo/build.sh" -c -k ||
    "$repo/build.sh" -b / || "$repo/build.sh" -b "$repo/build"; then
    echo "Invalid build arguments were accepted!" >&2
    exit 1
fi
echo "Build-flow fixtures passed"
