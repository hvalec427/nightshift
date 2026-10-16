#!/bin/sh
# What Claude is told on top of its system prompt, on this machine: nightshift's
# defaults (instructions.md, next to hooks/), then the machine's own
# $NIGHTSHIFT_HOME/instructions.md, which wins where the two disagree.
#   sh instructions.sh         for a nightshift run's system prompt
#   sh instructions.sh hook    for the SessionStart hook: nothing in a nightshift
#                              run, whose system prompt has it already
[ "${1:-}" = hook ] && [ -n "${NIGHTSHIFT_ISSUE:-}" ] && exit 0
defaults="$(dirname "$0")/../instructions.md"
machine="${NIGHTSHIFT_HOME:-$HOME/.nightshift}/instructions.md"
if [ -s "$defaults" ]; then
  cat "$defaults"
  [ -s "$machine" ] || exit 0
  printf "\n# This machine's instructions\n\n"
  printf "These come from ~/.nightshift/instructions.md, on top of nightshift's defaults\n"
  printf "above, and win where the two disagree.\n\n"
fi
[ -s "$machine" ] && cat "$machine"
exit 0
