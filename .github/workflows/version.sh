#!/usr/bin/env bash
# version.sh: doomball's version and every place that states it, run from the
# repository root by ci.yml and tools/agent/land.sh. A new place that states
# the version is added here. From skein's version.sh.
#   version.sh           prints the version; fails, listing the places, when
#                        one is missing or differs from build.zig.zon
#   version.sh set NEXT  sets every place to NEXT, as CI does when it begins
#                        the next version
set -euo pipefail

zon=build.zig.zon
count=1

# places: one "FILE: VERSION" line for each place that states the version
places() {
  sed -nE 's/^    \.version = "([^"]+)",$/\1/p' "$zon" | sed "s|^|$zon: |"
}

check() {
  local version list bad
  version=$(sed -nE 's/^    \.version = "([^"]+)",$/\1/p' "$zon")
  list=$(places)
  bad=$(grep -v ": $version\$" <<< "$list" || true)
  if ! [[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || [ "$(grep -c . <<< "$list")" -ne "$count" ] || [ -n "$bad" ]; then
    echo "version.sh: the $count places that state the version must all be $zon's MAJOR.MINOR.PATCH ('$version'); found:" >&2
    echo "$list" >&2
    exit 1
  fi
  echo "$version"
}

set_version() {
  local next=$1
  [[ $next =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "version.sh: '$next' is not MAJOR.MINOR.PATCH" >&2; exit 1; }
  sed -i -E "s/^(    \.version = \")[^\"]+(\",)$/\1$next\2/" "$zon"
  check > /dev/null
}

case "${1:-}" in
  "") check ;;
  set) set_version "${2:?version.sh set NEXT}" ;;
  *) echo "version.sh: [set NEXT]" >&2; exit 1 ;;
esac
