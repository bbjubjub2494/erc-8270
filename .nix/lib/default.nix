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
      outputHash = "sha256-2cbMk10TAtMsx6PlMd2oaGXwHCy0ZdoOQaMEATyW8BQ=";
    };

    solc_0_8_34 = pkgs.fetchurl {
      url = "https://binaries.soliditylang.org/linux-amd64/solc-linux-amd64-v0.8.34+commit.80d5c536";
      hash = "sha256-1Arcb5/bsiqX0yoC+gVoi/LueIav/EjJhRsK/Upyazk=";
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

          mkdir -p /build/.local/share/svm/0.8.34
          cp ${solc_0_8_34} /build/.local/share/svm/0.8.34/solc-0.8.34
          chmod +x /build/.local/share/svm/0.8.34/solc-0.8.34
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
