# remap

Installs a different keyboard layout for the **reMarkable Paper Pro** Type Folio
([Colemak](https://colemak.com) by default), applied at the evdev level with a
statically cross-compiled [`keyd`](https://github.com/rvaiya/keyd).

The Type Folio is a physical QWERTY keyboard. There is no X11/xkb on the device and the UI
runs in a Qt framebuffer app, so the usual layout tools (`setxkbmap`, `loadkeys`) are inert.
This project remaps keys *below* the application — keyd grabs the keyboard's input device and
re-emits translated key events through a virtual keyboard the app reads as plain US QWERTY.

> Tested on a Paper Pro (OS 3.x) in developer mode, with root SSH over USB.
> It should adapt to other reMarkable models by changing the keyboard's USB id in `keyd.conf`.

## How it works

- **Static aarch64 keyd.** The device has no package manager that ships keyd, and dynamic
  glibc builds won't run. `flake.nix` cross-compiles keyd against musl with `-static`, so the
  binary has zero runtime dependencies (`readelf -d` shows no dynamic section).
- **Device match, not a device path.** keyd scans `/dev/input/event*` and grabs any device
  matching the `[ids]` section of the config (the Folio is `2edd:0001`, name `rM_Keyboard`).
  Because it matches by id, it automatically re-grabs when the Folio powers down on collapse
  and re-enumerates on a different `eventN`.
- **Keycode swaps on a US-QWERTY base.** The app interprets keyd's emitted keycodes as US
  QWERTY, so the layout is expressed as `physical-key = key-whose-QWERTY-glyph-you-want`
  (e.g. `e = f`). See `keyd.conf`.
- **Config baked into `/home`.** keyd's config directory is compiled in. We override it to
  `/home/root/keyd` (via `CONFIG_DIR` in `flake.nix`) so the config lives on the partition
  that survives OS updates, with no `/etc` symlink dance.

## Requirements

- [Nix](https://nixos.org/download) with flakes enabled, on the build host (Linux x86_64;
  adjust `system` in `flake.nix` otherwise).
- A reMarkable in **developer mode** with SSH access. Over USB it's `root@10.11.99.1`.
- Your SSH key on the device (or be ready to enter the root password for each `scp`/`ssh`).

## Quick start

Requires [nix](https://nix.dev/) and an SSH setup to your reMarkable Pro
(ideally by sharing your public key so you don't have to write a password).

```sh
./build.sh
```

That one command builds the static binary, deploys it plus `keyd.conf` and the systemd unit to
the device, installs the unit, enables + starts the service, and writes the unit to the rootfs
so it comes back after a reboot. Type on the Folio — you should be in Colemak immediately.

Point at a different device with `RM_HOST=root@<ip> ./build.sh`.

### Sub-commands

| Command             | Does                                                |
|---------------------|-----------------------------------------------------|
| `./build.sh`        | build + deploy + (re)start the service + persist it |
| `./build.sh deploy` | build + deploy files only, leave the service        |
| `./build.sh build`  | build only, leaves `./result/bin/keyd`              |
| `./build.sh persist`| only re-write the unit to the rootfs                |

### Surviving a reboot

On current Paper Pro builds (checked on OS `20260911`) `/etc` is an overlay whose upper dir is
the tmpfs at `/var/volatile/etc`. Everything `systemctl enable` writes there is therefore gone
at the next boot — not only after an OS update, as "the rootfs gets replaced" would suggest.

So `build.sh` has a second install step. A plain, non-recursive bind mount of `/` exposes the
root filesystem's own directories *without* the submounts stacked on top of them, which means
the bind's `etc` is the real on-disk `/etc` rather than the overlay in front of it. The unit
and its `multi-user.target.wants` symlink are written there, with `/` remounted read-write for
the moment it takes and put back read-only afterwards. Enabling is done by hand — `systemctl`
would only ever write to the overlay.

## Customizing the layout

Edit `keyd.conf` and re-run `./build.sh` (it reloads the running daemon). The config is plain
keyd syntax; `keyd.conf` ships a full Colemak map you can edit row by row.

While experimenting you can iterate live on the device without redeploying:

```sh
ssh root@10.11.99.1 '/home/root/bin/keyd bind "e = f"'   # test one mapping
ssh root@10.11.99.1 '/home/root/bin/keyd list-keys'      # valid key names
ssh root@10.11.99.1 '/home/root/bin/keyd monitor'        # watch raw key events
```

For non-Colemak layouts, keep `[ids] 2edd:0001` and replace the `[main]` swaps.

## After an OS update

reMarkable updates are A/B image swaps: the entire root filesystem is replaced with a fresh
factory image, so the systemd unit in `/etc` is wiped. The binary, config, and a canonical copy
of the unit live under `/home/root/keyd`, which survives — so restoring everything is just:

```sh
./build.sh
./fonts.sh    # if you installed fonts too — they live on the rootfs, so they go as well
```

There is no reliable in-OS hook to re-install automatically (the post-update system is stock
and scans no persistent path), so these manual one-liners after a deliberate update are the
intended workflow.

## Fonts

A keyboard is half of typing; the other half is what the letters look like. `./fonts.sh`
installs [Inter](https://rsms.me/inter/) on the device.

```sh
./fonts.sh            # build + add + replace   [run this after an OS update]
./fonts.sh restore    # put the stock Noto Sans back
```

Two things happen, because xochitl treats fonts in two unrelated ways.

**Adding a font is not enough.** `xochitl` reads exactly one hardcoded directory,
`/usr/share/fonts/ttf/` — it ignores fontconfig's user paths, so `~/.local/share/fonts` is
never consulted. Dropping a font there makes it available for rendering and fallback, which is
what you want for, say, CJK coverage. But it will *not* appear in the font picker: that list is
curated, not scanned. The labels live in the UI translations (`FormatFont`), and there are four
of them — `Ebook default`, `reMarkable Sans`, `reMarkable Serif`, `EB Garamond`.

To read the list off the device yourself, decompile a *non-English* catalog — the English one
is the source language and is only partially populated:

```sh
scp root@10.11.99.1:/usr/share/remarkable/xochitl/translations/reMarkable_es.qm .
lconvert -i reMarkable_es.qm -o rm_es.ts   # then look at the Format* contexts
```

**So the font has to be let in under a name already on the list.** `retag-family.py` rewrites
Inter's name table to claim the `Noto Sans` family, and that file is installed over the stock
one. The picker entry is still called "reMarkable Sans"; the glyphs that come out are Inter's.
Only the name table is touched — outlines, metrics and the variable axes are untouched.

This does mean **Inter replaces Noto Sans everywhere**, interface included, not only in typed
text. The stock font is backed up to `/home/root/fonts/backup/` the first time, so
`./fonts.sh restore` is a complete undo. Scripts Inter does not cover (CJK, Arabic, Hebrew,
Devanagari, Thai) are unaffected — they live in their own Noto files, which are left alone.

Two practical notes. The rootfs runs at ~90% full with about 40M free, so only the two variable
TTFs are installed (under 2M); the `Inter.ttc` in the same nixpkgs package is 13M by itself.
And the UI is stopped before the swap: overwriting a font file that xochitl has mapped is what
otherwise leaves `/` stuck read-write.

## Repository layout

| File               | Purpose                                                           |
|--------------------|-------------------------------------------------------------------|
| `flake.nix`        | reproducible static aarch64 cross-build of keyd (musl, `-static`) |
| `keyd.conf`        | the layout — `[ids]` match + keycode swaps                        |
| `keyd.service`     | systemd unit; canonical copy is kept on `/home` and re-installed  |
| `build.sh`         | build / deploy / start helper                                     |
| `fonts.sh`         | install Inter — add to the font dir, and take over a picker entry |
| `retag-family.py`  | rewrite a font's family name so it can stand in for another       |

## Caveats

- Developer-mode and root SSH access are required; this modifies system state on the device.
- `keyd` runs as root and exclusively grabs the keyboard. To remove it, stop the running
  service *and* delete the rootfs copy the persist step wrote, or it comes back next boot:

  ```sh
  ssh root@10.11.99.1 'systemctl disable --now keyd.service
    mkdir -p /tmp/rootfs && mount -o remount,rw / && mount --bind / /tmp/rootfs
    rm -f /tmp/rootfs/etc/systemd/system/keyd.service \
          /tmp/rootfs/etc/systemd/system/multi-user.target.wants/keyd.service
    umount /tmp/rootfs; mount -o remount,ro /'
  ```
- The persist step writes to the lower dir of a mounted overlay, which overlayfs calls
  undefined for the *live* mount. It is only read again when the overlay is rebuilt at the
  next boot, and the current boot is already served by the copy in the upper dir.
- The harmless `failed to set effective group to "keyd"` warning just means keyd couldn't drop
  to a `keyd` group (which doesn't exist on the device); it keeps running as root.

## Credits

Built on [keyd](https://github.com/rvaiya/keyd) by Raheman Vaiya with a lot of help from [Claude](https://claude.ai)
