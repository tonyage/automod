# Reads the KEY=value lines of model.env, so Nix and Docker Compose share the
# same pins.
{ lib }:
let
  lines = lib.splitString "\n" (builtins.readFile ../model.env);
  pairs = lib.filter (m: m != null) (map (builtins.match "([A-Z_]+)=(.*)") lines);
in
lib.listToAttrs (
  map (m: {
    name = lib.elemAt m 0;
    value = lib.elemAt m 1;
  }) pairs
)
