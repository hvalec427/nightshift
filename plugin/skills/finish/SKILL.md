---
name: finish
description: Finish this task: commit, push, open a pull request, then clean up. Use when the user says finish, ship it, or asks for a PR for the work in this worktree, and when the build skill has built its last ticket.
allowed-tools: Bash(git status *) Bash(git diff *) Bash(git log *) Bash(git add *) Bash(git commit *) Bash(git push *) Bash(git rev-parse *) Bash(git worktree *) Bash(gh pr *) Bash(gh repo view *) Bash(cp *) Bash(mkdir *)
user-invocable: false
model: sonnet
effort: medium
---

# Finish

Ship the work in this worktree as a pull request, then clean up. Each step ends on its
own check; at the first one that fails, stop, say so and leave everything in place.

1. **Ready.** Confirm the change was seen working, or list what couldn't be verified, for
   the description. Done when you can say which.
2. **Show it.** When the project's instructions (its `CLAUDE.md`, rules, skills or
   nightshift instructions) say how to show a change, follow them, so a reviewer sees the
   change without running it (screenshots, a recording, as they say). Keep the media out
   of the commit: under a git-ignored or git-excluded path. Without such instructions, or
   with nothing to show, go to step 3. Done when each file they ask for is made, or there's
   nothing to show.
3. **Commit.** `git status` shows what's left: commit it in the repo's style and the
   user's commit conventions, and leave the media out. Done when `git status --porcelain`
   prints nothing.
4. **Push.** `git push -u origin HEAD`. Done when it succeeds.
5. **Pull request.** `gh pr create` against the repo's default branch
   (`gh repo view --json defaultBranchRef -q .defaultBranchRef.name`), following the user's
   PR conventions. The title says the change; write the body by [BODY.md](BODY.md). Place
   each media file where it belongs in the body by its path
   (`![Price list](<path>/price-list.jpg)`) and pass each with `--attach <path>`: gh uploads
   them and swaps in their URLs, so they show inline and videos play. An existing PR for
   this branch (`gh pr view`) gets the push, and new media through
   `gh pr edit --body … --attach …`. With gh older than 2.99 (no `--attach`), open it
   without the media and say `brew upgrade gh`. Done when you have its URL.
6. **Clean up.** Stop what this run started (an app, a simulator, a server), as the
   project's instructions say.
   - **Under nightshift** (started on an issue), stop here: the watcher removes the
     worktree after the run. When the run prompt says "This repo auto-merges", the build
     skill hands the pull request to the merge skill after its `done` comment, so the
     review it reports is there to read; merging is the merge skill's.
   - **In an interactive `claude --worktree` session,** remove the worktree from the main
     checkout, keeping the branch: `git -C <main checkout> worktree remove --force <this
     worktree>`, where the main checkout is `git rev-parse --path-format=absolute
     --git-common-dir` without its trailing `/.git`. Done when `git -C <main checkout>
     worktree list` no longer lists it.
7. **Hand back.** The PR's URL, and (interactive) that the worktree is gone, the branch
   stays until the PR is merged, and this session is finished.
