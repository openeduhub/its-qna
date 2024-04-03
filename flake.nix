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
    trusted-substituters =
      [ "https://numtide.cachix.org" "https://cuda-maintainers.cachix.org" ];
    trusted-public-keys = [
      "numtide.cachix.org-1:2ps1kLBUWjxIneOy1Ik6cQjb41X0iXVXeHigGmycPPE="
      "cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
    ];
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    let
      nix-filter = self.inputs.nix-filter.lib;

      ### create the python installation for the package
      python-packages-build = py-pkgs:
        with py-pkgs; [
          pandas
          transformers
          bitsandbytes
          accelerate
          llama-index-core
          llama-index-llms-huggingface
          fastapi
          pydantic
          uvicorn
        ];

      ### create the python installation for development
      # the development installation contains all build packages,
      # plus some additional ones we do not need to include in production.
      python-packages-devel = py-pkgs:
        with py-pkgs;
        [ black ipython isort mypy pyflakes pylint pytest pytest-cov ]
        ++ (python-packages-build py-pkgs);

      ### the python package and application
      get-python-package = py-pkgs:
        py-pkgs.buildPythonPackage {
          pname = "its-qna";
          version = "0.1.0";
          /* only include files that are related to the application.
                 this will prevent unnecessary rebuilds
          */
          src = nix-filter {
            root = self;
            include = [
              # folders
              "its_qna"
              "test"
              # files
              ./setup.py
              ./requirements.txt
            ];
            exclude = [ (nix-filter.matchExt "pyc") ];
          };
          propagatedBuildInputs = (python-packages-build py-pkgs);
        };

    in {
      # provide the library and application each as an overlay
      overlays = rec {
        default = app;
        app = (final: prev: {
          my-python-app = self.outputs.packages.${final.system}.default;
        });
        python-lib = (final: prev: {
          pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
            (python-final: python-prev: {
              # our python library
              its-qna = get-python-package python-final;

              # pull the latest version of bitsandbytes from pypi
              # (this may not actually be needed)
              bitsandbytes = python-final.buildPythonPackage rec {
                pname = "bitsandbytes";
                version = "0.43.0";
                format = "wheel";
                src = final.fetchPypi {
                  inherit pname version;
                  format = "wheel";
                  platform = "manylinux_2_24_x86_64";
                  python = "py3";
                  dist = "py3";
                  hash = "sha256-smJq2grkR64M890L6PWwq616vexwVsf7c4qhOlqGIAc=";
                };
              };

              # deterministically download NLTK data and provide it to
              # llama-index-core
              llama-index-core = let
                # unzip the data that is relevant to us
                nltk-data = final.runCommand "nltk-data" { } ''
                  NLTK_DIR=${self.inputs.nltk-data}/packages
                  mkdir $out
                  ${final.unzip}/bin/unzip \
                    $NLTK_DIR/corpora/stopwords.zip \
                    -d $out/corpora
                  ${final.unzip}/bin/unzip \
                    $NLTK_DIR/tokenizers/punkt.zip \
                    -d $out/tokenizers
                '';
              in python-prev.llama-index-core.overridePythonAttrs (old: {
                # provide the NLTK data created above to the library by
                # overriding its static reference to said data
                prePatch = ''
                  substituteInPlace llama_index/core/utils.py \
                    --replace-fail 'os.path.dirname(os.path.abspath(__file__))' \
                                   "\"${nltk-data.out}\"" \
                    --replace-fail '"_static/nltk_cache"' '""'
                '';
              });

              # build llama-index-llms-huggingface, as it is not provided in
              # nixpkgs
              llama-index-llms-huggingface =
                python-final.buildPythonPackage rec {
                  pname = "llama_index_llms_huggingface";
                  version = "0.1.4";
                  format = "pyproject";
                  src = final.fetchPypi {
                    inherit pname version;
                    hash =
                      "sha256-ssCWcbz+oi1Vt0RTlYJisEL4zEi6sbZg4V/Ux/GAj9Y=";
                  };
                  propagatedBuildInputs = with python-final; [
                    llama-index-core
                    huggingface-hub
                    torch
                    poetry-core
                    transformers
                  ];
                  # relax the requirement on huggingface-hub, as nixpkgs
                  # provides a newer version
                  postPatch = ''
                    substituteInPlace pyproject.toml \
                      --replace-fail 'huggingface-hub = "^0.20.3"' \
                                     'huggingface-hub = ">=0.20.3"'
                  '';
                };
            })
          ];
        });
      };
    } // flake-utils.lib.eachDefaultSystem (system:
      let
        # set up nixpkgs with and without CUDA support
        get-pkgs = cudaSupport:
          import nixpkgs {
            inherit system;
            config = {
              inherit cudaSupport;
              allowUnfree = true;
            };
            overlays = [ self.outputs.overlays.python-lib ];
          };
        pkgs-without-cuda = get-pkgs false;
        pkgs-with-cuda = get-pkgs true;

        # simple wrapper for creating the python application
        # TODO: deterministically provide the LLM to use here.
        #       see wlo-topic-assistant for how to do this with huggingface
        #       models.
        get-python-app = pkgs:
          let py-pkgs = (get-python pkgs).pkgs;
          in py-pkgs.toPythonApplication py-pkgs.its-qna;

        # use the default python3 version
        get-python = pkgs: pkgs.python3;

        # the docker image
        get-docker-img = pkgs:
          let
            python-app = get-python-app pkgs;
            nix2container =
              self.inputs.nix2container.packages.${system}.nix2container;
          in nix2container.buildImage {
            name = python-app.pname;
            tag = "latest";
            config = {
              Cmd = [ "${python-app}/bin/its-qna" ];
              ExposedPorts = { "8080/tcp" = { }; };
              # the container needs access to ssl certificates,
              # for downloading the LLM
              Env =
                [ "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt" ];
            };
            maxLayers = 100;
          };

        # the development environment
        get-dev-env = pkgs:
          let python = get-python pkgs;
          in pkgs.mkShell {
            buildInputs = [
              # the development installation of python
              (python.withPackages python-packages-devel)
              # python lsp server
              pkgs.nodePackages.pyright
              # for automatically generating nix expressions, e.g. from PyPi
              pkgs.nix-template
              pkgs.nix-init
              pkgs.poetry
            ];
          };
      in {
        # the packages that we can build
        packages = rec {
          default = without-cuda;
          without-cuda = get-python-app pkgs-without-cuda;
        } // (nixpkgs.lib.optionalAttrs
          # only allow CUDA support on linux systems
          # (PyTorch with CUDA support is marked as broken on darwin)
          (system == "x86_64-linux") {
            with-cuda = get-python-app pkgs-with-cuda;
            docker-with-cuda = get-docker-img pkgs-with-cuda;
          }) // (nixpkgs.lib.optionalAttrs
            # only build docker images on linux systems
            # (PyTorch with CUDA support is marked as broken on darwin)
            (system == "x86_64-linux" || system == "aarch64-linux") rec {
              docker = docker-without-cuda;
              docker-without-cuda = get-docker-img pkgs-without-cuda;
            });

        # the development environment
        devShells = rec {
          default = without-cuda;
          without-cuda = get-dev-env pkgs-without-cuda;
        } // (nixpkgs.lib.optionalAttrs
          # only build docker images on linux systems
          # (PyTorch with CUDA support is marked as broken on darwin)
          (system == "x86_64-linux") {
            with-cuda = get-dev-env pkgs-with-cuda;
          });
      });

}
