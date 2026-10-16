---
name: answer
description: Answer a question issue, or find the issue a duplicate one repeats, in an answer comment, with no plan and no pull request. Started by the issue skill for issues labelled question or duplicate.
user-invocable: false
model: sonnet
effort: medium
---

# Answer an issue

The issue skill sent you here, and its rules (comments, the status label, the issue's type,
bounds) hold throughout. No plan, no branch, no commits: one `answer` comment, then end the
run.

- **`question`**: answer it, from the code and the docs. Say where the answer comes from
  (files, commands you ran). The user's reply is a follow-up (another `answer`), or asks
  for a change: then swap the label to `bug` or `enhancement` and go back to the issue
  skill's steps from the top.
- **`duplicate`**: find the issue it duplicates (`gh issue list --state all --search …`)
  and post an `answer` linking it and saying how the two match. Found none: say so, swap
  the label for the type it is, and go back to the issue skill's steps as that type.
