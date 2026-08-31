# Beads

<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:1105d646 -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking - do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference

### Orchestrator: where a note goes

Agents surface things that outlive their own task - gaps, spec conflicts, cross-bead
hazards. Route each one to exactly ONE place. Do not write them into markdown files;
`IMPLEMENTATION_ORDER.md` was retired because a hand-maintained copy of the dependency
graph goes stale within the hour.

| The note. | Goes to |
|---|---|
| concerns one bead's implementation | that bead - `bd update <id> --append-notes` (never `--notes`, which replaces) |
| needs a human to decide | a NEW bead, `bd label add <id> human` |
| is a durable rule or convention | this file - permanent, never pruned |
| is cross-cutting **and** time-bound | the Implementation Notes bead (`bd list --label=meta`) |

**Human decisions get their own bead - never just a label on an implementation bead.**
`bd human respond <id>` adds a comment and CLOSES the bead, so labelling an implementation
bead would close the work along with the answer. File the decision separately, `bd dep add
<impl-bead> <decision-bead>` so the work is properly blocked, and state the concrete options
in the description - a decision bead that only asks "what should we do?" wastes the round trip.
Read the queue with `bd human list`.

**The Implementation Notes bead is not a log.** A note earns a place only if it is both
cross-cutting and time-bound (sequencing rationale, "why X moved ahead of Y", a live
same-file hazard across epics). Every note names the bead IDs it concerns and is deleted
when all of them close. Consult it before dispatching; prune it whenever you close an epic.
If it no longer fits on one screen, notes are being misrouted - re-apply the table above.

### Orchestrator: standing conventions

- **Tests are written by a different agent than the implementation** - always, no exception.
- **Every implementation bead is independently audited before merge**, by an agent that wrote
  neither the tests nor the code. Give the auditor the bead's specific attack surface, not a
  generic checklist.
- **Audit findings that are real but outside the audited bead's scope get their own bead** -
  never scope-crept into the bead under review.
- **Resolve cross-task design ambiguity before dispatch, and record it in the bead**, not only
  in the dispatch prompt - a prompt dies with the agent, a bead does not.
- **Serialize same-file edits with an explicit `bd dep`**; never dispatch two agents at one file.
- **Verify a reported hazard against the codebase before filing a bead on it.** An agent that
  reasons correctly about framework defaults can still be wrong about the project.
- **Close reasons are the post-implementation review** - say what was built, what the audit
  found, and what was deliberately left undone.

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/core-concepts/sync-concepts.md for details and anti-patterns.

<!-- END BEADS INTEGRATION -->
