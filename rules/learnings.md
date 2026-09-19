---
paths:
  - "learnings/**"
---

# Learnings entries

`learnings/` is the shared record of failures encountered while building this project and how they
were resolved, so the same error is never debugged twice. You are reading or writing one now.

**Only record genuine failures** a future agent would otherwise waste real time rediscovering:
environment quirks, tool version mismatches, non-obvious root causes, silent failure modes. A
missing flag, a typo or a one-off is not an entry.

**Filename:** `<issue-id>-<short-slug>.md` (e.g. `PROJ-142-alembic-autocommit-block.md`), so
concurrent writers never collide. Never delete another entry. To amend one:

- Incomplete → append a `## Update (<issue-id>)` section; do not rewrite it.
- Materially wrong → add a `> **Superseded:**` marker at the top of the wrong section with the
  correction, so a reader hitting the wrong text first is warned before acting on it.

**Entry format:**

```markdown
# <short title>

**Issue:** <issue id>
**Date:** <date>

## What was happening

Brief context: what task/command was being attempted when this surfaced.

## Error

The exact error message / symptom observed (verbatim, trimmed to the relevant lines).

## Root cause

What actually caused it — not just "X failed" but *why*.

## Fix

The concrete change that resolved it (command, config, code). Enough detail that the next agent can
apply it directly without re-diagnosing.
```
