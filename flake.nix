{
  description = "A Python application defined as a Nix Flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    nix-filter.url = "github:numtide/nix-filter";
    nix2container.url = "github:nlewo/nix2container";
    nltk-data = {
      url = "github:nltk/nltk_data";
      flake = false;
    };
  };

  nixConfig = {
    # additional caches for CUDA packages.
    # these packages are not included in the official NixOS cache, as they are
    # distributed under an unfree license
    trusted-substituters = [
      "https://numtide.cachix.org"
      "https://cuda-maintainers.cachix.org"
    ];
    trusted-public-keys = [
      "numtide.cachix.org-1:2ps1kLBUWjxIneOy1Ik6cQjb41X0iXVXeHigGmycPPE="
      "cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
    ];
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      ...
    }:
    {
      # provide the library and application each as an overlay
      overlays = import ./overlays.nix {
        inherit (nixpkgs) lib;
        inherit (self.inputs) nltk-data;
        nix-filter = self.inputs.nix-filter.lib;
      };
    }
    // flake-utils.lib.eachDefaultSystem (
      system:
      let
        # set up nixpkgs with and without CUDA support
        get-pkgs =
          cudaSupport:
          import nixpkgs {
            inherit system;
            config = {
              inherit cudaSupport;
              allowUnfree = true;
            };
            overlays = [
              self.outputs.overlays.python-lib
              self.outputs.overlays.its-qna
            ];
          };

        pkgs-without-cuda = get-pkgs false;
        pkgs-with-cuda = get-pkgs true;

        nix2container = self.inputs.nix2container.packages.${system}.nix2container;
      in
      {
        # the packages that we can build
        packages =
          rec {
            inherit (pkgs-without-cuda) its-qna;
            default = its-qna;
            docker = pkgs-without-cuda.callPackage ./docker.nix { inherit nix2container; };
          }
          // (nixpkgs.lib.optionalAttrs
            # only allow CUDA support on linux systems
            # (PyTorch with CUDA support is marked as broken on darwin)
            (system == "x86_64-linux")
            {
              with-cuda = pkgs-with-cuda.its-qna;
              docker-with-cuda = pkgs-with-cuda.callPackage ./docker.nix { inherit nix2container; };
            }
          );

        # the development environment
        devShells =
          rec {
            default = without-cuda;
            without-cuda = pkgs-without-cuda.callPackage ./shell.nix { };
          }
          // (nixpkgs.lib.optionalAttrs
            # only build docker images on linux systems
            # (PyTorch with CUDA support is marked as broken on darwin)
            (system == "x86_64-linux")
            { with-cuda = pkgs-with-cuda.callPackage ./shell.nix { }; }
          );
      }
    );
}
