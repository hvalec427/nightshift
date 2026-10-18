# Development

## Releases

Pull requests are squash-merged, so each title becomes a commit on `master`, and
titles are [Conventional Commits](https://www.conventionalcommits.org):
`type(scope): description`. Every push to `master` releases what the commits
since the last release call for (`.github/workflows/release.yml`):

| Commits | Release |
|---|---|
| `fix`, `perf` | patch: 0.4.1 → 0.4.2 |
| `feat` | minor: 0.4.1 → 0.5.0 |
| `!` after the type, or a `BREAKING CHANGE:` footer | major from 1.0 on; minor until then (1.0.0 is cut by hand) |
| only `docs`, `chore`, `ci`, `refactor`, `test`, … | none |

A release is a `vX.Y.Z` tag and a GitHub release, its notes grouped into
Breaking changes, Features and Fixes, each line linking its pull request.
`scripts/release.sh --dry-run` prints what the next one would be.

Each pull request is checked (`.github/workflows/check.yml`): its title must be a
Conventional Commit (`scripts/commit-lint.sh`), `shellcheck` must pass on the
scripts, and so must the tests (below, on macOS). To keep a pull request with a bad
title from merging, make the `title` check required: Settings → Branches (or
Rules) → a rule for `master` → Require status checks to pass → `title`.

## Tests

```sh
bash scripts/test.sh            # all of them
bash scripts/test.sh runs prs   # scripts/test-runs.sh and scripts/test-prs.sh
```

The files run in parallel, in a random order, 8 at a time (`NIGHTSHIFT_TEST_JOBS`
changes it); each one's results print when it ends, with how long it took. The
order comes from a seed, printed first as `seed <n>` and again after a failure,
with the command that repeats it: `NIGHTSHIFT_TEST_SEED=<n> bash scripts/test.sh`.
`NIGHTSHIFT_TEST_SHARD=1/3` runs every third file of the list by size, as CI's
three test jobs do; they share one seed, and a failed job's repeat command names its
shard too, so it runs the same files in the same order anywhere.

A test file passes alone, in any order and in any split across machines. Tests that
rely on each other (a shared setup, an order) live in the same file; nothing relies
on another file.

Each `scripts/test-*.sh` drives nightshift the way it's used, in a throwaway
`HOME` and `NIGHTSHIFT_HOME`, against a fake GitHub and a fake Claude
(`scripts/fake`): nothing reaches GitHub, Claude or your own `~/.nightshift`. The
fake `gh` keeps GitHub as files (issues, comments, labels, pull requests, project boards) and runs
nightshift's own `--jq` filters on them; it fails on any call it doesn't know.
The fake `claude` keeps each run's arguments and plays a script: its text,
comments, skills it invokes, `nightshift label`, commits, a pull request, a failure, or waiting to be
stopped. The fake `curl` answers the latest release and serves its `install.sh` and
a ref's tarball.
`scripts/test-service.sh` is the exception: it starts and stops a real
LaunchAgent, one of `com.nightshift.test.1` … `.8`, claimed for the run so suites
can run at once (skipped where there's no GUI session), and runs `install.sh` into
a throwaway `HOME`. `scripts/test-skills.sh` checks the skills' structure
(frontmatter, links, the skills and agents they name) and runs the plugin's
`SessionStart` hook; `scripts/test-review.sh` checks the wiring in the review
skill's files themselves. The fake `claude` can't see a run invoke a skill.

A suite run cleans up after itself: each test world is deleted when it ends, and
`test.sh` runs in its own temp directory under `$TMPDIR` and removes it on exit.
`KEEP_WORLD=1 bash scripts/test.sh runs` keeps them and prints where they are.

A test is a few lines in a subshell, with the helpers in `scripts/test-lib.sh`:

```sh
(world                                       # a machine watching o/r
  gh_issue o/r 7 alice agent                 # alice labels issue 7
  runs_do 'comment plan; label "needs you"'  # what the run does
  poll                                       # nightshift once
  expect "a plan: needs you" "$(status_label 7)" "needs you")
```
