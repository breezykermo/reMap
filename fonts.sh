#!/usr/bin/env bash
# Install fonts (Inter by default) on a reMarkable Paper Pro.
#
# xochitl treats fonts in two unrelated ways, so there are two things to do:
#
#   add      drops a font in /usr/share/fonts/ttf/<name>/, where it is available
#            for rendering and as a fallback -- but it will NOT appear in the
#            font picker, which is a curated list of labels, not a scan of that
#            directory.
#   replace  puts Inter behind the family one of those labels already resolves
#            to. This is the only way to actually type in a font the picker does
#            not list, and it is why "reMarkable Sans" comes out as Inter.
#
# Usage:
#   ./fonts.sh            build + add + replace  [run this after an OS update]
#   ./fonts.sh add        only the added copy
#   ./fonts.sh replace    only the picker takeover
#   ./fonts.sh restore    put the stock Noto Sans back, undo replace
#   ./fonts.sh build      build only
#
# Override the device address if needed:  RM_HOST=root@<ip> ./fonts.sh
set -euo pipefail

RM_HOST="${RM_HOST:-root@10.11.99.1}"
RM_FONTS="/home/root/fonts"              # stash on /home; survives OS updates
TTF_DIR="/usr/share/fonts/ttf"           # the only dir xochitl reads (hardcoded)
STOCK="NotoSans-VariableFont_wdth,wght.ttf"

build() {
  nix build .#inter-variable     --out-link result-inter      --print-build-logs
  nix build .#inter-as-noto-sans --out-link result-inter-noto --print-build-logs
}

# Everything lands in /home first, so a reinstall after an OS update never
# needs the build host's nix store.
stage() {
  ssh "$RM_HOST" "mkdir -p $RM_FONTS/inter $RM_FONTS/noto-sans $RM_FONTS/backup"
  scp -q result-inter/*.ttf      "$RM_HOST:$RM_FONTS/inter/"
  scp -q result-inter-noto/*.ttf "$RM_HOST:$RM_FONTS/noto-sans/"
  echo "== staged fonts in $RM_FONTS =="
}

# Run a script on the device with / writable, and put it back read-only however
# the script exits. The rootfs is read-only but, unlike /etc, is NOT overlaid,
# so a plain remount is enough here -- no bind-mount trick (see build.sh for
# the /etc case). Writes persist across reboots; an OS update loses them.
on_rootfs() {
  {
    cat <<'PREAMBLE'
set -e
remount_ro() {
  # A font file xochitl still has mapped can hold the mount busy for a moment
  # after we overwrite it, so this is worth a few attempts before giving up.
  for _ in 1 2 3 4 5; do
    sync
    mount -o remount,ro / 2>/dev/null && return 0
    sleep 1
  done
  echo "WARNING: / left read-write -- run: ssh <device> 'sync; mount -o remount,ro /'" >&2
  return 1
}
mount -o remount,rw /
trap remount_ro EXIT
PREAMBLE
    cat
  } | ssh "$RM_HOST" "TTF_DIR=$TTF_DIR RM_FONTS=$RM_FONTS STOCK='$STOCK' sh -s"
}

require_space() {  # require_space <kb needed>
  ssh "$RM_HOST" "
    free=\$(df -k / | awk 'NR==2 {print \$4}')
    [ \"\$free\" -ge $1 ] || { echo \"only \${free}K free on /, need $1K\" >&2; exit 1; }
  "
}

add() {
  require_space 4096
  on_rootfs <<'EOF'
    mkdir -p "$TTF_DIR"/inter
    cp "$RM_FONTS"/inter/*.ttf "$TTF_DIR"/inter/
    chmod 644 "$TTF_DIR"/inter/*.ttf
    ls -l "$TTF_DIR"/inter/
EOF
  echo "== Inter added to $TTF_DIR/inter (not in the picker; fallback only) =="
}

replace() {
  require_space 4096
  # Stop the UI first: overwriting a font it has mapped is what makes the
  # read-only remount fail, and it has to restart anyway to reread the dir.
  ssh "$RM_HOST" 'systemctl stop xochitl'
  on_rootfs <<'EOF'
    # Back up the stock font once, and never overwrite that backup with a font
    # we already replaced -- otherwise restore has nothing to restore to.
    if [ ! -e "$RM_FONTS/backup/$STOCK" ]; then
      cp "$TTF_DIR/noto/$STOCK" "$RM_FONTS/backup/$STOCK"
      echo "backed up stock Noto Sans to $RM_FONTS/backup/"
    fi
    cp "$RM_FONTS"/noto-sans/*.ttf "$TTF_DIR"/noto/
    chmod 644 "$TTF_DIR"/noto/*.ttf
EOF
  start_ui
  echo "== Inter now answers to \"Noto Sans\"; undo with ./fonts.sh restore =="
}

restore() {
  ssh "$RM_HOST" "test -e '$RM_FONTS/backup/$STOCK'" \
    || { echo "no backup at $RM_FONTS/backup/$STOCK -- nothing to restore" >&2; exit 1; }
  ssh "$RM_HOST" 'systemctl stop xochitl'
  on_rootfs <<'EOF'
    cp "$RM_FONTS/backup/$STOCK" "$TTF_DIR/noto/$STOCK"
    rm -f "$TTF_DIR/noto/NotoSans-Italic-VariableFont_wdth,wght.ttf"
    chmod 644 "$TTF_DIR/noto/$STOCK"
EOF
  start_ui
  echo "== stock Noto Sans restored =="
}

# xochitl reads the font directory once, at startup.
start_ui() {
  ssh "$RM_HOST" 'systemctl start xochitl; sleep 5; systemctl is-active xochitl'
}

case "${1:-all}" in
  build)    build ;;
  add)      build; stage; add ;;
  replace)  build; stage; replace ;;
  restore)  restore ;;
  all)      build; stage; add; replace ;;
  *) echo "usage: $0 [all|add|replace|restore|build]" >&2; exit 1 ;;
esac
