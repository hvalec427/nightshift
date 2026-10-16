#!/usr/bin/env bash
# Tests for the plugin's instructions.sh: what runs and sessions are told, from
# nightshift's defaults and a machine's own file, in a throwaway NIGHTSHIFT_HOME.
#   bash scripts/test-instructions.sh
set -euo pipefail
. "$(dirname "$0")/test-lib.sh"

SCRIPT="$ROOT/plugin/hooks/instructions.sh"
DEFAULTS="$ROOT/plugin/instructions.md"
HOME_DIR=$(mktemp -d)


# The script's output, with this test's NIGHTSHIFT_HOME and no issue.
run() { env -u NIGHTSHIFT_ISSUE NIGHTSHIFT_HOME="$HOME_DIR" sh "$SCRIPT" "$@"; }

MACHINE_HEADING="# This machine's instructions

These come from ~/.nightshift/instructions.md, on top of nightshift's defaults
above, and win where the two disagree."

expect "the defaults have the commit rules" \
  "$(grep -c 'Conventional Commits' "$DEFAULTS")" 1

expect "no machine file: the defaults alone" "$(run)" "$(cat "$DEFAULTS")"

: >"$HOME_DIR/instructions.md"
expect "an empty machine file: the defaults alone" "$(run)" "$(cat "$DEFAULTS")"

printf 'Write commits in Slovenian.\n' >"$HOME_DIR/instructions.md"
expect "a machine file: the defaults, then it under its heading" "$(run)" "$(cat "$DEFAULTS")

$MACHINE_HEADING

Write commits in Slovenian."

expect "hook: the same as for a run" "$(run hook)" "$(run)"
expect "hook in a nightshift run: nothing" \
  "$(NIGHTSHIFT_HOME="$HOME_DIR" NIGHTSHIFT_ISSUE=25 sh "$SCRIPT" hook)" ""
expect "no hook in a nightshift run: all of it" \
  "$(NIGHTSHIFT_HOME="$HOME_DIR" NIGHTSHIFT_ISSUE=25 sh "$SCRIPT")" "$(run)"

# Without the defaults (a copy of the script on its own): the machine file alone.
mkdir -p "$HOME_DIR/bare/hooks" && cp "$SCRIPT" "$HOME_DIR/bare/hooks/"
expect "no defaults: the machine file alone" \
  "$(env -u NIGHTSHIFT_ISSUE NIGHTSHIFT_HOME="$HOME_DIR" sh "$HOME_DIR/bare/hooks/instructions.sh")" \
  "Write commits in Slovenian."
rm "$HOME_DIR/instructions.md"
expect "neither: nothing" \
  "$(env -u NIGHTSHIFT_ISSUE NIGHTSHIFT_HOME="$HOME_DIR" sh "$HOME_DIR/bare/hooks/instructions.sh")" ""

report
