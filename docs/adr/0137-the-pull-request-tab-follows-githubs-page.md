# 0137. The Pull request tab follows GitHub's page

Status: accepted, 2026-11-20.

## Context
The Pull request tab had a layout of its own: a head with whose move it was ("Your move. 5 things block the merge…"), four status lights (Checks, Review, Threads, Branch), a To do list of what blocked the merge with a solid Send on each row, then Activity, Checks and Files as sections. It said the same thing three times (the sentence, the lights, the list), its blue Send buttons competed with the merge button, and people who live on github.com had to learn a second map of the same page. GitHub's current pull request page puts all of that in one merge status box with Checks, Comments and Approvals, the conversation under it, and the people and labels in a side column.

## Decision
The Pull request tab (and the GitHub view's pull request, the same pane) follows GitHub's current page, in Nushi's skin (issue #104):

- A slim bar (`#n`, the title, Merge status, Submit review), the head (title, state, who opened it, base ← head, size) and the tabs Overview, Commits, Checks, Files changed.
- Overview: the merge status card (state, one line of what blocks it, the merge button, a quiet Send N to agent; Checks, Comments and Approvals segments, each a bar, one list open at a time), the description, Comments (each review holding its threads by review id; All, Unresolved, Mine), the commit trail; a side column of reviewers, assignees, labels and participants.
- The To do card, the status lights, the "Your move" line and the per-row solid Send buttons go; what they said lives in the card and its segments. Send N to agent sends the same reply cards To do did.
- What GitHub's page also has but Nushi doesn't do yet stays out: editing the title or description, reactions, edit history, changing reviewers, assignees or labels, the activity timeline, avatar images.

## Consequences
- One map: what someone knows from github.com finds its place here, and the merge button is the page's one primary.
- The page needs a pull request's labels, assignees, every review, each thread's review id and hunk, and its commits (API 127). Commits are asked when they show and when the head moves, not with each poll.
- What blocks the merge is one click further (a segment's list) than To do's always-open rows; Send N to agent and Merge status keep it a click away.

## Amendments
- 2026-11-20: Comments start with the comment box, under the heading and its filter, then the reviews and comments newest first (a thread's replies still oldest first), as GitHub's page has them; one just posted lands right under the box.
