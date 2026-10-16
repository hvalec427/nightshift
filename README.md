# nightshift

A machine that works your GitHub issues with Claude Code. Label an issue `agent`;
nightshift asks you what it needs to know on the issue, posts a plan (a spec and
its tickets), builds the tickets in order once you say **go**, and opens a pull
request. You only ever reply on the issue.

It runs on a machine of yours (your Mac, a Mac mini, a macOS VM), polling GitHub,
so nothing is added to your repos and no admin rights are needed. In a React
Native repo, with [rn-agent](https://github.com/hvalec427/rn-agent) installed,
each change is checked on a simulator of its own and the pull request gets
screenshots and a recording.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/hvalec427/nightshift/master/install.sh | sh -s -- --service
```

It installs the latest release: the `nightshift` command (`~/.nightshift/bin`)
and its Claude Code plugin (also copied to `~/.nightshift/plugin`, for runs),
both at that release's tag, and with `--service` runs `nightshift watch` in the
background whenever you're logged in (a LaunchAgent, through `nightshift start`).
Leave out `--service` to run it by hand. Run it again to update to the latest
release; a running service is restarted on the new version. It ends with
`nightshift doctor` (below), and only starts the service once nothing required
is missing.

To test what's on `master` instead, add `--master` (`… | sh -s -- --master`);
run from a clone (`./install.sh`), it installs the clone's files.
`nightshift --version` says which one runs: `0.2.0` for a release,
`master (<commit>)`, or `dev (<commit>)` from a clone.

Then:

1. `claude setup-token`, and save the token it prints to `~/.nightshift/token`
   (`chmod 600`): a year of unattended runs on your Claude subscription.
2. `gh auth login` (gh 2.99 or newer, for screenshots in pull requests).
3. For each repo: a clone of it on the machine, then
   `nightshift add <owner/repo> <path to the clone>`. That also creates its
   `agent` label and the status labels.

## What it needs

`nightshift doctor` checks all of it on this machine, starting with the
nightshift version that runs (and, on a release, whether a newer one is out):
what's installed and its version, gh's login, a Claude token, nightshift's
plugin, and each watched repo's clone and `agent` label (with a hint when GitHub
keeps merged branches there). It says what's missing and how to get it, and
fails when something required is; `nightshift start` won't start the service until
nothing is.

Always:

| Tool | For | Minimum |
|---|---|---|
| git | worktrees and branches | 2.31 |
| [gh](https://cli.github.com), logged in | issues, labels and pull requests (with screenshots attached) | 2.99 |
| [Claude Code](https://claude.com/claude-code) (`claude`), with a token in `~/.nightshift/token` (or logged in) | the runs | 2.1.286 (the version its run flags were checked on) |
| jq | reading GitHub's and Claude's JSON, and the logs | 1.6 |

For React Native repos (required once a watched repo's `package.json` has
`react-native`; optional otherwise), all from
[rn-agent's installer](https://github.com/hvalec427/rn-agent) except tmux and Xcode:

| Tool | For |
|---|---|
| the rn-agent plugin | the run-app skill and its session hooks |
| signalbox | Metro, builds and a simulator per run |
| boop | screenshots, taps and recordings |
| tmux | signalbox's sessions (`brew install tmux`) |
| Xcode, selected (`sudo xcode-select -s /Applications/Xcode.app`) | building and simulating the app |

## Working an issue

| You | nightshift |
|---|---|
| Open an issue, add the `agent` label (and a [type](#issue-types) label) | Reads it and the code; asks its questions in one comment (each with its recommended answer), or goes straight to the plan |
| Reply | More questions, or a plan: the spec and its tickets, in the to-spec and to-tickets format of [Matt Pocock's skills](https://github.com/mattpocock/skills) |
| Reply **go** (or what to change) | Builds the tickets in order, a progress comment per ticket, then opens the pull request and links it |
| Comment on the issue after that | Makes the change on the same branch and pushes it |
| Merge another pull request | Rebases and updates the ones it affects (below) |
| Remove the label, add `invalid` or `wontfix`, or close the issue | Stops it; `nightshift status` says so and why |
| Add the label back, remove `invalid`/`wontfix`, or reopen it | Picks up the stopped run where it left off |
| Merge its pull request, or close the issue | It's done: `nightshift status` leaves it out, and its state and branch are cleaned up |

Each issue gets its own worktree (in the repo's clone, `.claude/worktrees/issue-<n>`,
branch `nightshift/issue-<n>`) and one Claude session that every run continues, so
it remembers the whole conversation. Once the pull request is open, the worktree is
removed; the branch stays. Once it's done (its pull request merged, or the issue
closed with nothing to resume), only its log and what it needs to come back stay
in `~/.nightshift`. A merged branch is deleted, here and on GitHub, unless it has
commits the pull request didn't (a failed delete on GitHub is logged, not fatal). A comment on a done issue (open and labelled) picks it up again.

## Issue types

Give an issue its type with one of GitHub's default labels, next to `agent`;
nightshift reads it at the start of every run and works the issue the way it
calls for:

| Label | nightshift |
|---|---|
| `bug` | finds the cause, and its plan starts with a test that fails the way the bug does; the fix makes it pass |
| `enhancement` | asks, plans, builds and opens a pull request, as above |
| `documentation` | the same, kept to the docs |
| `question` | answers it in a comment: no plan, no pull request. Reply to follow up, or ask for a change to have it built |
| `duplicate` | a comment linking the issue it duplicates; no pull request |
| `invalid`, `wontfix` | doesn't work it: as if you'd removed `agent` (a run in flight stops); remove the label to pick it up again |

With no type label, the run picks one from the issue, adds it, and says so in
its comment; when a type turns out wrong, it swaps the label and says why. It
only uses labels the repo has. Change the label yourself and yours stands: the
next run is told, and leaves it. `good first issue` and `help wanted` say who
should take an issue, not what it is, so they change nothing. If an issue has
two type labels, the first of `invalid`/`wontfix`, `duplicate`, `bug`, `question`, `documentation`,
`enhancement` wins in that order. `nightshift status` shows each issue's type.

## Status labels

Each issue nightshift works carries one status label at a time, so the issue
list shows where each stands, and `label:"nightshift: needs you"` lists the ones
waiting on you:

| Label | |
|---|---|
| `nightshift: queued` | labelled, waiting for its first run (or a free slot) |
| `nightshift: thinking` | a run is reading the issue and the code |
| `nightshift: planning` | a run is writing or revising the plan |
| `nightshift: building` | a run is building the tickets, or changing the open pull request |
| `nightshift: updating` | a run is updating the pull request after a merge |
| `nightshift: needs you` | waiting on your reply: questions, an answer, a plan, blocked, or a failed run |
| `nightshift: PR open` | the pull request is open, nothing running |
| `nightshift: stopped` | a run was stopped partway |

The watcher sets them as runs start and end; a run says when it moves on to
planning or building with `nightshift label <status>`. They come off once it's done, or when you remove the `agent` label with nothing
running (and come back with it). `nightshift status` says the same.

Its comments start with **🤖 nightshift** and carry a hidden `<!-- nightshift -->`
marker, which is how it tells them from yours: it runs as your GitHub account, so
on GitHub they're yours. It only acts on the label when you added it, and only on
comments from you (`allowed_users` below).

```sh
nightshift status                   # the service, the issues in progress, what each is doing (or why it stopped), for how long, and merge order
nightshift status --all             # the done ones too: when their pull request merged, or the issue closed
nightshift start                    # run the service: nightshift watch, in the background whenever you're logged in
nightshift stop                     # stop the service, and the runs in flight, until nightshift start
nightshift stop <owner/repo>#<n>    # stop one
nightshift logs -f                  # every issue, as it happens: picked up, runs started and done, comments, PRs
nightshift logs <owner/repo>#<n> -f # the same for one issue
nightshift logs -f -vv              # more: -v Claude's messages, -vv its tool calls, -vvv everything
nightshift doctor                   # what this machine is missing, and how to get it
nightshift --version                # the version that runs
```

`logs` shows a level and the ones above it, with or without an issue:

| Level | Flag | Adds |
|---|---|---|
| `runs` (default) | | issues picked up (or ignored, waiting, stopped), runs started and done (with how long they took), each comment nightshift posts and its stage, pull requests |
| `messages` | `-v` | Claude's text |
| `tools` | `-vv` | tool calls and failed tool results |
| `all` | `-vvv` | thinking, every tool result, and the polls with nothing new |

`-l <level>` (or `--level`) names the level instead. Without `-f`, `logs` prints
the whole log. The logs live in `~/.nightshift`: `watch.log` (every issue's
lines, kept to its last 20,000) and each issue's full history in
`issues/<owner>_<repo>_<n>/log`.

## Pull requests that overlap

Two nightshift issues overlap when their changes touch the same file, or one relies
on something the other adds (a function, a flag, a file). nightshift checks for this
against the other `nightshift/issue-*` branches and open pull requests when it
plans, and again when it opens the pull request. The plan says so ("touches the
same code as #10"), and so does the pull request: **Merge after #10** when it goes
second, **Overlaps with #10** when it goes first. The one relied on goes first;
otherwise the pull request that opened first does. `nightshift status` shows it as
`PR <url> · after #10`.

After a merge, each poll looks at the open nightshift pull requests. One that now
conflicts with the default branch (after any merge, nightshift's or not), or that
goes after or overlaps the nightshift pull request that just merged, gets a comment
on its issue and a run. That run rebases it onto the default branch, fixes the
conflicts, and updates the change to fit what merged, not just to apply. It runs the
checks again, force-pushes (`--force-with-lease`), and says what changed beyond the
conflict fixes. A conflict that needs your decision gets a question on the issue
instead. Meanwhile `status` shows `conflicts, rebasing` or `updating after #10`. So
the pull requests can be merged in any order.

## Config

`~/.nightshift/config`, written by `nightshift add`:

```
repo hvalec427/nightshift /Users/me/dev/nightshift
allowed_users=hvalec427
max_parallel=2
interval=30
permission_mode=auto
```

- `allowed_users`: whose labels and comments count (default: your gh account).
- `max_parallel`: issues worked at once (each may run a simulator).
- `interval`: seconds between polls.
- `permission_mode`: Claude Code's permission mode for runs. Commands that reach
  GitHub (`gh`, `git`) and signalbox and boop are always allowed.
- `isolated`: `true` (the default) runs Claude without the machine's own
  user-level setup, so every machine works an issue the same way: no skills from
  `~/.claude/skills`, no `~/.claude/settings.json`, `~/.claude/CLAUDE.md`,
  plugins, hooks or MCP servers of yours. A run loads the repo's own `.claude`
  setup, nightshift's plugin (its copy in `~/.nightshift/plugin`, which the
  install keeps up to date) and, when it's installed, rn-agent; commits and pull
  requests get no Claude attribution. `false` runs with your whole setup, as
  your own sessions do.

Every run, isolated or not, and every Claude session of yours where the
nightshift plugin is enabled get nightshift's default instructions:
[`plugin/instructions.md`](plugin/instructions.md) (installed at
`~/.nightshift/plugin/instructions.md`), its rules for commit messages and pull
requests, Conventional Commits and no AI attribution included. Runs get them in
their system prompt, your own sessions from the plugin's `SessionStart` hook.
To add to them, or override them, write your own rules in
`~/.nightshift/instructions.md`: they come after the defaults and win where the
two disagree. Each machine has its own; `nightshift doctor` says which ones
apply.

## A dedicated machine

A Mac mini, or a macOS VM on Apple silicon (Tart, UTM): iOS simulators need macOS,
so a Linux VM only works for non-mobile repos. Set it up to stay logged in:
automatic login, `sudo pmset -a sleep 0`, Xcode selected
(`sudo xcode-select -s /Applications/Xcode.app`), then the install above. For a
separate identity, log `gh` in as a second GitHub account (invite it to your repos;
in an organisation, an admin adds it).

## Finishing by hand

The plugin's `finish` skill works in any Claude Code session too: in a
`claude --worktree <name>` session, say **finish** and it commits, pushes, opens
the pull request (with screenshots and a recording when the app is running there)
and removes the worktree.

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

Each `scripts/test-*.sh` drives nightshift the way it's used, in a throwaway
`HOME` and `NIGHTSHIFT_HOME`, against a fake GitHub and a fake Claude
(`scripts/fake`): nothing reaches GitHub, Claude or your own `~/.nightshift`. The
fake `gh` keeps GitHub as files (issues, comments, labels, pull requests) and runs
nightshift's own `--jq` filters on them; it fails on any call it doesn't know.
The fake `claude` keeps each run's arguments and plays a script: its text,
comments, `nightshift label`, commits, a pull request, a failure, or waiting to be
stopped.

A test is a few lines in a subshell, with the helpers in `scripts/test-lib.sh`:

```sh
(world                                       # a machine watching o/r
  gh_issue o/r 7 alice agent                 # alice labels issue 7
  runs_do 'comment plan; label "needs you"'  # what the run does
  poll                                       # nightshift once
  expect "a plan: needs you" "$(status_label 7)" "needs you")
```

## Credits

How nightshift asks, specs, tickets and tests (the issue skill's `questions.md`,
`spec.md`, `tickets.md` and `tdd.md`) is adapted from
[Matt Pocock's skills](https://github.com/mattpocock/skills) (MIT): see
[plugin/THIRD_PARTY.md](plugin/THIRD_PARTY.md). They ship in the plugin, so a run
doesn't depend on which skills the machine has.
