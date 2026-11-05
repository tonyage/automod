# NixOS module: runs the model server as a systemd service.
self:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.automod;
  inherit (lib) mkOption types;
in
{
  options.services.automod = {
    enable = lib.mkEnableOption "the automod language model server";

    acceleration = mkOption {
      type = types.enum [
        "cuda"
        "vulkan"
        "cpu"
      ];
      default = "cuda";
      description = ''
        What runs the model: "cuda" for NVIDIA GPUs, "vulkan" for AMD and other
        GPUs, or "cpu".
      '';
    };

    package = mkOption {
      type = types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.${cfg.acceleration};
      defaultText = lib.literalExpression "automod.packages.\${system}.\${acceleration}";
      description = "The server to run.";
    };

    host = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Address to listen on. Use 0.0.0.0 to accept requests from other machines.";
    };

    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Port to listen on.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open the port in the firewall, for requests from other machines.";
    };

    apiKeyFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      example = "/run/secrets/automod-api-key";
      description = ''
        File holding the key that requests need, as
        `Authorization: Bearer <key>`. Without one, anyone who can reach the
        port can use the model. Read when the service starts; never copied into
        the Nix store.
      '';
    };

    parallel = mkOption {
      type = types.ints.positive;
      default = 4;
      description = "How many requests are handled at once.";
    };

    contextSize = mkOption {
      type = types.ints.positive;
      default = 16384;
      description = "Tokens of context, shared between the parallel requests.";
    };

    cpuMoeLayers = mkOption {
      type = types.nullOr types.ints.unsigned;
      default = null;
      example = 16;
      description = ''
        Keep the expert weights of the first N layers on the CPU. By default
        llama.cpp puts as much as fits on the GPU and the rest on the CPU; set
        this after an out-of-memory error. Fewer is faster, while it still fits.
      '';
    };

    extraArgs = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "More command-line options for llama-server.";
    };
  };

  config = lib.mkIf cfg.enable {
    warnings = lib.optional (cfg.openFirewall && cfg.apiKeyFile == null) ''
      services.automod: the port is open with no apiKeyFile, so anyone who can
      reach it can use the model.
    '';

    systemd.services.automod = {
      description = "automod language model server";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];

      environment = {
        LLAMA_ARG_HOST = cfg.host;
        LLAMA_ARG_PORT = toString cfg.port;
        LLAMA_ARG_N_PARALLEL = toString cfg.parallel;
        LLAMA_ARG_CTX_SIZE = toString cfg.contextSize;
      }
      // lib.optionalAttrs (cfg.cpuMoeLayers != null) {
        LLAMA_ARG_N_CPU_MOE = toString cfg.cpuMoeLayers;
      };

      serviceConfig = {
        ExecStart = lib.escapeShellArgs (
          [ (lib.getExe cfg.package) ]
          ++ lib.optionals (cfg.apiKeyFile != null) [
            "--api-key-file"
            "%d/api-key"
          ]
          ++ cfg.extraArgs
        );
        LoadCredential = lib.optional (cfg.apiKeyFile != null) "api-key:${cfg.apiKeyFile}";
        Restart = "on-failure";

        # The model is downloaded here on first start (about 19 GB)
        DynamicUser = true;
        StateDirectory = "automod";
        # GPUs: /dev/dri for Vulkan; NVIDIA's devices are open to all users
        SupplementaryGroups = [
          "render"
          "video"
        ];

        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictNamespaces = true;
        LockPersonality = true;
      };
    };

    networking.firewall.allowedTCPPorts = lib.optional cfg.openFirewall cfg.port;
  };
}
