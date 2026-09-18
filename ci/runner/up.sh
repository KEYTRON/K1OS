#!/bin/bash
# Build the runner image and (re)start the three lab runners. Registration
# tokens are fetched with the local `gh` login and are only consumed on a
# runner's very first start; afterwards the persisted config is reused.
set -euo pipefail
cd "$(dirname "$0")"

token() {
    gh api -X POST "repos/KEYTRON/$1/actions/runners/registration-token" --jq .token
}

export K1K_RUNNER_TOKEN="$(token K1K)"
export K1OS_RUNNER_TOKEN="$(token K1OS)"
export WARP_RUNNER_TOKEN="$(token WARP)"

docker compose up -d --build "$@"
docker compose ps
