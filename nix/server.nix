# Linux: llama.cpp's server, set up to download the pinned model on first
# start. Settings can be overridden with LLAMA_ARG_* variables.
{
  lib,
  writeShellApplication,
  llama-cpp,
  pins,
}:
writeShellApplication {
  name = "automod-serve";
  runtimeInputs = [ llama-cpp ];
  text = ''
    # Where the model is kept: systemd's StateDirectory, or a cache folder
    dir=''${STATE_DIRECTORY:-''${XDG_CACHE_HOME:-$HOME/.cache}/automod}
    mkdir -p "$dir"

    # Without a path, llama.cpp ignores the URL and starts with no model
    export LLAMA_ARG_MODEL_URL=''${LLAMA_ARG_MODEL_URL:-${lib.escapeShellArg pins.LLAMA_ARG_MODEL_URL}}
    export LLAMA_ARG_MODEL=''${LLAMA_ARG_MODEL:-$dir/model.gguf}
    export LLAMA_ARG_HOST=''${LLAMA_ARG_HOST:-127.0.0.1}
    export LLAMA_ARG_PORT=''${LLAMA_ARG_PORT:-8080}
    # Room for 4 requests at once, about 4,000 tokens each
    export LLAMA_ARG_N_PARALLEL=''${LLAMA_ARG_N_PARALLEL:-4}
    export LLAMA_ARG_CTX_SIZE=''${LLAMA_ARG_CTX_SIZE:-16384}

    exec llama-server "$@"
  '';
}
