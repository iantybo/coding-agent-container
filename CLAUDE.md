# Orchestrator rules — running tasks in the agentic container

This repo is a **harness**: a Dockerized environment with Claude Code, Codex, Copilot, and CodeRabbit pre-installed. When the user gives you an arbitrary task prompt and asks you to "run it in the container" (or similar), you are the **outer orchestrator** running on the host. Your job is to drive the container, not to do the task yourself.

The *inner* agent's rules (how Claude inside the container should behave — coderabbit invocation, honesty rules, etc.) live in [WORKSPACE_CLAUDE.md](./WORKSPACE_CLAUDE.md) and are auto-dropped into every mounted workspace by the entrypoint.

## The workflow

Given an arbitrary task prompt P from the user:

1. **Pick a workspace.** Default to a fresh dir under `~/git/<task-slug>` so you don't pollute the harness repo. If the user named a target dir, use that.
   ```bash
   mkdir -p ~/git/<slug> && cd ~/git/<slug> && git init -q -b main \
     && git config user.email "$(git config --global user.email)" && git config user.name "$(git config --global user.name)" \
     && echo "# <slug>" > README.md && git add . && git commit -q -m "init"
   ```

2. **Wire auth in `.env`.** Set `HOST_REPO` to the workspace path. Anthropic auth comes from the macOS keychain (no separate key needed):
   ```bash
   CRED=$(security find-generic-password -s "Claude Code" -w)
   ```
   Write `.env` with `HOST_REPO=<path>`, `LOCAL_UID=501`, `LOCAL_GID=20`, `ANTHROPIC_API_KEY=$CRED`. CodeRabbit needs no env wiring — `compose.yaml` bind-mounts `~/.coderabbit` and the CLI reads `auth.json` directly. **Do not pass `CODERABBIT_API_KEY`.** If the host CLI is logged in, the container is logged in.

3. **Build (cached after first run).**
   ```bash
   docker compose build
   ```

4. **Write the task prompt to a file in the workspace** (`PROMPT.md`), commit it. Always include in the prompt:
   - The actual task.
   - "Run `coderabbit-review` when complete and address every Critical and Minor issue. Re-run until clean."
   - "Produce `CODERABBIT_REPORT.md` listing the final review output and any unaddressed findings (with reasons). If there are none, say so plainly."
   - "Work non-interactively — do not ask for confirmation."
   The auto-dropped `WORKSPACE_CLAUDE.md` already carries the honesty rules and the exact coderabbit invocation, so you don't have to repeat those.

5. **Launch Claude non-interactively, in the background, with a `Monitor` watching the workspace.**
   ```bash
   nohup bash -c 'docker compose run --rm -T agentic bash -lc \
     "cd /workspace && claude --dangerously-skip-permissions --model claude-opus-4-5 -p \"\$(cat PROMPT.md)\" 2>&1"' \
     > /tmp/claude-run.log 2>&1 &
   ```
   Use a `Monitor` tool call that polls every ~30s for: log size, commit count, and `ls /workspace`. Critical: `docker compose` must run from this harness repo's directory — if you `cd` elsewhere first you'll get `no configuration file provided: not found`.

6. **When the run exits, verify rather than trust.** Check:
   - Did `CODERABBIT_REPORT.md` get created and committed?
   - Does it contain the literal "Review completed" line from the CLI, or a literal findings list? If it reads like a self-review or claims auth failed, the inner agent fabricated it — re-run coderabbit yourself and overwrite.
   - Run the test/smoke script the task defined.

7. **Surface results to the user**: workspace path, commits, sample tool output, the coderabbit verdict, and any unaddressed findings.

## Things that have bitten us before

- **The first run produced a fake CodeRabbit report.** Claude inside the container couldn't find a token (the host had `auth.json` without `accessToken` because the host CLI wasn't logged in), and instead of stopping it wrote a plausible-looking report claiming "auth required." Always verify step 6.
- **`docker compose` cwd matters.** Running it from the workspace dir fails with "no configuration file provided." Run it from this harness dir.
- **`coderabbit review` with no diff returns "No files found for review."** When everything is committed on a single branch with no remote, pass `--base-commit "$(git rev-list --max-parents=0 HEAD)"` or `--base <branch>`. The `WORKSPACE_CLAUDE.md` already tells the inner agent this; you should know it too in case you re-run coderabbit yourself in step 6.
- **macOS keychain prompts during `docker compose build`** can cancel the build if dismissed. If you see `error getting credentials ... User canceled the operation`, just retry — the keychain unlocks after one accepted prompt.
- **Don't use `CODERABBIT_API_KEY`.** It's a different auth path and the user's key may be rate-limited or out of credits. The mount-based auth Just Works.

## When NOT to follow this workflow

- The user asks you to modify the harness itself (Dockerfile, compose, scripts, this CLAUDE.md). Do that directly on the host.
- The user asks a question about the harness. Answer it; don't launch a container.
- The task is trivial enough that round-tripping through the container adds no value. Ask the user before deciding to skip it.
