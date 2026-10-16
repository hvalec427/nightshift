#!/usr/bin/env bash
# Tests for the service (`start` and `stop`, with the real launchctl and a
# LaunchAgent of the tests' own) and for install.sh, into a throwaway HOME.
#   bash scripts/test-service.sh
set -euo pipefail
. "$(dirname "$0")/test-lib.sh"

# A command's output (stdout and stderr) and, in $ST, its exit status.
try() {
  set +e
  OUT=$("$@" 2>&1)
  ST=$?
  set -e
}

# A world doctor finds all good in (see test-commands.sh).
healthy() {
  world
  echo token >"$NS/token"
  cp -R "$ROOT/plugin" "$NS/plugin"
  echo '[{"id":"nightshift@nightshift","enabled":true,"installPath":"/x"}]' >"$CLAUDE_FAKE/plugins.json"
  echo agent >>"$(gh_dir o/r)/labels"
}

# --- start and stop ----------------------------------------------------------------

(world
  try ns stop
  expect "stop, nothing installed: says so" "$ST $OUT" "1 nightshift: the service isn't installed")

(world
  try ns start
  expect "start while doctor fails: refuses" "$ST" 1
  expect_line "start: says what's missing" "$OUT" "^  missing nightshift's plugin for runs "
  expect_line "start: and why it didn't start" "$OUT" "^nightshift: not starting: fix what's missing, then nightshift start$"
  expect_ok "start: no LaunchAgent written" test ! -e "$HOME/Library/LaunchAgents/$NIGHTSHIFT_LABEL.plist")

(healthy
  sleep 30 &
  hand=$!
  echo "$hand" >"$NS/watch.pid"
  try ns start
  expect "start while a watch runs by hand: refuses" "$ST $OUT" "1 nightshift: a nightshift watch already runs by hand (pid $(cat "$NS/watch.pid")): stop it first"
  kill "$hand"
  wait "$hand" 2>/dev/null || true)

if ! launchctl print "gui/$(id -u)" >/dev/null 2>&1; then
  echo "skip the LaunchAgent: no GUI launchd domain here (gui/$(id -u))"
else
  (healthy
    # One label for every run of these tests: launchctl remembers each label
    # disabled or enabled.
    export NIGHTSHIFT_LABEL=com.nightshift.test
    plist="$HOME/Library/LaunchAgents/$NIGHTSHIFT_LABEL.plist"
    domain="gui/$(id -u)"
    stop_it() { launchctl bootout "$domain/$NIGHTSHIFT_LABEL" 2>/dev/null || true; }
    trap 'stop_it; end_world' EXIT
    stop_it
    try ns start
    expect "start: starts" "$ST" 0
    expect_line "start: says it runs" "$OUT" "^service: running (pid [0-9]*)$"
    expect_line "start: points to the log" "$OUT" "^log: nightshift logs -f$"
    pid=$(launchctl print "$domain/$NIGHTSHIFT_LABEL" | sed -n 's/^	pid = \([0-9]*\)$/\1/p')
    expect_ok "launchd runs it" test -n "$pid"
    expect_line "the LaunchAgent: its label" "$(cat "$plist")" "<key>Label</key><string>$NIGHTSHIFT_LABEL</string>"
    expect_line "the LaunchAgent: nightshift watch" "$(cat "$plist")" "<array><string>$ROOT/nightshift</string><string>watch</string></array>"
    expect_line "the LaunchAgent: this NIGHTSHIFT_HOME" "$(cat "$plist")" "<key>NIGHTSHIFT_HOME</key><string>$NS</string>"
    expect_line "the LaunchAgent: start's PATH" "$(cat "$plist")" "<key>PATH</key><string>$ROOT:$PATH</string>"
    expect "status: running" "$(ns status | head -1)" "service: running (pid $pid)"
    expect "start again: already running" "$(ns start)" "service: already running (pid $pid)"
    try ns stop
    expect "stop: stops it" "$OUT" "stopping the service (and the runs in flight)…
service: stopped (disabled)"
    expect_ok "stop: its process is gone" sh -c "! kill -0 $pid 2>/dev/null"
    expect "status: stopped, disabled" "$(ns status | head -1)" "service: stopped (disabled)"
    expect "stop again: still stopped" "$(ns stop)" "service: stopped (disabled)"
    try ns start
    expect_line "start after stop: runs again" "$OUT" "^service: running (pid [0-9]*)$"
    ns stop >/dev/null)
fi

# --- install.sh ------------------------------------------------------------------

# install.sh from this clone, into the world's HOME, with a zsh SHELL.
# shellcheck disable=SC2120 # options, when a test gives them
install() { env SHELL=/bin/zsh sh "$ROOT/install.sh" "$@"; }

(healthy
  try install
  bin="$HOME/.nightshift/bin/nightshift"
  version="dev ($(git -C "$ROOT" rev-parse --short HEAD))"
  expect_line "install: says what it installed" "$OUT" "^nightshift $version installed to $bin "
  expect "install: the command, with its version" "$("$bin" --version)" "nightshift $version"
  expect_ok "install: the plugin's copy" diff -r "$ROOT/plugin" "$HOME/.nightshift/plugin"
  expect "install: the PATH line, in .zshrc" "$(grep -c 'export PATH="$HOME/.nightshift/bin:$PATH"' "$HOME/.zshrc")" 1
  expect_line "install: the marketplace, pinned" "$(cat "$CLAUDE_FAKE/calls")" "^plugin marketplace add hvalec427/nightshift#master $"
  expect_line "install: the plugin" "$(cat "$CLAUDE_FAKE/calls")" "^plugin install nightshift@nightshift $"
  expect_line "install: then doctor" "$OUT" "^nightshift $version$"
  echo "stale" >"$HOME/.nightshift/plugin/stale"
  try install
  expect "install again: works" "$ST" 0
  expect "install again: the PATH line once" "$(grep -c 'nightshift/bin' "$HOME/.zshrc")" 1
  expect_ok "install again: the plugin's copy replaced" test ! -e "$HOME/.nightshift/plugin/stale"
  echo '[{"name":"nightshift","repo":"hvalec427/nightshift","ref":"master"}]' >"$CLAUDE_FAKE/marketplaces.json"
  : >"$CLAUDE_FAKE/calls"
  install >/dev/null 2>&1
  expect_line "install, pinned already: updates the marketplace" "$(cat "$CLAUDE_FAKE/calls")" "^plugin marketplace update nightshift $"
  expect_line "install, pinned already: doesn't add it again" "$(cat "$CLAUDE_FAKE/calls")" "^plugin marketplace add" no)

(healthy
  install >/dev/null 2>&1
  bin="$HOME/.nightshift/bin/nightshift"
  before=$(ls -i "$bin" | awk '{print $1}')
  install >/dev/null 2>&1
  expect_ok "install again: the script moved in, not written over (a watch reads it as it runs)" test "$(ls -i "$bin" | awk '{print $1}')" != "$before"
  expect_ok "install: nothing left aside" test ! -e "$bin.new"
  try env NIGHTSHIFT_UPDATING=1 SHELL=/bin/zsh sh "$ROOT/install.sh" --service
  expect "install in update mode: works" "$ST" 0
  expect_line "install in update mode: leaves the service as it is" "$OUT" "^service: " no
  expect_ok "install in update mode: no LaunchAgent written" test ! -e "$HOME/Library/LaunchAgents/$NIGHTSHIFT_LABEL.plist")

(healthy
  echo '[{"name":"nightshift","repo":"hvalec427/nightshift","ref":"v0.1.0"}]' >"$CLAUDE_FAKE/marketplaces.json"
  install >/dev/null 2>&1
  expect_line "install, pinned to another ref: removes it" "$(cat "$CLAUDE_FAKE/calls")" "^plugin marketplace remove nightshift $"
  expect_line "install, pinned to another ref: adds it at this one" "$(cat "$CLAUDE_FAKE/calls")" "^plugin marketplace add hvalec427/nightshift#master $")

(healthy
  try env SHELL=/bin/bash sh "$ROOT/install.sh"
  expect "install, not zsh: the PATH line in .profile" "$(grep -c 'nightshift/bin' "$HOME/.profile")" 1
  expect_ok "install, not zsh: no .zshrc" test ! -e "$HOME/.zshrc")

(healthy
  try env PATH="$HOME/.nightshift/bin:$PATH" SHELL=/bin/zsh sh "$ROOT/install.sh"
  expect_ok "install, already on PATH: no PATH line" test ! -e "$HOME/.zshrc")

(healthy
  try install --frobnicate
  expect "install, an unknown option: fails" "$ST $OUT" "2 unknown option: --frobnicate (options: --master, --service)")

(world
  try install
  expect_line "install, doctor fails: says so" "$OUT" "^4 to fix, then run nightshift doctor again$"
  try install --service
  expect_line "install --service, doctor fails: doesn't start it" "$OUT" "^The service starts once that's fixed: nightshift start$")

report
