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
    overlays.default = final: prev: let
      pkgs = import nixpkgs {
        inherit (prev) system;
        overlays = [ poetry2nix.overlay ];
      };
      project = projectWithPkgs pkgs;
    in {
      automatic-ripping-machine = project.app;
    };
  } // flake-utils.lib.eachSystem [ flake-utils.lib.system.x86_64-linux ] (system: let
    pkgs = import nixpkgs {
      overlays = [ self.overlays.default ];
      inherit system;
    };
    project = projectWithPkgs pkgs;
  in {
    devShells.default = pkgs.mkShell {
      nativeBuildInputs = [ pkgs.bashInteractive ];
      buildInputs = [ pkgs.poetry pkgs.automatic-ripping-machine project.env ];
    };

    packages = {
      inherit (pkgs) automatic-ripping-machine;
    };

    nixosModules.default = import ./nix/module.nix;

    checks = {
      pylint = pkgs.runCommandNoCC "pylint" {
        nativeBuildInputs = [ project.env ];
        preferLocalBuild = true;
        } "flake8 > $out";
      evalnix = pkgs.runCommandNoCC "evalnix" {
        nativeBuildInputs = [ pkgs.fd ];
        preferLocalBuild = true;
      } "fd --extension nix --exec nix-instantiate --parse --quiet {} > $out";
    };
  });
}

