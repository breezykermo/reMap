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
file result/bin/keyd
# No output from readelf -d == no NEEDED == truly static.
nix shell nixpkgs#binutils --command readelf -d result/bin/keyd || true

if [[ "${1:-}" == "deploy" ]]; then
  ssh "$RM_HOST" 'mkdir -p /home/root/bin'
  scp result/bin/keyd "$RM_HOST:$RM_DEST"
  ssh "$RM_HOST" "chmod 755 $RM_DEST && $RM_DEST --version || true"
  echo "== pushed to $RM_HOST:$RM_DEST =="
fi
