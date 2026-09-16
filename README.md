# README

This repository contains the framework for one developer's (opinionated) use of Claude. It
provides structure for agents to operate under by defining:

* the use of `beads` as an independent issue tracker
* an Orchestrator that coordinates work and never implements it
* a defined agent workflow: write tests, write code, audit code and results
* how to use Git
* recording "lessons learned" for future agents to reference

It is delivered as one small always-loaded instruction file, four role agents, a set of hooks that
enforce the rules mechanically, one path-scoped rule file and two on-demand skills. *Instruction
files advise; hooks enforce.* A CLI (`bd-board`) helps plan work.

For installation, see `INSTALL.md`.

# Why

This framework was born out of frustrations watching Claude go off the rails, fumble around,
clobber work, etc. while several subagents worked. As it evolved, Claude was observed to properly
order its operations, not trust itself (especially subagents), run git commands safely and, in
general, behave better.

The current layout exists because of a second observation: a rulebook that every agent has to read
is a rulebook agents forget. Earlier versions kept ~6,000 words of rules in files every agent was
told to read; the reads cost tool calls and context, were discarded on compaction, and were skipped
often enough to matter. Now each rule is delivered at the moment it applies, to the agent it applies
to, and nowhere else:

| Channel | Carries | Cost when idle |
|---|---|---|
| A hook's deny/ask message | the rule text itself, shown only when it is about to be broken | none |
| A role agent's body | the judgement rules for that role; loaded only for that role, for its whole life | none for other roles |
| `~/.claude/CLAUDE.md` | style, a short map of the workflow, and the code-reference form | ~400 tokens, re-injected after compaction |
| `~/.claude/rules/learnings.md` | the learnings entry format, loaded only when touching `learnings/**` | none |
| skills | rarely-needed procedures (`git-recovery`, `worktree-setup`) | a one-line description each |

# Required Tooling

* `beads` (https://github.com/gastownhall/beads), an agent-first issue tracker.
* `jq` (https://jqlang.org/), used by every hook to parse payloads and build responses.

**Recommended:** `bead-me-up-scotty` (https://beadmeupscotty.com/), a UI for beads. In its absence,
`bd-board` shows which beads are ready.

# How Do I Use It?

Start an orchestrated session as the orchestrator agent, so its rules are the session's system
prompt and survive compaction:

```
claude --agent orchestrator
> Work beads gg-12.1 and gg-13.4
```

The orchestrator reads the beads, resolves cross-task ambiguity, dispatches the `tester` for each
bead, merges the tests, dispatches the `coder` in its own worktree, dispatches the `auditor`, and
only then merges, cleans up and closes. You can hand any piece to Claude or keep it: write the
beads yourself, write the tests yourself, audit yourself. But anything Claude needs must be in
beads: that is how dependencies, specification, completion and audit are recorded.

A plain `claude` session still has every global hook. It lacks only the orchestration rules and the
role split; in a beads project a hook will refuse to dispatch a generic agent for implementation
work and point at the role agents.

# The role of your project's CLAUDE.md

Every agent, including every subagent, loads the project's `CLAUDE.md` itself, so a setting there
propagates automatically and survives context loss; a verbal override lives only in one agent's head
and cannot be safely relayed downward. If you find yourself repeating a verbal override, move it into
the project file.

Because hooks enforce the rules, overrides must be **exact, greppable lines**. Free prose is not
honoured. The vocabulary:

```
Default branch: main                     # authoritative; outranks anything inferred from git
Policy: commit-on-default allowed        # throw-away repos: work directly on the default branch
Policy: merge-to-default allowed         # merge into the default branch without a prompt
Policy: todo-comments allowed            # lift the TODO-comment ban
Policy: no issue tracker                 # no beads; NOTICKET scope; artifacts block in commit bodies
Test-paths: src/**/*_test.rs             # extend the set of paths the tester may write (repeatable)
```

Two rules no project file relaxes: **tests are written by a different agent than the
implementation**, and **every implementation is audited before merge**.

Example for a one-shot project:

```markdown
Default branch: main
Policy: commit-on-default allowed
Policy: merge-to-default allowed
Policy: no issue tracker
Use context7 to look up product/API/framework documentation.
```

# Components

## Role agents (`~/.claude/agents/`)

| Agent | Tools | Body carries |
|---|---|---|
| `orchestrator` | `Agent(tester, coder, auditor, Explore, Plan)`, Bash, Read, Grep, Glob, Write, Skill | no unverified assertions; resolve cross-task ambiguity first; premise-in-tree before dispatch; audit → merge → close → cleanup; harness-created worktrees, never hand-assigned; resume the same coder for findings and conflicts; note routing; tracking-off mode; default-branch resolution |
| `tester` | edit tools, Bash; `isolation: worktree`; agent hook `guard-edit.sh tester` | writes only tests; tests must fail for the right reason first; artifacts block; `ESCALATION:` escape |
| `coder` | edit tools, Bash; `isolation: worktree`; agent hook `guard-edit.sh coder` | TDD loop with the 10-attempt limit; never touches tests; challenge the brief; commit early; artifacts block; `ESCALATION:` escape |
| `auditor` | Bash, Read, Grep, Glob only; agent hook `guard-edit.sh auditor` | audit against the code, not the account; check the premise, the artifacts block, the tests against the criteria; report format; out-of-scope → own bead |

The `tester` and `coder` worktrees are created by the harness from `isolation: worktree` and become
the agent's working directory; the orchestrator must not create or assign a second one, and the
auditor gets none (it reads the coder's worktree by path). Agents see each other's work only through
merges into the integration branch, which is why the orchestrator merges the tester's branch before
dispatching the coder.

The orchestrator's `tools` line is an allowlist: it can dispatch only those agent types. Run it as
the main session with `claude --agent orchestrator`. Whether `SendMessage` (used to resume a stopped
subagent in some harness versions) is honoured in an agent allowlist is unverified; if resuming
fails, remove it from the list and use the `Agent` tool's resume path.

## Hooks (`~/.claude/hooks/`)

| Script | Event | What it enforces |
|---|---|---|
| `guard-git.sh` | `PreToolUse`, `if: Bash(git *)` | no stash / pathspec checkout / hard reset / clean / push / pull / `--force` (except `worktree add -f`); a **subagent** may not merge, delete a branch or remove a worktree; **no commit on the default branch**, detached HEAD is a stop; **merge into the default branch asks the user**; a worktree is removed only once its branch is merged; `branch -D` never; branch names `<type>/<id>` for branches created by hand (harness-generated worktree branches never pass through the hook); SemVer tags; **Conventional Commits** with a scope, ≤ 72-char subject, `!` ⇔ `BREAKING CHANGE:` |
| `guard-bd.sh` | `PreToolUse`, `if: Bash(bd *)` | `--notes` (the replace form) denied, `--append-notes` only; no inline `$(...)` into fields except `$(cat <file>)`; `bd edit` denied; a subagent may not `bd close` or `--status=closed`; `bd label add <id> human` asks |
| `guard-edit.sh` | `PreToolUse`, `Edit\|Write\|NotebookEdit\|MultiEdit` (global) and per-agent | global: an edit may not **add** a TODO/FIXME comment; `coder`: no test paths; `tester`: only test paths (asks otherwise); `auditor`: no Bash writes, no git/bd mutations |
| `guard-dispatch.sh` | `PreToolUse`, `Agent\|TodoWrite\|TaskCreate\|TaskUpdate` | in a beads project: no TodoWrite/TaskCreate; no `general-purpose` agent for work, use the role agents |
| `require-artifacts-block.sh` | `PreToolUse`, `if: Bash(bd close *)` | the close reason (inline or `--reason-file`) carries a **valid** fenced json `artifacts` block |
| `subagent-integrity.sh` | `SubagentStart`, `SubagentStop` | `coder`/`tester`: **stop is blocked** until the artifacts block exists and every claim is true on disk; other agents: warn on zero repository delta; read-only agent types skipped |
| `learnings-context.sh` | `SessionStart`, `SubagentStart`, `PostToolUseFailure` | when `learnings/` exists: inject the protocol and the file list (also after compaction); nudge to grep learnings after a failed command, at most once per 10 minutes |
| `post-merge-status.sh` | `PostToolUse`, `if: Bash(git merge *)` | report untracked files after a merge |
| `session-close-sweep.sh` | `SessionEnd` | every closed issue's artifacts claims verified against `HEAD` |
| `bd-verify-artifacts.sh` | CLI | the verifier the sweep and the stop gate call |
| `policy-lib.sh` | sourced | hook responses, policy lines, default-branch resolution, command splitting |

Global versus agent-scoped: everything that must hold even when the role agents are not in use is
global and keyed on the payload's `agent_id`/`agent_type` where the role matters (PreToolUse
payloads from inside a subagent carry both). Only the coder/tester path split and the auditor's
Bash write-deny are agent-scoped, because they need a role identity only the custom agent supplies.

### Merge approval changed meaning

Merging into the default branch now produces a permission prompt. **Approving the prompt is the
approval**, scoped to exactly that one merge. A verbal "for the rest of the session, merge to main
directly" no longer does anything; a project that wants no prompt says `Policy: merge-to-default
allowed`. Behaviour under bypass-permissions mode is unverified; if `ask` auto-allows there, the gate
degrades silently in that mode.

### Design principles

- **Instructions are advisory; hooks are enforcement.** A rule that must not break under pressure
  belongs in a hook. Its message carries the rule, so nobody has to remember it in advance.
- **A hook blocks the model, never the user.** You can always run the same command yourself. An
  over-blocking hook costs one round trip; a missing hook can cost a day's work. Err toward
  over-blocking: `git log --grep stash` is denied and that is deliberate.
- **Every hook exits 0.** Denials are JSON on stdout, not a non-zero exit.
- **Fail loudly, never silently.** Where a check cannot tell "nothing to verify" from "verification
  impossible", it reports the difference: a malformed artifacts block is `MALFORMED`, not "no block";
  a tracker that returns nothing blocks the stop rather than passing it.

### `subagent-integrity.sh`, two limitations

- The zero-delta warning is a **false negative in a shared checkout**: `git status` is tree-wide, so a
  concurrent agent's edits mask this agent's inactivity. Reliable only with one worktree per agent,
  which is what the role agents declare.
- The artifacts gate finds the issue id from the agent's transcript (its `bd show`/`bd update`
  calls) or the last commit's scope. An agent that never mentioned its issue id in either place is
  blocked with instructions to do so.

## bd-board

A CLI that reports which beads are ready to be worked, in four buckets: READY NOW (unblocked), IN
FLIGHT (in_progress), READY NEXT (blocked only by READY NOW), NEEDS REVIEW (awaiting a human). Each
bucket groups beads under their epics.

# The artifacts block

Every close reason, and every coder's and tester's notes, ends with a fenced `json` block. This is
what makes the mechanical check possible: a prose claim cannot be verified.

````
```json
{
  "artifacts": [
    { "path": "src/auth/resolver.py",
      "symbols": ["ProjectNotInScopeError", "require_project_scope"] },
    { "path": "tests/auth/test_scope.py", "symbols": [] },
    { "path": "src/auth/legacy.py", "symbols": ["OldThing"], "state": "removed" }
  ]
}
```
````

| field | required | default | meaning |
|---|---|---|---|
| `path` | yes | — | repo-relative path |
| `symbols` | no | `[]` | greppable tokens: function or class names, a response field, an error slug, a migration revision. Empty asserts only that the file exists. |
| `state` | no | `"present"` | `"removed"` asserts deletion, so refactors and deletions are checkable in the same pass |

An array of records rather than an object keyed by path, so the same file can appear as both
`present` and `removed` (a renamed symbol) and so `jq` can iterate it directly.

**When it is checked:**

| Moment | By | Against |
|---|---|---|
| the coder/tester stops | `subagent-integrity.sh` | the files on disk in the agent's worktree (`--ref worktree`) |
| `bd close` | `require-artifacts-block.sh` | the block parses and has the right shape |
| session end | `session-close-sweep.sh` | committed `HEAD` (`--ref HEAD`) |

The session-end check sees only committed work, which is why committing each task's work as soon as
its gates pass is a rule and not a suggestion: drop the commit rule and the sweep reports false gaps.

`bd-verify-artifacts.sh` is useful directly:

```
bd-verify-artifacts.sh                          # sweep every closed issue against HEAD
bd-verify-artifacts.sh <issue-id> ...           # specific issues, open or closed
bd-verify-artifacts.sh --ref <commit> ...       # against a specific commit
bd-verify-artifacts.sh --ref worktree ...       # against the files on disk
bd-verify-artifacts.sh --text-file <path>       # a block held in a file, e.g. a commit body
```

It answers one question: *did the named code land at all?* Not correctness (the auditor's job), not
authorship (a symbol that was already there passes). Paths are repo-relative and both backends anchor
to `git rev-parse --show-toplevel`, because a hook's working directory is not guaranteed to be the
repository root.

### Why JSON and not YAML

Measured, not assumed. Issue trackers reflow long lines when they render a description and strip
fence markers. Raw text round-trips intact through the JSON API, but anything reading rendered
output sees the reflowed form. A YAML wrapped scalar or block-sequence item then fails to parse; JSON,
however mangled, parses, and `jq -e` validates it instantly at close time.

# Tracker portability

`guard-bd.sh`, `require-artifacts-block.sh`, `bd-verify-artifacts.sh` and the issue-id discovery in
`subagent-integrity.sh` are an **adapter for the beads CLI**. The agent bodies say `bd` where a
command is needed. To adapt to another tracker: replace the calls that fetch an issue's reason and
notes, the close-command pattern in `if:`, the `bd` subcommand patterns in `guard-bd.sh`, and the
`.beads/` directory test in `policy-lib.sh`'s `tracker_active`. The artifacts schema, parsing and
verification logic are tracker-independent.

# Operating notes

- **Never use the replace form of a tracker field update** when an append form exists (enforced for
  notes). Replacing destroys another agent's findings.
- **Read an issue's raw fields, not its rendered output.** Renderers reflow text and insert blank
  lines; a parser built on rendered output breaks in ways that look like missing data.
- **Keep triple-backticks out of shell scripts.** A script containing one truncates any copy pasted
  out of a fenced document. The scripts build the fence at runtime.
- **The hook payload's `cwd` is the checkout the hooks reason about.** Commands of the form
  `git -C <elsewhere> ...` are only partially handled.
- **Guards match on the command with its prose removed.** Heredoc bodies and quoted strings are
  stripped before any rule is checked, so a commit message saying "clean up" or a bead note saying
  "avoided git stash" is not a `git clean` or a `git stash`. Double-quoted strings holding a `$(...)`
  are kept, since they are code. The accepted gap: a command hidden in a quoted string, such as
  `bash -c "git stash"`, passes. The commit-message and artifacts-block validators read the full text.
