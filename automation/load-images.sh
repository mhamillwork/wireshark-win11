#!/usr/bin/env bash
# Load the Docker images stored in this repository.
# Each directory under images/ that contains SHA256SUMS is one docker save archive
# split into pieces. The first line of SHA256SUMS is "<sha256> <archive name>".
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

if docker info >/dev/null 2>&1; then
  DOCKER=(docker)
elif command -v sudo >/dev/null 2>&1 && sudo docker info >/dev/null 2>&1; then
  DOCKER=(sudo docker)
else
  echo "Docker is not available." >&2
  exit 1
fi

shopt -s nullglob
dirs=(images/*/)
if [[ ${#dirs[@]} -eq 0 ]]; then
  echo "No image archives under images/." >&2
  exit 1
fi

loaded=0
for dir in "${dirs[@]}"; do
  sums="${dir}SHA256SUMS"
  [[ -f "${sums}" ]] || continue
  read -r expected name < "${sums}"
  parts=("${dir}${name}."*)
  if [[ ${#parts[@]} -eq 0 || ! -f "${parts[0]}" ]]; then
    echo "No pieces for ${name} in ${dir}" >&2
    exit 1
  fi
  actual="$(cat "${parts[@]}" | sha256sum | awk '{print $1}')"
  if [[ "${actual}" != "${expected}" ]]; then
    echo "Checksum mismatch for ${name}." >&2
    echo "expected ${expected}" >&2
    echo "actual   ${actual}" >&2
    exit 1
  fi
  echo "Loading ${name}"
  cat "${parts[@]}" | "${DOCKER[@]}" load
  loaded=$((loaded + 1))
done

if [[ "${loaded}" -eq 0 ]]; then
  echo "No image archives found." >&2
  exit 1
fi

echo "Loaded ${loaded} archive(s)."
"${DOCKER[@]}" images --format '{{.Repository}}:{{.Tag}}\t{{.ID}}\t{{.Size}}' | grep '^wireshark-win11/' || true
