#!/usr/bin/env bash
# Run the tests: every scripts/test-*.sh, or the ones named (`release`, or
# `scripts/test-release.sh`). The files run in parallel, the biggest first,
# NIGHTSHIFT_TEST_JOBS (default 8) at a time (NIGHTSHIFT_TEST_SHARD=i/n, a
# share of them); each one's results print once it
# ends, then a summary; fails if any test does. The files run in one temp dir
# of the run's own, as TMPDIR (see `temp` in test-lib.sh), removed at the end,
# even on INT; KEEP_WORLD=1 keeps it, and the worlds in it, and prints where it is.
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
jobs_max=${NIGHTSHIFT_TEST_JOBS:-8}
pids=""
# The files still running, stopped (on INT or TERM), then the suite dir removed.
stop() { [ -z "$pids" ] || kill $pids 2>/dev/null; wait 2>/dev/null; }
trap 'stop; if [ -n "${KEEP_WORLD:-}" ]; then echo "kept $SUITE" >&2; else rm -rf "${SUITE:?}"; fi' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# The files to run, the biggest (by lines, roughly the slowest) first, so the
# long ones don't start last.
sized() {
  local f
  for f in "$@"; do
    case "$f" in */*) ;; *) f="$SCRIPTS/test-$f.sh" ;; esac
    [ "$(basename "$f")" = test-lib.sh ] && continue
    printf '%s %s\n' "$(wc -l <"$f")" "$f"
  done
}
files=$(sized "$@" | sort -rn | awk '{print $2}')
# NIGHTSHIFT_TEST_SHARD=i/n: only the i-th of every n of them (CI splits the
# suite across machines this way); the sizes alternate, so each gets a share.
if [ -n "${NIGHTSHIFT_TEST_SHARD:-}" ]; then
  files=$(printf '%s\n' $files | awk -v s="$NIGHTSHIFT_TEST_SHARD" 'BEGIN { split(s, a, "/") } (NR - 1) % a[2] == a[1] - 1')
fi

# File $1's results: printed, and its name added to the failed ones if it failed.
failed=""
report() {
  local name
  name=$(basename "$1")
  echo "=== $name ($(($(date +%s) - $(cat "$SUITE/$name.start")))s)"
  cat "$SUITE/$name.out"
  echo
  [ "$(cat "$SUITE/$name.status")" = 0 ] || failed="$failed $name"
}

# Each file in a subshell of its own, its output and status kept until it ends.
running=""
for f in $files; do
  while [ "$(echo $running | wc -w)" -ge "$jobs_max" ]; do
    for r in $running; do
      [ -f "$SUITE/$(basename "$r").status" ] || continue
      report "$r"
      running=$(echo $running | tr ' ' '\n' | grep -vxF "$r" | tr '\n' ' ')
    done
    sleep 0.2
  done
  name=$(basename "$f")
  date +%s >"$SUITE/$name.start"
  (bash "$f" >"$SUITE/$name.out" 2>&1; echo $? >"$SUITE/$name.status") &
  pids="$pids $!"
  running="$running $f"
done
while [ -n "$(echo $running)" ]; do
  for r in $running; do
    [ -f "$SUITE/$(basename "$r").status" ] || continue
    report "$r"
    running=$(echo $running | tr ' ' '\n' | grep -vxF "$r" | tr '\n' ' ')
  done
  sleep 0.2
done
pids=""
if [ -n "$failed" ]; then
  echo "FAILED:$failed"
  exit 1
fi
echo "All tests pass."
