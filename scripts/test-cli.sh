#!/usr/bin/env bash
# Tests for nightshift's command line itself: the version, help and unknown
# commands; and for the test lib's own checks.
#   bash scripts/test-cli.sh
set -euo pipefail
. "$(dirname "$0")/test-lib.sh"

(world
  expect "--version: the version" "$(ns --version)" "nightshift dev"
  expect "version: the same" "$(ns version)" "nightshift dev"
  expect_line "help: the usage" "$(ns help)" "^  nightshift watch "
  expect_line "help: points to the logs' help" "$(ns --help)" "nightshift logs --help"
  set +e
  out=$(ns frobnicate 2>&1)
  expect "an unknown command: exit 2" "$?" 2
  set -e
  expect_line "an unknown command: the usage" "$out" "^  nightshift status "
  set +e
  ns >/dev/null 2>&1
  expect "no command: exit 2" "$?" 2
  set -e)

# expect_line under pipefail, on an input far bigger than a pipe holds whose
# first line matches: grep quits at line 1, and that is still a match.
(big=$(awk 'BEGIN { print "the line"; for (i = 0; i < 100000; i++) print "another line" }')
  got=$(FAILS=$(temp)
    set -o pipefail
    out=$(expect_line "big" "$big" "^the line$")
    printf '%s|%s' "${out%%$'\n'*}" "$(cat "$FAILS")"
    rm -f "$FAILS")
  expect "expect_line: a match on line 1 of a large input" "$got" "ok   big|")

# A test's world is removed when it ends; KEEP_WORLD=1 keeps it and says where.
w=$( (world; echo "$W") )
expect "world: removed when its test ends" "$([ -e "$w" ] && echo there || echo gone)" "gone"
both=$( (export KEEP_WORLD=1; world; echo "W=$W") 2>&1 )
w=${both%%$'\n'*}
w=${w#W=}
expect "KEEP_WORLD=1: the world stays" "$([ -d "$w" ] && echo there || echo gone)" "there"
expect_line "KEEP_WORLD=1: says where it is" "$both" "^kept $w\$"
rm -rf "$w"

# A test file's FAILS file is removed when the file exits, passed or failed.
(world
  printf '%s\n' '. "$1/scripts/test-lib.sh"' 'echo "$FAILS" >"$2"' 'expect "pass" 1 1' 'report' >"$W/pass.sh"
  printf '%s\n' '. "$1/scripts/test-lib.sh"' 'echo "$FAILS" >"$2"' 'expect "fail" 1 2' 'report' >"$W/fail.sh"
  for f in pass fail; do
    bash "$W/$f.sh" "$ROOT" "$W/$f.fails" >/dev/null || true
    expect "FAILS: removed when a $f file exits" "$([ -e "$(cat "$W/$f.fails")" ] && echo there || echo gone)" "gone"
  done)

# temp makes a file (or, with -d, a dir) under TMPDIR: on macOS a plain
# mktemp ignores TMPDIR, so it is the only way a test makes one.
(d=$(temp -d)
  trap 'rm -rf "$d"' EXIT
  f=$(TMPDIR=$d temp)
  expect "temp: a file in TMPDIR" "$([ -f "$f" ] && echo "${f%/*}")" "$d"
  g=$(TMPDIR=$d temp -d)
  expect "temp -d: a dir in TMPDIR" "$([ -d "$g" ] && echo "${g%/*}")" "$d")

# No test file or the test lib calls the plain tool (bar temp itself, and
# comments); that is what keeps a suite's files in its own TMPDIR.
plain='mk''temp'
found=$(cd "$ROOT" && grep -n "$plain" scripts/test-*.sh | grep -v ':[0-9]*:[[:space:]]*#' | grep -v '^scripts/test-lib\.sh:[0-9]*:temp() ' || true)
expect "no test file calls a plain $plain" "$found" ""

# A run of test.sh on files of its own (a pass, a fail, one stopped by INT),
# with a fresh TMPDIR as its caller's: it leaves that as it was, bar the
# label pool, and exits as ever.
(ct=$(temp -d)
  trap 'rm -rf "$ct"' EXIT
  fx=$ct/fixtures
  mkdir "$fx"
  head='. "$ROOT/scripts/test-lib.sh"; (world; temp >/dev/null; temp -d >/dev/null; echo "$NIGHTSHIFT_TEST_LABELS" >"$ct/labels")'
  printf '%s\nexpect pass 1 1\nreport\n' "$head" >"$fx/test-pass.sh"
  printf '%s\nexpect pass 1 1\nreport\n' "$head" >"$fx/test-quick.sh"
  printf '%s\nexpect fail 1 2\nreport\n' "$head" >"$fx/test-fail.sh"
  printf '%s\n(world; temp -d >/dev/null; : >"$ct/started"; sleep 30)\n' "$head" >"$fx/test-int.sh"
  # What a fresh caller's TMPDIR holds after test.sh ran on the files $1…
  # A fresh caller's environment, with $ct/caller as its TMPDIR.
  caller=(env -u NIGHTSHIFT_TEST_LABELS -u KEEP_WORLD ROOT="$ROOT" ct="$ct" TMPDIR="$ct/caller")
  run_suite() {
    "${caller[@]}" bash "$ROOT/scripts/test.sh" "$@" >/dev/null 2>&1
  }
  mkdir "$ct/caller"
  run_suite "$fx/test-pass.sh"
  expect "test.sh: a passing file exits 0" "$?" "0"
  expect "test.sh: a pass leaves the caller's TMPDIR as it was" "$(ls -A "$ct/caller")" ""
  expect "test.sh: the label pool comes from the caller's TMPDIR" "$(cat "$ct/labels")" "$ct/caller/nightshift-test-labels"
  rc=0
  run_suite "$fx/test-fail.sh" || rc=$?
  expect "test.sh: a failing file exits 1" "$rc" "1"
  expect "test.sh: a failure leaves the caller's TMPDIR as it was" "$(ls -A "$ct/caller")" ""
  # As a ^C reaches it: its own process group, and INT not ignored (as it is
  # for anything started in the background by a script).
  set -m
  perl -e '$SIG{INT} = "DEFAULT"; exec @ARGV' "${caller[@]}" bash "$ROOT/scripts/test.sh" "$fx/test-int.sh" >/dev/null 2>&1 &
  pid=$!
  wait_for "$ct/started"
  kill -INT -- "-$pid"
  rc=0
  { wait "$pid" || rc=$?; } 2>/dev/null
  set +m
  expect "test.sh: INT exits 130" "$rc" "130"
  expect "test.sh: INT leaves the caller's TMPDIR as it was" "$(ls -A "$ct/caller")" ""
  # A failure among files run at once still fails the run.
  rc=0
  run_suite "$fx/test-pass.sh" "$fx/test-fail.sh" || rc=$?
  expect "test.sh: a failure among parallel files exits 1" "$rc" "1"
  # NIGHTSHIFT_TEST_SHARD=i/n: the shards between them run each file once.
  ran() { "${caller[@]}" NIGHTSHIFT_TEST_SHARD="$1" bash "$ROOT/scripts/test.sh" "$fx/test-pass.sh" "$fx/test-quick.sh" "$fx/test-fail.sh" 2>/dev/null |
    sed -n 's/^=== \(test-[a-z0-9]*\)\.sh .*/\1/p'; }
  expect "test.sh: shards run each file once" "$( (ran 1/2; ran 2/2) | sort | paste -sd' ' -)" "test-fail test-pass test-quick"
  expect "test.sh: a shard runs a share" "$(ran 2/2 | wc -l | tr -d ' ')" "1"
  err=$("${caller[@]}" KEEP_WORLD=1 bash "$ROOT/scripts/test.sh" "$fx/test-pass.sh" 2>&1 >/dev/null)
  kept=$(sed -n "s|^kept \($ct/caller/nightshift-tests\.[A-Za-z0-9]*\)\$|\1|p" <<<"$err")
  expect "KEEP_WORLD=1: test.sh keeps its dir and says where" "$([ -n "$kept" ] && [ -d "$kept" ] && echo kept)" "kept")

report
