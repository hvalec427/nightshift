#!/usr/bin/env bash
# Tests for `nightshift top`: the frame it prints when stdout isn't a terminal,
# at a fixed COLUMNS×LINES, compared whole against the frame the spec asks for.
#   bash scripts/test-top.sh
set -euo pipefail
. "$(dirname "$0")/test-lib.sh"

# A command's output (stdout and stderr) and, in $ST, its exit status.
try() {
  set +e
  OUT=$("$@" 2>&1)
  ST=$?
  set -e
}

# The frame at $1 columns × $2 lines.
frame() { COLUMNS=$1 LINES=$2 ns top; }

# Issue $1, with its state files (the rest: name=content) and a log of eight
# lines, "line 1" … "line 8", tagged at levels 0-3 in turn.
issue() {
  local n=$1 s
  shift
  mkdir -p "$(idir "$n")"
  for s in "$@"; do printf '%s\n' "${s#*=}" >"$(idir "$n")/${s%%=*}"; done
}
log8() {
  local i
  for i in 1 2 3 4 5 6 7 8; do printf '%s\tline %s\n' $((i % 4)) "$i"; done >"$(idir "$1")/log"
}

# Four issues whose text doesn't change with time: the type and queued to
# build, queued, proposed (held), and a pull request queued for an update (#90,
# which the issue dirs' glob order puts after #9).
four() {
  issue 7 type=bug build=go
  issue 8
  issue 9 label=proposed
  issue 90 pr=https://github.com/o/r/pull/1 update=rebase
  log8 7
  log8 90
}

# $2 padded to $1 characters (printf pads bytes, and · is two): no emoji, a
# character is a cell.
cell() { jq -nr --arg t "$2" --argjson n "$1" '$t + ([range(0; $n - ($t | length))] | map(" ") | join(""))'; }

# How many lines come in on stdin.
rows() { wc -l | tr -d ' '; }

# --- one window -----------------------------------------------------------------

(world
  issue 7 type=bug build=go
  log8 7
  expect "top: one issue, a window of the whole screen: its header, then its log's last lines" "$(frame 40 6)" \
    "o/r#7 · bug · queued to build
line 4
line 5
line 6
line 7
line 8"
  expect "top: the lines the screen has, whatever its height" "$(frame 40 6 | rows) $(frame 100 20 | rows)" "6 20"
  expect "top: a tall window starts with what the log has, blank below" "$(frame 40 12 | sed -n '1p;2p;9p;10p' | tr '\n' '|')" \
    "o/r#7 · bug · queued to build|line 1|line 8||"
  expect "top: a header is cut to the width of its window" "$(frame 20 6 | head -1)" "o/r#7 · bug · queued")

# --- who gets a window -------------------------------------------------------------

(world
  sleep 300 &
  bg=$!
  issue 7 pid=$bg
  issue 8 session=abc label="needs you"
  issue 9 pr=https://github.com/o/r/pull/1 after=7 label="PR open"
  issue 10 done="issue closed"
  issue 11 ignored="labelled by someone else"
  f=$(frame 200 30)
  kill "$bg"
  { wait "$bg" || true; } 2>/dev/null
  expect_line "top: a running issue" "$f" "^o/r#7 · running [0-9]*s (pid $bg) *│"
  expect_line "top: one that needs you" "$f" "│o/r#8 · needs you  "
  expect_line "top: a pull request after another" "$f" "│o/r#9 · PR https://github.com/o/r/pull/1 · after #7"
  expect_line "top: not a done issue" "$f" "o/r#10" no
  expect_line "top: not an ignored one" "$f" "o/r#11" no)

# --- the tiling rule ---------------------------------------------------------------

# A frame as the tests write it: a | ends each row, so trailing blanks show.
rows_of() { sed 's/|$//'; }

(world
  four
  rm -rf "$(idir 8)" "$(idir 9)" "$(idir 90)"
  frame 80 24 >"$W/one"
  expect "top: 1 issue at 80×24, one window of 80×24" "$(sed -n '1p;2p;9p;10p' "$W/one" | tr '\n' '|')" \
    "o/r#7 · bug · queued to build|line 1|line 8||"
  four
  rm -rf "$(idir 9)" "$(idir 90)"
  expect "top: 2 issues at 82×12, side by side, 41 and 40 wide around a │" "$(frame 82 12)" "$(rows_of <<'F'
o/r#7 · bug · queued to build            │o/r#8 · queued|
line 1                                   │(nothing logged yet)|
line 2                                   │|
line 3                                   │|
line 4                                   │|
line 5                                   │|
line 6                                   │|
line 7                                   │|
line 8                                   │|
                                         │|
                                         │|
                                         │|
F
)"
  expect "top: 2 issues at 80×12, stacked: side by side, one would be 39 wide" "$(frame 80 12)" "$(rows_of <<'F'
o/r#7 · bug · queued to build|
line 4|
line 5|
line 6|
line 7|
line 8|
o/r#8 · queued|
(nothing logged yet)|
|
|
|
|
F
)"
  expect "top: 2 issues at 80×24, stacked, 12 rows each" "$(frame 80 24 | sed -n '1p;12p;13p;24p' | tr '\n' '|')" \
    "o/r#7 · bug · queued to build||o/r#8 · queued||"
  four
  rm -rf "$(idir 90)"
  expect "top: 3 issues at 80×24, stacked, 8 rows each" "$(frame 80 24 | sed -n '1p;2p;9p;17p;24p' | tr '\n' '|')" \
    "o/r#7 · bug · queued to build|line 2|o/r#8 · queued|o/r#9 · proposed: waiting for your comment||"
  four
  expect "top: 4 issues at 80×24, stacked, 6 rows each" "$(frame 80 24)" "$(rows_of <<'F'
o/r#7 · bug · queued to build|
line 4|
line 5|
line 6|
line 7|
line 8|
o/r#8 · queued|
(nothing logged yet)|
|
|
|
|
o/r#9 · proposed: waiting for your comment|
(nothing logged yet)|
|
|
|
|
o/r#90 · PR https://github.com/o/r/pull/1 · queued: rebase|
line 4|
line 5|
line 6|
line 7|
line 8|
F
)"
  expect "top: 4 issues at 120×30, 2 columns (60, 59) and 2 rows of 15" "$(frame 120 30)" "$(rows_of <<'F'
o/r#7 · bug · queued to build                               │o/r#8 · queued|
line 1                                                      │(nothing logged yet)|
line 2                                                      │|
line 3                                                      │|
line 4                                                      │|
line 5                                                      │|
line 6                                                      │|
line 7                                                      │|
line 8                                                      │|
                                                            │|
                                                            │|
                                                            │|
                                                            │|
                                                            │|
                                                            │|
o/r#9 · proposed: waiting for your comment                  │o/r#90 · PR https://github.com/o/r/pull/1 · queued: rebase|
(nothing logged yet)                                        │line 1|
                                                            │line 2|
                                                            │line 3|
                                                            │line 4|
                                                            │line 5|
                                                            │line 6|
                                                            │line 7|
                                                            │line 8|
                                                            │|
                                                            │|
                                                            │|
                                                            │|
                                                            │|
                                                            │|
F
)"
  expect "top: 4 issues at 123×30, 3 columns (41, 40, 40) and 2 rows of 15" "$(frame 123 30 | sed -n '1p;16p')" \
    "$(cell 41 'o/r#7 · bug · queued to build')│$(cell 40 'o/r#8 · queued')│o/r#9 · proposed: waiting for your comme
$(cell 41 'o/r#90 · PR https://github.com/o/r/pull/1')│$(cell 40 '')│"
  rm -rf "$(idir 90)"
  expect "top: 3 issues at 120×30, 2 columns and 2 rows, the last slot empty" "$(frame 120 30 | sed -n '1p;16p;17p;30p')" \
    "$(cell 60 'o/r#7 · bug · queued to build')│o/r#8 · queued
$(cell 60 'o/r#9 · proposed: waiting for your comment')│
$(cell 60 '(nothing logged yet)')│
$(cell 60 '')│"
  rm -rf "$(idir 9)"
  expect "top: 2 issues at 120×30, 2 columns (60, 59)" "$(frame 120 30 | head -1)" \
    "$(cell 60 'o/r#7 · bug · queued to build')│o/r#8 · queued"
  expect "top: 2 issues at 60×14, stacked, 7 rows each" "$(frame 60 14 | sed -n '1p;8p')" \
    "o/r#7 · bug · queued to build
o/r#8 · queued")

# --- overflow, empty, and nothing logged ----------------------------------------------

(world
  four
  expect "top: too many issues for 40×6 windows: the windows that fit, then +N more" "$(frame 81 11)" "$(rows_of <<'F'
o/r#7 · bug · queued to build           │o/r#8 · queued|
line 1                                  │(nothing logged yet)|
line 2                                  │|
line 3                                  │|
line 4                                  │|
line 5                                  │|
line 6                                  │|
line 7                                  │|
line 8                                  │|
                                        │|
+2 more: o/r#9, o/r#90|
F
)"
  expect "top: a window under 40×6 is shown, at the size there is" "$(frame 20 5 | sed -n '1p;5p')" \
    "o/r#7 · bug · queued
+3 more: o/r#8, o/r#"
  expect "top: one line: just the first header" "$(frame 80 1)" "o/r#7 · bug · queued to build")

(world
  expect "top: no issues, no issues in progress on the first row, the rest blank" "$(frame 80 24 | sed -n '1p;2p;24p' | tr '\n' '|') $(frame 80 24 | rows)" \
    "no issues in progress||| 24"
  issue 10 done="issue closed"
  expect "top: only a done issue: the same" "$(frame 80 24 | head -1)" "no issues in progress"
  issue 7
  expect "top: an issue with no log yet" "$(frame 40 6 | tr '\n' '|')" \
    "o/r#7 · queued|(nothing logged yet)|||||")

# --- cells, not characters ----------------------------------------------------------------

# $1 spaces.
sp() { printf "%$1s" ''; }

(world
  issue 7
  issue 8
  printf '0\t%s\n' "ünï·😀·😀 and some text" "✗ fail ✓ pass ☀" "⭐⌚ star" \
    "🤖🤖🤖🤖🤖🤖🤖🤖🤖🤖🤖🤖🤖🤖🤖🤖🤖🤖🤖🤖🤖🤖🤖🤖🤖" "x🤖🤖🤖🤖🤖🤖🤖🤖🤖🤖🤖🤖🤖🤖🤖🤖🤖🤖🤖🤖🤖🤖🤖🤖🤖" \
    "·······················································································" >"$(idir 7)/log"
  f=$(frame 81 12)
  expect "top: multibyte characters are a cell each, emoji two (✗ ✓ ☀ one): the window is 40 cells wide on every row" \
    "$(printf '%s\n' "$f" | sed -n '2,7p' | sed 's/│.*/│/')" \
    "ünï·😀·😀 and some text$(sp 17)│
✗ fail ✓ pass ☀$(sp 25)│
⭐⌚ star$(sp 31)│
🤖🤖🤖🤖🤖🤖🤖🤖🤖🤖🤖🤖🤖🤖🤖🤖🤖🤖🤖🤖│
x🤖🤖🤖🤖🤖🤖🤖🤖🤖🤖🤖🤖🤖🤖🤖🤖🤖🤖🤖 │
········································│"
  rm -rf "$(idir 8)"
  printf '0\t%s\n' "🤖 nightshift · plan" >"$(idir 7)/log"
  expect "top: a line one cell too wide for its emoji is cut by a character" "$(frame 19 2)" \
    "o/r#7 · queued
🤖 nightshift · pla")

# --- the log -------------------------------------------------------------------------------

(world
  issue 7
  printf '0\tat zero\n1\tat one\n2\tat two\n3\tat three\nuntagged\n3\ttab\tseparated\n' >"$(idir 7)/log"
  expect "top: the log at every level, without its tags, tabs expanded" "$(frame 40 8 | sed -n '2,7p')" \
    "at zero
at one
at two
at three
untagged
tab     separated")

# --- the command ------------------------------------------------------------------------------

(world
  expect_line "top --help: the usage" "$(ns top --help)" "^usage: nightshift top$"
  try ns top frobnicate
  expect "top, an argument: exit 2" "$ST" 2
  expect_line "top, an argument: the usage" "$OUT" "^usage: nightshift top$"
  expect_line "help lists top" "$(ns help)" "^  nightshift top "
  issue 7
  log8 7
  expect "top: without COLUMNS and LINES, 80×24 (or the terminal's, which a pipe has none of)" \
    "$(env -u COLUMNS -u LINES TERM=dumb "$ROOT/nightshift" top | head -1)" "o/r#7 · queued"
  expect "top: no escape codes when stdout isn't a terminal" "$(frame 40 6 | grep -c "$(printf '\033')" || true)" 0
  expect "top: stdout on a terminal but stdin not: one frame, no live screen" \
    "$(script -q /dev/null sh -c 'COLUMNS=40 LINES=6 "$0" top </dev/null' "$ROOT/nightshift" | tr -d '\r' | grep -c "$(printf '\033')\[?1049h" || true)" 0)

# --- live, on a terminal ---------------------------------------------------------------------

esc=$(printf '\033')

# Waits up to $2 seconds for process $1 to end; kills it, by its PID, if it doesn't.
await() {
  local i
  for i in $(seq $(($2 * 5))); do kill -0 "$1" 2>/dev/null || return 0; sleep 0.2; done
  kill "$1" 2>/dev/null || true
  return 1
}

# Runs `nightshift top` under a pty (BSD script) sized 40×6, TERM=xterm, with $1
# on its stdin, and, given a signal $2, sends it that once its screen is up.
# Its screen is in $W/tty (carriage returns dropped), its exit status in $ST
# ("hung" if it outlasted 20 s), and the terminal's icanon, echo, min and time
# in $W/before and $W/after, from before it ran and after. Its INT is reset to
# the default: a background job starts with INT ignored, which a trap can't undo.
live() {
  local pid i top=
  rm -f "$W/st" "$W/before" "$W/after" "$W/sh"
  printf '%s' "$1" >"$W/in"
  TERM=xterm script -q /dev/null sh -c 'mode() { stty -a | tr " ;" "\n\n" | grep -x -e icanon -e -icanon -e echo -e -echo; stty -g | tr ":" "\n" | grep -e "^min=" -e "^time="; }
    echo $$ >"$1"; stty cols 40 rows 6; unset COLUMNS LINES; mode >"$2"
    perl -e "\$SIG{INT} = q(DEFAULT); exec @ARGV" "$0" top; echo $? >"$3"; mode >"$4"' \
    "$ROOT/nightshift" "$W/sh" "$W/before" "$W/st" "$W/after" <"$W/in" >"$W/tty.raw" 2>&1 &
  pid=$!
  if [ -n "${2:-}" ]; then
    # nightshift is the shell's child, and draws once it has the alternate screen.
    for i in $(seq 100); do
      if grep -q "${esc}\[?1049h" "$W/tty.raw" 2>/dev/null && [ -s "$W/sh" ]; then top=$(pgrep -P "$(cat "$W/sh")" | head -1); [ -z "$top" ] || break; fi
      sleep 0.2
    done
    if [ -n "$top" ]; then kill -"$2" "$top"; fi
  fi
  if await "$pid" 20; then wait "$pid" || true; ST=$(cat "$W/st" 2>/dev/null || echo none); else ST=hung; fi
  tr -d '\r' <"$W/tty.raw" >"$W/tty"
}

(world
  issue 7
  log8 7
  live q
  expect "top, live: q quits with status 0" "$ST" 0
  expect_line "top, live: it draws a frame, the header in reverse video padded to the terminal's 40" "$(cat "$W/tty")" \
    "${esc}\[7mo/r#7 · queued \{26\}${esc}\[0m"
  expect_line "top, live: and the log lines padded to 40 too" "$(cat "$W/tty")" "^line 4 \{34\}"
  expect_line "top, live: it enters the alternate screen" "$(cat "$W/tty")" "${esc}\[?1049h"
  expect_line "top, live: leaves it on q" "$(cat "$W/tty")" "${esc}\[?1049l"
  expect_line "top, live: and shows the cursor again" "$(cat "$W/tty")" "${esc}\[?25h"
  expect "top, live: q restores the terminal's settings" "$(cat "$W/after")" "$(cat "$W/before")"
  live Q
  expect "top, live: Q quits too" "$ST" 0
  live "" INT
  expect "top, live: Ctrl-C (INT) ends it with status 130" "$ST" 130
  expect_line "top, live: INT leaves the alternate screen" "$(cat "$W/tty")" "${esc}\[?1049l"
  expect "top, live: INT restores the terminal's settings" "$(cat "$W/after")" "$(cat "$W/before")"
  live "" TERM
  expect "top, live: TERM ends it with status 143" "$ST" 143
  expect_line "top, live: TERM leaves the alternate screen" "$(cat "$W/tty")" "${esc}\[?1049l"
  expect "top, live: TERM restores the terminal's settings" "$(cat "$W/after")" "$(cat "$W/before")"
  live "" HUP
  expect "top, live: HUP ends it with status 129" "$ST" 129
  expect_line "top, live: HUP shows the cursor again" "$(cat "$W/tty")" "${esc}\[?25h"
  expect "top, live: HUP restores the terminal's settings" "$(cat "$W/after")" "$(cat "$W/before")")

report
