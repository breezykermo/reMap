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

# start_service only gets us to the next reboot. On current Paper Pro builds
# (checked on OS 20260911) /etc is an overlay whose upper dir is the tmpfs at
# /var/volatile/etc, so everything systemctl writes there is gone on reboot --
# not just on an OS update, as the rootfs-is-replaced story would suggest.
#
# To outlive a reboot the unit has to land in the *lower* dir: the /etc that
# lives on the rootfs partition itself. A plain (non-recursive) bind mount of /
# exposes exactly that -- the root filesystem's own directories, without the
# submounts stacked on top of them -- so $MNT/etc is the on-disk /etc rather
# than the overlay. We enable by hand (the wants/ symlink) instead of calling
# systemctl, which would only ever write to the overlay.
persist_service() {
  ssh "$RM_HOST" "RM_DIR=$RM_DIR sh -s" <<'EOF'
    set -e
    MNT=/tmp/rootfs                       # mountpoint on tmpfs: leaves no stray dir on the rootfs
    mkdir -p "$MNT"
    mount -o remount,rw /
    mount --bind / "$MNT"
    trap 'umount "$MNT" 2>/dev/null || true; mount -o remount,ro / || echo "WARNING: / left read-write" >&2' EXIT

    # Sanity: the bind must expose the rootfs, not the live view we came from.
    # /var/volatile is where the tmpfs gets mounted, so on the bare rootfs it is
    # an empty mountpoint; in the live view it holds the overlay upper dirs.
    if [ -n "$(ls -A "$MNT"/var/volatile 2>/dev/null)" ]; then
      echo "refusing: $MNT looks like the live view, not the rootfs" >&2; exit 1
    fi

    cp "$RM_DIR"/keyd.service "$MNT"/etc/systemd/system/keyd.service
    chmod 644 "$MNT"/etc/systemd/system/keyd.service
    mkdir -p "$MNT"/etc/systemd/system/multi-user.target.wants
    ln -sf ../keyd.service "$MNT"/etc/systemd/system/multi-user.target.wants/keyd.service
    sync
    echo "persisted to rootfs:"
    ls -l "$MNT"/etc/systemd/system/keyd.service \
          "$MNT"/etc/systemd/system/multi-user.target.wants/keyd.service
EOF
  echo "== keyd.service written to the rootfs; survives reboots (an OS update still needs a rerun) =="
}

case "${1:-all}" in
  build)      build ;;
  deploy)     build; deploy ;;
  persist)    persist_service ;;
  all)        build; deploy; start_service; persist_service ;;
  *) echo "usage: $0 [all|deploy|build|persist]" >&2; exit 1 ;;
esac
