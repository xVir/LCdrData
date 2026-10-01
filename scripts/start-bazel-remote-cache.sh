#!/bin/bash
#
# Starts the local Bazel remote cache (buchgr/bazel-remote-cache) in Docker.
#
# The compose file binds gRPC to 127.0.0.1:39092, which is the address
# local.bazelrc passes to --remote_cache. The cache lives on a tmpfs, so
# stopping the container drops it. Bazel treats an unreachable --remote_cache
# as a hard failure, which is why that flag stays in the gitignored
# local.bazelrc rather than .bazelrc.
#
# Usage:
#   scripts/start-bazel-remote-cache.sh
#
# Stop with:
#   docker compose -f scripts/bazel-remote-cache.yaml down

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

compose_file="scripts/bazel-remote-cache.yaml"
host="127.0.0.1"
port="39092"

if ! command -v docker >/dev/null 2>&1; then
    echo "error: docker is not installed or not on PATH" >&2
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    echo "error: the Docker daemon is not running" >&2
    exit 1
fi

echo "==> Starting Bazel remote cache"
docker compose -f "${compose_file}" up -d

echo "==> Waiting for grpc://${host}:${port}"
for _ in $(seq 1 50); do
    if nc -z "${host}" "${port}" >/dev/null 2>&1; then
        echo "==> Bazel remote cache is ready"
        exit 0
    fi
    sleep 0.2
done

echo "error: the cache container started, but port ${port} is not accepting connections" >&2
docker compose -f "${compose_file}" logs --tail=40 bazel-cache >&2 || true
exit 1
