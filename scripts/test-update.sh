#!/usr/bin/env bash
# Tests for auto_update: a release install's watch updating itself to the
# latest release, between runs.
#   bash scripts/test-update.sh
set -euo pipefail
. "$(dirname "$0")/test-lib.sh"

# The latest release, as github.com's releases/latest says (see scripts/fake/curl).
latest() { echo "v$1" >"$CURL_FAKE/latest"; }

# The release's install.sh, for the watch to run: it notes NIGHTSHIFT_UPDATING
# (in $W/installed) and installs this clone's script at version $1; with no
# $1, it fails.
release_install() {
  if [ -n "${1:-}" ]; then
    cat >"$CURL_FAKE/install.sh" <<EOF
echo "\${NIGHTSHIFT_UPDATING:-unset}" >>"$W/installed"
echo "installing v$1"
sed "s/^VERSION=dev\\\$/VERSION='$1'/" "$ROOT/nightshift" >"$NS/bin/nightshift.new"
chmod +x "$NS/bin/nightshift.new"
mv "$NS/bin/nightshift.new" "$NS/bin/nightshift"
EOF
  else
    printf 'echo "${NIGHTSHIFT_UPDATING:-unset}" >>"%s/installed"\necho "no luck" >&2\nexit 1\n' "$W" >"$CURL_FAKE/install.sh"
  fi
}

# The release install's watch, in the background ($BG), and stopping it.
watch_bg() {
  "$NS/bin/nightshift" watch &
  BG=$!
}
stop_bg() {
  kill -TERM "$BG" 2>/dev/null || true
  wait "$BG" 2>/dev/null || true
}

# Wait until watch.log has a line matching $1 (10s at most).
wait_log() {
  local i=0
  until grep -q -- "$1" "$NS/watch.log" 2>/dev/null || [ $i -gt 100 ]; do sleep 0.1; i=$((i + 1)); done
}

# How many times the latest release was asked.
checks() { cat "$CURL_FAKE/calls" 2>/dev/null | grep -c 'releases/latest' || true; }

(world
  release_ns 0.5.1
  set_config interval 1
  set_config auto_update true
  latest 0.6.0
  release_install 0.6.0
  watch_bg
  wait_log "watching (nightshift 0.6.0)"
  log=$(cat "$NS/watch.log")
  expect_line "a newer release: logged" "$log" "v0.6.0 is out: updating to it$"
  expect_line "updated: logged" "$log" "updated to v0.6.0: restarting$"
  expect_line "then it watches on the new version" "$log" "watching (nightshift 0.6.0): o/r $"
  expect "install.sh ran once, in update mode" "$(cat "$W/installed")" 1
  expect "its output: in update.log" "$(cat "$NS/update.log")" "installing v0.6.0"
  expect_ok "the same process watches" kill -0 "$BG"
  expect "its pid: kept" "$(cat "$NS/watch.pid")" "$BG"
  stop_bg)

(world
  release_ns 0.5.1
  set_config interval 1
  set_config auto_update true
  export NIGHTSHIFT_UPDATE_INTERVAL=0
  release_install 0.6.0
  gh_issue o/r 7 alice agent
  runs_do 'hold'
  watch_bg
  wait_for "$CLAUDE_FAKE/runs/1/waiting"
  latest 0.6.0
  wait_log "v0.6.0 is out"
  expect_line "a run in flight: the update waits for it" "$(cat "$NS/watch.log")" "v0.6.0 is out: updating once the runs in flight finish$"
  gh_issue o/r 8 alice agent
  wait_log "#8 waits (updating)"
  expect_line "a new issue meanwhile: waits" "$(cat "$NS/watch.log")" "#8 waits (updating)"
  expect "its status: queued" "$(status_label 8)" queued
  expect "no new run" "$(runs)" 1
  expect_ok "install.sh: not yet" test ! -e "$W/installed"
  runs_do ''
  touch "$CLAUDE_FAKE/runs/1/go"
  wait_log "watching (nightshift 0.6.0)"
  expect_line "the run done: it updates" "$(cat "$NS/watch.log")" "updated to v0.6.0: restarting$"
  wait_for "$CLAUDE_FAKE/runs/2/env"
  expect_line "then the waiting issue starts" "$(cat "$CLAUDE_FAKE/runs/2/env")" "^NIGHTSHIFT_ISSUE=8$"
  stop_bg)

(world
  release_ns 0.5.1
  set_config interval 1
  set_config auto_update true
  latest 0.6.0
  release_install
  watch_bg
  wait_log "update to v0.6.0 failed"
  expect_line "a failed install: logged, on the old version" "$(cat "$NS/watch.log")" "update to v0.6.0 failed (see $NS/update.log): staying on 0.5.1, trying again in an hour$"
  expect "update.log: why" "$(cat "$NS/update.log")" "no luck"
  gh_issue o/r 7 alice agent
  wait_for "$CLAUDE_FAKE/runs/1/args"
  expect_ok "it keeps watching, and runs start again" test -e "$CLAUDE_FAKE/runs/1/args"
  expect "no other check within the hour" "$(checks)" 1
  expect "install.sh: run once" "$(wc -l <"$W/installed" | tr -d ' ')" 1
  stop_bg)

(world
  release_ns 0.5.1
  set_config interval 1
  set_config auto_update true
  latest 0.6.0
  watch_bg
  wait_log "update to v0.6.0 failed"
  expect_line "install.sh not there: a failed update" "$(cat "$NS/watch.log")" "update to v0.6.0 failed"
  expect_ok "the watch: still running" kill -0 "$BG"
  stop_bg)

(world
  release_ns 0.6.0
  set_config interval 1
  set_config auto_update true
  latest 0.6.0
  release_install 0.6.0
  watch_bg
  wait_log "polled o/r"
  sleep 1
  expect "the latest already: checked" "$(checks)" 1
  expect_ok "and nothing installed" test ! -e "$W/installed"
  stop_bg)

(world
  release_ns 0.5.1
  set_config interval 1
  latest 0.6.0
  release_install 0.6.0
  export NIGHTSHIFT_UPDATE_INTERVAL=0
  watch_bg
  wait_log "polled o/r"
  sleep 1
  expect "auto_update off (the default): never checks" "$(checks)" 0
  stop_bg)

(world
  set_config interval 1
  set_config auto_update true
  latest 0.6.0
  release_install 0.6.0
  export NIGHTSHIFT_UPDATE_INTERVAL=0
  "$ROOT/nightshift" watch &
  BG=$!
  wait_log "polled o/r"
  sleep 1
  expect "a dev install: never checks" "$(checks)" 0
  stop_bg)

(world
  release_ns 0.5.1
  set_config auto_update true
  latest 0.6.0
  release_install 0.6.0
  "$NS/bin/nightshift" once
  expect "once: doesn't update" "$(checks)" 0)

# --- doctor ---------------------------------------------------------------------

(world
  release_ns 0.5.1
  set_config auto_update true
  out=$("$NS/bin/nightshift" doctor 2>&1 || true)
  expect_line "doctor, on: says so" "$out" "^  ok      auto-update: each new release installs itself, between runs$"
  : >"$NS/config"
  out=$("$NS/bin/nightshift" doctor 2>&1 || true)
  expect_line "doctor, off: how to turn it on" "$out" "^  hint    auto-update is off: curl .*install.sh | sh -s -- --auto-update, "
  set_config auto_update true
  out=$(ns doctor 2>&1 || true)
  expect_line "doctor, on in a dev install: it won't update" "$out" "^  hint    auto_update is on, but only a release install updates itself: "
  : >"$NS/config"
  out=$(ns doctor 2>&1 || true)
  expect_line "doctor, off in a dev install: nothing" "$out" "auto.update" no)

report
