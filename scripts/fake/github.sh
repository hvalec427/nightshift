# shellcheck shell=bash
# GitHub as files in $GH_FAKE, for the tests: what the fake gh reads and
# changes, and what a test sets up through the same functions. Per repo, in
# repos/<owner>_<repo>/: repo.json, labels (a name a line), pulls.json (newest
# first, as gh lists them), origin (the path of its git remote) and per issue
# issues/<n>.json (created_at: now, or gh_created), <n>.comments.json and
# <n>.events.json. `user` is who gh is logged in as; `clock` counts, for ids
# and update times.

# A repo's directory.
gh_dir() { printf '%s/repos/%s' "$GH_FAKE" "$(echo "$1" | tr '/' '_')"; }

# Holding the lock: the files change one writer at a time (runs work issues
# side by side).
gh_lock() { until mkdir "$GH_FAKE/lock" 2>/dev/null; do sleep 0.01; done; }
gh_unlock() { rmdir "$GH_FAKE/lock"; }

# The next number on the clock (comment ids, update times).
gh_tick() {
  local c
  c=$(($(cat "$GH_FAKE/clock" 2>/dev/null || echo 0) + 1))
  echo "$c" >"$GH_FAKE/clock"
  echo "$c"
}

# Rewrite JSON file $1 with jq filter $2 (and jq's arguments after it).
gh_edit() {
  local f=$1 filter=$2
  shift 2
  jq "$@" "$filter" "$f" >"$f.tmp" && mv "$f.tmp" "$f"
}

# A repo on GitHub, with its git remote: gh_repo <owner/repo> <origin path>.
gh_repo() {
  local d
  d=$(gh_dir "$1")
  mkdir -p "$d/issues"
  echo "$2" >"$d/origin"
  printf '{"default_branch":"master","delete_branch_on_merge":false}\n' >"$d/repo.json"
  echo '[]' >"$d/pulls.json"
  : >"$d/labels"
}

# Issue $2 in repo $1, opened by $3, with labels $4.. (each added by $3).
gh_issue() {
  local repo=$1 n=$2 by=$3 d
  shift 3
  d=$(gh_dir "$repo")
  gh_lock
  printf '{"number":%s,"state":"open","title":"Issue %s","user":{"login":"%s"},"labels":[],"created_at":"%s","updated_at":"t%s"}\n' \
    "$n" "$n" "$by" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(gh_tick)" >"$d/issues/$n.json"
  echo '[]' >"$d/issues/$n.comments.json"
  echo '[]' >"$d/issues/$n.events.json"
  gh_unlock
  for l in "$@"; do gh_label_add "$repo" "$n" "$by" "$l"; done
}

# Issue $2 was opened at $3 (UTC, 2026-01-01T00:00:00Z); gh_issue says now.
gh_created() { gh_edit "$(gh_dir "$1")/issues/$2.json" '.created_at = $t' --arg t "$3"; }

# Mark issue $2 updated now.
gh_touch() { gh_edit "$(gh_dir "$1")/issues/$2.json" '.updated_at = $t' --arg t "t$(gh_tick)"; }

# $3 adds label $4 to issue $2.
gh_label_add() {
  local f
  f="$(gh_dir "$1")/issues/$2"
  gh_lock
  gh_edit "$f.json" 'if any(.labels[]; .name == $l) then . else .labels += [{name: $l}] end' --arg l "$4"
  gh_edit "$f.events.json" '. + [{event: "labeled", label: {name: $l}, actor: {login: $u}}]' --arg l "$4" --arg u "$3"
  gh_touch "$1" "$2"
  gh_unlock
}

# $3 removes label $4 from issue $2.
gh_label_remove() {
  local f
  f="$(gh_dir "$1")/issues/$2"
  gh_lock
  gh_edit "$f.json" '.labels |= map(select(.name != $l))' --arg l "$4"
  gh_edit "$f.events.json" '. + [{event: "unlabeled", label: {name: $l}, actor: {login: $u}}]' --arg l "$4" --arg u "$3"
  gh_touch "$1" "$2"
  gh_unlock
}

# Issue $2's labels, a line each.
gh_labels() { jq -r '.labels[].name' "$(gh_dir "$1")/issues/$2.json"; }

# Close (or with $3 = open, reopen) issue $2.
gh_state() {
  gh_lock
  gh_edit "$(gh_dir "$1")/issues/$2.json" '.state = $s' --arg s "${3:-closed}"
  gh_touch "$1" "$2"
  gh_unlock
}

# $3 comments $4 on issue $2; prints the comment's id.
gh_comment() {
  local id
  gh_lock
  id=$(gh_tick)
  gh_edit "$(gh_dir "$1")/issues/$2.comments.json" '. + [{id: $id, user: {login: $u}, body: $b}]' \
    --argjson id "$id" --arg u "$3" --arg b "$4"
  gh_touch "$1" "$2"
  gh_unlock
  echo "$id"
}

# Issue $2's comments' bodies, separated by a line of `---`.
gh_comments() { jq -r '.[] | .body, "---"' "$(gh_dir "$1")/issues/$2.comments.json"; }

# A pull request from branch $2 into $3 with body $4: prints its URL. Its head
# is the branch's commit on the remote.
gh_pr() {
  local d n url head
  d=$(gh_dir "$1")
  head=$(git -C "$(cat "$d/origin")" rev-parse -q --verify "refs/heads/$2")
  gh_lock
  n=$((100 + $(jq length "$d/pulls.json")))
  url="https://github.com/$1/pull/$n"
  gh_edit "$d/pulls.json" '[{number: $n, url: $url, headRefName: $h, baseRefName: $b, state: "OPEN", mergeable: "MERGEABLE", body: $body, headRefOid: $oid}] + .' \
    --argjson n "$n" --arg url "$url" --arg h "$2" --arg b "$3" --arg body "$4" --arg oid "$head"
  gh_unlock
  echo "$url"
}

# Set field $3 of pull request $2 (its number) to the JSON value $4.
gh_pr_set() {
  gh_lock
  gh_edit "$(gh_dir "$1")/pulls.json" 'map(if .number == $n then .[$k] = $v else . end)' \
    --argjson n "$2" --arg k "$3" --argjson v "$4"
  gh_unlock
}
