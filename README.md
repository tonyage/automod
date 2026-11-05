# automod

Runs a language model as its own server, with an OpenAI-compatible HTTP API
(`/v1/chat/completions`), for anything that needs one. The model isn't part of
any image or this repo; which model to use is pinned to an exact version in
[`model.env`](model.env), so it only changes when that file does.

The current model needs about 20 GB of memory: on the GPU, in system memory, or
split between them.

It runs with Nix or Docker Compose. Both read the pins in `model.env` and run
the same llama.cpp build (0.6.0, build 11429) on Linux.

## NixOS

Add the flake to your system's flake and enable the service:

```nix
{
  inputs.automod.url = "github:tonyage/automod";

  outputs = { nixpkgs, automod, ... }: {
    nixosConfigurations.rack = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [ ./configuration.nix automod.nixosModules.default ];
    };
  };
}
```

```nix
# configuration.nix
{
  services.automod.enable = true;

  # NVIDIA driver
  nixpkgs.config.allowUnfree = true;
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.graphics.enable = true;
  hardware.nvidia.open = true;

  # llama.cpp's CUDA build, so it isn't compiled on the machine
  nix.settings = {
    substituters = [ "https://cache.nixos-cuda.org" ];
    trusted-public-keys = [
      "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
    ];
  };
}
```

Add the cache and rebuild once before enabling the service, so the first build
already uses it. The service listens on `127.0.0.1:8080` and downloads the
model (about 19 GB) into `/var/lib/automod` on first start;
`journalctl -u automod -f` shows progress.

| Option | Default | Description |
| ------ | ------- | ----------- |
| `acceleration` | `"cuda"` | `"cuda"` for NVIDIA GPUs, `"vulkan"` for AMD and other GPUs, or `"cpu"` |
| `host`, `port` | `127.0.0.1`, `8080` | Where it listens. `0.0.0.0` for other machines. |
| `openFirewall` | `false` | Open the port, for other machines |
| `apiKeyFile` | none | File with the key requests need. Use one whenever other machines can reach it. |
| `parallel` | `4` | Requests handled at once |
| `contextSize` | `16384` | Tokens of context, shared between parallel requests |
| `cpuMoeLayers` | none | See [GPU memory](#gpu-memory) |
| `extraArgs` | `[]` | More `llama-server` options |

With `apiKeyFile` set, requests need an `Authorization: Bearer <key>` header.
The key is read when the service starts and never copied into the Nix store.

## Docker Compose (Linux)

`compose.yaml` runs it on an NVIDIA GPU. The host needs the NVIDIA driver and
the
[NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html);
check with `docker run --rm --gpus all ubuntu nvidia-smi`. Then:

```console
docker compose up -d
```

The first start downloads the model (about 19 GB) into the `model-cache`
volume; `docker compose logs model` shows progress.

For other hardware, change the image to the build with the same number:
`server-…` for CPU only, `server-vulkan-…` for AMD and other GPUs, or
`server-intel-…` for Intel, and remove the service's `deploy` section.

### Using it from other Compose projects

The server is only reachable from containers on the `automod` network. To use
it from another project on the same machine, add the network to that project's
`compose.yaml`:

```yaml
services:
  app:
    networks: [default, automod]

networks:
  automod:
    external: true
```

The app then reaches it at `http://automod:8080`. Start this project first, or
the other one won't find the network.

### Using it from other machines

Put a key in a `.env` file next to `compose.yaml`, then uncomment `ports` in
`compose.yaml`:

```text
API_KEY=a-long-random-key
```

Requests then need an `Authorization: Bearer <key>` header. Without a key,
anyone who can reach the port can use the model.

## Mac (Apple silicon)

Docker on a Mac can't use the GPU, so the model runs with MLX instead. Either:

```console
nix run github:tonyage/automod
```

or, from a clone, with [uv](https://docs.astral.sh/uv/) installed:

```console
./serve-mac.sh
```

The first run downloads the model (about 17 GB) into `~/.cache/huggingface`.
It then listens on `127.0.0.1:8080`. From inside Docker, it's at
`http://host.docker.internal:8080`.

## Other Linux, with Nix

Without the NixOS module, the same server runs in the foreground, keeping the
model in `~/.cache/automod`:

```console
nix run github:tonyage/automod#cuda    # or #vulkan, #cpu
```

## GPU memory

If the model is bigger than the GPU's memory, as the current one is for a 16 GB
card, llama.cpp keeps as much as fits on the GPU and the rest in system memory,
and logs the split when it starts. If it runs out of GPU memory, or to tune it,
keep the expert weights of the first N layers on the CPU: `cpuMoeLayers` with
NixOS, or `LLAMA_ARG_N_CPU_MOE` in `compose.yaml`. Start around 16; fewer is
faster, while it still fits.

## Changing the model

Update the pins in `model.env`, check the new model does its jobs as well as
the old one, and commit it. With Docker, each machine downloads the new model on
its next start; with NixOS, after `nix flake update automod` and a rebuild.

To update llama.cpp, move the `nixpkgs` input in `flake.nix` and the image tags
in `compose.yaml` to the same build, so both keep running the same version.
