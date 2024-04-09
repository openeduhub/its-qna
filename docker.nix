# build a OCI images using nix2container
{ nix2container, its-qna, cacert }:
nix2container.buildImage {
  name = its-qna.pname;
  tag = "latest";
  config = {
    Cmd = [ "${its-qna}/bin/its-qna" ];
    ExposedPorts = {
      "8080/tcp" = { };
    };
    # the container needs access to ssl certificates,
    # for downloading the LLM
    Env = [ "SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt" ];
  };
  maxLayers = 100;
}
