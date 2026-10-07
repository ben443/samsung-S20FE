#!/bin/bash
set -euo pipefail

repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
workflow="$repo/.github/workflows/build-images.yml"
fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT

if grep -q 'inputs\.' "$workflow"; then
    echo "Workflow still requires dispatch inputs!" >&2
    exit 1
fi
while IFS= read -r assignment; do
    export "${assignment?}"
done < <(sed -n 's/^          \([A-Z]*_URL\): \(https:\/\/.*\)$/\1=\2/p' "$workflow")
[[ "$ROOTFS_URL" == https://ci.ubports.com/job/ubuntu-touch-rootfs/job/ubports%252Ffocal/389/artifact/ubuntu-touch-hybris-rootfs-arm64.tar.gz ]]
[[ "$HALIUM_URL" == https://ci.ubports.com/job/UBportsCommunityPortsJenkinsCI/job/ubports%252Fporting%252Fcommunity-ports%252Fjenkins-ci%252Fgeneric_arm64/job/halium-11.0/991/artifact/halium_halium_arm64.tar.xz ]]
[[ "$RAMDISK_URL" == https://github.com/halium/initramfs-tools-halium/releases/download/dynparts/initrd.img-touch-arm64 ]]
awk '
    /      - name: Download inputs and compute checksums/ { download = 1; next }
    download && /      - name:/ { exit }
    download && /        run: \|/ { script = 1; next }
    script { sub(/^          /, ""); print }
' "$workflow" > "$fixture/download.sh"
[[ -s "$fixture/download.sh" ]]
bash -n "$fixture/download.sh"

mkdir -p "$fixture/bin"
cat > "$fixture/bin/curl" <<'EOF'
#!/bin/bash
set -euo pipefail
[[ "$#" == 11 && "$1" == --fail && "$2" == --location && "$3" == --retry && "$4" == 3 ]]
[[ "$5" == --proto && "$6" == '=https' && "$7" == --proto-redir && "$8" == '=https' ]]
[[ "$9" == https://* && "${10}" == -o ]]
file="${11}"
printf '%s\n' "$file" >> "$CURL_LOG"
if [[ "$file" == "inputs/${FAIL_KIND:-}" ]]; then
    printf 'partial download\n' > "$file"
    exit 22
fi
if [[ "$file" == "inputs/${EMPTY_KIND:-}" ]]; then
    : > "$file"
else
    printf 'archive fixture for %s\n' "$9" > "$file"
fi
EOF
chmod +x "$fixture/bin/curl"
export PATH="$fixture/bin:$PATH"
cd "$fixture"
export GITHUB_ENV="$fixture/github-env" CURL_LOG="$fixture/curl-log"
bash "$fixture/download.sh"
[[ "$(wc -l < "$GITHUB_ENV")" == 3 ]]
for kind in ROOTFS HALIUM RAMDISK; do
    hash="$(sha256sum "inputs/$kind" | cut -d' ' -f1)"
    grep -qx "${kind}_SHA256=$hash" "$GITHUB_ENV"
    grep -q "          ${kind}_ARCHIVE: inputs/$kind" "$workflow"
done

for mode in FAIL_KIND EMPTY_KIND; do
    for kind in ROOTFS HALIUM RAMDISK; do
        : > "$GITHUB_ENV"
        : > "$CURL_LOG"
        if env "$mode=$kind" bash "$fixture/download.sh"; then
            echo "$mode download for $kind was accepted!" >&2
            exit 1
        fi
        if grep -q "^${kind}_SHA256=" "$GITHUB_ENV"; then
            echo "A checksum was exported for an invalid download!" >&2
            exit 1
        fi
        [[ "$(tail -n1 "$CURL_LOG")" == "inputs/$kind" ]]
    done
done
echo "Workflow download fixtures passed"
