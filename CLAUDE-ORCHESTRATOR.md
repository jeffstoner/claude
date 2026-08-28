# Multi-Agent Orchestration

## Resolve cross-task design ambiguity before dispatching

Before dispatching multiple subagents whose work will compose or interact — one task's output feeds another, two tasks might duplicate the same logic, a technical approach has real tradeoffs — identify and resolve any genuine cross-task design ambiguity yourself first. Don't leave it for individual subagents to independently guess.

**How:**
1. Before dispatching, scan the planned body of work for real cross-task coupling — not just sequencing dependencies, but genuine judgment calls: shared vs. duplicated logic, which task owns an artifact another depends on, a naming/contract convention, a technical approach with real tradeoffs.
2. When it's a pure technical call, resolve it yourself with the same rigor you'd apply to writing the code — state the tradeoff, decide, justify.
3. When it's a judgment call without a clearly correct answer (a priority or product tradeoff, not a technical fact), surface it to the user rather than deciding silently.
4. Record the resolution in the channel already scoped to match its actual reach — don't invent a new one:
   - **Concerns only one task** — write it into that task's own record (a ticket's description/design field, a linked doc, a comment) — wherever that subagent's normal onboarding step already looks.
   - **A pattern likely to recur on future tasks of the same kind** (a framework gotcha, a testing anti-pattern, a non-obvious technical constraint) — write it to the project's durable lessons file so it surfaces the next time a relevant task starts, not just this time. See `~/.claude/CLAUDE-LEARNINGS.md` for details.
   - **A convention or architectural stance the project should follow going forward**, beyond any single task — write it to `~/.claude/CLAUDE.md` or the project's decision-record convention (an ADR, a design doc) if one exists.
5. Reference the resolution explicitly in each dependent task's dispatch prompt, and add an execution-order dependency (if the tracker supports one) when the coupling means one task's artifact must exist before another can be built or tested against it.

## Multi-Agent Isolation

**One worktree per concurrent agent.** Each gets its own index, working tree and `HEAD`, so a
stash, checkout or `reset --hard` in one cannot reach another.

* The `Agent` tool's `isolation: "worktree"` does this natively. Prefer it over hand-rolling.
* Hand-rolled: `git worktree add ../wt-<issue-id> -b <type>/<issue-id>`, then merge the branch
  back and `git worktree remove` it.
* **A worktree does not need its own virtualenv or `node_modules`** — the usual reason to avoid
  them. Two ways to solve it:
  1. `worktree.symlinkDirectories` in `settings.json` (see `~/.claude/README.md`). Symlinks the
     named directories from the main repo into each worktree.
  2. Invoke the main checkout's interpreter by absolute path with the worktree as CWD. For a
     `src`-layout Python project with `pythonpath = ["src"]` and no editable install, the venv
     holds only third-party dependencies, so imports resolve to the **worktree's** `src`.
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
* The orchestrator **dispatches the audit agent** once a coding task's work is complete and its
  artifacts block is recorded — before the issue is closed. If the audit finds problems, resume the
  original coding agent with the findings rather than dispatching a fresh one: a resumed agent keeps
  its context and knows why it made each choice. See `~/.claude/CLAUDE-CODE-FLOW.md`.
* Tell each agent **not to run the full test suite** while others are mid-edit — it will observe
  half-finished work and report phantom regressions. The orchestrator runs the full suite once
  the tree is quiet. (With per-agent worktrees this restriction disappears, which is most of the
  argument for worktrees.)
* Watch for **shared test infrastructure** as the real scaling limit. If each test module stands
  up its own container/database, N agents multiply that N times; expect genuine transient
  failures. Prefer a session-scoped service with per-test schema isolation.
* A read-only agent can observe **stale state** — a tracker entry closed seconds ago, a file just
  rewritten. Treat a subagent's report as a snapshot, and re-verify anything load-bearing.
