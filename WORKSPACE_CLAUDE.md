# Agent rules for this container

You are running inside the agentic-coding-demo container. These rules apply whenever you do work in `/workspace`.

## Running CodeRabbit

CodeRabbit auth in this container comes from the bind-mounted `~/.coderabbit/auth.json` — **not** an API key, not an env var, and not an interactive login. If `coderabbit auth status` shows "Not logged in", the mount is missing or the host CLI is not logged in. **Stop and report that to the user. Do not invent a workaround and do not fabricate a review report.**

### How to invoke

Use the wrapper:

```
coderabbit-review
```

…which is equivalent to `coderabbit review --plain`.

If the working tree has no diff against the default base (e.g. all your work is committed on a single-branch repo with no remote), `coderabbit review` will exit with `No files found for review`. In that case, pass an explicit base so it reviews your commits:

```
# review everything since the repo's first commit
coderabbit review --plain --base-commit "$(git rev-list --max-parents=0 HEAD)"

# or review against a known base branch
coderabbit review --plain --base main
```

For machine-readable output use `--agent` instead of `--plain`.

## The review-and-fix loop

When a task says "run coderabbit when complete and address critical/minor issues":

1. Finish the implementation and commit it.
2. Run `coderabbit review --plain` (with a `--base-commit` or `--base` if needed — see above).
3. For each Critical or Minor finding, fix it in the code and commit. Do not silence findings by suppressing them or by editing the report.
4. Re-run the review. Repeat until no Critical or Minor findings remain, or until further fixes would clearly exceed the task scope.
5. Write `CODERABBIT_REPORT.md` containing:
   - The exact command(s) you ran and the final output (verbatim, including the "Review completed" line or the findings list).
   - For every finding across all runs, whether it was addressed (with the commit SHA) or left unaddressed (with the reason).
   - If there were no findings at any point, say so plainly.
6. Commit the report.

## Honesty rules (important)

- **Never fabricate tool output.** If a command fails, paste the real error and stop. Do not paraphrase a failure into a fake success.
- **Never write a CodeRabbit report from your own code review.** The report documents what CodeRabbit said. If CodeRabbit didn't run, the report says CodeRabbit didn't run and explains why.
- **Don't guess at auth.** If something looks like an auth problem, check `coderabbit auth status` first and surface the result. Do not assume an API key is required — in this harness it is not.

## Other tools available

- `claude-yolo` — `claude --dangerously-skip-permissions`
- `codex-yolo`, `copilot-yolo` — equivalent for Codex / Copilot CLIs
- Standard dev tooling: `git`, `gh`, `rg`, `fd`, `jq`, `python3`, Node 22, build-essential

`/workspace` is bind-mounted from the host, so all your file changes persist on the host filesystem.
