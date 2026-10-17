# Commit messages and pull requests

These apply in every repository, on top of the repo's own conventions.

- **Conventional Commits.** Every commit subject is `type(scope): description`, the scope
  optional: `feat(status): show how long a run waited`, `fix: keep the session of a stopped run`.
  - Types: `feat` (new behaviour), `fix` (a bug), `refactor`, `perf`, `test`, `docs`,
    `build`, `ci`, `chore`, `style`, `revert`.
  - The scope is the part of the project it touches (`status`, `logs`, `installer`), lowercase.
  - The description starts lowercase, in the imperative ("add", not "added"), with no full
    stop at the end.
  - A breaking change gets a `!` before the colon (`feat(config)!: rename max_parallel`) and
    a `BREAKING CHANGE:` line in the body saying what to change.
- **No AI attribution.** Never add `Co-Authored-By: Claude ...`, `🤖 Generated with [Claude
  Code]`, or any other line, trailer, emoji or footer saying Claude or an AI wrote it. The
  commit message contains nothing but the description of the change.
- **Keep it short.** The whole subject line under 72 characters, ideally under 50.
- **No body unless it's genuinely needed.** No bullet lists, "Changes:" sections or summaries
  of the diff; the diff already says that. A short body only to explain *why*, when that
  isn't obvious.
- **Pull requests** follow the same rules. The **title is a Conventional Commit subject**
  too, since pull requests are squash-merged and the title becomes the commit on the default
  branch. No AI attribution footer; brief descriptions.

# CLAUDE.md

A project's `CLAUDE.md` is read by every run, so keep it small and true. Most changes leave
it alone.

- **When.** Only when a change taught something future runs need and won't find on their own.
- **What.** Durable, non-obvious facts: a gotcha, a convention, why something is the way it
  is. Never what the code or the diff already shows.
- **How.** Edit or replace the line that covers it rather than append a new one, and delete
  what's no longer true.
- **Where.** Keep the root `CLAUDE.md` a short map, under about 200 lines. Knowledge about one
  area goes in a `CLAUDE.md` in that directory, loaded only when a run works there; decisions
  and their reasons go in `docs/adr/`.

# CONTEXT.md

A project's `.nightshift/CONTEXT.md` is its glossary, and runs read it. A term your work
introduces, or finds used wrongly, gets its entry in `.nightshift/CONTEXT.md` in the same
pull request: the term and what it means here, in a line or two.

# Runs

When nightshift runs you on an issue, the run is one headless turn. A run ends when you
stop: nothing wakes you when a background task finishes, so whatever you left waiting
stays undone. Run checks (tests, builds, linters) in the foreground and wait for them,
even when they're slow. When one outlasts the tool's timeout and moves to the background,
wait on it in the same turn (a loop that polls its output until it ends). Never end a run
to wait for something.

Stop a background task by its PID or with TaskStop, never by a name pattern like
`pkill -f` or `killall`: a run's command line holds its prompt, so a pattern matches other
runs too.

Send git as one plain command per Bash call: no env prefix, pipe, `&&` or `;`. A run is
allowed `Bash(git *)`, which matches only a plain git command; anything around it goes to
the auto mode classifier, which can deny it. The editors are already off in a run
(`GIT_EDITOR` and `GIT_SEQUENCE_EDITOR` are `true`), so `git rebase --continue` and
`git commit` need no prefix. When a git step is denied anyway, retry it once as separate
plain git commands before you write a `blocked` comment.

Keep a check's logs and scratch files inside the worktree's ignored files or under
`$TMPDIR` (make them with a template, `mktemp "${TMPDIR:-/tmp}/x.XXXXXX"`: plain `mktemp`
ignores `TMPDIR` on macOS), remove them when you're done, and never leave loose files in
`/tmp`.
