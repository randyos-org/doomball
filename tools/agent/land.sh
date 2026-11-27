#!/usr/bin/env bash
# land.sh --model "Claude MODEL" ISSUE LABEL "COMMIT" "PR TITLE" BODY_FILE close|keep PATH...
# Lands a change of an agent's on dev: the checks, a commit of the PATHs
# named (never everything: emanspeaks works in this tree too) on the current
# branch (not dev or main), a pull request into dev with the label, its
# merge, and the issue closed (close) or commented on (keep); ISSUE - for a
# change emanspeaks asked for without one. The model is the one the agent
# runs on, for the commit's Co-Authored-By. Run from a branch made for the
# change; the app's wrappers are outside the repository (see CLAUDE.md).
# From skein's land.sh.
set -euo pipefail
[ "${1:-}" = --model ] && [ -n "${2:-}" ] || { echo "land.sh: first --model \"Claude MODEL\", the model this agent runs on (Claude Opus 5.5, say)"; exit 1; }
model=$2
shift 2
issue=$1 label=$2 message=$3 title=$4 body=$5 close=$6
shift 6
body="$(cd "$(dirname "$body")" && pwd)/$(basename "$body")"
cd "$(dirname "$0")/../.."
app=randyos-org
GH_TOKEN="$(bash /c/scratch/github-apps/app-token.sh "$app")"
export GH_TOKEN
Z=${ZIG:-zig}
branch=$(git branch --show-current)
[ "$branch" != dev ] && [ "$branch" != main ] || { echo "land.sh: on $branch; make a branch for the change first"; exit 1; }
# the label is needed after the push: a wrong one is refused before anything is done
gh label list --limit 100 --json name -q '.[].name' < /dev/null | grep -qx -- "$label" || { echo "land.sh: the repository has no label '$label'"; exit 1; }

# the checks CI makes (ci.yml), on this platform
bash .github/workflows/version.sh > /dev/null
"$Z" fmt --check build.zig src
"$Z" build
"$Z" build test
"$Z" build run -Dbackend=headless -Dframes=300 --prefix zig-out/headless
test -s doomball.ppm && rm doomball.ppm
for target in x86_64-windows aarch64-windows; do
  "$Z" build -Dtarget="$target" -Dcpu=baseline -Doptimize=fast --prefix "zig-out/$target"
done
npx --no-install markdownlint-cli2 "**/*.md" 2>&1 | tail -1
npx --no-install cspell --no-progress "**/*.md" ".github/**" "src/**" "tools/**" 2>&1 | tail -1

# .claude/ may be in the checkout's own ignore file: its paths are added past it
for path in "$@"; do
  case "$path" in
    .claude/*) git add -f -- "$path" ;;
    *) git add -- "$path" ;;
  esac
done
git status --short
bash /c/scratch/github-apps/app-git.sh "$app" commit -q -m "$message" -m "Co-Authored-By: $model <noreply@anthropic.com>"
bash /c/scratch/github-apps/app-git.sh "$app" push -q -u origin "$branch" 2>&1 | tail -1 || true
url=$(gh pr create --base dev --head "$branch" --title "$title" --body-file "$body" --label "$label" < /dev/null | tail -1)
echo "$url"
gh pr merge "$url" --merge < /dev/null 2>&1 | tail -1
git switch -q dev
bash /c/scratch/github-apps/app-git.sh "$app" pull -q --ff-only
git branch -D "$branch" | tail -1
git fetch -q --prune
if [ "$issue" = - ]; then
  : # a change with no issue
elif [ "$close" = close ]; then
  gh issue close "$issue" --comment "Landed on dev with #${url##*/}. _Posted by Claude at the request of emanspeaks._" < /dev/null | tail -1
else
  gh issue comment "$issue" --body "Part of this landed on dev with #${url##*/}. _Posted by Claude at the request of emanspeaks._" < /dev/null | tail -1
fi
git log --oneline -1
