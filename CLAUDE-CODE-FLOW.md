# Coding Flow

## Before you touch the codebase

**ALWAYS** review the project's learnings before doing any work in a codebase — not only when you
hit an error. Past agents record environment quirks, tool-version mismatches, non-obvious root
causes and silent failure modes there, and the cost of reading them is seconds against hours of
rediscovery. Search for terms relevant to the task (`grep -ril "<keyword>" learnings/`) and for the
subsystem you are about to change. See `~/.claude/CLAUDE-LEARNINGS.md` for the protocol, the entry
format, and the rules for amending an existing entry.

Consult learnings again, specifically, when: a test or build fails in a way you did not expect;
you are about to choose between two plausible technical approaches; or you are working in a
subsystem you have not touched before. Write a new entry once your work is green and you hit
something a future agent would otherwise waste real time rediscovering.

## Test Driven Development

Use Test Driven Development when coding.
- Every coding task must have at least 1 test.
- A coding agent **MUST NEVER** write tests. Tests **MUST** be written by a separate agent.
- A coding agent must execute tests until they pass, up to a maximum of 10 times. After 10
  attempts, escalate to the user.
- **NEVER** dispatch a task whose premise is not yet in the working tree. A test task that
  depends on an implementation must not start until that implementation has landed — otherwise
  the tests it "fixes" were passing, and it breaks them. Record the ordering as a dependency in
  the issue tracker, not just in the dispatch prompt.
- A closed issue's close-reason is a **claim about a past working tree**, not evidence. Before
  building on one, verify the code exists: grep for the symbols the close-reason names. This
  takes seconds and catches the failure mode where a whole subsystem is missing.
- **NEVER** write TODOs for work that is still to be done. **ALWAYS** create a new issue in the 
  issue tracker **OR** update an existing issue with sufficient context and direction to finish 
  the work.

## Closing a task: the audit gates the close

An issue is **not** closed by the agent that did the work until an audit has passed. The sequence:

1. The coding agent finishes and **MUST** update the issue with a description of the work for human
   review, including the JSON fenced-block detailing the files and symbols involved (schema below).
   Write it to the issue's **notes**, using the tracker's *append* form — never the replace form.
2. The coding agent stops. It does **not** close the issue, and if it worked in its own worktree/
   branch, it does **not** merge or remove that worktree/branch itself — merging is always the
   orchestrator's action, never the coding agent's own. See `~/.claude/CLAUDE-BEADS.md`'s
   "audited before merge" standing convention and `~/.claude/CLAUDE-ORCHESTRATOR.md`'s
   merge/cleanup/close ordering.
3. The orchestrator dispatches an auditing agent.
4. Audit clean → the orchestrator merges the branch (if any). If the merge conflicts, resume the
   original coding agent with the conflict details so it resolves it with context intact, then
   re-merge. Once merged cleanly, remove the worktree, then close the issue. Audit finds
   problems instead → resume the original coding agent with the findings so it can fix them with
   its context intact, then re-audit.
5. Anything not fixed now is communicated to the user, who decides: fix it now, or open a new issue
   carrying the detail so it can be fixed later.

**How the resume works, because it is not obvious.** A subagent terminates when it finishes; there is
no pause primitive and a subagent cannot block waiting on a sibling. Terminating is not destruction:
sending a message to a stopped agent resumes it **with its context intact**, whereas dispatching a
fresh agent starts with no memory of the work. So the agent that wrote the code is the one that
should fix audit findings — it knows why it made each choice. The same logic applies to a merge
conflict discovered at step 4: resume the agent that wrote the change, don't resolve the conflict
yourself and don't dispatch a fresh agent to re-derive it from scratch. If resume is unavailable,
dispatch a fresh agent with the findings (audit or conflict) instead; the sequence is unchanged,
only slower. The most common way resume becomes unavailable is self-inflicted: merging and
deleting the coding agent's worktree/branch as soon as its change lands, before the audit has even
run — which is exactly what step 2 above forbids.

**One duplication to expect.** The artifacts block goes into the issue's notes at step 1 so the
auditor has it, and again in the close reason at step 4 so the close-time gate accepts the close.
Use the tracker's read-reason-from-file option to avoid shell-escaping the JSON.

When working with code:
* The auditing agent validates the work performed against the issue's description, what the
  corresponding tests verify, and what the code actually does.
* An audit validates against **the code**, never against the implementer's own account. Where
  the close-reason and the code disagree, the code wins and the close-reason gets corrected —
  including when the implementer *understated* what it delivered.
* When a task's own premise turns out to be false — the bug describes code that does not exist,
  the test it cites already passes — **stop and correct the premise** before doing the work.
  Silently doing something adjacent is how phantom issues propagate into other issues.
* At session close, an integrity check runs over everything closed this session: for each issue,
  every symbol its close-reason claims is checked against the repository. This is automated by the
  `SessionEnd` hook (see `~/.claude/README.md`). Where those hooks are not installed, run the
  equivalent by hand — grep for the symbols each close-reason names — and report anything missing.

## close-reason's JSON block

A fenced `json` block at the end of every close-reason:

```json
{
  "artifacts": [
    { "path": "api/src/owasp_aggregator/auth/resolver.py",
      "symbols": ["ProjectNotInScopeError", "require_project_scope"] },
    { "path": "api/tests/auth/test_project_scope_enforcement.py", "symbols": [] },
    { "path": "api/src/owasp_aggregator/legacy.py",
      "symbols": ["OldThing"], "state": "removed" }
  ]
}
```

| field | required | default | meaning |
|---|---|---|---|
| `path` | yes | — | repo-relative path |
| `symbols` | no | `[]` | greppable tokens: function/class names, a response field, an error slug, a migration revision id. Empty asserts only that the file exists. |
| `state` | no | `"present"` | `"removed"` asserts deletion, so refactors and deletions are checkable in the same pass |

An array of records so the same file can appear as both `present` and `removed` — a renamed 
symbol — and so `jq` can iterate it directly.

### Notes

A `state: "removed"` claim correctly **fails** while the symbol is still present and
passes once it is gone; and a block with an `artifacts` key that does **not** parse is reported as
`MALFORMED` and exits non-zero, rather than reading as "no block"