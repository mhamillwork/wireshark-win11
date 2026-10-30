#!/usr/bin/env bash
# Rebuild the vendored Windows image archive and split it for git.
# The archive contains wireshark-win11/windows-base:11 and
# wireshark-win11/wireshark-runtime:4.6.9. Those images share layers.
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

PART_SIZE="${PART_SIZE:-48M}"
DEST="images/windows-base"
tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

"${DOCKER[@]}" compose --profile base build windows-base
"${DOCKER[@]}" compose build wireshark-runtime
"${DOCKER[@]}" save \
  wireshark-win11/windows-base:11 \
  wireshark-win11/wireshark-runtime:4.6.9 \
  -o "${tmpdir}/windows-images.tar"

rm -rf "${DEST}"
mkdir -p "${DEST}"
split -b "${PART_SIZE}" -d -a 2 "${tmpdir}/windows-images.tar" "${DEST}/windows-images.tar."

{
  sha256sum "${tmpdir}/windows-images.tar" | awk '{print $1 "  windows-images.tar"}'
  (
    cd "${DEST}"
    sha256sum windows-images.tar.*
  )
} > "${DEST}/SHA256SUMS"

bytes="$(wc -c < "${tmpdir}/windows-images.tar" | tr -d ' ')"
cat > images/windows-base.txt <<EOF
name: wireshark-win11/windows-base
tag: "11"
also_contains: wireshark-win11/wireshark-runtime:4.6.9
upstream: dockurr/windows:6.06
manifest_digest: sha256:16fd7c39a3e48bb946d29c59dc6015942e5b900a1fa5d7e5552053bfc48ee2ea
guest: Windows 11 Pro
archive: images/windows-base/windows-images.tar
archive_bytes: ${bytes}
part_size: ${PART_SIZE}
archive_sha256: $(awk 'NR==1{print $1}' "${DEST}/SHA256SUMS")
EOF

echo "Wrote ${DEST}"
ls -lh "${DEST}"
