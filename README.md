# Samsung Galaxy S20 FE (r8q)

Halium 13 / Ubuntu Touch device configuration for the Snapdragon Galaxy S20 FE
(SM8250, codename `r8q`). This does not target the Exynos `r8s` variant.

## Build

The root `deviceinfo` is the configuration consumed by the Halium generic
adaptation build tools. It selects the r8q Halium 13 kernel source and
`halium_defconfig`; the matching kernel tree is
[droidian-S20FE/android_kernel_samsung_sm8250](https://github.com/droidian-S20FE/android_kernel_samsung_sm8250),
branch `Halium-13.0-minimal`.

Run `./build.sh` from any working directory. On the first run it downloads the
Halium generic adaptation build tools into `build/` and forwards all arguments
to their `build.sh`. Use that tool's instructions for available build targets
and host dependencies.

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
