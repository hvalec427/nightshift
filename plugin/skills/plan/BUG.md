# A bug's plan

On a `bug`, the `nightshift:diagnose` skill handed you the cause, the red check and the
ranked hypotheses; the plan shows all three.

- **On top:** the cause in a line or two, and the red check (the command that fails the way
  the bug does).
- **In the spec:** how the cause was proven; the minimised repro; the hypotheses ranked,
  each with its prediction and verdict (proven or ruled out), so the user can overrule the
  ranking; and any finding that no right seam exists to lock the bug down.
- **Tickets:** the first turns the minimised repro into a failing test at a seam that
  exercises the real bug path, and the fix makes it pass.

Done when the comment's top, its spec and its first ticket each carry their part.
