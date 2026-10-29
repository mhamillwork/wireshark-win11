#!/usr/bin/env bash
# Build the Windows 11 base image and save it into the project tree.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"
mkdir -p images

if docker info >/dev/null 2>&1; then
  DOCKER=(docker)
elif command -v sudo >/dev/null 2>&1 && sudo docker info >/dev/null 2>&1; then
  DOCKER=(sudo docker)
else
  echo "Docker is not available." >&2
  exit 1
fi

"${DOCKER[@]}" compose --profile base build windows-base
"${DOCKER[@]}" save wireshark-win11/windows-base:11 -o images/windows-base.tar
"${DOCKER[@]}" image inspect wireshark-win11/windows-base:11 \
  --format 'name: {{.RepoTags}}
id: {{.Id}}
size_bytes: {{.Size}}
created: {{.Created}}
upstream: dockurr/windows:6.06
manifest_digest: sha256:16fd7c39a3e48bb946d29c59dc6015942e5b900a1fa5d7e5552053bfc48ee2ea
guest: Windows 11 Pro
archive: images/windows-base.tar' > images/windows-base.txt

echo "Saved images/windows-base.tar"
ls -lh images/windows-base.tar images/windows-base.txt
