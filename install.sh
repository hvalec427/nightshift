#!/bin/sh
# Install nightshift: the `nightshift` command (into ~/.nightshift/bin) and its
# Claude Code plugin, at the latest release; with --master, at master instead
# (for testing); with --service, also run `nightshift watch` in the background
# whenever you're logged in.
#
#   curl -fsSL https://raw.githubusercontent.com/hvalec427/nightshift/master/install.sh | sh
#   … | sh -s -- --master
#   … | sh -s -- --service
#
# Run it again to update. Run from a clone, it installs the clone's files.
set -e

REPO="hvalec427/nightshift"
NS="$HOME/.nightshift"
BIN="$NS/bin"
SERVICE="gui/$(id -u)/${NIGHTSHIFT_LABEL:-com.nightshift.watch}" # NIGHTSHIFT_LABEL is for tests

service=0 master=0
for arg in "$@"; do
  case "$arg" in
  --service) service=1 ;;
  --master) master=1 ;;
  *) echo "unknown option: $arg (options: --master, --service)" >&2; exit 2 ;;
  esac
done

# What to install: the clone this runs from, or a ref of $REPO (the latest
# release's tag, or master), and the version that `nightshift --version` says.
here=$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)
if [ -f "$here/nightshift" ] && [ -f "$here/.claude-plugin/marketplace.json" ]; then
  ref=master
  version="dev ($(git -C "$here" rev-parse --short HEAD 2>/dev/null || echo "?"))"
else
  here=""
  ref=master
  if [ $master -eq 0 ]; then
    # Where releases/latest redirects: …/releases/tag/vX.Y.Z, or …/releases with none yet.
    tag=$(curl -fsS -o /dev/null -w '%{redirect_url}' "https://github.com/$REPO/releases/latest" |
      sed -n 's|.*/releases/tag/\(v[0-9][0-9.]*\)$|\1|p')
    if [ -n "$tag" ]; then ref=$tag
    else echo "No nightshift release yet: installing master."
    fi
  fi
  if [ "$ref" = master ]; then
    sha=$(git ls-remote "https://github.com/$REPO" refs/heads/master | cut -c1-7)
    version="master (${sha:-?})"
  else
    version="${ref#v}"
  fi
fi

mkdir -p "$BIN"
# A running service is stopped (its runs cleanly) while its script is replaced.
restart=0
if [ -x "$BIN/nightshift" ] && launchctl print "$SERVICE" 2>/dev/null | grep -q '^	pid = '; then
  restart=1
  "$BIN/nightshift" stop 2>/dev/null || launchctl bootout "$SERVICE" || true # before `nightshift stop` had no argument
fi
# The script, and the plugin's copy that runs load (`--plugin-dir`).
rm -rf "$NS/plugin.new" "$NS/src"
if [ -n "$here" ]; then
  src=$here
else
  src="$NS/src"
  mkdir "$src"
  curl -fsSL "https://codeload.github.com/$REPO/tar.gz/$ref" | tar -xz -C "$src" --strip-components 1
fi
sed "s/^VERSION=dev\$/VERSION='$version'/" "$src/nightshift" >"$BIN/nightshift"
cp -R "$src/plugin" "$NS/plugin.new"
[ -n "$here" ] || rm -rf "$src"
rm -rf "$NS/plugin" && mv "$NS/plugin.new" "$NS/plugin"
chmod +x "$BIN/nightshift"
echo "nightshift $version installed to $BIN/nightshift (its plugin for runs: $NS/plugin)"

# shellcheck disable=SC2016 # written to the rc file as is
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
  # The marketplace is pinned to the same ref, so the plugin you use by hand
  # is the one runs use; a different ref means removing and adding it again.
  pinned=$(claude plugin marketplace list --json 2>/dev/null |
    jq -r '.[] | select(.name == "nightshift") | "\(.repo)#\(.ref // "")"' 2>/dev/null) || pinned="?"
  if [ "$pinned" = "$REPO#$ref" ]; then
    claude plugin marketplace update nightshift
  else
    [ -n "$pinned" ] && claude plugin marketplace remove nightshift >/dev/null || true
    claude plugin marketplace add "$REPO#$ref"
  fi
  claude plugin install nightshift@nightshift
  claude plugin update nightshift@nightshift >/dev/null 2>&1 || true
else
  echo "Claude Code isn't installed: install it and run this again."
fi

# What's missing on this machine, and how to get it. `nightshift start` writes
# the LaunchAgent and starts it; a service that was running is started again on
# the new version, once nothing required is missing.
echo "──"
"$BIN/nightshift" doctor && ok=1 || ok=0
if [ $service -eq 1 ] || [ $restart -eq 1 ]; then
  echo "──"
  if [ "$ok" -eq 1 ]; then
    "$BIN/nightshift" start || true
  else
    echo "The service starts once that's fixed: nightshift start"
  fi
fi
