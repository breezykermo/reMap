{
  description = "Static aarch64 keyd for reMarkable Paper Pro (cross-compiled, musl, -static)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";

  outputs = { self, nixpkgs }:
    let
      # Build host. Override if you build on aarch64/macOS-linux-builder.
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      # aarch64 target, fully static. pkgsStatic uses musl and links static,
      # which is exactly what we need: nothing on the rM rootfs to depend on.
      crossStatic = pkgs.pkgsCross.aarch64-multiplatform.pkgsStatic;

      keyd-static = crossStatic.stdenv.mkDerivation (finalAttrs: {
        pname = "keyd";
        version = "2.5.0";

        src = pkgs.fetchFromGitHub {
          owner = "rvaiya";
          repo = "keyd";
          rev = "v${finalAttrs.version}";
          hash = "sha256-pylfQjTnXiSzKPRJh9Jli1hhin/MIGIkZxLKxqlReVo=";
        };

        # scdoc only matters if `make`'s default target builds the man pages.
        # It's a build-host tool, so it goes in nativeBuildInputs. Harmless if unused.
        nativeBuildInputs = [ pkgs.scdoc ];

        enableParallelBuilding = true;

        # Bake the config dir into /home/root/keyd so config survives OS updates
        # (rootfs/etc is wiped; /home is not). CONFIG_DIR?=/etc/keyd in the Makefile.
        makeFlags = [ "CONFIG_DIR=/home/root/keyd" ];

        # pkgsStatic already forces static linking via the musl stdenv; this is
        # belt-and-suspenders and *appends* (doesn't clobber keyd's own LDFLAGS).
        NIX_CFLAGS_LINK = "-static";

        # keyd's default target compiles the daemon to bin/keyd. That's all we
        # want on-device — skip `make install` (systemd units, udev, man, the
        # python application-mapper) and just lift the binary.
        installPhase = ''
          runHook preInstall
          install -Dm755 bin/keyd $out/bin/keyd
          runHook postInstall
        '';

        doCheck = false;

        meta.description = "keyd daemon, static aarch64 build for reMarkable Paper Pro";
      });

      # Fonts are architecture-independent, so they come from the native pkgs
      # set rather than the cross one.
      #
      # Only the two variable TTFs. The device's rootfs runs at ~90% full with
      # around 40M to spare, and the `Inter.ttc` in the same package is 13M on
      # its own -- while the variable pair is under 2M and matches how the
      # device ships its own fonts (Noto and EB Garamond are both variable).
      inter-variable = pkgs.runCommand "inter-variable-ttf" { } ''
        mkdir -p $out
        find ${pkgs.inter}/share/fonts -name 'InterVariable*.ttf' -exec cp {} $out/ \;
        test -e $out/InterVariable.ttf   # fail loudly if upstream renames these
      '';

      # Inter wearing the "Noto Sans" name, to stand behind one of the font
      # picker's entries -- see retag-family.py and the README. The filenames
      # match what the device ships so the upright font lands on top of the
      # stock one; the italic is an addition, since stock ships none.
      inter-as-noto-sans = pkgs.runCommand "inter-as-noto-sans" {
        nativeBuildInputs = [ (pkgs.python3.withPackages (ps: [ ps.fonttools ])) ];
      } ''
        mkdir -p $out
        python3 ${./retag-family.py} \
          ${inter-variable}/InterVariable.ttf \
          "$out/NotoSans-VariableFont_wdth,wght.ttf" "Noto Sans" Regular
        python3 ${./retag-family.py} \
          ${inter-variable}/InterVariable-Italic.ttf \
          "$out/NotoSans-Italic-VariableFont_wdth,wght.ttf" "Noto Sans" Italic
      '';
    in {
      packages.${system} = {
        inherit keyd-static inter-variable inter-as-noto-sans;
        default = keyd-static;
      };
    };
}
