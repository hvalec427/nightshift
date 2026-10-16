#!/usr/bin/env bash
# Release the checked-out commit: a vX.Y.Z tag and a GitHub release, the
# version from scripts/next-version.sh and the notes from
# scripts/release-notes.sh. Does nothing when HEAD is already released or
# nothing since the last release calls for one. Needs GH_TOKEN, unless
# --dry-run, which prints what it would release.
#   release.sh [--dry-run]
set -euo pipefail

SCRIPTS="$(cd "$(dirname "$0")" && pwd -P)"
DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1

LATEST=$(git tag -l 'v[0-9]*' | { grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' || true; } | sort -V | tail -1)
if [ -n "$LATEST" ] && [ "$(git rev-list -n1 "$LATEST")" = "$(git rev-parse HEAD)" ]; then
  echo "HEAD is already released as $LATEST: nothing to release."
  exit 0
fi
VERSION=$(bash "$SCRIPTS/next-version.sh")
if [ -z "$VERSION" ]; then
  echo "Nothing to release since ${LATEST:-the start}: no feat, fix, perf or breaking change."
  exit 0
fi
TAG="v$VERSION"

NOTES=$(mktemp)
{
  [ -z "$LATEST" ] && printf 'The first release of nightshift.\n\n'
  bash "$SCRIPTS/release-notes.sh" "$LATEST"
} >"$NOTES"

if [ "$DRY" -eq 1 ]; then
  echo "Would release $TAG (previous: ${LATEST:-none}) at $(git rev-parse --short HEAD), with these notes:"
  echo "──"
  cat "$NOTES"
  exit 0
fi
gh release create "$TAG" --target "$(git rev-parse HEAD)" --title "$TAG" --notes-file "$NOTES"
