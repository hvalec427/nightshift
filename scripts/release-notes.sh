#!/usr/bin/env bash
# Print the release notes (markdown) for the commits since tag $1 (all of
# history when it's empty), grouped: Breaking changes, Features, Fixes (perf
# included). Each line is the subject without its type, scope in bold; the
# "(#123)" a squash merge adds links its pull request. Other types and commits
# that aren't Conventional are left out.
#   release-notes.sh [<previous tag>]
set -euo pipefail

FROM="${1:-}"
RE='^([a-z]+)(\(([^)]+)\))?(!)?: (.+)$'
breaking=() features=() fixes=()
for sha in $(git log ${FROM:+"$FROM..HEAD"} --reverse --no-merges --format='%H'); do
  subject=$(git log -1 --format='%s' "$sha")
  [[ "$subject" =~ $RE ]] || continue
  type="${BASH_REMATCH[1]}" scope="${BASH_REMATCH[3]}" bang="${BASH_REMATCH[4]}" line="${BASH_REMATCH[5]}"
  [ -n "$scope" ] && line="**$scope:** $line"
  if [ -n "$bang" ] || git log -1 --format='%b' "$sha" | grep -qE '^BREAKING[ -]CHANGE: '; then breaking+=("$line")
  elif [ "$type" = feat ]; then features+=("$line")
  elif [ "$type" = fix ] || [ "$type" = perf ]; then fixes+=("$line")
  fi
done

# A group's heading and lines, with a blank line between groups.
sep=""
group() {
  local title="$1"
  shift
  [ $# -eq 0 ] && return
  printf '%s### %s\n\n' "$sep" "$title"
  printf -- '- %s\n' "$@"
  sep=$'\n'
}
group "Breaking changes" ${breaking[@]+"${breaking[@]}"}
group "Features" ${features[@]+"${features[@]}"}
group "Fixes" ${fixes[@]+"${fixes[@]}"}
