# Beads

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

### Nuances when using beads

Never reconstruct a bead field through an inline command substitution. Keep the source text on
disk and rebuild the whole field from files, then verify:

```bash
cat original-design.txt append.txt > full-design.txt
bd update <id> --design-file full-design.txt          # or --design="$(cat full-design.txt)"
bd show <id> | grep -c "^  D[1-9] --"                 # assert the expected section count
```

`--body-file` and `--design-file` are the better channel for long text regardless — it avoids 
shell quoting entirely.

The only exception to this is the `notes` field. The `--append-notes` command appends the 
given text to the `notes` field. You **MUST** use `--append-notes` and not `--notes`. 
The `--notes` command will *overwrite* the contents of the `notes` field in a bead.

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

## Overriding beads

A project's `CLAUDE.md` may switch issue tracking off for its repo — intended for throw-away
projects, experiments and one-shots where filing a bead per task costs more than it returns. It
does so by saying so plainly, e.g.:

> This project does not use an issue tracker. Do not create beads; report work in conversation.

With tracking off:

* **Do not create beads, and do not substitute a shadow tracker** — no `TodoWrite`, no
  `tasks/todo.md`, no markdown checklist. If the project names a replacement, use that one and
  nothing else. If it names none, the conversation is the record.
* **Commit scope becomes `NOTICKET`** (`~/.claude/CLAUDE-CONVENTIONAL-COMMITS.md`), and branch
  names drop the issue ID: `<type>/<short-slug>`.
* **Unfinished work is reported to the user before the task ends**, named specifically enough to
  act on. The ban on silent TODOs is not lifted — only its destination changes. A `TODO` left in
  code with no bead and no report is still exactly the failure that rule exists to prevent.

### What this override does not lift

**Tests are written by a different agent than the implementation, and every implementation is
independently audited before merge.** Those hold in every repo, always. No project file relaxes
them.

They consume artifacts the bead normally carries, so with tracking off those move — they do not
disappear:

* The coding agent's work description and its `artifacts` JSON block go in the **commit message
  body**, same schema as the close-reason block (`~/.claude/CLAUDE-CODE-FLOW.md`). The auditor
  reads it there. Correcting it after audit is an amend on the task branch, which is pre-merge and
  therefore safe.
* The post-implementation review that would have been the close reason goes to the orchestrator in
  the agent's final report, and from the orchestrator to the user.
* **The session-close integrity check degrades and you must cover for it.** It walks close-reasons;
  there are none. Run the equivalent by hand over the session's commits — grep each `artifacts`
  entry's symbols against the repo — and report anything missing.
