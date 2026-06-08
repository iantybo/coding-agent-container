#!/usr/bin/env bash
# Quickstart: pick a directory to mount, then run Claude Code in yolo mode inside
# the container with a user-given prompt.
#
# Usage:
#   ANTHROPIC_API_KEY=... ./quickstart.sh ["your prompt here"]
#
# If no prompt is passed, you'll be prompted for one interactively.
# If HOST_REPO is unset, an fzf directory browser lets you pick what to mount;
# the browser starts in $START_DIR (default: current directory).
# Drops you into an interactive Claude session seeded with your prompt.
#
# Defaults:
#   - model: claude-opus-4-8 (override with CLAUDE_MODEL)
#   - mode:  --dangerously-skip-permissions (yolo)
set -euo pipefail

HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
  echo "ANTHROPIC_API_KEY is not set in the environment" >&2
  exit 1
fi

if ! command -v fzf >/dev/null 2>&1; then
  echo "fzf is required for the directory browser (brew install fzf)" >&2
  exit 1
fi

# --- Pick the directory to mount as /workspace -------------------------------
# fzf-driven filesystem browser: Enter descends into a dir, Ctrl-S selects the
# current dir as the mount, Ctrl-H goes up a level.
browse_dir() {
  local cur="${1:-$PWD}"
  while :; do
    local choice
    choice="$(
      { printf '.  [mount this directory: %s]\n' "$cur"
        printf '..\n'
        find "$cur" -mindepth 1 -maxdepth 1 -type d 2>/dev/null \
          | sort | sed "s#^$cur/#  #"
      } | fzf --height=90% --reverse --no-multi \
            --prompt="$cur > " \
            --header='Enter: open  |  pick "." to mount this dir  |  ".." to go up' \
    )" || return 1

    case "$choice" in
      ".  "*) printf '%s\n' "$cur"; return 0 ;;
      "..")   cur="$(dirname "$cur")" ;;
      *)      cur="$cur/$(printf '%s' "$choice" | sed 's/^  //')" ;;
    esac
  done
}

if [[ -n "${HOST_REPO:-}" ]]; then
  MOUNT_DIR="$HOST_REPO"
else
  MOUNT_DIR="$(browse_dir "${START_DIR:-$PWD}")" || { echo "no directory selected" >&2; exit 1; }
fi

if [[ ! -d "$MOUNT_DIR" ]]; then
  echo "not a directory: $MOUNT_DIR" >&2
  exit 1
fi
MOUNT_DIR="$(cd "$MOUNT_DIR" && pwd)"

# --- Prompt ------------------------------------------------------------------
PROMPT="$*"
if [[ -z "$PROMPT" ]]; then
  read -r -e -p "Prompt for Claude: " PROMPT
fi
if [[ -z "$PROMPT" ]]; then
  echo "no prompt given" >&2
  exit 1
fi

# --- CodeRabbit auth ---------------------------------------------------------
# compose.yaml bind-mounts ~/.coderabbit, so the container's CLI reads auth.json
# directly. Only warn if the host isn't logged in; otherwise it Just Works.
CR_AUTH="$HOME/.coderabbit/auth.json"
if [[ -s "$CR_AUTH" ]] && grep -q '"accessToken"' "$CR_AUTH" 2>/dev/null; then
  echo "coderabbit: using host auth at $CR_AUTH"
else
  echo "coderabbit: no auth found at $CR_AUTH — run 'coderabbit auth login' on the host first if you need reviews" >&2
fi

# --- Launch ------------------------------------------------------------------
MODEL="${CLAUDE_MODEL:-claude-opus-4-8}"

# Use a clean, throwaway Claude config so the container authenticates purely via
# ANTHROPIC_API_KEY. Mounting the host login (~/.claude.json) makes interactive
# Claude prefer its OAuth account and report "not logged in" when the env key's
# hash isn't pre-approved there. An empty config sidesteps that entirely.
CLEAN_CFG="$HARNESS_DIR/.agent-home/quickstart-claude"
mkdir -p "$CLEAN_CFG"
printf '{"hasCompletedOnboarding":true}\n' > "$CLEAN_CFG.json"

cat > "$HARNESS_DIR/.env" <<EOF
HOST_REPO=$MOUNT_DIR
LOCAL_UID=$(id -u)
LOCAL_GID=$(id -g)
ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY
CLAUDE_CONFIG_DIR=$CLEAN_CFG
CLAUDE_CONFIG_JSON=$CLEAN_CFG.json
EOF

echo "mounting $MOUNT_DIR -> /workspace, model $MODEL"
cd "$HARNESS_DIR"
# Build with stdin closed so BuildKit doesn't wait on the terminal ("no stdin
# data received" warning). Skip the build entirely with QUICKSTART_NO_BUILD=1.
if [[ -z "${QUICKSTART_NO_BUILD:-}" ]]; then
  docker compose build < /dev/null
fi
# Interactive session (TTY, no -p) seeded with the prompt as the first turn.
exec docker compose run --rm agentic bash -lc \
  'cd /workspace && exec claude --dangerously-skip-permissions --model "$1" "$2"' \
  _ "$MODEL" "$PROMPT"
