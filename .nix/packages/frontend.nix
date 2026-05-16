{
  pkgs,
  flake,
  ...
}:
flake.lib.genPackage rec {
  npmWorkspace = "frontend";
  inherit pkgs;
  buildNpmPackageArgs = {
    installPhase = ''
      cp -R ${npmWorkspace}/dist  $out
    '';
  };
}
