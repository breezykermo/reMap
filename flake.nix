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
    in {
      packages.${system} = {
        inherit keyd-static;
        default = keyd-static;
      };
    };
}
