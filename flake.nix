{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    poetry2nix.url = "github:nix-community/poetry2nix";
  };

  outputs = { self, nixpkgs, flake-utils, poetry2nix, ...}@inputs: let
    projectWithPkgs = pkgs: let
      p2n = pkgs.poetry2nix;
      args = {
        projectDir = ./.;
        preferWheels = true;
        overrides = p2n.overrides.withDefaults (self: super: {
          inherit (pkgs.python39Packages) pyudev pycurl six;
        });
      };
    in {
      env = p2n.mkPoetryEnv args;
      app = p2n.mkPoetryApplication args;
    };
  in {
    overlay = final: prev: let
      pkgs = import nixpkgs {
        inherit (prev) system;
        overlays = [ poetry2nix.overlay ];
      };
      project = projectWithPkgs pkgs;
    in {
      automatic-ripping-machine = project.app;
    };
  } // flake-utils.lib.eachDefaultSystem (system: let
    pkgs = import nixpkgs{
      overlays = [ self.overlay ];
      inherit system;
    };
    project = projectWithPkgs pkgs;
  in {
    devShell = pkgs.mkShell {
      nativeBuildInputs = [ pkgs.bashInteractive ];
      buildInputs = [ pkgs.poetry pkgs.automatic-ripping-machine project.env ];
    };

    packages = {
      inherit (pkgs) automatic-ripping-machine;
    };

    defaultPackage = self.packages.automatic-ripping-machine;

    checks = {
      pylint = pkgs.runCommandNoCC "pylint" {
        nativeBuildInputs = [ project.env ];
        preferLocalBuild = true;
        } "flake8 > $out";
    };
  });
}
