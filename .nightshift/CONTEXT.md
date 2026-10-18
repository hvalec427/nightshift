# Context

The project's glossary: the terms it uses and what each means here, one entry per term.
nightshift's runs read this file and keep it up to date.

- **watch**: the long-running `nightshift watch` (the launchd service) that polls the watched
  repos and starts runs.
- **run**: one headless `claude -p` session working an issue, in the issue's worktree; it ends
  when the agent stops.
- **issue dir**: `~/.nightshift/issues/<owner>_<repo>_<n>/`, an issue's state (session, cost,
  log, pid, skill, pr).
- **stage**: where an issue is (questions, plan, build, update, merge…), shown by its
  `nightshift: …` label and the `<!-- nightshift:<stage> -->` marker on each comment.
- **ticket**: one vertical slice of an approved plan, built and committed on its own.
- **small issue**: one the issue skill builds straight from the issue, with no plan or **go**:
  about 20 lines in one or two files, nothing for the user to decide, no new command or option,
  no breaking change, nothing security-relevant or touching CI, releases or installing, and on
  a bug a plain cause. A **full process** reply gets it a plan.
- **look item**: what stops the merge skill with a `look` comment until the user replies
  **merge**: a failed hard gate, an open review finding the plan didn't settle, a decision the
  plan didn't cover, a security-relevant change, or a request to see it first.
- **worth knowing**: what the merge skill reports in its closing comment without stopping the
  merge (a wide blast radius, a new command, a CI change, …).
- **overlap markers**: `<!-- nightshift:after #N -->` and `<!-- nightshift:overlaps #N -->` in
  a PR body, the order PRs should merge in.
- **cycle**: open PRs whose after markers lead back to themselves, so none can merge first. The
  lowest issue goes first, turning its after markers on the cycle into overlaps markers.
- **heartbeat**: what `nightshift status` shows of a running issue's run, from its `log`: its
  latest step (the last tool call, a subagent's too) and its last activity (the log's last change).
- **top**: `nightshift top`, the dashboard: a grid of at least 8 windows (the most that fit,
  never fewer than the issues), a window per issue not done or ignored and the spare ones
  blank, tiled to fit the terminal, each with its status text and the end of its log at the
  `all` level; one frame as plain text when stdout isn't a terminal, and on a terminal live:
  redrawn every second on the alternate screen until `q`. When the issues don't all fit, the
  grid scrolls by rows of windows (`j`/`k`, ↑↓, Space, PgDn/PgUp), a bottom line saying which.
- **world**: a test's throwaway machine from `world()` in `scripts/test-lib.sh`, with the
  fakes in `scripts/fake/`.
- **full_suite**: the `.nightshift/config` option for where a repo's whole test suite runs:
  `local` (before each push), `nothing` (never by nightshift), or unset (on CI; locally only
  without CI). An unknown value counts as unset.
- **test_command**: the `.nightshift/config` option naming the command that runs a repo's whole
  test suite. The prompt's whole-suite line names it, except under `full_suite=nothing`.
- **cost_breakdown**: the `.nightshift/config` option for the closing cost comment: `false` keeps
  it to one line of cost, tokens, time and the pull request's size; anything else (or unset) adds
  the dollars of each model, the agents table and the time line.
- **cost_comment**: the `.nightshift/config` option that, set to `false`, leaves out the closing
  cost comment altogether, `cost_breakdown` or not.
- **has CI**: a workflow in `.github/workflows/` triggers on `pull_request`, or the repo's latest
  merged pull request lists checks (`gh pr checks`), so external CI counts. It matters only when
  `full_suite` is unset.
- **seed / shard**: `NIGHTSHIFT_TEST_SEED` fixes the random order `scripts/test.sh` runs the test
  files in; `NIGHTSHIFT_TEST_SHARD=i/n` runs every n-th file, one of CI's three test jobs.
- **open choice**: a decision in a plan that the issue and the user's answers don't settle, and
  that the user might make differently (an assumption in place of an answer counts). A plan with
  none carries on to the build without waiting for a go.
- **board**: a GitHub project (v2) named by a repo's `project=` in `.nightshift/config`. The repo
  is worked from its cards, in place of the `agent` label; nightshift reads them with one
  GraphQL query a poll (`BOARD_QUERY`).
- **column**: an option of the board's `Status` field, matched by name without regard to case:
  Backlog, Ready, In progress, In review, Your review, Ready to merge and Done. The repo's
  issues in a column other than Backlog and Done are worked; the rest are off.
- **card**: an item of the board. An issue's card is where nightshift reads its column and moves
  it as the work goes; a pull request's card is skipped.
- **draft card**: a card with no issue behind it. One in Ready is turned into an issue of the
  repo (the first one listed that names the board), its card kept.
