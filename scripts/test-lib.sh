# shellcheck shell=bash
# What the tests share, sourced by each scripts/test-*.sh: `expect` and its
# kin, which count failures, `report`, which ends a test file with them, and
# `world`, a throwaway machine for nightshift with a fake GitHub and a fake
# Claude (scripts/fake) and a clone of o/r watched.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

# A temp file, or with -d a dir, under TMPDIR, which a plain call to the tool
# ignores on macOS: the only way a test makes one, so a suite's go in its dir.
temp() { mktemp "$@" "${TMPDIR:-/tmp}/tmp.XXXXXX"; }
# Tests run in subshells, so failures are counted in a file.
FAILS=$(temp)
# Gone when the test file exits, passed or failed. A subshell has its own traps.
trap 'rm -f "$FAILS"' EXIT
FAKES="$ROOT/scripts/fake"
# shellcheck source=fake/github.sh
. "$FAKES/github.sh"

# Whether $2 (what it gave) is $3, for the test named $1.
expect() {
  if [ "$2" = "$3" ]; then echo "ok   $1"
  else
    printf 'FAIL %s\n  expected: %s\n  got:      %s\n' "$1" "$3" "$2"
    echo "$1" >>"$FAILS"
  fi
}

# Whether $2 has a line matching the grep pattern $3 (with $4 = no, hasn't).
expect_line() {
  local has=no
  grep -q -- "$3" <<<"$2" && has=yes
  if [ "$has" = "${4:-yes}" ]; then echo "ok   $1"
  else
    printf 'FAIL %s\n  expected a line %s: %s\n  in:\n%s\n' "$1" "$([ "${4:-yes}" = yes ] && echo matching || echo "not matching")" "$3" "$(printf '%s\n' "$2" | sed 's/^/    /')"
    echo "$1" >>"$FAILS"
  fi
}

# Whether the test named $1 holds: the command after it succeeds.
expect_ok() {
  local name=$1
  shift
  if "$@" >/dev/null; then echo "ok   $name"
  else
    printf 'FAIL %s\n  this failed: %s\n' "$name" "$*"
    echo "$name" >>"$FAILS"
  fi
}

# The end of a test file: what failed, and its exit status.
report() {
  if [ -s "$FAILS" ]; then
    echo "$(wc -l <"$FAILS" | tr -d ' ') failed"
    exit 1
  fi
  echo "all passed"
}

# --- a world ----------------------------------------------------------------------

# A throwaway machine, set up in the current shell (so call it in a subshell):
# HOME and NIGHTSHIFT_HOME in a temp dir W, a PATH of the fakes, git, jq and
# the system's own tools, GitHub logged in as alice, and o/r on GitHub (its
# remote in $ORIGIN, with a commit on master) watched with its clone in $CLONE.
world() {
  W=$(temp -d)
  W=$(cd "$W" && pwd -P)
  mkdir -p "$W/home" "$W/ns/issues" "$W/gh" "$W/claude" "$W/curl" "$W/bin"
  export HOME="$W/home" NIGHTSHIFT_HOME="$W/ns" GH_FAKE="$W/gh" CLAUDE_FAKE="$W/claude" CURL_FAKE="$W/curl"
  export XDG_CONFIG_HOME="$W/home/.config" GIT_CONFIG_NOSYSTEM=1
  export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
  # A LaunchAgent of its own, never the machine's.
  export NIGHTSHIFT_LABEL="com.nightshift.test.$$.${W##*.}"
  unset NIGHTSHIFT_REPO NIGHTSHIFT_ISSUE NIGHTSHIFT_WAIT NIGHTSHIFT_LIB NIGHTSHIFT_UPDATING CLAUDE_CODE_OAUTH_TOKEN
  # The pull requests checked on every poll, not every 30 s.
  export NIGHTSHIFT_PR_INTERVAL=0
  # git and jq from wherever they are; nothing else of this machine's own
  # (no real gh or claude).
  for t in git jq; do ln -s "$(command -v "$t")" "$W/bin/$t"; done
  export PATH="$FAKES:$W/bin:/usr/bin:/bin:/usr/sbin:/sbin"
  echo alice >"$GH_FAKE/user"
  NS=$NIGHTSHIFT_HOME
  REPO=o/r
  ORIGIN="$W/origin.git"
  CLONE="$W/clone"
  git init -q --bare -b master "$ORIGIN"
  git clone -q "$ORIGIN" "$CLONE" 2>/dev/null
  git -C "$CLONE" config commit.gpgsign false
  echo hello >"$CLONE/README"
  git -C "$CLONE" add README && git -C "$CLONE" commit -q -m "chore: start"
  git -C "$CLONE" push -q origin master
  gh_repo "$REPO" "$ORIGIN"
  printf 'repo %s %s\n' "$REPO" "$CLONE" >"$NS/config"
  trap end_world EXIT
}

# Whatever a test left running in its world (on a failure): stopped, and the
# world removed, unless KEEP_WORLD=1, which keeps it and says where it is.
end_world() {
  local p
  for p in "$NS/watch.pid" "$NS"/issues/*/pid; do
    [ -f "$p" ] && { kill -9 "$(cat "$p")" 2>/dev/null || true; }
  done
  pkill -9 -f "$W/" 2>/dev/null || true
  if [ -n "${KEEP_WORLD:-}" ]; then echo "kept $W" >&2; else rm -rf "${W:?}"; fi
  return 0
}

# --- a LaunchAgent label ------------------------------------------------------------

# The tests that run a real LaunchAgent take its label from a pool of 8,
# com.nightshift.test.1 … .8: launchd remembers every label it has seen (and
# `nightshift stop` disables it), so not one per run; and suites run at once
# (worktrees in parallel), so not one for all. A slot is a lock dir in
# $NIGHTSHIFT_TEST_LABELS with its holder's pid; a dead holder's is free.
NIGHTSHIFT_TEST_LABELS=${NIGHTSHIFT_TEST_LABELS:-${TMPDIR:-/tmp}/nightshift-test-labels}

# Claim a free slot for the current (sub)shell, as NIGHTSHIFT_LABEL, waiting
# for one 10 minutes at most.
claim_label() {
  local me slot lock tries=0
  # This (sub)shell's pid ($$ is the top shell's; bash 3.2 has no BASHPID).
  me=$(exec sh -c 'echo $PPID')
  mkdir -p "$NIGHTSHIFT_TEST_LABELS"
  while [ $tries -lt 600 ]; do
    for slot in $(seq 8); do
      lock="$NIGHTSHIFT_TEST_LABELS/$slot"
      free_dead_label "$lock"
      if mkdir "$lock" 2>/dev/null; then
        echo "$me" >"$lock/pid"
        export NIGHTSHIFT_LABEL="com.nightshift.test.$slot" NIGHTSHIFT_LABEL_LOCK="$lock"
        return 0
      fi
    done
    sleep 1
    tries=$((tries + 1))
  done
  echo "claim_label: every test label stayed taken for 10 minutes ($NIGHTSHIFT_TEST_LABELS)" >&2
  return 1
}

# Free a slot whose holder died (one with no pid yet is mid-claim). Under a
# lock of its own, with the pid read again inside, so two claims can't both
# free it, the second removing the first's fresh claim.
free_dead_label() {
  local holder
  mkdir "$1.free" 2>/dev/null || return 0
  holder=$(cat "$1/pid" 2>/dev/null) || true
  if [ -n "$holder" ] && ! kill -0 "$holder" 2>/dev/null; then rm -rf "$1"; fi
  rmdir "$1.free"
}

# Give back the slot claim_label took.
release_label() { rm -rf "${NIGHTSHIFT_LABEL_LOCK:?}"; }

# nightshift, as the user runs it.
ns() { "$ROOT/nightshift" "$@"; }

# nightshift as a release install has it: this clone's script, at version $1,
# in $NS/bin/nightshift (written aside and moved in, as install.sh does).
release_ns() {
  mkdir -p "$NS/bin"
  sed "s/^VERSION=dev\$/VERSION='$1'/" "$ROOT/nightshift" >"$NS/bin/nightshift.new"
  chmod +x "$NS/bin/nightshift.new"
  mv "$NS/bin/nightshift.new" "$NS/bin/nightshift"
}

# One poll, waiting for the runs it starts.
poll() { "$ROOT/nightshift" once; }

# $2 as the file $1 in o/r's origin, committed to its branch $3 (default master,
# made from master if it's new), through a clone of its own: the watched clone
# doesn't have it until it fetches.
origin_file() {
  local c="$W/pusher" b=${3:-master}
  [ -d "$c" ] || {
    git clone -q "$ORIGIN" "$c" 2>/dev/null
    git -C "$c" config commit.gpgsign false
  }
  git -C "$c" fetch -q origin
  git -C "$c" checkout -q -B "$b" "origin/master"
  mkdir -p "$c/$(dirname "$1")"
  printf '%s\n' "$2" >"$c/$1"
  git -C "$c" add "$1" && git -C "$c" commit -q -m "chore: $1"
  git -C "$c" push -q -f origin "$b"
}

# A repo's settings, as committed to o/r's default branch: .nightshift/config.
origin_config() { origin_file .nightshift/config "$1"; }

# A setting in the config.
set_config() { echo "$1=$2" >>"$NS/config"; }

# Plugin $1 (an id, name@marketplace) installed in $W/<name>, enabled unless $2 is false.
plugin() {
  mkdir -p "$W/${1%@*}"
  [ -f "$CLAUDE_FAKE/plugins.json" ] || echo '[]' >"$CLAUDE_FAKE/plugins.json"
  # shellcheck disable=SC2016 # a jq program: $ is jq's
  jq -c --arg id "$1" --arg p "$W/${1%@*}" --argjson e "${2:-true}" '. + [{id: $id, enabled: $e, installPath: $p}]' \
    "$CLAUDE_FAKE/plugins.json" >"$W/plugins.json" && mv "$W/plugins.json" "$CLAUDE_FAKE/plugins.json"
}

# What the next runs do: their script (see scripts/fake/claude).
runs_do() { printf '%s\n' "$1" >"$CLAUDE_FAKE/script"; }

# How many runs there were.
runs() { find "$CLAUDE_FAKE/runs" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' '; }

# Run $1's arguments (default: the last), a line each (multi-line ones as they are).
run_args() { tr '\0' '\n' <"$CLAUDE_FAKE/runs/${1:-$(runs)}/args"; }

# The value run $2 (default: the last) gave option $1 ("" if none; "-" if
# it has it with no value).
run_opt() {
  local a prev="" k=${2:-$(runs)} found=""
  while IFS= read -r -d '' a; do
    [ "$prev" = "$1" ] && { printf '%s' "$a"; return; }
    prev=$a
  done <"$CLAUDE_FAKE/runs/$k/args"
  [ "$prev" = "$1" ] && found=-
  printf '%s' "$found"
}

# Run $1's prompt (default: the last).
run_prompt() { run_opt -p "${1:-}"; }

# Issue $1's state dir, and a file of it.
idir() { printf '%s/issues/o_r_%s' "$NS" "$1"; }
state() { cat "$(idir "$1")/$2" 2>/dev/null; }

# Issue $1's `cost`, its seconds (field 5) as S.
cost() { state "$1" cost | awk '{ $5 = "S"; print }'; }

# The cost tests' models, as a run's costs name them, and the first line of
# the cost comment (as a grep pattern).
# shellcheck disable=SC2034 # used by the files that source this
OPUS=claude-opus-5-5 HAIKU=claude-haiku-4-5-20251001 SONNET=claude-sonnet-4-5-20250929
# shellcheck disable=SC2034
COMMENT="🤖 \*\*nightshift\*\* · cost"

# Issue $1's status label on GitHub (without `nightshift: `), or nothing.
status_label() { gh_labels "$REPO" "$1" | sed -n 's/^nightshift: //p'; }

# The gh calls so far matching the grep pattern $1.
gh_calls() { grep -- "$1" "$GH_FAKE/calls" 2>/dev/null; }

# Whether the fake gh was asked anything it doesn't know.
expect_no_unexpected() {
  expect "${1:-gh}: no unexpected calls" "$(cat "$GH_FAKE/unexpected" 2>/dev/null)" ""
}

# Wait until the file $1 exists (10s at most).
wait_for() {
  local i=0
  while [ ! -e "$1" ] && [ $i -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
  [ -e "$1" ]
}

# Wait until the issue $1's log has a line with $2 (10s at most).
wait_log() {
  local i=0 f
  f="$(idir "$1")/log"
  while ! grep -qF -- "$2" "$f" 2>/dev/null && [ $i -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
}

# Wait until the issue $1 has no run going (10s at most).
wait_idle() {
  local i=0 d
  d=$(idir "$1")
  while [ -f "$d/pid" ] && kill -0 "$(cat "$d/pid")" 2>/dev/null && [ $i -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
}

# The number of the first line in $1 matching the grep pattern $2, or 0.
line_of() { l=$(grep -n -m1 -- "$2" "$1" | cut -d: -f1); echo "${l:-0}"; }
# The file $1 as one line, so a phrase matches however the prose wraps.
flat() { tr -s ' \n' ' ' <"$1"; }
