---
name: finish
description: Finish this task: commit, push, open a pull request (with screenshots and a recording when the app is running here), then clean up. Use when the user says finish, ship it, or asks for a PR for the work in this worktree, and when the build skill has built its last ticket.
allowed-tools: Bash(git status *) Bash(git diff *) Bash(git log *) Bash(git add *) Bash(git commit *) Bash(git push *) Bash(git rev-parse *) Bash(git worktree *) Bash(gh pr *) Bash(gh repo view *) Bash(signalbox *) Bash(boop *) Bash(cp *) Bash(mkdir *)
user-invocable: false
---

# Finish

Ship the work in this worktree as a pull request, then clean up. Each step ends on its
own check; stop and say so at the first one that fails, leaving everything in place.

1. **Ready.** The change was seen working, or what couldn't be verified is known, to go in
   the description. Done when you can say which.
2. **Show it,** only when this checkout's app is running: `.signalbox/session.json` exists
   and `signalbox ctl status` answers (it fails when no session is running). A reviewer should see the change without running it:
   - every screen the change touched, in its final state: `boop screenshot -o
     .signalbox/media/<what-it-shows>.jpg`;
   - for a change you interact with (a flow, an animation, a form), a recording of you
     walking it: `boop record start`, walk the flow with boop at a pace a viewer can
     follow, then `boop record stop .signalbox/media/<what-it-shows>.mp4`. Keep it short:
     the one flow the change is about.

   No running app, or nothing visual: skip it. Done when each changed screen and flow has
   its file, or there's nothing to show.
3. **Commit.** `git status` shows what's left: commit it in the repo's style and the
   user's commit conventions. `.signalbox/` is git-excluded and stays out. Done when
   `git status --porcelain` prints nothing.
4. **Push.** `git push -u origin HEAD`. Done when it succeeds.
5. **Pull request.** `gh pr create` against the repo's default branch
   (`gh repo view --json defaultBranchRef -q .defaultBranchRef.name`), following the user's
   PR conventions. The title says the change; the body is a few lines: what changed (not
   a summary of the diff), how it was verified (screens seen, checks run), and anything
   left open. Place each media file
   where it belongs in the body by its path (`![Price list](.signalbox/media/price-list.jpg)`)
   and pass each with `--attach <path>`: gh uploads them and swaps in their URLs, so they
   show inline and videos play. An existing PR for this branch (`gh pr view`) gets the push,
   and new media through `gh pr edit --body … --attach …`. With gh older than 2.99 (no
   `--attach`), open it without the media and say `brew upgrade gh`. Done when you have
   its URL.
6. **Clean up.** If this checkout's app is running, stop it: `signalbox down
   --detached-only`, which deletes its simulator.
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
