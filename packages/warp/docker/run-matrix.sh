#!/bin/sh

set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    COMPOSE="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE="docker-compose"
else
    echo "ERROR: docker compose or docker-compose is required" >&2
    exit 1
fi

for service in warp-alpine warp-debian warp-fedora; do
    echo "==> Building ${service}"
    $COMPOSE -f "${ROOT_DIR}/docker-compose.yml" build "${service}"
    echo "==> Running ${service}"
    $COMPOSE -f "${ROOT_DIR}/docker-compose.yml" run --rm "${service}"
done
