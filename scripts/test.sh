#!/usr/bin/env bash
# Run the tests: every scripts/test-*.sh, or the ones named (`release`, or
# `scripts/test-release.sh`). Prints each file's results, then a summary;
# fails if any test does. The files run in one temp dir of the run's own, as
# TMPDIR (see `temp` in test-lib.sh), removed at the end, even on INT; KEEP_WORLD=1
# keeps it, and the worlds in it, and prints where it is.
#   bash scripts/test.sh [<name>…]
set -u

SCRIPTS="$(cd "$(dirname "$0")" && pwd -P)"
if [ $# -eq 0 ]; then
  set -- "$SCRIPTS"/test-*.sh
fi
# The pool of LaunchAgent labels is shared by suites running at once, so it
# stays in the caller's TMPDIR, not in the dir below.
export NIGHTSHIFT_TEST_LABELS=${NIGHTSHIFT_TEST_LABELS:-${TMPDIR:-/tmp}/nightshift-test-labels}
SUITE=$(mktemp -d "${TMPDIR:-/tmp}/nightshift-tests.XXXXXX")
export TMPDIR=$SUITE
trap 'if [ -n "${KEEP_WORLD:-}" ]; then echo "kept $SUITE" >&2; else rm -rf "${SUITE:?}"; fi' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
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
