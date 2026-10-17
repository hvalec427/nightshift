---
name: answer
description: Answer a question issue, or find the issue a duplicate one repeats, in one answer comment. Started by the issue skill for issues labelled question or duplicate.
user-invocable: false
model: sonnet
effort: medium
---

# Answer an issue

The issue skill sent you here, and its rules (comments, the status label, the issue's type,
bounds) hold throughout. Your output is one `answer` comment, then the run ends: the issue
gets no plan, no branch and no commits.

- **`question`**: answer it from the code and the docs, and say where the answer comes from
  (files, commands you ran). Done when the answer comes first and each claim has its source.
  The user's reply is a follow-up (another `answer`), or asks for a change: then swap the
  label to `bug` or `enhancement` and go back to the issue skill's steps from the top.
- **`duplicate`**: find the issue it duplicates (`gh issue list --state all --search …`)
  and post an `answer` linking it and saying how the two match. Done when the link is in
  the comment. Found none: say so, swap the label for the type the issue is, and go back to
  the issue skill's steps as that type.
