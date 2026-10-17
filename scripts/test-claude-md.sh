#!/usr/bin/env bash
# Tests for nightshift's own CLAUDE.md, which every run here reads: it's there,
# it's a short map, and every repo path it names exists. Static.
#   bash scripts/test-claude-md.sh
set -euo pipefail
. "$(dirname "$0")/test-lib.sh"

FILE="$ROOT/CLAUDE.md"

expect_ok "the root CLAUDE.md exists" test -f "$FILE"
[ -f "$FILE" ] || report
expect_ok "it's under 150 lines" test "$(wc -l <"$FILE")" -lt 150

# The backticked repo paths it names, a line each: tokens with a `/` or a file
# extension, but no spaces, globs, placeholders, home paths or URLs (a trailing
# `/`, a directory's, dropped).
paths() {
  grep -o '`[^`]*`' "$FILE" | tr -d '`' |
    grep -E '/|\.[a-z]+$' | grep -v -E '[ *<>~$]|://' | sed 's|/$||' | sort -u
}
missing=""
for p in $(paths); do
  [ -e "$ROOT/$p" ] || missing="$missing $p"
done
expect_ok "it names repo paths" test -n "$(paths)"
expect "every repo path it names exists" "$missing" ""

report
