# Agentic Coding Container

This image is a small harness for demonstrating coding agents inside a container with a mounted Git checkout and CodeRabbit CLI as the review step.

The image still installs all four CLIs, but the auth harness is currently wired only for Claude Code and CodeRabbit.

Installed CLIs:

- Claude Code
- OpenAI Codex CLI
- GitHub Copilot CLI
- CodeRabbit CLI

## Quickstart: run against a local repo

Prereqs: Docker Desktop running, and the host `claude` CLI logged in once (so `~/.claude*` exists) and the host `coderabbit` CLI logged in once (so `~/.coderabbit/auth.json` exists). The container inherits both via bind mounts — you don't need to copy API keys around.

No CodeRabbit API key? You don't need one — log the host CLI in with your user credentials and the container will mount the resulting `auth.json`. On macOS the keychain has to be unlocked for the login to write the file:

```bash
security lock-keychain login.keychain-db
coderabbit auth login
security unlock-keychain login.keychain-db
```

That creates `~/.coderabbit/auth.json`, which `compose.yaml` bind-mounts into the container so `coderabbit-review` authenticates as you.

From this harness directory:

```bash
# 1. Point at your repo and wire auth into .env.
#    ANTHROPIC_API_KEY is read from your host environment.
cp .env.example .env
REPO=/absolute/path/to/your/repo            # <-- edit me
cat > .env <<EOF
HOST_REPO=$REPO
LOCAL_UID=$(id -u)
LOCAL_GID=$(id -g)
ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY
EOF

# 2. Build (cached after the first run)
docker compose build

# 3a. Drop into an interactive shell in the container, with your repo at /workspace
docker compose run --rm agentic

# 3b. ...or run Claude non-interactively against a prompt file in the repo
docker compose run --rm -T agentic bash -lc \
  'cd /workspace && claude --dangerously-skip-permissions -p "$(cat PROMPT.md)"'
```

## Quickstart

The fastest path: pick a directory to mount with an `fzf` browser, hand Claude Code a prompt, and let it run in yolo mode.

```bash
export ANTHROPIC_API_KEY=...           # from your host environment
./quickstart.sh "add a /health endpoint and tests"
```

`quickstart.sh` opens an `fzf` directory browser so you can navigate the filesystem and mount any directory as `/workspace` (Enter descends, pick `.` to mount the current dir, `..` to go up). If you omit the prompt, it asks for one interactively. CodeRabbit auth is auto-detected from `~/.coderabbit/auth.json` (mounted into the container); the script warns if you aren't logged in.

Requires [`fzf`](https://github.com/junegunn/fzf) on the host (`brew install fzf`).

Defaults: the model is `claude-opus-4-8` and Claude runs with `--dangerously-skip-permissions`. Skip the browser by setting `HOST_REPO=...`; override the model with `CLAUDE_MODEL=...`.

Inside the container you have `claude-yolo`, `codex-yolo`, `copilot-yolo`, and `coderabbit-review` on `PATH`. A typical loop:

```bash
claude-yolo            # let the agent make changes
coderabbit-review      # review the diff; re-run the agent on findings
```

Notes:

- `LOCAL_UID`/`LOCAL_GID` must match your host user so files the container writes stay owned by you. On macOS that's usually `501` / `20`.
- If `coderabbit review` reports "No files found for review" (single-branch repo with no remote), pass `--base-commit "$(git rev-list --max-parents=0 HEAD)"`. The bundled `coderabbit-review` wrapper handles this for you.
- If `docker compose build` fails with `error getting credentials ... User canceled`, accept the macOS keychain prompt and retry.

## Why this shape

- `ubuntu:24.04` so the container feels like a fuller coding workstation instead of a thin runtime image.
- Node.js 22 is installed on top because GitHub Copilot CLI currently requires Node.js 22+.
- Non-root runtime user because Claude's `--dangerously-skip-permissions` mode is intended for non-root container users.
- Auth is env-first so secrets stay out of the image.
- Tool state is persisted through bind mounts so interactive logins can survive container restarts.

Included general-purpose tooling:

- `build-essential`, `make`, `python3`, `python3-pip`, `python3-venv`
- `git`, `git-lfs`, `gh`, `openssh-client`, `rsync`
- `ripgrep`, `fd`, `jq`, `tree`, `tmux`, `vim`, `nano`, `less`
- `shellcheck`, `curl`, `wget`, `dnsutils`, `zip`, `unzip`

## Files

- [Dockerfile](./Dockerfile)
- [compose.yaml](./compose.yaml)
- [.env.example](./.env.example)

## Mount plan

Required:

- Your Git repo at `/workspace`

Recommended persistent state mounts:

- `/home/agent/.claude`
- `/home/agent/.claude.json`
- `/home/agent/.coderabbit`
- `/home/agent/.config/claude`
- `/home/agent/.local/share/claude`

The compose file bind-mounts the live host Claude and CodeRabbit state directly from `${HOME}`, instead of copying snapshots into the workspace.

## Auth plan

Preferred non-interactive auth for demos:

- Claude Code: `ANTHROPIC_API_KEY` or `CLAUDE_CODE_OAUTH_TOKEN`

CodeRabbit should be treated as persisted CLI state instead of env-based auth in this harness. Copy or mount `~/.coderabbit` so the container sees your existing `auth.json`.

Interactive login can still work if you persist the mounted state directories and run the login commands inside the container.

## Suggested demo flow

1. Mount a real Git repo into `/workspace`.
2. Run one agent in its permissive mode against a contained task.
3. Review the result with `coderabbit-review`.
4. Fix findings with the same or a different agent.
5. Repeat until CodeRabbit comes back clean enough for handoff or commit.

## Notes

- The entrypoint marks `/workspace` as a Git safe directory to avoid ownership warnings on mounted repos.
- CodeRabbit auth should come from mounted `~/.coderabbit` state.
- This repo does not pin tool versions yet; if you want reproducible demos, add build args for explicit versions next.
