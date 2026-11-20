# 0141. A workflow shows its plan

Status: accepted, 2026-11-20 (#96). Amends [0127](0127-claudes-workflows-show-in-the-chat.md) and [0139](0139-the-workflow-card-says-each-thing-once-and-opens-in-place.md).

## Context
A workflow's card and pane showed only the phases a run had reached (ADR 0127): while the first phase ran, nothing said how many came after it. Claude's script names them all up front, in its `export const meta` (`docs/facts/claude.md`); the snapshot repeats that list only once the run ended.

## Decision
- **The daemon reads the plan from the script**, once it's there: the first 256 KB of `workflows/scripts/<name>-<run>.js`, its `meta` literal read as plain data (strings, numbers, booleans, arrays, objects); a call, a spread or a template's `${}` in it is no meta, and the run shows as before. Nothing of the script is run. Its name and description fill in where nothing else gave them (a replayed call has no name).
- **Planned phases ride beside the reached ones**, as `Workflow.planned` (API 134): those the script plans and the run hasn't reached, in the script's order, titles and details only, with the reached ones 32 at most. `phases` keeps its meaning (reached, in order; the agent's own list at the end), so an older app is unchanged and a running agent's phase index still points into it. A phase leaves `planned` once an agent of it starts.
- **In the app** a planned phase is a line of its own after the reached ones, in the opened card and in the Workflow pane: an empty ring as its mark (a plan's step to come, ADR 0135), its title in the secondary text, and the word "planned" where a reached phase has its count. Once the run ended, a phase it never reached says "not reached", the same way; a phase of the snapshot's with no agents is one of those too, no longer a check mark.
- **The card's collapsed line stays as it was**: "Review 4/7" already says where it is, and a second fraction beside it ("phase 2 of 4") would make the busiest line longer for what the chevron shows.

## Consequences
A script whose meta is built by code shows no plan, only the phases reached. A phase reached under a title the meta doesn't list shows as reached and the planned one stays planned until the run ends.
