#!/usr/bin/env bash
# Print the version the next release gets, from the Conventional Commits since
# the latest release tag (vX.Y.Z), or nothing when there's nothing to release:
#   fix, perf          → patch
#   feat               → minor
#   ! or BREAKING CHANGE → major, or minor while below 1.0
#   anything else      → no release
# With no tag yet, the first release is 0.1.0.
set -euo pipefail

LATEST=$(git tag -l 'v[0-9]*' | { grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' || true; } | sort -V | tail -1)
SUBJECTS=$(git log ${LATEST:+"$LATEST..HEAD"} --no-merges --format='%s')
BODIES=$(git log ${LATEST:+"$LATEST..HEAD"} --no-merges --format='%b')

T='[a-z]+(\([^)]+\))?'
if grep -qE "^$T!: " <<<"$SUBJECTS" || grep -qE '^BREAKING[ -]CHANGE: ' <<<"$BODIES"; then
  BUMP="major"
elif grep -qE '^feat(\([^)]+\))?: ' <<<"$SUBJECTS"; then
  BUMP="minor"
elif grep -qE '^(fix|perf)(\([^)]+\))?: ' <<<"$SUBJECTS"; then
  BUMP="patch"
else
  exit 0
fi

if [ -z "$LATEST" ]; then
  echo "0.1.0"
  exit 0
fi
IFS=. read -r MAJOR MINOR PATCH <<<"${LATEST#v}"
# Below 1.0 a breaking change is a minor bump: 1.0.0 is cut by hand.
[ "$BUMP" = major ] && [ "$MAJOR" -eq 0 ] && BUMP="minor"
case "$BUMP" in
major) echo "$((MAJOR + 1)).0.0" ;;
minor) echo "$MAJOR.$((MINOR + 1)).0" ;;
patch) echo "$MAJOR.$MINOR.$((PATCH + 1))" ;;
esac
