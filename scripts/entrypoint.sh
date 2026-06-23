#!/usr/bin/env bash
set -euo pipefail

workspace="${WORKSPACE:-/workspace}"

mkdir -p \
  "$HOME/.claude" \
  "$HOME/.coderabbit" \
  "$HOME/.config/claude" \
  "$HOME/.config/devin" \
  "$HOME/.local/share/claude" \
  "$HOME/.local/share/devin"

if [ -d "$workspace/.git" ]; then
  git config --global --add safe.directory "$workspace" || true
fi

if [ -f "$HOME/.claude/.claude.json" ] && [ ! -e "$HOME/.claude.json" ]; then
  cp "$HOME/.claude/.claude.json" "$HOME/.claude.json"
fi

if [ -f /etc/agentic/CLAUDE.md ] && [ ! -e "$workspace/CLAUDE.md" ]; then
  cp /etc/agentic/CLAUDE.md "$workspace/CLAUDE.md" 2>/dev/null || true
fi

exec "$@"
