#!/usr/bin/env bash
# Launch the agentic container mounted on ../fifteen-thirty-one-go for demos.
set -euo pipefail

HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_REPO="${DEMO_REPO:-$(cd "$HARNESS_DIR/../fifteen-thirty-one-go" && pwd)}"

if [[ ! -d "$DEMO_REPO" ]]; then
  echo "demo repo not found: $DEMO_REPO" >&2
  exit 1
fi

LINK="$HARNESS_DIR/fifteen-thirty-one-go"
if [[ ! -e "$LINK" ]]; then
  ln -s "$DEMO_REPO" "$LINK"
fi

if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
  echo "ANTHROPIC_API_KEY is not set in the environment" >&2
  exit 1
fi

cat > "$HARNESS_DIR/.env" <<EOF
HOST_REPO=$DEMO_REPO
LOCAL_UID=$(id -u)
LOCAL_GID=$(id -g)
ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY
EOF

cd "$HARNESS_DIR"
docker compose build
exec docker compose run --rm agentic "$@"
