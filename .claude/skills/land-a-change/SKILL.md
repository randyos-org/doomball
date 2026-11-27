---
name: land-a-change
description: Land a change in doomball on dev - the checks, commit and pull request as the randyos-org agent app, merge, the issue closed or commented on, and the CI of the standing dev to main pull request watched. Use when a change for an issue is ready.
---

# Landing a change

Every change reaches `dev` through a pull request that is merged at once (no check is required on `dev`; CI does not run there). The checks run locally are what stand between the change and `dev`.

1. **Branch:** `git switch -c feature/NAME` (or `fix/NAME`) from an up-to-date `dev`.
2. **Write the pull request body** to a file (heredocs mangle backslashes and quotes): what changed and why, `Closes #N` (or `Part of #N`), **How it was checked** (the checks below, and anything tried by hand), **Choices made without guidance**, and the Claude Code line at the end.
3. **Land it:** `bash tools/agent/land.sh --model "Claude MODEL" ISSUE LABEL "Commit line" "PR title" BODY_FILE close|keep PATH...`, with the model this session runs on (`Claude Opus 5.5`, say: emanspeaks switches models, so it is never assumed) for the commit's `Co-Authored-By`, naming every path of the change (never `git add -A`: emanspeaks works in this tree too). It runs `version.sh`, `zig fmt --check`, `zig build`, `zig build test`, the headless game, the two Windows builds, markdownlint and cspell, then commits as the app, opens the pull request into `dev` with the release-note label, merges it, deletes the branch and closes (or comments on) the issue; `-` as the issue for a change asked for without one. Set `ZIG` to the Zig 0.17.1 executable when `zig` is not on the PATH.
4. **CI:** each merge into `dev` restarts CI on the standing pull request. Watch it (`gh run list --branch dev --limit 1`, then `gh run view ID`); a red run means `dev` is broken, and its fix is the next pull request.

Labels: `feature`, `fix`, `performance`, `tests`, `refactor`, `ci`, `documentation`, `skip-changelog` (`.github/release.yml`); the script refuses one the repository does not have before it does anything. Commit lines are about 50 characters, no body; the AI attribution trailer is added by the script.

Traps: in the Bash tool on this machine, a command line containing a single quote fails with "unexpected EOF while looking for matching" before it runs, so put such commands in a script file and run the file.
