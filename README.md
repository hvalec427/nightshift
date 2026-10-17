# nightshift

A machine that works your GitHub issues with Claude Code. Label an issue `agent`;
nightshift asks you what it needs to know on the issue, posts a plan (a spec and
its tickets), builds the tickets in order once you say **go**, and opens a pull
request. You only ever reply on the issue.

It runs on a machine of yours (your Mac, a Mac mini, a macOS VM), polling GitHub,
so nothing is added to your repos and no admin rights are needed. A repo's runs
load the Claude Code plugins its line names, and follow its own instructions on
how to check and show a change, so a pull request can come with screenshots and
a recording (see [Plugins](#plugins)).

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

To stop updating by hand, add `--auto-update` (`… | sh -s -- --service
--auto-update`): it sets `auto_update=true` in the config (below), and from then
on the watch installs each new release itself.

To test what's on `master` instead, add `--master` (`… | sh -s -- --master`);
run from a clone (`./install.sh`), it installs the clone's files.
`nightshift --version` says which one runs: `0.2.0` for a release,
`master (<commit>)`, or `dev (<commit>)` from a clone.

Then:

1. `claude setup-token`, and save the token it prints to `~/.nightshift/token`
   (`chmod 600`): a year of unattended runs on your Claude subscription.
2. `gh auth login` (gh 2.99 or newer, for screenshots in pull requests).
3. For each repo: a clone of it on the machine, then
   `nightshift add <owner/repo> <path to the clone>`, with
   `instructions=<file>` for the project's own rules (see below) and
   `plugins=<name>,…` for the plugins its runs need (see [Plugins](#plugins)).
   That also creates its `agent` label and the status labels.
   nightshift merges the repo's pull requests itself; to merge them yourself,
   add `auto_merge=false` (see [Config](#config)).

## What it needs

`nightshift doctor` checks all of it on this machine, starting with the
nightshift version that runs (and, on a release, whether a newer one is out):
what's installed and its version, gh's login, a Claude token, nightshift's
plugin, and each watched repo's clone and `agent` label (with a hint when GitHub
keeps merged branches there), then a line for each plugin its repo line names:
`ok`, or `missing` with how to install it (`claude plugin install <name>`) or
enable it (`claude plugin enable <id>`). It says what's missing and how to get it, and
fails when something required is; `nightshift start` won't start the service until
nothing is.

Always:

| Tool | For | Minimum |
|---|---|---|
| git | worktrees and branches | 2.31 |
| [gh](https://cli.github.com), logged in | issues, labels and pull requests (with screenshots attached) | 2.99 |
| [Claude Code](https://claude.com/claude-code) (`claude`), with a token in `~/.nightshift/token` (or logged in) | the runs | 2.1.286 (the version its run flags were checked on) |
| jq | reading GitHub's and Claude's JSON, and the logs | 1.6 |

What a repo's runs need beyond that comes with the plugins its line names
(see [Plugins](#plugins)).

## Working an issue

| You | nightshift |
|---|---|
| Open an issue, add the `agent` label (and a [type](#issue-types) label) | Reads it and the code; asks its questions in one comment (each with its recommended answer), or goes straight to the plan |
| Reply | More questions, or a plan: the spec and its tickets, in the to-spec and to-tickets format of [Matt Pocock's skills](https://github.com/mattpocock/skills) |
| Reply **go** (or what to change) | Makes each ticket a sub-issue of the issue, then builds the tickets in order, each in a subagent of its own (so one ticket's work doesn't crowd the next; a one-ticket plan is built directly), a progress comment per ticket; has two fresh subagents review the change against the plan and the repo's standards, and fixes what they found in one pass; then opens the pull request, which closes the issue and its sub-issues, and links it, with what the review found |
| Nothing (unless the repo has `auto_merge=false`) | Once the pull request is open or updated and its checks pass, squash-merges it when nothing in it needs you; otherwise lists what does in a look comment (a decision the plan didn't cover, a finding left open, a breaking or security-relevant change, …) |
| Reply **merge** to a look comment | Checks it again (checks, conflicts, the pull requests it goes after) and merges it |
| Comment on the issue after that | Makes the change on the same branch and pushes it (and checks it for merging again) |
| Merge another pull request | Rebases and updates the ones it affects (below) |
| Remove the label, add `invalid` or `wontfix`, or close the issue | Stops it; `nightshift status` says so and why |
| Add the label back, remove `invalid`/`wontfix`, or reopen it | Picks up the stopped run where it left off |
| Merge its pull request, or close the issue | It's done: a last comment says what its runs cost (dollars at API prices, tokens, time), the dollars of each model and the pull request's size (`PR +412 −37 in 9 files`), and lists every agent that ran (each session and the subagents it started) in a table with its model, effort, skills, tokens, time and tool calls; `nightshift status` leaves it out, and its state and branch are cleaned up |

Each issue gets its own worktree (in the repo's clone, `.claude/worktrees/issue-<n>`,
branch `nightshift/issue-<n>`) and a Claude session that its runs continue. When
you approve the plan, the build starts in a fresh one, given the issue, the plan, the
comments since the plan and your approval, so it doesn't carry (and pay for) the
planning conversation: a reply
of just **go** starts it straight away, and any other approval once the planning
session has read it. Later runs (your comments, updates) continue the build session,
until its context is half the model's window: the next run then starts a fresh
session, given the issue, the latest plan, the pull request and what's new (the old
session ids stay in the issue's `sessions` file under `~/.nightshift/issues`). A run
that was stopped or stalled always resumes its session.
A build, update or merge run that ends without commenting (it stopped to wait on
something) is resumed once by itself; a second in a row asks you in a comment.
Once the pull request is open, the worktree is
removed; the branch stays. Once it's done (its pull request merged, or the issue
closed with nothing to resume), only its log and what it needs to come back stay
in `~/.nightshift`. A merged branch is deleted, here and on GitHub, unless it has
commits the pull request didn't (a failed delete on GitHub is logged, not fatal). A comment on a done issue (open and labelled) picks it up again.

Each run starts in the plugin's `issue` skill, which reads the thread and hands the
stage to a skill of its own: `questions`, `plan`, `build` (then `review`,
`finish` and `merge`), `update` (then `merge`), or `answer` for question and
duplicate issues. Invoking a skill loads all of its guidance, so no stage runs without it. The status label follows the skill, `nightshift logs`
shows each one a run invokes, and each comment names the skill that wrote it
(`🤖 nightshift · plan · nightshift:plan`).

## Issue types

Give an issue its type with one of GitHub's default labels, next to `agent`;
nightshift reads it at the start of every run and works the issue the way it
calls for:

| Label | nightshift |
|---|---|
| `bug` | finds the cause with a check that fails the way the bug does (or asks, when it can't build one), and its plan starts with a test that fails the way the bug does; the fix makes it pass |
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
| `nightshift: proposed` | a defect a run found and filed: held until you comment |
| `nightshift: queued` | labelled, waiting for its first run (or a free slot), or a run stopped with the watcher, to resume when it starts again |
| `nightshift: thinking` | a run is reading the issue and the code |
| `nightshift: planning` | a run is writing or revising the plan |
| `nightshift: building` | a run is building the tickets, or changing the open pull request |
| `nightshift: updating` | a run is updating the pull request after a merge |
| `nightshift: merging` | a run is checking the pull request and merging it |
| `nightshift: answering` | a run is answering a `question` or `duplicate` issue |
| `nightshift: needs you` | waiting on your reply: questions, an answer, a plan, blocked, a pull request to look at before it merges, a failed run, or one that stalled twice |
| `nightshift: PR open` | the pull request is open, nothing running |
| `nightshift: stopped` | a run was stopped partway |

The watcher sets them as runs start and end, and as a run invokes one of
nightshift's skills: `nightshift:questions` and `diagnose` set `thinking`, `plan` `planning`,
`build`, `tdd`, `review` and `finish` `building`, `update` `updating`, `merge` `merging` and
`answer` `answering` (`nightshift label <status>` sets one by hand). They come off once
it's done, or when you remove the `agent` label with nothing running (and come back with
it). `nightshift status` says the same, with the
skill a run is in (or its last one ended in).

A run that spots a real defect outside its own issue (a bug, broken docs, a
failing check; not an idea) files it, after looking for a duplicate, with
`agent`, its type and `nightshift: proposed`, at most three a run, and names
them in its next comment; it doesn't fix them on its branch. That's the one
status a run sets, not the watcher. An issue labelled `nightshift: proposed` is
held: the watcher doesn't start it until you comment on it, or remove that
label. Your comment starts its first run, and the run gets your comment.
Others' comments don't start it. `nightshift status` shows a held one as
`proposed: waiting for your comment`.

nightshift's comments start with **🤖 nightshift** and carry a hidden `<!-- nightshift -->`
marker, which is how it tells them from yours: it runs as your GitHub account, so
on GitHub they're yours. It only acts on the label when you added it, and only on
comments from you (`allowed_users` below).

```sh
nightshift status                   # the service, the issues in progress, what each is doing and in which skill (or why it stopped), for how long, what it spent so far, its context size, and merge order
nightshift status --all             # the done ones too: when their pull request merged, or the issue closed
nightshift start                    # run the service: nightshift watch, in the background whenever you're logged in
nightshift stop                     # stop the service, and the runs in flight (they resume when it starts again), until nightshift start
nightshift stop <owner/repo>#<n>    # stop one (it stays stopped until you comment)
nightshift logs -f                  # every issue, as it happens: picked up, runs started and done, skills, comments, PRs
nightshift logs <owner/repo>#<n> -f # the same for one issue
nightshift logs -f -vv              # more: -v Claude's messages, -vv its tool calls, -vvv everything
nightshift doctor                   # what this machine is missing, and how to get it
nightshift --version                # the version that runs
```

`logs` shows a level and the ones above it, with or without an issue:

| Level | Flag | Adds |
|---|---|---|
| `runs` (default) | | issues picked up (or ignored, waiting, stopped), runs started and done (with how long they took, the models they used and their context at the end), each skill a run invokes, each comment nightshift posts and its stage, pull requests |
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
the pull requests can be merged in any order. With auto-merge on, a pull request
that goes after another waits for it, then merges after that update run.

## Models

Each skill and subagent runs on its own model and effort, set in the frontmatter
of the plugin's skills (`plugin/skills/*/SKILL.md`) and agents (`plugin/agents/*.md`).
Once a run invokes a skill, its model covers the run until the next skill sets its own.
No setting changes them: `model=` and `effort=` in the config are ignored, and
`nightshift doctor` notes them.

| | model | effort |
|---|---|---|
| `issue` (routing) | sonnet | low |
| `questions`, `plan` | opus | high |
| `build`, `update`, `review` (its fixes), `merge` | sonnet | high |
| Ticket builder (agent `ticket`) | sonnet | high |
| Spec reviewer (agent `spec-review`) | opus | high |
| Standards reviewer (agent `standards-review`) | sonnet | medium |
| `answer`, `finish` | sonnet | medium |

Each run's line in `nightshift logs` shows the models it used, the main one first.

## Config

`~/.nightshift/config`, written by `nightshift add`:

```
repo hvalec427/nightshift /Users/me/dev/nightshift
repo me/app /Users/me/dev/app instructions=/Users/me/notes/app.md plugins=web-tools
repo hvalec427/other /Users/me/dev/other auto_merge=false
allowed_users=hvalec427
max_parallel=2
interval=5
```

- `repo <owner/repo> <clone path> [key=value …]`: a watched repo and its clone
  (spaces in the path are fine, but its last word can't look like `key=value`:
  it would read as an option), then its options, in any order:
  - `instructions`: a file of the project's own rules for runs (below);
    `nightshift doctor` says when it's missing.
  - `auto_merge=false` makes its pull requests wait for you to merge; without
    it, nightshift merges them on its own. It's on by default, so repos added
    before it start merging on their own after an upgrade. `status` and
    `doctor` say which repos have it off.
  - `plugins`: the Claude Code plugins its runs load, comma-separated:
    `plugins=web-tools,other@marketplace`. A name matches that plugin from any
    marketplace; `name@marketplace`, that one. Each must be installed and
    enabled (`claude plugin install …`); one that isn't, the run goes without,
    and its log says so. Without `plugins=`, runs get only nightshift's plugin.
- `allowed_users`: whose labels and comments count (default: your gh account).
- `max_parallel`: issues worked at once (each may run its app).
- `interval`: seconds between polls (default 5). A poll that finds nothing new
  costs no rate limit: the issues list is asked with the ETag of its last
  answer, and GitHub's `304 Not Modified` doesn't count. The pull requests are
  checked every 30 s at most.
- `auto_update`: `true` has the watch install each new release itself (default
  `false`; `install.sh --auto-update` sets it). It checks for one once an hour.
  Once a new release is out, no new runs start; their issues show `queued`. When
  the runs in flight finish, it runs the release's `install.sh` and restarts on
  the new version, then starts the waiting issues. A failed update is logged
  (what went wrong is in `~/.nightshift/update.log`), and it stays on its version
  until the next check. Only a release install updates itself, not `--master` or
  a clone's.

Runs use Claude Code's `auto` permission mode. Commands that reach GitHub (`gh`,
`git`) are always allowed; what else a repo's runs may do goes in its committed
`.claude/settings.json`. Runs are isolated from the
machine's own user-level setup, so every machine works an issue the same way: no
skills from `~/.claude/skills`, no `~/.claude/settings.json`,
`~/.claude/CLAUDE.md`, plugins, hooks or MCP servers of yours. A run loads the
repo's own `.claude` setup, nightshift's plugin (its copy in
`~/.nightshift/plugin`, which the install keeps up to date) and the plugins
its repo line names; commits and pull requests get no Claude attribution.
`isolated=` and `permission_mode=` lines from older versions are ignored
(`nightshift doctor` notes them).

Every run and every Claude session of yours where the nightshift plugin is
enabled get nightshift's default instructions:
[`plugin/instructions.md`](plugin/instructions.md) (installed at
`~/.nightshift/plugin/instructions.md`): its rules for commit messages and pull
requests, Conventional Commits and no AI attribution included, for keeping a
project's `CLAUDE.md` small and true, and that a run ends when the agent stops, so
it waits for its checks instead of leaving them running. Your own sessions get them
from the plugin's `SessionStart` hook. Runs get them in the worktree's `CLAUDE.local.md`,
which every agent and subagent loads: nightshift writes it before each run, kept
out of git (in the clone's `info/exclude`), so a change applies from the next
run. Then come the repo's `instructions=` file, if it names one, which wins where
the two disagree; nightshift only reads it. A repo that tracks its own
`CLAUDE.local.md` keeps it, without nightshift's instructions (`nightshift
doctor` flags it). Runs skip the clone's own
`CLAUDE.md`, `.claude/CLAUDE.md` and `CLAUDE.local.md` (the worktree has its
branch's), so personal notes in the clone don't change them. What runs should
learn about a project belongs in its committed `CLAUDE.md`. A
`~/.nightshift/instructions.md` from an older version is ignored (`nightshift
doctor` notes it).

## Plugins

A repo's runs load nightshift's plugin and the ones its line names
(`plugins=`, see [Config](#config)), nothing else. The rest of what its runs
need is in the repo's own committed setup: the tools they may use in its
`.claude/settings.json`, and how to check and show a change (screenshots, a
recording) in its `CLAUDE.md` (or its `instructions=` file). Installing the
plugins and the tools they drive is up to each machine; the repo's `CLAUDE.md`
lists them, and `nightshift doctor` says which named plugins are missing.

A React Native repo that relied on [rn-agent](https://github.com/hvalec427/rn-agent)
being loaded in every run gets it back with:

- `plugins=rn-agent` on its line: `nightshift add me/app ~/dev/app plugins=rn-agent`.
- signalbox and boop allowed in its committed `.claude/settings.json`:

  ```json
  {
    "permissions": {
      "allow": ["Bash(signalbox *)", "Bash(boop *)"]
    }
  }
  ```

- In its `CLAUDE.md` (or `instructions=` file), how to show a change: e.g. run the app on its own
  simulator, take screenshots and a recording with boop into a git-excluded
  folder, and stop the app with `signalbox down --detached-only` when done.

## A dedicated machine

A Mac mini, or a macOS VM on Apple silicon (Tart, UTM): iOS simulators need macOS,
so a Linux VM only works for non-mobile repos. Set it up to stay logged in:
automatic login, `sudo pmset -a sleep 0`, and what your repos' tools need (for
iOS, Xcode), then the install above. For a
separate identity, log `gh` in as a second GitHub account (invite it to your repos;
in an organisation, an admin adds it).

## Finishing by hand

The plugin's `finish` skill works in any Claude Code session too: in a
`claude --worktree <name>` session, say **finish** and it commits, pushes, opens
the pull request (showing the change as the project's instructions say) and
removes the worktree.

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
comments, skills it invokes, `nightshift label`, commits, a pull request, a failure, or waiting to be
stopped. The fake `curl` answers the latest release and serves its `install.sh` and
a ref's tarball.
`scripts/test-service.sh` is the exception: it starts and stops a real
LaunchAgent, one of `com.nightshift.test.1` … `.8`, claimed for the run so suites
can run at once (skipped where there's no GUI session), and runs `install.sh` into
a throwaway `HOME`. `scripts/test-skills.sh` and
`scripts/test-review.sh` check the skills' wiring in the skill files themselves,
since the fake `claude` can't see a run invoke a skill; `test-skills.sh` also runs
the plugin's `SessionStart` hook.

A test is a few lines in a subshell, with the helpers in `scripts/test-lib.sh`:

```sh
(world                                       # a machine watching o/r
  gh_issue o/r 7 alice agent                 # alice labels issue 7
  runs_do 'comment plan; label "needs you"'  # what the run does
  poll                                       # nightshift once
  expect "a plan: needs you" "$(status_label 7)" "needs you")
```

## Credits

How nightshift asks, specs, tickets, tests and reviews (the plugin's `questions`, `plan`,
`build` and `review` skills) is adapted from
[Matt Pocock's skills](https://github.com/mattpocock/skills) (MIT): see
[plugin/THIRD_PARTY.md](plugin/THIRD_PARTY.md). They ship in the plugin, so a run
doesn't depend on which skills the machine has.
