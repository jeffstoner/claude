<!-- jbcontext-instructions-start -->
# Tools

## Code discovery: context-explorer first

When a task requires finding or understanding code whose location you don't
already know, your FIRST code-discovery step MUST be:

Task(subagent_type='context-explorer',
     description=<short label>,
     prompt=<1-2 sentence intent describing what to find>)

Start there instead of opening with your own `grep`/`glob`/`bash` searches or
git history: the subagent runs the semantic exploration in its own context and
hands back concrete `file:line` references, so you don't burn your context
re-reading the same files.

This governs *how* you begin code discovery — not whether every task needs it.
Do NOT call context-explorer when the task doesn't involve locating code:

- the task names the exact file, class, or symbol — open it or grep directly;
- the relevant file is already open or identified;
- the work is a git operation (rebase, merge, commit), a test/build run,
  shell/statusline/config setup, or a review of a diff you already have.

Invoking context-explorer as a formality "to get started" on such tasks wastes
a subagent round and returns irrelevant findings. It is a research step, not a
gate to clear — skip it and proceed directly.

When you do use it, the subagent runs up to 3 semantic searches in its own
context (restricted to `jbcontext search` via `Bash` and `Read` only) and
returns a short report:

Searched: <one-line summary>
Findings:
- <relative/path>:<line> — <description>
- ...
Notes: <confidence; whether keyword grep would be more direct here>

Use its findings if they look useful, or ignore them entirely if `Notes:` flags
the task as keyword-based. You retain full freedom for the rest of the run.

## Semantic Code Search (jbcontext)

You have access to `jbcontext search` for searching the codebase semantically.
It finds code by meaning, not just keywords.

### Usage

```bash
jbcontext search "<detailed and descriptive query>"
jbcontext search -p <path> "<query>"  # <path> must be relative to the project root
```

### Query Tips

- Be descriptive: "function that validates user email addresses" > "email"
- Include context: "error handling middleware for HTTP requests with logging"
- Specify what you're looking for: "React component that renders a modal dialog"

### Single-Shot Policy

Use `jbcontext search` as a semantic bootstrap when the relevant file or subsystem is still unknown.

- If no relevant file is open yet, start with one `jbcontext search`.
- Make the first query specific to the issue's named feature, class, method, config flag, or behavior when available.
- After the first search, open at least one returned file and inspect it locally.
- If the first hit is relevant but incomplete, inspect neighboring files locally in that same directory or subsystem before any semantic retry.
- After the first relevant file or path is known, prefer direct file reads and exact search to inspect nearby code.
- If a semantic retry is still needed, use `jbcontext search -p <path> ...` with the directory of the best first hit.

### Examples

```bash
# Find authentication-related code
jbcontext search "user authentication login flow"

# Narrow to specific directory
jbcontext search -p src/auth "JWT token validation"
```

Use `jbcontext search` once to get the initial pointer, then inspect nearby code locally. If that still fails, do a narrowed retry with `-p`.
<!-- jbcontext-instructions-end -->

# Git

## After merging a subagent's worktree branch, check `git status`, not just `git diff`

**What:** When a subagent does its work in an isolated git worktree and you merge its branch back into the main line, run `git status --short` (or equivalent) on the primary working directory as part of verifying that merge — in addition to, not instead of, reviewing the branch's actual diff/log.

**Why:** `git diff <base>..<branch>` and `git log <base>..<branch>` only show *tracked* changes carried by the branch you're merging. They cannot reveal a mistake a subagent made directly against the shared main checkout before switching to its own worktree — e.g. running a scaffolding or codegen command (`npm init`, a framework's `make:*` generator, an editor autosave, a stray `touch`) from the wrong working directory, noticing, and redoing the work correctly inside its worktree, but leaving the first, wrong-directory artifact behind. That artifact is untracked, so it produces zero footprint in the branch diff and is invisible to a review that only checks what the branch changed. It can still be picked up by anything that scans the filesystem rather than git's tracked-file list — a build tool, a migrator, a linter, a test runner — breaking something in a way that looks unrelated to the merge that actually caused it. Don't rely on a subagent's own "my worktree is clean" self-report to cover this either: by definition, the mistake happens *outside* that worktree, so the agent may not even know to check for it, and in practice this has gone both ways — one agent caught and disclosed its own slip, another didn't.

**How:** After merging a worktree branch, run `git status --short` in the main checkout. Anything reported as `??` (untracked) that you didn't expect is a candidate stray file from a subagent having operated outside its assigned worktree — investigate before considering the merge step done. If you find one, confirm it's genuinely inert junk (not something legitimate already in progress) before deleting it, and prefer a reversible removal over `git clean -fd` or similar broad-strokes commands that could take out unrelated in-progress work.

# Multi-Agent Orchestration

## Resolve cross-task design ambiguity before dispatching

**What:** Before dispatching multiple subagents whose work will compose or interact — one task's output feeds another, two tasks might duplicate the same logic, a technical approach has real tradeoffs — identify and resolve any genuine cross-task design ambiguity yourself first. Don't leave it for individual subagents to independently guess.

**How:**
1. Before dispatching, scan the planned body of work for real cross-task coupling — not just sequencing dependencies, but genuine judgment calls: shared vs. duplicated logic, which task owns an artifact another depends on, a naming/contract convention, a technical approach with real tradeoffs.
2. When it's a pure technical call, resolve it yourself with the same rigor you'd apply to writing the code — state the tradeoff, decide, justify.
3. When it's a judgment call without a clearly correct answer (a priority or product tradeoff, not a technical fact), surface it to the user rather than deciding silently.
4. Record the resolution in the channel already scoped to match its actual reach — don't invent a new one:
   - **Concerns only one task** — write it into that task's own record (a ticket's description/design field, a linked doc, a comment) — wherever that subagent's normal onboarding step already looks.
   - **A pattern likely to recur on future tasks of the same kind** (a framework gotcha, a testing anti-pattern, a non-obvious technical constraint) — write it to the project's durable lessons file (e.g. a `learnings/` directory) so it surfaces the next time a relevant task starts, not just this time.
   - **A convention or architectural stance the project should follow going forward**, beyond any single task — write it to CLAUDE.md or the project's decision-record convention (an ADR, a design doc) if one exists.
5. Reference the resolution explicitly in each dependent task's dispatch prompt, and add an execution-order dependency (if the tracker supports one) when the coupling means one task's artifact must exist before another can be built or tested against it.
