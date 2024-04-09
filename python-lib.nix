# the standalone python application
{
  nix-filter,
  buildPythonPackage,
  pandas,
  transformers,
  bitsandbytes,
  accelerate,
  llama-index-core,
  llama-index-llms-huggingface,
  fastapi,
  pydantic,
  uvicorn,
}:
buildPythonPackage {
  pname = "its-qna";
  version = "0.1.0";
  
  # only include files that are related to the application.
  # this will prevent unnecessary rebuilds
  src = nix-filter {
    root = ./.;
    include = [
      "its_qna"
      ./setup.py
      ./requirements.txt
    ];
    exclude = [ (nix-filter.matchExt "pyc") ];
  };
  
  propagatedBuildInputs = [
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
}
