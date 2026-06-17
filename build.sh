#!/usr/bin/env bash
# Build, deploy, and start keyd (Colemak remap) on a reMarkable Paper Pro.
#
# Usage:
#   ./build.sh           build + deploy + (re)start the service   [run this after OS updates]
#   ./build.sh deploy    build + deploy files, don't touch the service
#   ./build.sh build     build only, leaves ./result/bin/keyd
#
# Override the device address if needed:  RM_HOST=root@<ip> ./build.sh
set -euo pipefail

RM_HOST="${RM_HOST:-root@10.11.99.1}"   # reMarkable USB IP
RM_BIN="/home/root/bin/keyd"
RM_DIR="/home/root/keyd"                # CONFIG_DIR baked into the binary; survives OS updates

build() {
  nix build .#keyd-static --print-build-logs
  echo "== verifying static link (want AArch64 + no dynamic section) =="
  nix shell nixpkgs#binutils --command sh -c '
    readelf -h result/bin/keyd | grep -E "Class|Machine|Type"
    readelf -d result/bin/keyd
  '
}

deploy() {
  ssh "$RM_HOST" "mkdir -p /home/root/bin $RM_DIR"
  # Upload to a temp name and rename over the target: a running keyd holds the
  # binary's inode open (ETXTBSY on direct overwrite); rename swaps it cleanly.
  scp result/bin/keyd  "$RM_HOST:$RM_BIN.new"
  ssh "$RM_HOST" "chmod 755 $RM_BIN.new && mv $RM_BIN.new $RM_BIN"
  scp keyd.conf        "$RM_HOST:$RM_DIR/keyd.conf"
  scp keyd.service     "$RM_HOST:$RM_DIR/keyd.service"   # canonical copy in /home (survives updates)
  ssh "$RM_HOST" "chmod 755 $RM_BIN && $RM_BIN --version"
  echo "== deployed binary + keyd.conf + keyd.service to $RM_HOST =="
}

# Install the unit into systemd (rootfs /etc, wiped on OS update) from the
# surviving /home copy, then enable + (re)start. Idempotent.
start_service() {
  ssh "$RM_HOST" '
    set -e
    systemctl stop keyd.service 2>/dev/null || true
    pkill -x keyd 2>/dev/null || true                 # clear any stray foreground daemon holding the grab
    cp '"$RM_DIR"'/keyd.service /etc/systemd/system/keyd.service
    chmod 644 /etc/systemd/system/keyd.service
    systemctl daemon-reload
    systemctl enable --now keyd.service
    sleep 1
    systemctl --no-pager --full status keyd.service | head -n 8
  '
  echo "== keyd.service enabled and running =="
}

case "${1:-all}" in
  build)      build ;;
  deploy)     build; deploy ;;
  all)        build; deploy; start_service ;;
  *) echo "usage: $0 [all|deploy|build]" >&2; exit 1 ;;
esac
