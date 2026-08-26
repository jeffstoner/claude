# CLAUDE.md — proposed update for review

**Date:** 2026-08-25
**Scope:** replacement text for the `# Coding`, `## Flow`, and `# Git` sections of
`~/.claude/CLAUDE.md`, plus two new sections (`## Multi-Agent Isolation`, `# Hooks`) and a
`settings.json` block. Nothing here has been merged; `~/.claude/CLAUDE.md` is untouched.

## Why

On 2026-08-24, in the `owasp-reporting` repo, three closed beads' implementations
(`or-13q.11.2`, `or-13q.11.4`, `or-13q.11.6`) were found to be **absent from the repository**
despite detailed close-reasons describing them. Forensics (`git fsck --unreachable`, 10 recovered
stash commits):

- A pathspec-less, message-less `git stash` at 17:35:25 swept up the **union** of every concurrent
  agent's uncommitted work.
- The next blanket stash at 17:43:35 shows the tree had moved **backwards** — an older snapshot
  restored on top. Loss window: 8 minutes.
- **The unit of loss was the stash entry, not the file.** In one recovered commit, `resolver.py`
  contains bead A's edits and zero trace of bead B's — same file, same moment. Agents holding
  their own *named, pathspec-scoped* stash re-applied and survived.
- Four days of multi-agent work had accumulated uncommitted. That is what turned one bad command
  into three destroyed beads instead of a minor annoyance.

Second-order damage: four beads (`or-13q.11.32`, `.33`, `.34`, `.36`) had descriptions written
against code that never existed, and one (`or-2cw`) would have *broken two green tests* if acted on
before its premise landed. Detecting all of this took a dedicated forensic agent.

Two independent facts worth recording, because both were assumed wrong at the time:

1. **Worktrees were never actually tried.** They were rejected because `api/.venv` is gitignored,
   on the assumption each worktree needs its own interpreter. False — see `## Multi-Agent
   Isolation`, verified empirically.
2. **`git stash` did not "fail"; it was misused.** But the correct conclusion is stronger: the
   *idiom* it was serving ("stash my change, re-run, confirm this failure is pre-existing") never
   needed tree mutation at all.

---

## `# Coding` — replacement text

> Changes: adds the sequencing rule (4), the close-reason rule (5), and the verification rule (6).
> Rules 1–3 and the `learnings` paragraph are unchanged.

```markdown
# Coding

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
- **NEVER** mutate the working tree to answer "is this failure pre-existing?" Read the committed
  version with `git show HEAD:<path>`, or run the test in the read-only baseline worktree. Never
  `git stash`.

Before coding, check in `learnings` directory for known issues relevant to the task that have
been encountered and resolved so you don't make the same mistake(s). After coding is complete and
tests have been verified "green", document any errors/issues encountered in the `learnings`
directory. Include a quick (2-3 sentences) summary of the task, relevent technologies, the exact
error, the root cause, and what the resolution was.
```

## `## Flow` — replacement text

> Changes: keeps both existing bullets verbatim, adds four.

```markdown
## Flow

When working with code:
* **NEVER** write TODOs for work that is still to be done. **ALWAYS** create a new bead **OR**
  update an existing bead with sufficient context and direction to finish the work.
* Before closing a coding task, use another agent to audit the task. The auditing agent should
  validate the work performed against the task's description, what the corresponding tests
  verify, and what the code actually does. Missing, incomplete, or incorrect code/tests need to
  be communicated to the user. Ask the user if they should be fixed or a new bead created with
  the details so it can be fixed at a later time.
* An audit validates against **the code**, never against the implementer's own account. Where
  the close-reason and the code disagree, the code wins and the close-reason gets corrected —
  including when the implementer *understated* what it delivered.
* Write close-reasons so they are **checkable**: name the symbols added, the files touched, and
  paste the verbatim output of each quality gate. A close-reason that only describes intent
  cannot be audited and cannot be verified after the fact.
* When a task's own premise turns out to be false — the bug describes code that does not exist,
  the test it cites already passes — **stop and correct the premise** before doing the work.
  Silently doing something adjacent is how phantom issues propagate into other issues.
* At session close, run an integrity check over everything closed this session: for each issue,
  grep for the symbols its close-reason names. Report anything missing.
```

## `# Git` — replacement text

> Changes: all nine original hygiene bullets and all three `NEVER` rules are preserved. Added: the
> commit-frequency inversion, the stash ban, the worktree recipe, and the recovery path.

```markdown
# Git

Observe good git hygiene:

* Branching is cheap. Use it liberally. Creating branches for epic/feature/bugfix work is highly
  encouraged.
* Branches should be merged only when all work has been successfully completed.
* Subagents should use worktrees when their use case fits the situation.
* Remove worktrees when its changes have been successfully merged back into the main worktree
  ("clean up after yourself")
* Don't combine multiple changes into a single commit. Use 1 commit per task/fix/chore/etc..
* Write brief (no more than 2 paragraphs) but meaningful commit messages.
* It is better to have many small commits than a few large commits.
* Obey Semantic Versioning. Use it when creating version tags.

**Commit early — uncommitted work is unprotected work.**

* Commit each task's work to a branch **as soon as its quality gates pass**. Do not accumulate
  multiple tasks', or multiple agents', changes in a dirty working tree. Committed work is
  effectively unloseable; uncommitted work is one bad command away from gone.
* The user controls what gets **merged**, not what gets **committed**. "Do not commit without
  asking" is the wrong default for a long or multi-agent session: it maximises the amount of
  unprotected state, which is exactly backwards. Commit to a task branch freely; never merge to
  `main` without approval.

**`git stash` is banned.**

* **NEVER** run `git stash` in a checkout that anything else might be working in. It is a
  whole-tree operation: a pathspec-less stash captures every concurrent agent's work, and an
  incomplete restore destroys it silently. This has already cost three implementations.
* Even a correctly-scoped `git stash push -m "<id>" -- <my files>` is disruptive — it can make a
  concurrent reader observe a self-inconsistent tree and report a phantom regression.
* The idiom it usually serves — "confirm this failure is pre-existing" — does not need it. Use
  `git show HEAD:<path>` or the baseline worktree.
* To shelve work, commit it to a branch.

**Never discard uncommitted changes you did not create.**

* **NEVER** `git checkout -- <path>`, `git restore <path>`, `git reset --hard`, or `git clean` in
  a shared checkout. Untracked files include other agents' new test files.

**Recovery.**

* Uncommitted work that appears lost is usually recoverable. `git fsck --unreachable | grep
  commit`, then `git show <sha>` / `git diff HEAD <sha> -- <path>`. Dropped stashes survive here.
* Check this **before** re-deriving a lost implementation — but still diff the recovery against
  your re-derivation, because the recovered version may predate refactors `HEAD` has since
  absorbed.

Unless overridden directly by the user or a project-level `CLAUDE.md` file:

* **NEVER** merge to the `main` branch without user approval.
* **NEVER** use '--force', especially if git returns an error. Git errors should be investigated
  and resolved cleanly. If unsure, escalate to the user.
* **NEVER** push to or pull from a remote. The user is responsible for syncing with remotes.
```

## `## Multi-Agent Isolation` — new section

```markdown
## Multi-Agent Isolation

**One worktree per concurrent agent.** Each gets its own index, working tree and `HEAD`, so a
stash, checkout or `reset --hard` in one cannot reach another. This is the only structural fix;
everything else is discipline that degrades under pressure.

* The `Agent` tool's `isolation: "worktree"` does this natively. Prefer it over hand-rolling.
* Hand-rolled: `git worktree add ../wt-<issue-id> -b <type>/<issue-id>`, then merge the branch
  back and `git worktree remove` it.
* **A worktree does not need its own virtualenv or `node_modules`** — the usual reason to avoid
  them. Two ways to solve it:
  1. `worktree.symlinkDirectories` in `settings.json` (see `# Hooks`). Symlinks the named
     directories from the main repo into each worktree.
  2. Invoke the main checkout's interpreter by absolute path with the worktree as CWD. For a
     `src`-layout Python project with `pythonpath = ["src"]` and no editable install, the venv
     holds only third-party dependencies, so imports resolve to the **worktree's** `src`.
     *Verified 2026-08-25:* `cd <wt>/api && /main/api/.venv/bin/python -m pytest tests/models`
     → 12 passed, and `owasp_aggregator.__file__` pointed inside the worktree, not the main tree.
* Set `worktree.baseRef: "head"`. The default (`fresh`) branches from `origin/<default-branch>`,
  which silently omits local commits — for this workflow that is the wrong base.

**Keep one read-only baseline worktree pinned at `HEAD`**, never modified. This is the
replacement for `git stash`: to check whether a failure is pre-existing, run the test there.

**Right-size the parallelism.**

* TDD is inherently **serial per task**: test → code → audit. Parallelism buys nothing *within* a
  task. Parallelise *across independent tasks* only.
* 2–3 concurrent agents on genuinely disjoint subsystems is the practical ceiling. Beyond that,
  coordination overhead and shared-resource contention cost more than the wall-clock saved.
* The orchestrator **assigns file ownership explicitly** in each dispatch prompt, and states
  which paths belong to other agents.
* Tell each agent **not to run the full test suite** while others are mid-edit — it will observe
  half-finished work and report phantom regressions. The orchestrator runs the full suite once
  the tree is quiet. (With per-agent worktrees this restriction disappears, which is most of the
  argument for worktrees.)
* Watch for **shared test infrastructure** as the real scaling limit. If each test module stands
  up its own container/database, N agents multiply that N times; expect genuine transient
  failures. Prefer a session-scoped service with per-test schema isolation.
* A read-only agent can observe **stale state** — a tracker entry closed seconds ago, a file just
  rewritten. Treat a subagent's report as a snapshot, and re-verify anything load-bearing.
```

## `# Hooks` — new section

```markdown
# Hooks

Instructions are advisory; hooks are enforcement. Any rule that must not be broken under
pressure belongs in a `PreToolUse` hook, not only in this file.

Note the division of labour: a hook blocks **the model**. The user can always run the same
command themselves with `!` in the prompt. So a hook that over-blocks costs a round trip; a
missing hook can cost a day's work.
```

**`~/.claude/settings.json`** — merge into the existing file, do not replace it (the current file
has `model`, `enabledPlugins`, `extraKnownMarketplaces`, `tui`, `skipWorkflowUsageWarning` and no
`hooks` key):

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "if": "Bash(git *)",
            "command": "~/.claude/hooks/guard-git.sh",
            "timeout": 10,
            "statusMessage": "Checking git safety"
          }
        ]
      }
    ]
  },
  "worktree": {
    "baseRef": "head",
    "symlinkDirectories": ["node_modules", ".venv", "api/.venv"]
  }
}
```

Notes on the above:

- `if: "Bash(git *)"` uses permission-rule syntax to avoid spawning the hook for non-git
  commands. The script re-checks anyway, so the `if` is an optimisation, not the guard.
- `PreToolUse` denials **must** use `hookSpecificOutput.permissionDecision`. The older
  `decision: "block"` is deprecated for this event and will not reliably block.
- `symlinkDirectories`: `node_modules` and `.venv` match the documented examples (bare directory
  names). Whether a **nested** path like `api/.venv` is honoured is unverified — test it, and if
  it isn't, fall back to the absolute-interpreter approach, which is verified.

**`~/.claude/hooks/guard-git.sh`** — `chmod +x` after creating. Tested 2026-08-25: 11/11 dangerous
commands denied, 12/12 safe commands allowed (including `git checkout -b`, `git worktree remove
--force`, `git show HEAD:<path>`, and `git add && git commit`).

```bash
#!/usr/bin/env bash
# PreToolUse(Bash) guard: blocks git commands that can destroy another agent's
# uncommitted work in a shared checkout. Always exits 0; a denial is expressed as
# JSON on stdout via hookSpecificOutput.permissionDecision.
set -uo pipefail

cmd="$(jq -r '.tool_input.command // empty' 2>/dev/null)" || exit 0
[ -z "$cmd" ] && exit 0

deny() {
  jq -nc --arg r "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

# Only inspect git invocations. `git` must appear as a command word, not inside a path.
printf '%s' "$cmd" | grep -qE '(^|[;&|(){}[:space:]])git([[:space:]]|$)' || exit 0

# Does $cmd use this git subcommand? Matched as a whole word anywhere after `git`,
# so global options with values (`git -C /repo stash`) are covered. Deliberately
# over-inclusive: over-blocking is recoverable, destroying a peer's work is not.
uses() { printf '%s' "$cmd" | grep -qwE "$1"; }

# 1. stash — the mechanism that destroyed three implementations on 2026-08-24.
if uses 'stash'; then
  deny "BLOCKED: 'git stash' is banned in a shared checkout — it is a whole-tree operation that silently sweeps up every concurrent agent's uncommitted work, and an incomplete restore destroyed three implementations on 2026-08-24. To answer 'is this failure pre-existing?' use the read-only baseline worktree or 'git show HEAD:<path>'. To shelve work, commit it to a branch."
fi

# 2. Discarding working-tree changes.
if uses 'checkout|restore' \
   && printf '%s' "$cmd" | grep -qE '(--[[:space:]]|--force|--hard|\.$)'; then
  deny "BLOCKED: 'git checkout/restore' with a pathspec discards uncommitted changes, which in a shared checkout may not be yours. Read the committed version with 'git show HEAD:<path>' instead."
fi

# 3. Hard reset / clean.
if uses 'reset' && printf '%s' "$cmd" | grep -qE '\-\-hard|\-\-merge|\-\-keep'; then
  deny "BLOCKED: 'git reset --hard' (or --merge/--keep) discards uncommitted work across the whole tree. Never run this in a shared checkout."
fi
if uses 'clean'; then
  deny "BLOCKED: 'git clean' deletes untracked files — in this workflow that includes other agents' new test files, which are untracked until committed."
fi

# 4. Remote sync and force — already 'NEVER' in CLAUDE.md; enforced here.
if uses 'push|pull'; then
  deny "BLOCKED: pushing to or pulling from a remote is the user's responsibility (CLAUDE.md, Git). Report the command you would run and let the user run it."
fi
if printf '%s' "$cmd" | grep -qE '(--force([[:space:]]|=|$)|[[:space:]]-f([[:space:]]|$))' \
   && ! uses 'worktree'; then
  deny "BLOCKED: '--force' on a git command is banned (CLAUDE.md, Git). Investigate and resolve the underlying error cleanly, or escalate to the user."
fi

exit 0
```

Known trade-off: `uses()` matches the subcommand word anywhere, so `git log --grep stash` is
blocked. That is deliberate — over-blocking costs a rephrase, under-blocking cost three
implementations.

---

## Other suggestions

Ordered by value; all optional.

**1. A `SubagentStop` integrity hook.** The session-close grep is the cheapest possible safety net
and would have caught all three losses in seconds. `SubagentStop` and `SessionEnd` are both
available events. A first cut: on `SubagentStop`, if the working tree is clean *and* no commit was
made, emit a `systemMessage` warning — an agent that reported success while changing nothing is
the exact signature of the failure this document exists to prevent.

**2. Make close-reasons machine-checkable.** If close-reasons are required to name symbols
(`Added require_project_scope() to auth/resolver.py`), the integrity check becomes a one-liner.
Consider a template or a tracker validation rule.

**3. Reconsider the `learnings` protocol for wrong entries.** The protocol says append an
`## Update` section rather than editing. That is right for provenance, but this session produced a
learnings entry whose **root-cause section was wrong** and which a later agent would have believed.
Consider requiring a `> **Superseded:**` marker at the top of any section a later update
contradicts, so a reader hitting the wrong text first is warned before they act on it.

**4. Test-infrastructure isolation deserves its own standard.** "Every test module stands up its
own container" is fine serially and quadratic under parallelism. Worth a standing rule: shared
session-scoped services, per-test schema/database isolation.

**5. `permissions.deny` as a second layer.** Hooks can be disabled (`disableAllHooks`) and are
per-machine. `"permissions": {"deny": ["Bash(git stash*)", "Bash(git reset --hard*)"]}` is
declarative, cheaper, and survives hook misconfiguration. Weaker matching than the script, so use
it *alongside*, not instead.

**6. Consider `sandbox.filesystem.denyWrite` for the baseline worktree.** If a read-only baseline
worktree is adopted, making it genuinely read-only at the sandbox level removes the possibility of
an agent "fixing" it.

---

## What I would merge first

If only one thing: **the hook plus the stash ban**. It is the single change that prevents the
specific catastrophe, it needs no workflow adjustment, and it is verified.

The commit-frequency inversion is the highest-value change but it is a genuine policy shift — it
changes when the user reviews work — so it deserves a deliberate decision rather than being
absorbed with the rest.
