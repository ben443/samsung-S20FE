# Samsung Galaxy S20 FE (r8q)

Halium 13 / Ubuntu Touch device configuration for the Snapdragon Galaxy S20 FE
(SM8250, codename `r8q`). This does not target the Exynos `r8s` variant.

## Build

The root `deviceinfo` is the configuration consumed by the Halium generic
adaptation build tools. It selects the r8q Halium 13 kernel source and
`vendor/halium-13_defconfig`; the matching kernel tree is
[droidian-S20FE/android_kernel_samsung_sm8250](https://github.com/droidian-S20FE/android_kernel_samsung_sm8250),
branch `Halium-13.0-minimal`.

Run `./build.sh` from any working directory. Paths supplied by the caller are
resolved before switching to the device directory (upstream reads `deviceinfo`
from its working directory). Supported options are `-b WORKDIR`, `-o OUTPUT`,
`-c` (fetch dependencies only), `-k` (kernel and boot images only), and `-m`
(menuconfig). Positional arguments are rejected: upstream's positional output
parser incorrectly reads the next argument. Defaults are repository-local
`workdir/` and `out/`.

### Versions and host dependencies

The wrapper pins the inspected generic-tools snapshot
[`a1099f7`](https://github.com/Talustus/halium-generic-adaptation-build-tools/tree/a1099f7fff34620f66b1efb690de6e7ce1ee5002)
in `build/`, and kernel revision
[`6dff6df`](https://github.com/droidian-S20FE/android_kernel_samsung_sm8250/tree/6dff6dfa0aff47ccb03802e10bbcf63cd50076de).
The tools are an accessible copy of the
[GitLab project](https://gitlab.com/ubports/porting/community-ports/halium-generic-adaptation-build-tools);
GitLab was inaccessible during this change, so this is **not** a claim about
its current HEAD. This snapshot explicitly supports Halium 13, Focal, local
prebuilt ramdisks, and release overlays. An existing, different or dirty tools/
kernel checkout fails instead of silently building another version; move it
aside to fetch the pinned version.

Use an x86_64 Ubuntu 22.04 host with the dependencies in
`.github/workflows/build-images.yml`. Upstream selects Clang `r450784e` from
`master-kernel-build-2022`; LLD is enabled. The kernel source's actual config
is under `arch/arm64/configs/vendor/`, not `halium_defconfig`.
Upstream still downloads some toolchains/tooling from branches. Preserve
`workdir/downloads/` when reproducing a build; these are not bit-for-bit
reproducible builds across arbitrary hosts and dependency updates.
`out/build-info.txt` records source/dependency Git revisions, input hashes, and
the downloaded Clang binary hash so a build's actual inputs can be audited.

### Full image build

Supply three trusted, local inputs and their independently verified SHA256s:

- `ROOTFS_ARCHIVE`: Ubuntu Touch **Focal arm64 hybris** rootfs `.tar.gz`, with
  root-level `etc/`, `usr/`, usrmerge (`lib -> usr/lib`), and
  `usr/libexec/lxc-android-config/mount-halium-overlay`.
- `HALIUM_ARCHIVE`: **Halium 13 arm64** generic adaptation `.tar.xz`, with the
  OTA `system/` prefix and the Android image in `system/var/lib/lxc/android/`.
- `RAMDISK_ARCHIVE`: Halium **dynparts arm64 gzip initrd**, used to build boot.img.
  The wrapper replaces upstream's unverified, mutable cached initrd with this
  verified input on every invocation.

For locating these inputs, the inspected tools' `prepare-fake-ota.sh` uses the
UBports `ubuntu-touch-rootfs/ubports%252Ffocal` job's
`ubuntu-touch-android9plus-rootfs-arm64.tar.gz`, the `generic_arm64/halium-13.0`
job's `halium_halium_arm64.tar.xz`, and the Halium initramfs `dynparts` release.
Resolve a **specific build/release URL** and record its trusted hash rather
than relying on `lastSuccessfulBuild`. Downloads/vendor blobs are not supplied
by this repository.

```bash
export ROOTFS_ARCHIVE=/absolute/path/focal-arm64.tar.gz
export ROOTFS_SHA256=<trusted-rootfs-sha256>
export HALIUM_ARCHIVE=/absolute/path/halium-13-arm64.tar.xz
export HALIUM_SHA256=<trusted-halium-sha256>
export RAMDISK_ARCHIVE=/absolute/path/initrd.img-touch-arm64
export RAMDISK_SHA256=<trusted-initrd-sha256>
./build.sh
```

Full builds invoke kernel/boot assembly, package device adaptation, then build
`out/ubuntu.img` (raw ext4), `out/boot.img`, `out/device_r8q.tar.xz`, any other
generated partition images, and `out/SHA256SUMS`. Kernel-only builds need only
the initrd and hash. `ROOTFS_SIZE` defaults to `4G` and can be adjusted, e.g.
`ROOTFS_SIZE=5G ./build.sh`; it is not the phone's system-partition size.
`deviceinfo_rootfs_image_sector_size` is not consumed by these tools.

`build-rootfs.sh` verifies inputs then uses sudo and `mke2fs -d`, without loop
mounts. Real privilege preserves capability xattrs that fakeroot cannot restore.
It preserves numeric ownership, ACLs and xattrs and applies Focal, generic Halium, then device
adaptation in that order. It renames a generic `system.img` to
`android-rootfs.img` for Halium's system-as-root mount flow.
It deliberately does **not** invoke upstream's development fake-OTA helper:
that helper enables insecure SSH/ADB defaults and uses stub signature checks.
Input hashes are required here; SSH/ADB settings remain those of the supplied
rootfs. This is a local development image, not a signed OTA/update channel.

### Runtime layout

- Linux modules retain their versioned tree and dependency metadata at
  `/usr/lib/modules/<kernel-release>/` (`/lib` is a Focal usrmerge symlink).
  Host-only `build`/`source` module symlinks are removed.
- Copies under `/usr/share/halium-overlay/android/system/lib/modules/` provide the
  Android `/system/lib/modules` tree, including flat relative `.ko` links for
  Android `insmod` paths. `.halium-overlay-dir` at the parent `lib/` merges
  directories, rather than silently skipping files absent from the generic image.
- `/usr/share/halium-overlay/android/vendor/lib/modules/` uses
  `.halium-overlay-dir` at `lib/` to merge into `/android/vendor/lib`, retaining
  firmware-supplied drivers. Duplicate compiled module basenames fail packaging.
  Module load order remains the vendor/init configuration's responsibility;
  no fabricated `modules.load` or blanket autoload list is installed.
- `overlay/system/etc/gbinder.conf` becomes `/etc/gbinder.conf`.
  `overlay/system/usr/share/halium-overlay/android/vendor/etc/init/vndservicemanager.rc`
  remains an Android vendor-init overlay, applied by Focal's
  `mount-halium-overlay` before LXC starts. Do not put it in Ubuntu's `/etc/init`.
  Explicit `/android` prefixes target the mounted tree shared with LXC, without
  assuming host `/system` or `/vendor` aliases.
- The builder preserves Focal's mount helper as `mount-halium-overlay.generic`.
  The device wrapper calls it first, then explicitly merges the r8q Android
  library/module and vendor-init directories, and refreshes LXC/module binds.
  This prevents upstream's first-overlay-wins selection (GSI, `/opt`, then
  `/usr/share`) from silently omitting the device files. Missing Android targets
  fail the mount hook with a firmware diagnostic instead of skipping files.
  The final device archive also includes the preserved helper from the exact
  supplied Focal input; use it only with that matching rootfs.
- Header-v2 `boot.img` contains the kernel, included r8q DTB and supplied Halium
  initrd. Normal post-mount modules and adaptation files belong in the rootfs,
  **not** a fictional header-v2 `vendor_boot.img`. If a future config needs
  modules to mount userdata, supply a matching initrd with those early modules;
  this flow does not guess them or inject all modules into the ramdisk.

### GitHub Actions and checks

Run **Actions → Halium 13 images → Run workflow**, supplying HTTPS URLs and
trusted SHA256s for the three inputs. It builds using the same entry point
and uploads images, device adaptation and checksums for 14 days. Pushes/PRs
run shell checks and small fixture-based packaging/ext4 tests, without
downloading firmware or compiling a kernel.

Local checks:

```bash
bash -n build.sh package-device.sh build-rootfs.sh deviceinfo tests/build-flow.sh
shellcheck build.sh package-device.sh build-rootfs.sh tests/build-flow.sh
shellcheck overlay/system/usr/libexec/lxc-android-config/mount-halium-overlay
bash tests/build-flow.sh
```

## Device and image notes

- Use a Snapdragon SM8250 `r8q` device. The included `sm8250-r8q.dtb` and
  `SRPUB26A007` board value are for this target.
- Boot image header version 2, 4096-byte pages, and the boot command line are
  aligned with the SM8250 common device configuration; the virtual framebuffer
  argument is retained for Halium.
- `overlay/` contains the current binder compatibility settings. Do not copy
  overlays from other Samsung variants without confirming their Android vendor
  interface and init requirements.
- This repository does not contain Android vendor blobs or an Ubuntu Touch
  root filesystem. A successful kernel/image build does not by itself verify
  that the device boots or that its hardware works; test on the intended
  firmware and device before flashing.
- A compatible r8q Android 13 vendor/firmware installation is still required.
  The generic Halium image is not Samsung vendor firmware. Stock modules must
  match the built kernel's ABI/signature policy; copying them cannot repair an
  ABI mismatch. Boot acceptance/AVB and userdata installation require r8q
  device testing; `ubuntu.img` is not an Android system-partition flashing recipe.
- The supplied [Tab S7+ Droidian reference](https://github.com/mukahraman/galaxy-tab-s7-plus-droidian)
  and [kernel source](https://github.com/mukahraman/kernel_samsung_sm8250)
  share SM8250, but the documented build targets `gts7xlwifi`, Halium 11/API 30,
  and Droidian. Its tablet config, DTBO, signing keys and flashing instructions
  are not substituted for the r8q Halium 13/Focal target.
- The [Droidian recipes](https://github.com/mukahraman/droidian-recipes) are useful
  metadata-preserving assembly references, but their supplied recipe is API 30/
  Debian Trixie/Phosh for `gts7xlwifi`. The kernel has r8q fragments, not a complete
  r8q image recipe; a Droidian migration needs phone-specific adaptation and must
  not inherit the Wi-Fi tablet's disabled modem stack. This fix retains Focal.
