# Questions

Adapted from Matt Pocock's `grilling` skill (see `THIRD_PARTY.md` in the plugin), for an
issue: every round is one `questions` comment, and the user's reply ends the run's wait.

Map the issue as a **design tree**: every decision branches into the decisions that hang
off it. The **frontier** is every decision whose prerequisites are already settled: the
questions you can ask now without guessing at answers you haven't heard yet.

- **One round per comment.** Ask the whole frontier in one `questions` comment. A question
  whose answer depends on another question still open in this round belongs to a later
  round.
- **Numbered, each with a recommendation.** Word each question so "yes" accepts your
  recommended answer, and give lettered options where there are several, so the user can
  reply "1 yes, 2 b". Say what each option costs, in the same line.
- **Short.** No intro or restated issue: straight to question 1. One line per question or
  option; a fact goes in only when the answer turns on it.
- **Facts are yours, decisions are the user's.** Look up anything the code, the tools or
  the docs can tell you (dispatch a sub-agent for a wide search) and put what the answer
  needs in the question; never ask the user for a fact. Ask only the decisions that change what gets
  built (behaviour, scope, UX, trade-offs).
- **Settle the rest.** After the questions, say what you decided yourself, so the user
  can overrule it in the same reply: the three that matter most, a line each, and any
  others in a collapsed `<details>` block.
- **Next round.** Each reply reshapes the tree: recompute the frontier, and ask the next
  round only if it's not empty. When it is, nothing is left silently assumed: write the
  plan.

```
1. **<decision>?** I recommend **a**.
   - a. <option>: <what it costs>.
   - b. <option>: <what it costs>.
2. **<decision>?** <recommendation>. Yes?

Settled myself: <decision>; <decision>.

Reply e.g. "1 a, 2 yes".
```
