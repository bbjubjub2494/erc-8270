{flake, ...}: {
  genPackage = {
    npmWorkspace,
    pkgs,
    buildNpmPackageArgs ? {},
  }: let
    src = builtins.path {
      path = flake;
      name = "source";
    };

    soldeer-dependencies = pkgs.stdenvNoCC.mkDerivation {
      name = "soldeer-dependencies";

      inherit src;
      sourceRoot = "source/contracts";

      nativeBuildInputs = [
        pkgs.foundry
        pkgs.git
      ];

      buildPhase = ''
        export GIT_SSL_CAINFO="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
        forge soldeer install
        rm -rf dependencies/ercs-unversioned/.git # for reproducibility
      '';

      installPhase = ''
        cp -R dependencies $out
      '';

      dontPatchShebangs = true; # not allowed to reference store paths in FOD

      outputHashMode = "recursive";
      outputHashAlgo = "sha256";
      outputHash = "sha256-52tL8zsOxfAvJZl7btgLSVhraRD9+GMuHpGIzeXDDvI=";
    };

    solc_0_8_35 = pkgs.fetchurl {
      url = "https://binaries.soliditylang.org/linux-amd64/solc-linux-amd64-v0.8.35+commit.47b9dedd";
      hash = "sha256-+orJoy0wGtAjo27lop+OKR/jIAxgJE5DwUJTnoKmF/Q=";
    };
  in
    pkgs.buildNpmPackage (
      {
        pname = "erc-8270-${npmWorkspace}";
        version = "1.0.0";

        inherit src;
        npmDeps = pkgs.fetchNpmDeps {
          inherit src;
          hash = "sha256-MpG1H3ILYUTSHvsiWuJQlEaeBJbTyL4G0Qja4FU+oW8=";
        };

        buildInputs = [
          pkgs.systemd # includes libudev
        ];

        nativeBuildInputs = [
          pkgs.foundry
          pkgs.solc
          pkgs.vyper
        ];

        postPatch = ''
          cp -R ${soldeer-dependencies} contracts/dependencies

          mkdir -p /build/.local/share/svm/0.8.35
          cp ${solc_0_8_35} /build/.local/share/svm/0.8.35/solc-0.8.35
          chmod +x /build/.local/share/svm/0.8.35/solc-0.8.35
        '';

        # metadata prepare script depends on contracts prepare script
        # Per https://docs.npmjs.com/cli/v11/using-npm/scripts, prepare scripts
        # run concurrently unless we pass this option.
        npmFlags = ["--foreground-scripts"];

        inherit npmWorkspace;
      }
      // buildNpmPackageArgs
    );
}
