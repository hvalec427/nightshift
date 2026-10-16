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
AGENT="$HOME/Library/LaunchAgents/com.nightshift.watch.plist"

mkdir -p "$BIN"
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

if [ "${1:-}" = "--service" ]; then
  mkdir -p "$(dirname "$AGENT")"
  cat >"$AGENT" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.nightshift.watch</string>
  <key>ProgramArguments</key>
  <array><string>$BIN/nightshift</string><string>watch</string></array>
  <key>EnvironmentVariables</key>
  <dict><key>PATH</key><string>$BIN:$PATH</string></dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$NS/service.log</string>
  <key>StandardErrorPath</key><string>$NS/service.log</string>
</dict>
</plist>
EOF
  launchctl bootout "gui/$(id -u)" "$AGENT" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$AGENT"
  echo "nightshift watch runs in the background (log: $NS/watch.log); stop it with: launchctl bootout gui/\$(id -u) $AGENT"
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
