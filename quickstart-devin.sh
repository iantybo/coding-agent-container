#!/usr/bin/env bash
# Quickstart: pick a directory to mount, then run the Devin CLI in yolo mode
# inside the container with a user-given prompt.
#
# Usage:
#   ./quickstart-devin.sh ["your prompt here"]
#
# If no prompt is passed, you'll be prompted for one interactively.
# If HOST_REPO is unset, an fzf directory browser lets you pick what to mount;
# the browser starts in $START_DIR (default: current directory).
# Drops you into an interactive Devin session seeded with your prompt.
#
# Auth: Devin reads the host login mounted from ~/.local/share/devin
# (credentials.toml) — no API key needed. Log in on the host with `devin`
# first if you haven't. ANTHROPIC_API_KEY is optional and only wired through
# for Claude/CodeRabbit tooling you might invoke inside the session.
#
# Defaults:
#   - model: whatever the host config selects (override with DEVIN_MODEL)
#   - mode:  --permission-mode dangerous (yolo: auto-approves all tools)
set -euo pipefail

HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v fzf >/dev/null 2>&1; then
  echo "fzf is required for the directory browser (brew install fzf)" >&2
  exit 1
fi

# --- Pick the directory to mount as /workspace -------------------------------
# fzf-driven filesystem browser: Enter descends into a dir, picking "." selects
# the current dir as the mount, ".." goes up a level.
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
  read -r -e -p "Prompt for Devin: " PROMPT
fi
if [[ -z "$PROMPT" ]]; then
  echo "no prompt given" >&2
  exit 1
fi

# --- Devin auth --------------------------------------------------------------
# compose.yaml bind-mounts ~/.local/share/devin, so the container's CLI reads
# credentials.toml directly. Only warn if the host isn't logged in.
DEVIN_CREDS="$HOME/.local/share/devin/credentials.toml"
if [[ -s "$DEVIN_CREDS" ]]; then
  echo "devin: using host auth at $DEVIN_CREDS"
else
  echo "devin: no credentials found at $DEVIN_CREDS — run 'devin' on the host and log in first" >&2
fi

# --- CodeRabbit auth (optional, for reviews inside the session) --------------
CR_AUTH="$HOME/.coderabbit/auth.json"
if [[ -s "$CR_AUTH" ]] && grep -q '"accessToken"' "$CR_AUTH" 2>/dev/null; then
  echo "coderabbit: using host auth at $CR_AUTH"
fi

# --- Launch ------------------------------------------------------------------
# Use a clean, throwaway Claude config so any Claude tooling invoked inside the
# session authenticates purely via ANTHROPIC_API_KEY (mirrors quickstart.sh).
CLEAN_CFG="$HARNESS_DIR/.agent-home/quickstart-claude"
mkdir -p "$CLEAN_CFG"
printf '{"hasCompletedOnboarding":true}\n' > "$CLEAN_CFG.json"

{
  echo "HOST_REPO=$MOUNT_DIR"
  echo "LOCAL_UID=$(id -u)"
  echo "LOCAL_GID=$(id -g)"
  echo "CLAUDE_CONFIG_DIR=$CLEAN_CFG"
  echo "CLAUDE_CONFIG_JSON=$CLEAN_CFG.json"
  [[ -n "${ANTHROPIC_API_KEY:-}" ]] && echo "ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY"
} > "$HARNESS_DIR/.env"

echo "mounting $MOUNT_DIR -> /workspace, agent devin"
cd "$HARNESS_DIR"
# Build with stdin closed so BuildKit doesn't wait on the terminal. Skip the
# build entirely with QUICKSTART_NO_BUILD=1.
if [[ -z "${QUICKSTART_NO_BUILD:-}" ]]; then
  docker compose build < /dev/null
fi
# Interactive session (TTY) seeded with the prompt as the first turn. Pass the
# model as a positional arg ($1): empty means "no --model flag", letting the
# host config decide. (Forwarding it via the DEVIN_MODEL env var instead would
# make an empty value an error — devin reads [env: DEVIN_MODEL=] and rejects "".)
exec docker compose run --rm agentic bash -lc '
  cd /workspace
  args=(--permission-mode dangerous)
  [[ -n "$1" ]] && args+=(--model "$1")
  exec devin "${args[@]}" -- "$2"
' _ "${DEVIN_MODEL:-}" "$PROMPT"
