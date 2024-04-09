{
  lib,
  nix-filter,
  nltk-data,
}:
let
  additional-py-pkgs = (
    final: prev: python-final: python-prev: {
      # pull the latest version of bitsandbytes from pypi.
      # we do this because the version in nixpkgs is slightly outdated
      # and does not appear to be compiled with all required CUDA
      # libraries.
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
      llama-index-core =
        let
          # unzip the data that is relevant to us
          relevant-nltk-data = final.runCommand "relevant-nltk-data" { } ''
            NLTK_DIR=${nltk-data}/packages
            mkdir $out
            ${final.unzip}/bin/unzip \
              $NLTK_DIR/corpora/stopwords.zip \
              -d $out/corpora
            ${final.unzip}/bin/unzip \
              $NLTK_DIR/tokenizers/punkt.zip \
              -d $out/tokenizers
          '';
        in
        python-prev.llama-index-core.overridePythonAttrs (old: {
          # provide the NLTK data created above to the library by
          # overriding its static reference to said data
          prePatch = ''
            substituteInPlace llama_index/core/utils.py \
              --replace-fail 'os.path.dirname(os.path.abspath(__file__))' \
                             "\"${relevant-nltk-data}\"" \
              --replace-fail '"_static/nltk_cache"' \
                             '""'
          '';
        });

      # build llama-index-llms-huggingface, as it is not provided in nixpkgs
      llama-index-llms-huggingface = python-final.buildPythonPackage rec {
        pname = "llama_index_llms_huggingface";
        version = "0.1.4";
        format = "pyproject";
        src = final.fetchPypi {
          inherit pname version;
          hash = "sha256-ssCWcbz+oi1Vt0RTlYJisEL4zEi6sbZg4V/Ux/GAj9Y=";
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
    }
  );
in
rec {
  default = its-qna;

  # apply the python package fixes from above
  fix-nixpkgs = (
    final: prev: {
      pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [ (additional-py-pkgs final prev) ];
    }
  );

  # add the python library and its related python libraries
  python-lib = lib.composeExtensions fix-nixpkgs (
    final: prev: {
      pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
        (python-final: python-prev: {
          its-qna = python-final.callPackage ./python-lib.nix { inherit nix-filter; };
        })
      ];
    }
  );

  # add the standalone python application (without also adding the python
  # library)
  its-qna = (
    final: prev:
    let
      py-pkgs = final.python3Packages;
      its-qna = py-pkgs.callPackage ./python-lib.nix (
        { inherit nix-filter; } //
        # inject our additional / changed python dependencies into the
        # callPackage call
        (additional-py-pkgs final prev py-pkgs py-pkgs)
      );
    in
    {
      its-qna = py-pkgs.callPackage ./package.nix { inherit its-qna; };
    }
  );
}
