# Learnings

The `learnings` directory is a shared knowledge base of failures encountered while 
implementing a project, and how they were resolved. It exists so that the same error is never 
debugged twice.

## Protocol

**Before troubleshooting any error or failure**, search this directory first
(`grep -ril "<keyword>" learnings/`) to see whether the same problem — or one close enough to be
useful — has already been solved. If a matching entry exists, apply its fix (or explain in your
ticket update why it doesn't apply) before spending time re-deriving a solution.

**After resolving a novel failure**, add one Markdown file here documenting it. Use the filename
convention `<ticket-issue-id>-<short-slug>.md` (e.g. `or-13q.1.6-alembic-autocommit-block.md`) so
concurrent writers never collide on the same file. Do not delete another entry's file and only
modify an existing entry using these rules:
- If an existing entry is incomplete append a `## Update (<issue-id>)` section to it instead
  of rewriting it.
- If a section is materially incorrect, add a `> **Superseded:**` marker at the top of the 
  section with the corrected information, so a reader hitting the wrong text first is warned
  before they act on it.

Only record genuine failures — a command that needed an obvious flag, a typo, or a one-off is not
worth an entry. Record things a future agent would otherwise waste real time rediscovering:
environment quirks, tool version mismatches, non-obvious root causes, silent failure modes.

## Entry format

```markdown
# <short title>

**Issue:** <beads issue id>
**Date:** <date>

## What was happening

Brief context: what task/command was being attempted when this surfaced.

## Error

The exact error message / symptom observed (verbatim, trimmed to the relevant lines).

## Root cause

What actually caused it — not just "X failed" but *why*.

## Fix

The concrete change that resolved it (command, config, code). Include enough detail that the next
agent can apply it directly without re-diagnosing.
```
