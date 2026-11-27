# shellcheck shell=bash
# Which changed files can change the shipped game. Sourced (in bash, from the
# repository root) by ci.yml's "Changes" job, which decides whether a pull
# request needs the checks, and by its "Version" job, which decides whether a
# push to main is a release. From skein's changes.sh, after zfls's.

# patterns LIST...: the globs of the lists (one bash `case` glob per line;
# lines starting with # and blank lines are ignored)
patterns() { cat "$@" | grep -v '^\s*#' | grep -v '^\s*$'; }

# matches FILE GLOB...: whether FILE matches one of the globs
matches() {
    local f=$1 pat
    shift
    for pat in "$@"; do
        # shellcheck disable=SC2254
        case "$f" in $pat) return 0 ;; esac
    done
    return 1
}

# The files whose changes alone skip CI, and the files that cannot change
# the shipped game (used where this is sourced)
# shellcheck disable=SC2034
mapfile -t no_ci < <(patterns .github/workflows/no-ci.txt)
# shellcheck disable=SC2034
mapfile -t docs_only < <(patterns .github/workflows/docs-only.txt)
# shellcheck disable=SC2034
mapfile -t exempt < <(patterns .github/workflows/no-ci.txt .github/workflows/docs-only.txt .github/workflows/ci-only.txt)

# version_only FILE TAG: whether FILE differs from what it was at TAG in
# nothing but its version line
version_only() {
    local line='^\s*\.version = "'
    diff <(git show "$2:$1" 2> /dev/null | grep -vE "$line") <(grep -vE "$line" "$1" 2> /dev/null) > /dev/null
}

# shipped_changes TAG: the files changed since TAG that change what a
# release ships. A version begun on dev changes only the version line
# (version.sh), which alone ships nothing new.
shipped_changes() {
    local f
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        case "$f" in
            build.zig.zon) version_only "$f" "$1" && continue ;;
            *) matches "$f" "${exempt[@]}" && continue ;;
        esac
        echo "$f"
    done <<< "$(git diff --name-only "$1" HEAD)"
}
