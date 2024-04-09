{
  mkShell,
  python3,
  pyright,
  nix-template,
  nix-init,
  nix-tree,
}:
mkShell {
  packages = [
    (python3.withPackages (
      py-pkgs:
      with py-pkgs;
      [
        black
        ipython
        isort
        mypy
        pyflakes
        pylint
        pytest
        pytest-cov
      ]
      ++ py-pkgs.its-qna.propagatedBuildInputs
    ))
    pyright
    nix-template
    nix-init
    nix-tree
  ];
}
