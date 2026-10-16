#!/usr/bin/env bash
# Run the tests: every scripts/test-*.sh, or the ones named (`release`, or
# `scripts/test-release.sh`). Prints each file's results, then a summary;
# fails if any test does.
#   bash scripts/test.sh [<name>…]
set -u

SCRIPTS="$(cd "$(dirname "$0")" && pwd -P)"
if [ $# -eq 0 ]; then
  set -- "$SCRIPTS"/test-*.sh
fi
failed=""
for f in "$@"; do
  case "$f" in */*) ;; *) f="$SCRIPTS/test-$f.sh" ;; esac
  [ "$(basename "$f")" = test-lib.sh ] && continue
  echo "=== $(basename "$f")"
  bash "$f" || failed="$failed $(basename "$f")"
  echo
done
if [ -n "$failed" ]; then
  echo "FAILED:$failed"
  exit 1
fi
echo "All tests pass."
