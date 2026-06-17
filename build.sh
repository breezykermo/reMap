#!/usr/bin/env bash
# Build the static aarch64 keyd and (optionally) push it to the device.
# Usage:
#   ./build.sh            # build only, leaves ./result/bin/keyd
#   ./build.sh deploy     # build + scp to the rM over USB
set -euo pipefail

RM_HOST="${RM_HOST:-root@10.11.99.1}"   # reMarkable USB IP
RM_DEST="${RM_DEST:-/home/root/bin/keyd}"

nix build .#keyd-static --print-build-logs

echo "== verifying static link =="
# "no dynamic section" == truly static; confirm arch is AArch64.
nix shell nixpkgs#binutils --command sh -c '
  readelf -h result/bin/keyd | grep -E "Class|Machine|Type"
  readelf -d result/bin/keyd
'

if [[ "${1:-}" == "deploy" ]]; then
  ssh "$RM_HOST" 'mkdir -p /home/root/bin'
  scp result/bin/keyd "$RM_HOST:$RM_DEST"
  ssh "$RM_HOST" "chmod 755 $RM_DEST && $RM_DEST --version || true"
  echo "== pushed to $RM_HOST:$RM_DEST =="
fi
