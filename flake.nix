{
  description = "A language model server with an OpenAI-compatible API";

  # A nixos-unstable update from 2026-10-20, with llama.cpp 0.6.0 (build 11429),
  # the same build as the Docker images in compose.yaml
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/02c087f3fe673c9e317f206a627cb6b910336dbe";

  # The NixOS CUDA team's cache has llama.cpp's CUDA build, so it isn't
  # compiled on every machine. The others are in cache.nixos.org.
  nixConfig = {
    extra-substituters = [ "https://cache.nixos-cuda.org" ];
    extra-trusted-public-keys = [
      "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
    ];
  };

  outputs =
    { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;
      pins = import ./nix/pins.nix { inherit lib; };
      linux = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      mac = [ "aarch64-darwin" ];
      forSystems = systems: f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      # CUDA is unfree, so its licenses are allowed, not unfree packages in general
      withCuda =
        system:
        import nixpkgs {
          inherit system;
          config.allowUnfreePredicate =
            pkg:
            lib.all (
              license:
              license.free
              || lib.elem license.shortName [
                "CUDA EULA"
                "cuDNN EULA"
                "cuSPARSELt EULA"
                "cuTENSOR EULA"
              ]
            ) (lib.toList (pkg.meta.license or [ ]));
        };
    in
    {
      packages =
        forSystems linux (
          pkgs:
          let
            server = llama-cpp: pkgs.callPackage ./nix/server.nix { inherit llama-cpp pins; };
            cudaPkgs = withCuda pkgs.stdenv.hostPlatform.system;
          in
          rec {
            cpu = server pkgs.llama-cpp;
            cuda = server (cudaPkgs.llama-cpp.override { cudaSupport = true; });
            vulkan = server (pkgs.llama-cpp.override { vulkanSupport = true; });
            default = cuda;
          }
        )
        // forSystems mac (pkgs: {
          default = pkgs.callPackage ./nix/mac.nix { };
        });

      nixosModules.default = import ./nix/module.nix self;

      formatter = forSystems (linux ++ mac) (pkgs: pkgs.nixfmt);
    };
}
