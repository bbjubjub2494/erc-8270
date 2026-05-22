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
      ];

      buildPhase = ''
        forge soldeer update
      '';

      installPhase = ''
        cp -R dependencies $out
      '';

      outputHashMode = "recursive";
      outputHashAlgo = "sha256";
      outputHash = "sha256-VixcA+T/lsEG4APrmCJmWpNJkIGwFgRDkFQWy3kcjBg=";
    };

    solc_0_8_35 = pkgs.fetchurl {
      url = "https://binaries.soliditylang.org/linux-amd64/solc-linux-amd64-v0.8.35+commit.47b9dedd";
      hash = "sha256-+orJoy0wGtAjo27lop+OKR/jIAxgJE5DwUJTnoKmF/Q=";
    };
  in
    pkgs.buildNpmPackage (
      {
        pname = "erc-xxxx-${npmWorkspace}";
        version = "1.0.0";

        inherit src;
        npmDeps = pkgs.fetchNpmDeps {
          inherit src;
          hash = "sha256-xTxsP4syF/UBkpfyFBR4l/635DMqUifeTcwLFUS6gnA=";
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
          ln -s ${soldeer-dependencies} contracts/dependencies

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
