#!/usr/bin/env bash
# Tests for the release scripts: next-version.sh, release-notes.sh and
# commit-lint.sh, each run in a throwaway git repo with chosen commits and tags.
#   bash scripts/test-release.sh
set -euo pipefail
. "$(dirname "$0")/test-lib.sh"

SCRIPTS="$(cd "$(dirname "$0")" && pwd -P)"

# A fresh repo in a temp dir, as the current directory.
repo() {
  cd "$(temp -d)"
  git init -q
  git config user.name test
  git config user.email test@example.com
  git config commit.gpgsign false
  git config tag.gpgsign false
}

# A commit with message $1 (and body $2).
commit() { git commit -q --allow-empty -m "$1" ${2:+-m "$2"}; }


next() { bash "$SCRIPTS/next-version.sh"; }
notes() { bash "$SCRIPTS/release-notes.sh" "$@"; }
lint() { bash "$SCRIPTS/commit-lint.sh" --title "$1" 2>/dev/null && echo pass || echo fail; }

# --- next-version.sh -----------------------------------------------------------

(repo
  commit "Initial commit"
  expect "no tag, nothing conventional: nothing to release" "$(next)" ""
  commit "feat: first feature"
  expect "no tag: 0.1.0" "$(next)" "0.1.0")

(repo
  commit "fix: one"; git tag v0.1.0
  expect "nothing since the tag" "$(next)" ""
  commit "docs: readme"; commit "chore: deps"; commit "ci(release): cache"
  expect "only docs/chore/ci: nothing" "$(next)" ""
  commit "fix(status): a bug"
  expect "fix: patch" "$(next)" "0.1.1")

(repo
  commit "fix: one"; git tag v0.1.0
  commit "perf: faster"
  expect "perf: patch" "$(next)" "0.1.1"
  commit "feat(logs): levels"
  expect "feat: minor" "$(next)" "0.2.0")

(repo
  commit "fix: one"; git tag v0.3.2
  commit "feat(config)!: rename max_parallel"
  expect "breaking below 1.0: minor" "$(next)" "0.4.0")

(repo
  commit "fix: one"; git tag v0.3.2
  commit "fix: drop the old flag" "BREAKING CHANGE: --foo is gone"
  expect "BREAKING CHANGE footer below 1.0: minor" "$(next)" "0.4.0")

(repo
  commit "fix: one"; git tag v1.4.2
  commit "feat!: new config"
  expect "breaking from 1.0: major" "$(next)" "2.0.0")

(repo
  commit "fix: one"; git tag v0.9.0; git tag v0.10.0
  commit "fix: two"
  expect "latest tag by version, not by name" "$(next)" "0.10.1")

(repo
  commit "fix: one"; git tag v0.1.0
  commit "chore: bump" "* feat: listed in a squash body"
  expect "types only from subjects" "$(next)" "")

# --- release-notes.sh ----------------------------------------------------------

(repo
  commit "Old history"; commit "fix: one (#1)"; git tag v0.1.0
  commit "feat(status): show waits (#5)"
  commit "fix: keep the session (#6)"
  commit "docs: readme (#7)"
  commit "perf(logs): faster tail (#8)"
  commit "feat(config)!: rename max_parallel (#9)"
  commit "refactor: tidy" "BREAKING CHANGE: the old flag is gone"
  expect "notes grouped by type" "$(notes v0.1.0)" "$(cat <<'EOF'
### Breaking changes

- **config:** rename max_parallel (#9)
- tidy

### Features

- **status:** show waits (#5)

### Fixes

- keep the session (#6)
- **logs:** faster tail (#8)
EOF
)")

(repo
  commit "Old history (#2)"; commit "feat: releases (#3)"
  expect "no tag: the whole history, conventional commits only" "$(notes)" "$(cat <<'EOF'
### Features

- releases (#3)
EOF
)")

(repo
  { echo "refactor: tidy"; echo; echo "BREAKING CHANGE: the old flag is gone"
    awk 'BEGIN { for (i = 0; i < 50000; i++) print "a line of a long body" }'; } >msg
  git commit -q --allow-empty -F msg
  expect "a large body's BREAKING CHANGE: breaking" "$(notes)" "$(cat <<'EOF'
### Breaking changes

- tidy
EOF
)")

# --- commit-lint.sh ------------------------------------------------------------

expect "lint: plain" "$(lint "fix: keep the session of a stopped run")" pass
expect "lint: scope" "$(lint "feat(status): show how long a run waited")" pass
expect "lint: breaking" "$(lint "feat(config)!: rename max_parallel")" pass
expect "lint: no type" "$(lint "Run the same on any machine")" fail
expect "lint: unknown type" "$(lint "feature: add x")" fail
expect "lint: no space" "$(lint "fix:add x")" fail
expect "lint: empty scope" "$(lint "fix(): add x")" fail
expect "lint: uppercase description" "$(lint "fix: Add x")" fail
expect "lint: full stop" "$(lint "fix: add x.")" fail
expect "lint: over 72" "$(lint "fix: $(printf 'a%.0s' $(seq 1 68))")" fail
expect "lint: 72 exactly" "$(lint "fix: $(printf 'a%.0s' $(seq 1 67))")" pass

(cd "$(temp -d)"
  { echo "fix: keep the session"; echo
    awk 'BEGIN { for (i = 0; i < 50000; i++) print "a line of a long body" }'; } >msg
  expect "lint: a large message file" \
    "$(bash "$SCRIPTS/commit-lint.sh" --file msg 2>/dev/null && echo pass || echo fail)" pass)

report
