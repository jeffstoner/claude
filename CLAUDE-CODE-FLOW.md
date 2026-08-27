# Coding Flow

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

When working with code:
* Before closing a task, the agent **MUST** update its ticket with a description of the work
  it performed for human review. The update **MUST** include a JSON fenced-block that details 
  the files and symbols involved in the work. See below for the schema and description.
* After closing a coding task, the orchestrator **MUST** dispatch an auditing agent to audit 
  the task. The auditing agent should validate the work performed against the task's 
  description, what the corresponding tests verify, and what the code actually does. Missing,
  incomplete, or incorrect code/tests need to be communicated to the user. Ask the user if
  they should be fixed or a new bead created with the details so it can be fixed at a later time.
* An audit validates against **the code**, never against the implementer's own account. Where
  the close-reason and the code disagree, the code wins and the close-reason gets corrected —
  including when the implementer *understated* what it delivered.
* When a task's own premise turns out to be false — the bug describes code that does not exist,
  the test it cites already passes — **stop and correct the premise** before doing the work.
  Silently doing something adjacent is how phantom issues propagate into other issues.
* At session close, run an integrity check over everything closed this session: for each issue,
  grep for the symbols its close-reason names. Report anything missing.

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