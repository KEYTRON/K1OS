#!/bin/bash
# Configure the runner once (the registration token is only needed then;
# .runner/.credentials live on the persistent volume) and run it forever.
set -euo pipefail

: "${REPO_URL:?REPO_URL is required (https://github.com/OWNER/REPO)}"
: "${RUNNER_NAME:=k1lab-$(hostname)}"
: "${RUNNER_LABELS:=}"

cd /runner

if [ ! -f .runner ]; then
    : "${RUNNER_TOKEN:?RUNNER_TOKEN (registration token) is required for first start}"
    labels="self-hosted,k1lab,linux,x64${RUNNER_LABELS:+,$RUNNER_LABELS}"
    ./config.sh --unattended \
        --url "${REPO_URL}" \
        --token "${RUNNER_TOKEN}" \
        --name "${RUNNER_NAME}" \
        --labels "${labels}" \
        --work _work \
        --replace
fi

# Forward SIGTERM so `docker stop` finishes the current job cleanly.
trap 'kill -TERM "$child" 2>/dev/null' TERM INT
./run.sh &
child=$!
wait "$child"
