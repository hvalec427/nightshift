---
name: finish
description: Finish this task: commit, push, open a pull request (showing the change as the project's instructions say), then clean up. Use when the user says finish, ship it, or asks for a PR for the work in this worktree, and when the build skill has built its last ticket.
allowed-tools: Bash(git status *) Bash(git diff *) Bash(git log *) Bash(git add *) Bash(git commit *) Bash(git push *) Bash(git rev-parse *) Bash(git worktree *) Bash(gh pr *) Bash(gh repo view *) Bash(cp *) Bash(mkdir *)
user-invocable: false
model: sonnet
effort: medium
---

# Finish

Ship the work in this worktree as a pull request, then clean up. Each step ends on its
own check; stop and say so at the first one that fails, leaving everything in place.

1. **Ready.** The change was seen working, or what couldn't be verified is known, to go in
   the description. Done when you can say which.
2. **Show it,** only when the project's instructions (its `CLAUDE.md`, rules, skills or
   nightshift instructions) say how to show a change: follow them, so a reviewer sees the
   change without running it (screenshots, a recording, as they say). Keep the media out
   of the commit: under a git-ignored or git-excluded path. No such instructions, or
   nothing to show: skip it. Done when each file they ask for is made, or there's nothing to show.
3. **Commit.** `git status` shows what's left: commit it in the repo's style and the
   user's commit conventions; the media stay out. Done when `git status --porcelain`
   prints nothing.
4. **Push.** `git push -u origin HEAD`. Done when it succeeds.
5. **Pull request.** `gh pr create` against the repo's default branch
   (`gh repo view --json defaultBranchRef -q .defaultBranchRef.name`), following the user's
   PR conventions. The title says the change; the body follows [The body](#the-body). Place
   each media file where it belongs in the body by its path
   (`![Price list](<path>/price-list.jpg)`) and pass each with `--attach <path>`: gh uploads
   them and swaps in their URLs, so they show inline and videos play. Under nightshift the
   body ends with a closing line per issue, one on each line: `Closes #<issue>` for the
   issue the run works, and `Closes #<sub>` for each sub-issue number the build passes, so
   the merge closes them all. An existing PR for this branch (`gh pr view`) gets the push,
   and new media through `gh pr edit --body … --attach …`. With gh older than 2.99 (no
   `--attach`), open it without the media and say `brew upgrade gh`. Done when you have
   its URL.
6. **Clean up.** Stop what this run started (an app, a simulator, a server), as the
   project's instructions say.
   - **Under nightshift** (started on an issue), stop here: the watcher removes the
     worktree after the run. When the run prompt says "This repo auto-merges", the build
     skill hands the pull request to the merge skill after its `done` comment, so the
     review it reports is there to read; you don't merge.
   - **In an interactive `claude --worktree` session,** remove the worktree from the main
     checkout, keeping the branch: `git -C <main checkout> worktree remove --force <this
     worktree>`, where the main checkout is `git rev-parse --path-format=absolute
     --git-common-dir` without its trailing `/.git`. Done when `git -C <main checkout>
     worktree list` no longer lists it.
7. **Hand back.** The PR's URL, and (interactive) that the worktree is gone, the branch
   stays until the PR is merged, and this session is finished.

## The body

Adapted from Matt Pocock's `pr` skill (see `THIRD_PARTY.md` in the plugin). It starts at
the first heading, with no preamble, and keeps prose brief. It uses the project's own
words for things. It is for a reviewer who has the diff open, so it shows the change's
shape, how you know it works, and how risky it is to land.

```markdown
## Summary

<the smallest visual that shows the change>

## Evidence

- **Before:** <screenshot, output or failing test run>
  **After:** <screenshot, output or passing test run>

## Merge Danger

**Door:** <one-way or two-way>

**Blast radius:** <narrow or wide>

<optional: what could break if the change is wrong>
```

- **Summary.** The smallest view that makes the key point: pseudocode for logic, a call
  tree for control flow, a file tree for a broad refactor, or a diff sketch when the
  surrounding shape already exists. One visual, sometimes two, with the short text it
  supports beside it. Keep only the calls, files and boundaries a reviewer needs.
- **Evidence.** A before and an after. A screenshot or recording when the change is visual
  (the media from step 2 go here). Otherwise the exact test that failed and now passes, as
  pseudocode, or the output that changed. "Tests are green" alone is a claim, not a before
  and after. What couldn't be verified goes here too, said plainly.
- **Merge Danger.** State the call, so the reviewer can disagree with it; you graded your
  own change, so doubt "two-way, narrow" most.
  - **Door.** Two-way when it's cheap to reverse. One-way when it destroys something or
    can't be walked back: a migration, a removed public interface, data written in a new
    format.
  - **Blast radius,** in one word. Wide when the change reaches past its feature: config,
    the repo's persisted state or data layout, an installer, a CLI's commands or flags, or
    what a run can reach. Narrow otherwise.

Under nightshift the body also carries, from the build:
- the open review findings, a line each, under **Left open:** at the end of Merge Danger;
- the overlap lines, kept as written with their markers (`<!-- nightshift:after #N -->`,
  `<!-- nightshift:overlaps #N -->`), after Merge Danger;
- the closing `Closes` lines of step 5, last.

Outside nightshift the body has no `Closes` line unless the user names an issue to close,
and no overlap lines or review findings. Only the three sections remain.
