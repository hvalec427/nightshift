# Working an issue

| You | nightshift |
|---|---|
| Open an issue, add the `agent` label (and a [type](#issue-types) label) | Reads it and the code, picks its [size](#sizes) and says so in its first comment; asks its questions in one comment (each with its recommended answer), or goes straight to the plan; a small issue it builds straight away, with no plan, and says so: reply **full process** for a plan instead |
| Reply | More questions, or a plan: the spec and its tickets, in the to-spec and to-tickets format of [Matt Pocock's skills](https://github.com/mattpocock/skills). A plan with no open choices (nothing it decided that the issue and your answers didn't) says so and goes on to the build without waiting for **go**; comment to stop or change it |
| Reply **small**, **medium** or **large** before the build starts | Switches the size, and rewrites a plan already posted for it |
| Reply **go** (or what to change) | Builds the tickets in order, each in a subagent of its own (so one ticket's work doesn't crowd the next; a one-ticket plan is built directly), with no comment on the issue meanwhile; has two fresh subagents review the change against the plan and the repo's standards (a small change, one cheaper reviewer for both), and fixes what they found in one pass; then opens the pull request, which closes the issue, and links it, with what the review found. A large plan makes its sub-issues instead (below) |
| Nothing (unless the repo's `.nightshift/config` has `auto_merge=false`) | Once the pull request is open or updated and its checks pass (it fixes a failing check itself first, twice at most), squash-merges it when nothing in it needs a decision; otherwise lists what does in a look comment (a review finding left open that the plan didn't settle, a decision the plan didn't cover, a security-relevant change, or you asked to see it first). The rest worth knowing (a wide blast radius, a new command, a CI change, …) goes in its `done` comment |
| Reply **merge** to a look comment | Checks it again (checks, conflicts, the pull requests it goes after) and merges it |
| Comment on the issue after that | Makes the change on the same branch and pushes it (and checks it for merging again) |
| Merge another pull request | Rebases and updates the ones it affects ([below](#pull-requests-that-overlap)) |
| Remove the label, add `invalid` or `wontfix`, or close the issue | Stops it; `nightshift status` says so and why |
| Add the label back, remove `invalid`/`wontfix`, or reopen it | Picks up the stopped run where it left off |
| Merge its pull request, or close the issue | It's done: a last comment says what its runs cost (dollars at API prices, tokens, time) and the pull request's size (`PR +412 −37 in 9 files`), and, unless `.nightshift/config` has `cost_breakdown=false`, the dollars of each model and every agent that ran in a table (`cost_comment=false` leaves the comment out): a row a run (`plan run`), in the order they ran, with the subagents it started under it; each row's model, effort, skills, tokens (a subagent's: those of its turns), cost, time and tool calls; a subagent's cost is an estimate (`~$0.30`: the tokens of its turns at its model's average rate in that run, `–` when unknown) and a run's row is the rest of the run's cost, so the rows add up to the total row (unless the estimates overshoot the run's cost). Under it, the time from the first run to the last: how much the agent worked, how long it waited on you, and other waits (queued, an update); `nightshift status` leaves it out, and its state and branch are cleaned up |

## Working from a project board

A repo whose `.nightshift/config` has `project=<a GitHub project's URL>` (see
[Config](config.md#config)) is worked from that board in place of the `agent` label. Each
poll reads the project's cards with one GraphQL query (`gh api graphql`, with the
`project` scope: `gh auth refresh -s project`). The project's `Status` field is its
columns, matched by name without regard to case:

| Column | nightshift |
|---|---|
| Backlog | nothing: the card is left alone |
| Ready | works the issue: a first run asks its questions or posts the plan |
| Needs you | works it too: it waits on your reply before a pull request (questions, a plan waiting for its go, an answer, blocked) |
| In progress, In review, Your review, Ready to merge | works it too |
| Done | nothing |

Only issues of the repo count: its cards in a column other than Backlog and Done, open.
An issue of the repo that isn't on the board, or is in Backlog or Done, is off, as if its
label were removed: a run in flight stops (`nightshift status` says `moved to Backlog`),
and moving the card back to a working column picks it up where it left off. An issue
labelled `agent` that isn't on the board is ignored. Everything else works as for a
labelled issue: your comments (from `allowed_users`) are the news, `invalid` and `wontfix`
hold it, and the status labels follow the runs. A card in a working column starts work
without the label check: only people who can write to the project can move cards.
Cards of other repos and pull requests are skipped.

A draft card has no issue to talk in. One in Ready is turned into an issue of the repo
(titled as the draft, the card kept in Ready) and then worked like any card; a draft in any
other column is left alone. When several repos in `~/.nightshift/config` name the same
project, the first one listed turns its drafts into issues. A conversion that fails is
logged and tried again on the next poll.

Moving a card to In progress from any other column (from Needs you, where a plan waits),
after nightshift has posted a plan, approves it: the build starts in a fresh session as it
does for a **go**, its approval the line `- the board: moved to In progress`. A card
already in In progress when the plan posts doesn't approve it: reply **go**, or move the
card out of In progress and back. A **go** reply approves as before and nightshift moves
the card to In progress for you (with no In progress column, it builds and logs that it
didn't move the card). The card moving without a plan waiting (questions still open) starts
nothing. A board repo never builds without one of these: `auto_merge` is ignored, a plan
never carries on by itself, nothing counts as a small issue, and nothing merges outside the
card being in Ready to merge or a **merge** reply.

The card then follows the work, one move (a GraphQL mutation) each, only when it changes:

| When | The card goes to |
|---|---|
| A run starts on a card in Needs you (your reply, or the card moved to Ready) | Ready |
| A run ends needing you before a pull request (questions, a plan waiting for its go, an answer, blocked) | Needs you, from Ready |
| A build hands off, or a **go** approves; the build, tdd or update skill starts | In progress |
| The review, finish or merge skill starts | In review |
| Your comment starts a run on a card in Ready to merge | Your review, then In progress as the run starts |
| A run starts on a card in Your review (a change request or an update) | In progress |
| A run ends with its pull request open or needing you (a `look`, a `blocked`) | Your review |
| A merge run ends needing you | Your review, from Ready to merge |
| Its pull request merges | Done |

So a comment on a card in Your review moves it to In progress, and the run ending puts it in
Your review again; a reply on a card in Needs you moves it to Ready while the run works, and
the run ending still waiting on you (before a pull request) puts it back. A card only moves forward along
Backlog, Ready, Needs you, In progress, In review, Your review, Ready to merge, Done; where
you've already moved it past a column, nightshift leaves it. The ways back are Needs you to
Ready, Your review to In progress, and Ready to merge to Your review. Each move is decided on
the board as it is then (read again just before), not as the last poll read it, so a card you moved a moment ago isn't overwritten. A column the project lacks means no move,
and a line in the log (`nightshift logs`) says which.

`nightshift doctor` checks each board repo: that `gh` has the `project` scope (it names the fix,
`gh auth refresh -s project`), that the project and its Status field can be read, and which of
the eight columns the project lacks (you add them, Needs you too; nightshift doesn't). A `project=` that isn't
a project's URL is reported too.

Nothing merges until you move a card to Ready to merge (or reply **merge**). With a pull
request open, a run on a board repo still checks it, fixes the failing checks and posts its
`look` comment (even with nothing to look at), but doesn't merge. Moving the card to Ready to
merge then starts a run whose news is `- the board: the card is in Ready to merge`: the
merge skill takes it as your **merge** reply, runs its hard gates again (rebasing if the
default branch moved) and merges, and the merged pull request puts the card in Done. Other
runs nightshift starts on a card in Ready to merge with a pull request (an update, a resumed
run) carry that news too, so they merge. Your comment on such a card doesn't: it may ask for
a change, so its run gets no merge news and the card goes back to Your review, like any
change request (even when you moved the card there in the same poll). To merge it then, move
the card to Ready to merge again or reply **merge**. A merge run that ends needing you (a gate
failed, or something needs a decision) puts the card back in Your review, and its `look`
comment says why; one that ends waiting (for the pull request it goes after, say) leaves the
card in Ready to merge. If you move the card there while a run works, the run's end leaves it
and the next poll starts the merge run. A card that was in Ready to merge before nightshift
saw it starts no merge by itself, and a card moved there with no pull request yet starts
none until a run ends with one open.

A card with open blockers (GitHub's "blocked by") is held at any stage, not only before its
first run: it starts no run, labelled `nightshift: waiting`, until they close. What you do
meanwhile is kept: your comments, a move to In progress with a plan waiting, a move to Ready
to merge with a pull request open. The first poll after the last blocker closes starts the
run with all of it. A card with nothing to run when it's released goes back to the status it
had (`PR open`, `needs you`). A blocker added while a run is going doesn't stop it; the card
is held once the run ends.

`nightshift status` names what a held card waits for: `waiting · after #5, owner/repo#3`, or
`PR <url> · waiting · after #5` when it has a pull request open. The line goes when the last
blocker closes.

## Sessions and worktrees

Each issue gets its own worktree (in the repo's clone, `.claude/worktrees/issue-<n>`,
branch `nightshift/issue-<n>`) and a Claude session that its runs continue. When
you approve the plan (or it carries on, with no open choices), the build starts in a fresh one, given the issue, the plan, the
comments since the plan and your approval, so it doesn't carry (and pay for) the
planning conversation: a reply of just **go** starts it straight away, and any other approval once the planning
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

## Skills

Each run starts in the plugin's `issue` skill, which reads the thread and hands the
stage to a skill of its own: `questions`, `plan`, `build` (then `review`,
`finish` and `merge`), `update` (then `merge`), or `answer` for question and
duplicate issues. Invoking a skill loads all of its guidance, so no stage runs without it. The status label follows the skill, `nightshift logs`
shows each one a run invokes, and each comment names the skill that wrote it
(`🤖 nightshift · plan · nightshift:plan`).

## Sizes

nightshift picks a size on the first run and names it, with why, in that run's comment:

- **small**: about 20 lines in a file or two, nothing to decide, no new command or option,
  no breaking change, nothing touching CI, releases, installing or security. Built straight
  from the issue, with no plan and **go**, and reviewed by one quick reviewer.
- **medium**: everything else. The table above: questions if there are any, a plan, **go**
  (or none, when the plan has no open choices), one pull request, two reviewers.
- **large**: it touches many areas, adds several features, or changes how things work.
  It always asks its questions first, and its plan is split into **sub-issues**, each a few
  tickets, naming the sub-issues it's blocked by. The plan always waits for **go**, never
  carrying on. On **go**, nightshift creates the sub-issues (`nightshift sub-issue`, labelled
  `agent` and with the parent's type), builds nothing on the parent and opens no pull
  request for it, and posts one comment listing them. Each sub-issue is then built from its
  body, with no questions, plan or **go** (your **go** on the parent covers them), reviewed
  and merged as its own pull request. One with no open blockers starts right away, in
  parallel with the others; one with open blockers waits (`nightshift: waiting`) until they
  close. The parent shows `waiting` and closes after the last merge (below).

Reply **small**, **medium** or **large** to change the size before the build starts.

## Issue types

Give an issue its type with one of GitHub's default labels, next to `agent`;
nightshift reads it at the start of every run and works the issue the way it
calls for:

| Label | nightshift |
|---|---|
| `bug` | finds the cause with a check that fails the way the bug does (or asks, when it can't build one), and its plan starts with a test that fails the way the bug does; the fix makes it pass; a small one whose cause is plain is fixed straight away; a large one asks first, then finds the cause, then plans |
| `enhancement` | asks, plans, builds and opens a pull request, as above; a small one is built straight away |
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
| `nightshift: needs you` | waiting on your reply: questions, an answer, a plan, blocked, a pull request to look at before it merges, a failed run, or one that stalled twice. It comes off as soon as the watcher sees your reply |
| `nightshift: PR open` | the pull request is open, nothing running |
| `nightshift: waiting` | a sub-issue blocked by issues that are still open: held until they close, then its first run starts (a board card is held at any stage); or a parent whose sub-issues are not all done |
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

An issue with open blockers (GitHub's "blocked by", as `nightshift sub-issue` sets) that hasn't had
its first run is held the same way, labelled `nightshift: waiting`: the watcher checks it every
poll and starts it once its blockers are closed. One already worked on isn't held, unless its repo
works from a [project board](#working-from-a-project-board), where a card is held at any stage.

A parent (an issue whose run made sub-issues) is `waiting` until they're all done. Each time a
sub-issue's pull request merges, the watcher comments `#161 merged (2 of 4)` on the parent, once;
when the last one has, it closes the parent, which retires as "issue closed" with one cost comment
that totals the parent and every sub-issue, a line each (and, unless `cost_breakdown=false`, the
dollars of each model, summed). A sub-issue closed without merging leaves the parent open for you.

nightshift's comments start with **🤖 nightshift** and carry a hidden `<!-- nightshift -->`
marker, which is how it tells them from yours: it runs as your GitHub account, so
on GitHub they're yours. It only acts on the label when you added it, and only on
comments from you (`allowed_users` in [Config](config.md#config)).

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
conflicts with its base branch (the default branch, or `base_branch`; after any merge,
nightshift's or not), or that goes after or overlaps the nightshift pull request that
just merged, gets a run (its issue gets no comment until the run's own). That run
rebases it onto its base branch, fixes the conflicts, and updates the change to fit what merged, not just to
apply. It runs the checks again, force-pushes (`--force-with-lease`), and says what changed beyond the
conflict fixes. A conflict that needs your decision gets a question on the issue
instead. Meanwhile `status` shows `conflicts, rebasing` or `updating after #10`. So
the pull requests can be merged in any order. With auto-merge on, a pull request
that goes after another waits for it, then merges after that update run. When open
pull requests go after each other in a loop, so none could merge first, the lowest
issue's goes first: its run turns its after markers on the loop into overlaps
markers, merges, and says so on its issue; the others update on top of it.

## Finishing by hand

The plugin's `finish` skill works in any Claude Code session too: in a
`claude --worktree <name>` session, say **finish** and it commits, pushes, opens
the pull request (showing the change as the project's instructions say) and
removes the worktree.
