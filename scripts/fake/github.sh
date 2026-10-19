# shellcheck shell=bash
# GitHub as files in $GH_FAKE, for the tests: what the fake gh reads and
# changes, and what a test sets up through the same functions. Per repo, in
# repos/<owner>_<repo>/: repo.json, labels (a name a line), pulls.json (newest
# first, as gh lists them), origin (the path of its git remote) and per issue
# issues/<n>.json (created_at: now, or gh_created), <n>.comments.json and
# <n>.events.json. An issue has an `id` (5000 + its number, apart from the
# number, as on GitHub), an `issue_dependencies_summary` whose `blocked_by`
# counts its open blockers (a test sets it: gh_set_blocked_by),
# `blocked_by_ids` (the ids it was made to wait for) and, as a parent,
# `sub_issue_ids`. `user` is who gh is logged in as; `scopes` (once a test has
# called gh_scopes) the scopes of its token; `clock` counts, for ids and update
# times.

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
  jq -n -c --arg r "$1" '{default_branch: "master", delete_branch_on_merge: false, full_name: $r, node_id: ("R_" + ($r | gsub("/"; "_")))}' >"$d/repo.json"
  echo '[]' >"$d/pulls.json"
  : >"$d/labels"
}

# Issue $2 in repo $1, opened by $3, with labels $4.. (each added by $3).
gh_issue() {
  local repo=$1 n=$2 by=$3 d
  shift 3
  d=$(gh_dir "$repo")
  gh_lock
  printf '{"number":%s,"id":%s,"state":"open","title":"Issue %s","user":{"login":"%s"},"labels":[],"created_at":"%s","updated_at":"t%s","issue_dependencies_summary":{"blocked_by":0,"blocking":0,"total_blocked_by":0,"total_blocking":0},"blocked_by_ids":[],"sub_issue_ids":[]}\n' \
    "$n" "$((5000 + n))" "$n" "$by" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(gh_tick)" >"$d/issues/$n.json"
  echo '[]' >"$d/issues/$n.comments.json"
  echo '[]' >"$d/issues/$n.events.json"
  gh_unlock
  for l in "$@"; do gh_label_add "$repo" "$n" "$by" "$l"; done
}

# Issue $2 was opened at $3 (UTC, 2026-01-01T00:00:00Z); gh_issue says now.
gh_created() { gh_edit "$(gh_dir "$1")/issues/$2.json" '.created_at = $t' --arg t "$3"; }

# The number of the issue with id $2, if there is one.
gh_id_number() {
  local f
  for f in "$(gh_dir "$1")"/issues/*.json; do
    case "${f##*/}" in *.*.json) ;; *) jq -r --argjson i "$2" 'select(.id == $i) | .number' "$f" ;; esac
  done | head -1
}

# Issue $3 (an id) becomes a sub-issue of issue $2.
gh_sub_issue_add() {
  local number
  number=$(gh_id_number "$1" "$3")
  [ -n "$number" ] || return 1
  gh_lock
  gh_edit "$(gh_dir "$1")/issues/$2.json" '.sub_issue_ids += [$i]' --argjson i "$3"
  gh_edit "$(gh_dir "$1")/issues/$number.json" '.parent_issue_id = $p' --argjson p "$((5000 + $2))"
  gh_unlock
}

# Issue $2's sub-issues' numbers, a line each.
gh_sub_issues() {
  local i
  for i in $(jq -r '.sub_issue_ids[]' "$(gh_dir "$1")/issues/$2.json"); do gh_id_number "$1" "$i"; done
}

# Issue $2 is made to wait for issue $3 (an id): recorded, and counted as open
# in its summary when that issue is.
gh_block_add() {
  local number
  number=$(gh_id_number "$1" "$3")
  [ -n "$number" ] || return 1
  gh_lock
  gh_edit "$(gh_dir "$1")/issues/$2.json" '
    .blocked_by_ids += [$i]
    | .issue_dependencies_summary.total_blocked_by += 1
    | .issue_dependencies_summary.blocked_by += $open' --argjson i "$3" \
    --argjson open "$(jq 'if .state == "open" then 1 else 0 end' "$(gh_dir "$1")/issues/$number.json")"
  gh_unlock
}

# Issue $2 is made to wait for issue $4 of another repo $3, as
# `blocked_by_other` records it (the board query reads it).
gh_block_add_other() {
  gh_lock
  gh_edit "$(gh_dir "$1")/issues/$2.json" '.blocked_by_other += [{repo: $r, number: $n}]' --arg r "$3" --argjson n "$4"
  gh_unlock
}

# The numbers of the issues issue $2 was made to wait for, a line each.
gh_blockers() {
  local i
  for i in $(jq -r '.blocked_by_ids[]' "$(gh_dir "$1")/issues/$2.json"); do gh_id_number "$1" "$i"; done
}

# Set how many open blockers GitHub counts for issue $2 to $3.
gh_set_blocked_by() {
  gh_lock
  gh_edit "$(gh_dir "$1")/issues/$2.json" '.issue_dependencies_summary.blocked_by = $c' --argjson c "$3"
  gh_unlock
}

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

# --- a project board ----------------------------------------------------------------
# Projects (v2), in projects/<owner>_<number>/ of $GH_FAKE, which the fake gh
# answers nightshift's GraphQL operations from (`gh api graphql`, see
# scripts/fake/gh): project.json, the project's id and its Status field with
# its options ({id, field: {id, options: [{id, name}]}}), and items.json, its
# cards in order: {id, repo, number, option} for an issue and {id, draft:
# {id, title}, option} for a draft, `option` the id of the card's Status
# option (null: none). An issue card is read live from the issue's own file.
# A repo's node id (repo.json) is R_<owner>_<repo>.
# A project is named by "<owner>/<number>" in the functions below.

# A project's directory.
gh_project_dir() { printf '%s/projects/%s' "$GH_FAKE" "$(echo "$1" | tr '/' '_')"; }

# Project $1 (<owner>/<number>) with Status columns $2.. (default: the eight
# nightshift uses), and no cards.
gh_project() {
  local p=$1 d cols
  shift
  [ $# -gt 0 ] || set -- Backlog Ready "Needs you" "In progress" "In review" "Your review" "Ready to merge" Done
  d=$(gh_project_dir "$p")
  mkdir -p "$d"
  cols=$(printf '%s\n' "$@" | jq -R -s -c 'split("\n")[:-1]')
  jq -n -c --arg id "PVT_$(echo "$p" | tr '/' '_')" --argjson cols "$cols" '
    {id: $id, field: {id: ($id + "_status"), options: [range(0; $cols | length) as $i | {id: ($id + "_opt\($i)"), name: $cols[$i]}]}}' >"$d/project.json"
  echo '[]' >"$d/items.json"
}

# The scopes of gh's token, as `gh auth status` lists them: names $1.. (default
# gist, project, read:org, repo).
gh_scopes() {
  printf '%s\n' "$@" | sed "s/.*/'&'/" | paste -sd, - | sed 's/,/, /g' >"$GH_FAKE/scopes"
}

# The id of project $1's Status option named $2 (case-insensitive), or null.
gh_option() {
  jq -c --arg n "$2" '[.field.options[] | select(.name | ascii_downcase == ($n | ascii_downcase)) | .id][0]' "$(gh_project_dir "$1")/project.json"
}

# Issue $3 of repo $2 as a card of project $1, in column $4.
gh_card() {
  local d
  d=$(gh_project_dir "$1")
  gh_lock
  gh_edit "$d/items.json" '. + [{id: ("PVTI_" + ($r | gsub("/"; "_")) + "_\($n)"), repo: $r, number: $n, option: $o}]' \
    --arg r "$2" --argjson n "$3" --argjson o "$(gh_option "$1" "$4")"
  gh_unlock
}

# A draft card titled $2 in column $3 of project $1: prints its item id.
gh_draft() {
  local d id
  d=$(gh_project_dir "$1")
  gh_lock
  id="PVTI_draft_$(gh_tick)"
  gh_edit "$d/items.json" '. + [{id: $id, draft: {id: ("DI_" + $id), title: $t}, option: $o}]' \
    --arg id "$id" --arg t "$2" --argjson o "$(gh_option "$1" "$3")"
  gh_unlock
  echo "$id"
}

# Card of issue $3 of repo $2 (project $1) in column $4.
gh_card_move() {
  gh_lock
  gh_edit "$(gh_project_dir "$1")/items.json" 'map(if .repo == $r and .number == $n then .option = $o else . end)' \
    --arg r "$2" --argjson n "$3" --argjson o "$(gh_option "$1" "$4")"
  gh_unlock
}

# Card (item id $2) of the project in directory $1 set to option id $3.
gh_item_move() {
  gh_lock
  gh_edit "$1/items.json" 'map(if .id == $i then .option = $o else . end)' --arg i "$2" --arg o "$3"
  gh_unlock
}

# Issue $3 of repo $2 taken off project $1.
gh_card_remove() {
  gh_lock
  gh_edit "$(gh_project_dir "$1")/items.json" 'map(select((.repo == $r and .number == $n) | not))' --arg r "$2" --argjson n "$3"
  gh_unlock
}

# The Status column of issue $3 of repo $2 on project $1: its name, or nothing
# when it has none or isn't on the board.
gh_card_column() {
  jq -r --arg r "$2" --argjson n "$3" --slurpfile p "$(gh_project_dir "$1")/project.json" '
    first(.[] | select(.repo == $r and .number == $n)).option as $o
    | $p[0].field.options[] | select(.id == $o) | .name' "$(gh_project_dir "$1")/items.json"
}

# The draft card $2 (its item id) of project $1 turned into an issue in repo $3,
# titled as the draft, opened by the logged-in user: the card keeps its item id
# and column, and becomes an issue card. Prints the issue's number.
gh_draft_convert() {
  local d n f title
  d=$(gh_project_dir "$1")
  title=$(jq -r --arg i "$2" '.[] | select(.id == $i and .draft) | .draft.title' "$d/items.json")
  [ -n "$title" ] || return 1
  n=1
  for f in "$(gh_dir "$3")"/issues/*.json; do
    case "${f##*/}" in *.*.json) ;; *) [ -f "$f" ] && n=$((n + 1)) ;; esac
  done
  gh_issue "$3" "$n" "$(cat "$GH_FAKE/user")"
  gh_edit "$(gh_dir "$3")/issues/$n.json" '.title = $t' --arg t "$title"
  gh_lock
  gh_edit "$d/items.json" 'map(if .id == $i then {id, repo: $r, number: $n, option} else . end)' \
    --arg i "$2" --arg r "$3" --argjson n "$n"
  gh_unlock
  echo "$n"
}
