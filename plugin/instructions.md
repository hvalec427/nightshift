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
