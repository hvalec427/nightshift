# Config

`~/.nightshift/config`, whose `repo` lines `nightshift add` writes:

```
repo hvalec427/nightshift /Users/me/dev/nightshift
repo me/app /Users/me/dev/app
repo hvalec427/other /Users/me/dev/other
allowed_users=hvalec427
max_parallel=2
interval=5
```

- `repo <owner/repo> <clone path> [key=value …]`: a watched repo and its clone
  (spaces in the path are fine, but its last word can't look like `key=value`:
  it would read as an option). `instructions=`, `auto_merge=` and `plugins=` on a
  repo line are ignored now, and `doctor` says where they go: the repo's
  `.nightshift/instructions/` folder, or its `.nightshift/config`.
- `<repo>/.nightshift/config`, committed to the repo's **default branch**
  (`key=value` lines, `#` comments; the last value of a key wins). nightshift
  reads it from origin's copy of that branch, fetched before each run, so a
  branch or pull request can't change its own settings: a change applies once
  it's merged. `status` and `doctor` use the last fetch. Without the file or a
  key, the defaults apply.
  - `auto_merge=false` makes its pull requests wait for you to merge; without
    it, nightshift merges them on its own. An `auto_merge=false` left on a
    repo line from an older version is ignored, so that repo merges on its own
    after an upgrade until the file has it (`doctor` notes it). `status` and
    `doctor` say which repos have it off.
  - `plugins`: the Claude Code plugins its runs load, comma-separated:
    `plugins=web-tools,other@marketplace`. A name matches that plugin from any
    marketplace; `name@marketplace`, that one. Each must be installed and
    enabled (`claude plugin install …`); one that isn't, the run goes without,
    and its log says so. Without `plugins=`, runs get only nightshift's plugin.
  - `full_suite` says where the whole test suite runs: `local` runs it before each
    push, `nothing` never has nightshift run it. Unset (or any other value), the
    default: CI runs it, and a run runs it itself only in a repo with no CI checks on
    its pull requests. Every run's prompt carries the setting.
  - `test_command`: the command that runs the whole test suite (`test_command=npm test`).
    Where a run may run the suite, its prompt names the command; unset, the run works it
    out from the repo's instructions.
  - `project`: a GitHub project (v2) board, `project=https://github.com/users/me/projects/5`
    (an organisation's is `…/orgs/acme/projects/5`; a trailing `/views/2` is ignored).
    The repo is then worked from the board, not the `agent` label: see
    [Working from a project board](working-an-issue.md#working-from-a-project-board);
    a draft card in Ready becomes an issue of the repo there, and `auto_merge` is ignored.
    `gh` needs the `project` scope (`gh auth refresh -s project`), and the project's Status
    field its eight columns; `nightshift doctor` checks both and names what is missing. Unset,
    nothing changes.
  - `base_branch=develop` is the branch its pull requests merge into, when that isn't the
    default branch. A new issue's branch starts from `origin/develop`, its pull request opens
    against it, and the review and merge compare against it. Unset, the default branch.
    `base_branch` is read from the default branch like the other keys, so a change applies
    once it's merged there. A branch that isn't on origin is ignored: runs use the default
    branch and the issue's log says so. GitHub closes an issue by `Closes #n` only on a merge
    into the default branch, so nightshift closes the issue itself after it merges.
  - `cost_breakdown=false` keeps the closing cost comment to one line: dollars, tokens,
    time and the pull request's size. Unset (or any other value), it has the breakdown
    too: the dollars of each model, the agents table and the time line.
  - `all_issues=true` works every issue an allowed user opens from then on, with or
    without the `agent` label, so the repo needs no `agent` label (`add` doesn't
    create it, `doctor` doesn't ask for it). Only issues opened at or after the
    moment nightshift first read the option on count (the *all-issues on-time*,
    kept in `~/.nightshift/all_issues/`, dropped when the option is read off): the
    backlog is left alone. A stranger's issue still needs `agent` from an allowed
    user, and closing an issue or adding `wontfix`/`invalid` stops it as usual.
    Only the newest 100 open issues are looked at, and the watcher fetches the
    clone between runs to read the option. Unset or any other value, off.
  - `cost_comment=false` posts no closing cost comment at all (`nightshift status`
    still shows what a done issue spent).
- `allowed_users`: whose labels and comments count (default: your gh account).
- `max_parallel`: issues worked at once (each may run its app).
- `interval`: seconds between polls (default 5). A poll that finds nothing new
  costs no rate limit: the issues list is asked with the ETag of its last
  answer, and GitHub's `304 Not Modified` doesn't count. The pull requests are
  checked every 30 s at most.
- `auto_update`: the watch installs each new release itself (default `true`;
  `false` turns it off, `install.sh --auto-update` sets `true`). It checks for
  one once an hour.
  A new release never holds a run back: issues keep starting. After a poll that
  leaves no run in flight, it runs the release's `install.sh` and restarts on
  the new version (a busy machine updates late). A failed update is logged
  (what went wrong is in `~/.nightshift/update.log`), and it stays on its version
  until the next check. Only a release install updates itself, not `--master` or
  a clone's.

## Permissions and isolation

Runs use Claude Code's `auto` permission mode. Commands that reach GitHub (`gh`,
`git`) are always allowed; what else a repo's runs may do goes in its committed
`.claude/settings.json`. Runs are isolated from the
machine's own user-level setup, so every machine works an issue the same way: no
skills from `~/.claude/skills`, no `~/.claude/settings.json`,
`~/.claude/CLAUDE.md`, plugins, hooks or MCP servers of yours. A run loads the
repo's own `.claude` setup, nightshift's plugin (its copy in
`~/.nightshift/plugin`, which the install keeps up to date) and the plugins
its `.nightshift/config` names; commits and pull requests get no Claude attribution.
Runs can't use `pkill` or `killall`: a name pattern matches other runs
too, so they stop a background task by its PID.
`isolated=` and `permission_mode=` lines from older versions are ignored
(`nightshift doctor` notes them).

## Instructions

Every run and every Claude session of yours where the nightshift plugin is
enabled get nightshift's default instructions:
[`plugin/instructions.md`](../plugin/instructions.md) (installed at
`~/.nightshift/plugin/instructions.md`): its rules for commit messages and pull
requests, Conventional Commits and no AI attribution included, for keeping a
project's `CLAUDE.md` small and true, and that a run ends when the agent stops, so
it waits for its checks instead of leaving them running. Your own sessions get them
from the plugin's `SessionStart` hook. Runs get them in the worktree's `CLAUDE.local.md`,
which every agent and subagent loads: nightshift writes it before each run, kept
out of git (in the clone's `info/exclude`), so a change applies from the next
run. Then come the repo's own: every `.md` in the worktree's `.nightshift/instructions/`
(the branch's copy, committed), in name order, under a "This project's instructions"
heading, which win where they disagree with nightshift's. Split them by topic as you
like; none there, and runs get nightshift's alone. An `instructions=` file on a repo
line from an older version is ignored: copy it into that folder (`nightshift doctor`
notes it). A repo that tracks its own
`CLAUDE.local.md` keeps it, without nightshift's instructions (`nightshift
doctor` flags it). Runs skip the clone's own
`CLAUDE.md`, `.claude/CLAUDE.md` and `CLAUDE.local.md` (the worktree has its
branch's), so personal notes in the clone don't change them. What runs should
learn about a project belongs in its committed `CLAUDE.md`. A
`~/.nightshift/instructions.md` from an older version is ignored (`nightshift
doctor` notes it).

## Plugins

A repo's runs load nightshift's plugin and the ones its `.nightshift/config` names
(`plugins=`, see [Config](#config)), nothing else. The rest of what its runs
need is in the repo's own committed setup: the tools they may use in its
`.claude/settings.json`, and how to check and show a change (screenshots, a
recording) in its `CLAUDE.md` (or its `.nightshift/instructions/`). Installing the
plugins and the tools they drive is up to each machine; the repo's `CLAUDE.md`
lists them, and `nightshift doctor` says which named plugins are missing.

A React Native repo that relied on [rn-agent](https://github.com/hvalec427/rn-agent)
being loaded in every run gets it back with:

- `plugins=rn-agent` in its `.nightshift/config`, committed to its default branch.
- signalbox and boop allowed in its committed `.claude/settings.json`:

  ```json
  {
    "permissions": {
      "allow": ["Bash(signalbox *)", "Bash(boop *)"]
    }
  }
  ```

- In its `CLAUDE.md` (or `.nightshift/instructions/`), how to show a change: e.g. run the app on its own
  simulator, take screenshots and a recording with boop into a git-excluded
  folder, and stop the app with `signalbox down --detached-only` when done.

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
| Quick reviewer (agent `quick-review`, a small change's only reviewer) | sonnet | medium |
| `answer`, `finish` | sonnet | medium |

Each run's line in `nightshift logs` shows the models it used, the main one first.
