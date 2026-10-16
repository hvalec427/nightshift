#!/bin/sh
# Install nightshift: the `nightshift` command (into ~/.nightshift/bin) and its
# Claude Code plugin; with --service, also run `nightshift watch` in the
# background whenever you're logged in.
#
#   curl -fsSL https://raw.githubusercontent.com/hvalec427/nightshift/master/install.sh | sh
#   … | sh -s -- --service
#
# Run it again to update.
set -e

REPO="hvalec427/nightshift"
NS="$HOME/.nightshift"
BIN="$NS/bin"
SERVICE="gui/$(id -u)/com.nightshift.watch"

mkdir -p "$BIN"
# A running service is stopped (its runs cleanly) while its script is replaced.
restart=0
if [ -x "$BIN/nightshift" ] && launchctl print "$SERVICE" 2>/dev/null | grep -q '^	pid = '; then
  restart=1
  "$BIN/nightshift" stop 2>/dev/null || launchctl bootout "$SERVICE" || true # before `nightshift stop` had no argument
fi
here=$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)
if [ -f "$here/nightshift" ] && [ -f "$here/.claude-plugin/marketplace.json" ]; then
  cp "$here/nightshift" "$BIN/nightshift" # run from a clone
else
  curl -fsSL "https://raw.githubusercontent.com/$REPO/master/nightshift" -o "$BIN/nightshift"
fi
chmod +x "$BIN/nightshift"
echo "nightshift installed to $BIN/nightshift"

LINE='export PATH="$HOME/.nightshift/bin:$PATH"'
case ":$PATH:" in
*":$BIN:"*) ;;
*)
  rc="$HOME/.zshrc"
  [ -n "${SHELL##*zsh}" ] && rc="$HOME/.profile"
  grep -qF "$LINE" "$rc" 2>/dev/null || printf '\n# nightshift\n%s\n' "$LINE" >>"$rc"
  echo "Added $BIN to PATH in $rc (open a new terminal, or run: $LINE)"
  ;;
esac

if command -v claude >/dev/null 2>&1; then
  if ! claude plugin marketplace list 2>/dev/null | grep -q nightshift; then
    claude plugin marketplace add "$REPO"
  else
    claude plugin marketplace update nightshift
  fi
  claude plugin install nightshift@nightshift
  claude plugin update nightshift@nightshift >/dev/null 2>&1 || true
else
  echo "Claude Code isn't installed: install it and run this again."
fi

# `nightshift start` writes the LaunchAgent and starts it; a service that was
# running is started again on the new version.
if [ "${1:-}" = "--service" ] || [ $restart -eq 1 ]; then
  "$BIN/nightshift" start || true
fi

echo "──"
ghv=$(gh --version 2>/dev/null | sed -n 's/^gh version \([0-9]*\)\.\([0-9]*\).*/\1 \2/p')
if [ -z "$ghv" ]; then
  echo "Also needed: GitHub's CLI (brew install gh, then gh auth login)."
elif [ "${ghv% *}" -eq 2 ] && [ "${ghv#* }" -lt 99 ]; then
  echo "Update GitHub's CLI (brew upgrade gh): pull requests get screenshots from gh 2.99 on."
fi
[ -s "$NS/token" ] || echo "For unattended runs: claude setup-token, and save the token to $NS/token (chmod 600)."
[ -s "$NS/config" ] || echo "Then watch a repo: nightshift add <owner/repo> <path to a clone of it>"
