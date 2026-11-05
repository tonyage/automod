#!/bin/sh
# Runs the model server on a Mac with Apple silicon, using MLX. The model
# and mlx-lm versions are pinned in model.env. Needs uv; the first run downloads
# the model (about 17 GB) into ~/.cache/huggingface.
#
#   ./serve-mac.sh                  # listens on 127.0.0.1:8080
#   PORT=8081 ./serve-mac.sh
set -eu
cd "$(dirname "$0")"
. ./model.env

set -- uv run --quiet --no-project --with "mlx-lm==$MLX_LM_VERSION"

model=$("$@" python -c '
import sys
from huggingface_hub import snapshot_download
print(snapshot_download(sys.argv[1], revision=sys.argv[2]))
' "$MLX_MODEL" "$MLX_REVISION")

exec "$@" mlx_lm.server --model "$model" \
    --host "${HOST:-127.0.0.1}" --port "${PORT:-8080}"
