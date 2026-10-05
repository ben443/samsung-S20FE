#!/bin/bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
build_tools="${repo_root}/build"

if [[ ! -d "${build_tools}" ]]; then
    git clone https://gitlab.com/ubports/community-ports/halium-generic-adaptation-build-tools "${build_tools}"
fi

if [[ ! -f "${build_tools}/build.sh" ]]; then
    printf 'Halium build tools are missing at %s\n' "${build_tools}" >&2
    exit 1
fi

cd "${repo_root}"
exec "${build_tools}/build.sh" "$@"
