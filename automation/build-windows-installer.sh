#!/usr/bin/env bash
# Build the Wireshark 4.6.9 Windows NSIS installer.
#
# On the host this builds the wireshark-build image and runs it.
# Inside that image it configures, compiles, and packages Wireshark.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

docker_compose() {
  if docker info >/dev/null 2>&1; then
    docker compose "$@"
  elif command -v sudo >/dev/null 2>&1 && sudo docker info >/dev/null 2>&1; then
    sudo docker compose "$@"
  else
    echo "Docker is not available." >&2
    exit 1
  fi
}

run_on_host() {
  cd "${ROOT}"
  mkdir -p dist
  docker_compose --profile build build wireshark-build
  docker_compose --profile build run --rm wireshark-build
  echo
  echo "Windows installer output:"
  find dist -maxdepth 1 -type f \( -name 'Wireshark-*-x64.exe' -o -name 'SHA256SUMS' \) -print
}

fix_nsis_manifest() {
  local manifest="packaging/nsis/wireshark-profile-manifest.nsh"
  if [[ -f "${manifest}" ]]; then
    # makensis treats "\ " as an escape. The generated "No Reassembly"
    # profile path is otherwise quoted as "No\ Reassembly" and the file
    # lookup fails. See Wireshark issue 21022.
    sed -i 's/No\\ Reassembly/No Reassembly/g' "${manifest}"
  fi
}

prefer_ipv4() {
  # Docker DNS often returns IPv6 first, and this environment has no working
  # IPv6 path. CMake downloads (Npcap, Lua, third-party sources) then hang.
  local conf=/etc/gai.conf
  if [[ ! -e "${conf}" ]] || ! grep -q '::ffff:0:0/96' "${conf}"; then
    printf 'precedence ::ffff:0:0/96  100\n' >> "${conf}"
  fi
}

run_in_container() {
  local jobs log
  jobs="${JOBS:-2}"
  log="/out/build-windows-installer.log"
  mkdir -p /out /src/wireshark/build "${CCACHE_DIR:-/var/cache/ccache}"
  prefer_ipv4
  touch "${log}"
  exec > >(tee -a "${log}") 2>&1

  echo "Wireshark Windows installer build"
  echo "source: $(git -C /src/wireshark describe --tags --always)"
  echo "jobs: ${jobs}"
  echo "version extra: ${WIRESHARK_VERSION_EXTRA:-}"

  cd /src/wireshark/build
  if [[ ! -f CMakeCache.txt || "${RECONFIGURE:-0}" == "1" ]]; then
    mingw64-cmake -G Ninja \
      -DENABLE_CCACHE=Yes \
      -DFETCH_lua=Yes \
      ..
  fi

  ninja -j "${jobs}"
  ninja -j "${jobs}" wireshark_nsis_prep
  fix_nsis_manifest
  ninja -j "${jobs}" wireshark_nsis

  mapfile -t exes < <(find packaging/nsis -maxdepth 1 -type f -iname 'wireshark-*-x64.exe' | sort)
  if [[ ${#exes[@]} -eq 0 ]]; then
    echo "NSIS did not produce an installer under packaging/nsis." >&2
    exit 1
  fi
  local copied=() exe base
  for exe in "${exes[@]}"; do
    cp -v "${exe}" /out/
    base="$(basename "${exe}")"
    copied+=("${base}")
  done
  (
    cd /out
    sha256sum "${copied[@]}" > SHA256SUMS
  )
  echo "Installer written to /out"
  cat /out/SHA256SUMS
}

if [[ "${INSIDE_WIRESHARK_BUILD_IMAGE:-0}" == "1" ]]; then
  run_in_container
else
  run_on_host
fi
