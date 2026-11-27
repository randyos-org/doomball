# Notes for coding agents

What a coding agent working on doomball needs to know besides the code, the [readme](README.md) and the [issues](https://github.com/randyos-org/doomball/issues). Notes about one machine (paths, hosts, caches) go in `CLAUDE.local.md`, which is not committed. Mistakes made more than once are written down here so they are not made again.

The repository's setup follows skein (chasingdaylight/skein), after zfls (cesiumlang/zfls) and rstd (randyos-org/rstd): when something here is missing, do it as they do.

## What doomball is

Doom-themed pinball in Zig. The game core (`src/game.zig`, `src/render.zig`) draws into a framebuffer and reads an `Input` snapshot; each platform backend (`src/platform_*.zig`) implements `Platform` (`src/platform.zig`). Windows has a Win32 front end; every other platform builds the headless backend, which plays scripted input and writes `doomball.ppm`.

## Rules

- No dependencies: `build.zig.zon` lists none, and the game links only the system libraries of its backend.
- Zig over other languages, built with the pinned official release (0.17.1). Scripts in the repository are bash. Scratch scripts an agent writes to analyze something may be in any language and stay in its scratchpad, never committed.
- Never run a command that downloads or installs software without asking first, package managers included (markdownlint and cspell through `npx` excepted).
- The repository owner is `emanspeaks` in every file, issue and pull request; write `@emanspeaks` only to ask for his input, since every `@` notifies him.
- GitHub is the record of the work, not the chat: a bug, follow-up or decision for emanspeaks gets an issue when it is found.

## Git

- `main` and `dev`. Work goes on a branch from `dev` and reaches `dev` through a pull request; `main` only takes releases, through the standing `dev` to `main` pull request, which emanspeaks merges. Nothing blocks `dev`: no check is required there and CI does not run for it.
- A release is made by CI when `main` gets a version (`build.zig.zon`) that has no tag and something a release ships has changed since the last tag (not documentation or CI alone: `docs-only.txt` and `ci-only.txt` in `.github/workflows/`): it tags the commit, publishes one exe for each Windows target (built with `-Dcpu=baseline`: a release must never take the CPU features of the machine that builds it) and begins the next patch version on `dev`. Releases are not signed; skein's `ci.yml` has the jobs should they be. `.github/workflows/version.sh` lists and checks every place that states the version and sets them all (`version.sh set NEXT`); a new place that states the version goes into it. Never tag or publish by hand.
- On GitHub, agents act as the GitHub App `randyos-agent`, never as emanspeaks: `GH_TOKEN="$(bash /c/scratch/github-apps/app-token.sh randyos-org)"` for `gh`, and `bash /c/scratch/github-apps/app-git.sh randyos-org <git arguments>` for commits, fetches and pushes, with the harness's AI attribution trailer. Never print, copy or commit anything in `/c/scratch/github-apps/randyos-org/`. What the app cannot do stays with emanspeaks: merging `dev` into `main`, repository variables and secrets, and rulesets.
- Commit messages are one short line (about 50 characters), with no body; rationale and test results go in the pull request or the issue.
- Pull requests take the release-note labels of `.github/release.yml` (`fix`, `feature`, `performance`, `tests`, `refactor`, `ci`, `skip-changelog`); their titles are the release notes.
- Before a commit, check `git diff --cached` and `git status` so a commit takes only your own changes. After a merge, delete the branch, locally and on GitHub.
- `.local-gitignore` is this checkout's own ignore file (`git config core.excludesFile .local-gitignore`).

## Zig 0.17: what not to use

doomball builds with Zig 0.17.1, whose standard library marks many older declarations deprecated in their doc comments without the compiler warning about them. The global `zig` skill has the full table; the ones met here:

| Deprecated | Use |
| --- | --- |
| `std.fmt.bufPrint(buf, fmt, args)` | `std.mem.print(buf, fmt, args)` |
| `std.builtin` | `std.lang` |
| `init.minimal.args.iterate()` (POSIX only: does not compile for Windows) | `init.minimal.args.toSlice(init.arena.allocator())` |
| `-Doptimize=Debug`, `ReleaseSafe`, `ReleaseFast`, `ReleaseSmall` | `-Doptimize=debug`, `safe`, `fast`, `small` |

## Style

- `.editorconfig` is authoritative. Zig: four spaces, as `zig fmt` writes them; everything else two.
- `const sysinfo = @import("builtin");`, never `builtin`. Every `@import` is a `const` near the top of the file. A switch mapping tags to values has one prong per distinct value.
- Files ideally under 500 lines, never over 1000, one per logical unit. Test-only code goes in `_test/` folders. Code several files use goes in one shared file, never copied.
- Panics only for unrecoverable states; bad input is an error. Exact error sets with plain names; slices, not pointers plus lengths; allocator first; `try`, never `catch @panic("OOM")`.
- Comments sparse and terse, no em dashes (semicolons instead), American English. Don't remove comments or commented-out lines you didn't write.
- Markdown: one line per paragraph or list item, no hard wraps; no markdownlint warnings. Don't add dictionary words on your own; list new ones in your report.

## Commands

- Never write a redirect that can create a `nul` file: `/dev/null` in Bash, `$null` in PowerShell.
- Search with `rg` (with an explicit path) or the Grep tool, excluding `zig-pkg`, `.zig-cache` and `zig-out`.
- Kill only processes you started, matched by their own command line.

## Checks before a pull request

`bash .github/workflows/version.sh`, `zig fmt --check build.zig src`, `zig build`, `zig build test`, the headless game (`zig build run -Dbackend=headless -Dframes=300`, which writes `doomball.ppm`), the Windows builds (`zig build -Dtarget=x86_64-windows -Dcpu=baseline -Doptimize=fast`, and `aarch64-windows`), `npx markdownlint-cli2 "**/*.md"` and `npx cspell --no-progress "**/*.md" ".github/**" "src/**" "tools/**"`. CI does not run on pull requests into `dev` (only on those into `main`, and when started by hand: `gh workflow run CI --ref BRANCH`), so these checks are what stands between a change and `dev`; say in the pull request which were run. `tools/agent/land.sh` runs them and lands the change (the `land-a-change` skill in `.claude/skills/`).

## Traps met before

- In the Bash tool on this machine, a command line containing a single quote fails ("unexpected EOF while looking for matching") before it runs: put such a command in a script file and run the file.
- The Win32 `doomball.exe` opens a window and runs until closed: never start it from a check or a script; use the headless backend.
- On this machine `npx` is pnpm's shim, which exits 0 even when markdownlint or cspell report problems: read their summary line, as `land.sh` does.
- Windows Error Reporting keeps a crashed process alive while it reports, so "still running" does not mean it did not crash; the Application event log ("Application Error") has the exception code.
