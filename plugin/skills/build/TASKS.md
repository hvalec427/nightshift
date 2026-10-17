# Tasks

One `tasks` comment on the issue lists the tickets as a checklist, so the user can follow
the build in the thread. The tickets' text stays in the plan comment.

```
🤖 **nightshift** · tasks · `nightshift:build`

- [x] T1: <ticket title>
- [ ] T2: <ticket title>

<!-- nightshift --> <!-- nightshift:tasks -->
```

- **A line per ticket,** `- [ ] T1: <ticket title>`, in the plan's order, with the titles
  as the latest plan has them.
- **Reuse before posting.** Before the first ticket, find the latest comment carrying
  `<!-- nightshift:tasks -->` on its last line (`gh api
  repos/{owner}/{repo}/issues/<issue>/comments --paginate`, its `id` and `body`): a plan
  comment can quote the marker in its text, and isn't one. With none, post it with
  `gh issue comment`. With one, edit it to match the latest plan's tickets, keeping the
  ticks of the tickets already committed, so a resumed or fresh build leaves the issue one
  checklist with its state right.
- **Edit it by its comment id:** write the whole body to a file and
  `gh api -X PATCH repos/{owner}/{repo}/issues/comments/<id> -F body=@<file>`. Ticking a
  box is the same edit, with its `- [ ]` turned to `- [x]`.

Done when the issue has one `tasks` comment with a line per ticket of the latest plan.
Keep its id for the ticks.
