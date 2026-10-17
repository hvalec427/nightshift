#!/usr/bin/env bash
# Check that a commit message or pull request title is a Conventional Commit:
# `type(scope)!: description`, a known type, a description that starts
# lowercase and has no full stop, the whole line at most 72 characters.
# Pull requests are squash-merged, so their title becomes the commit.
#   commit-lint.sh --title "<pull request title>"
#   commit-lint.sh --file <message file>      (a commit-msg hook)
set -euo pipefail

TYPES='build|chore|ci|docs|feat|fix|perf|refactor|revert|style|test'
RE="^($TYPES)(\([a-z0-9._/-]+\))?!?: [^A-Z ].*[^. ]$|^($TYPES)(\([a-z0-9._/-]+\))?!?: [^A-Z .]$"

case "${1:-}" in
--title) HEADER="${2:-}" ;;
--file) HEADER=$(grep -v -m1 '^#' "$2") ;;
*) sed -n '2,7s/^# \{0,1\}//p' "$0" >&2; exit 2 ;;
esac

if [[ "$HEADER" =~ $RE ]] && [ "${#HEADER}" -le 72 ]; then
  exit 0
fi
echo "✖ Not a Conventional Commit: $HEADER" >&2
echo "  Expected <type>(<scope>)?: <description>, at most 72 characters, e.g." >&2
echo "  \"feat(status): show how long a run waited\". Types: ${TYPES//|/, }." >&2
exit 1
