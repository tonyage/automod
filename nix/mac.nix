# Mac: runs serve-mac.sh (MLX) with uv, next to the model.env it reads.
{
  stdenvNoCC,
  makeWrapper,
  uv,
}:
stdenvNoCC.mkDerivation {
  name = "automod-serve-mac";
  src = ../.;
  nativeBuildInputs = [ makeWrapper ];
  installPhase = ''
    mkdir -p $out/libexec/automod $out/bin
    cp serve-mac.sh model.env $out/libexec/automod/
    makeWrapper $out/libexec/automod/serve-mac.sh $out/bin/automod-serve \
      --prefix PATH : ${uv}/bin
  '';
  meta.mainProgram = "automod-serve";
}
