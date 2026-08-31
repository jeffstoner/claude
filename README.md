# Agent instruction set + enforcement hooks

A set of instruction files that shape how coding agents work, plus five hooks that enforce the rules
the instructions cannot be trusted to hold on their own.

For installation, see `INSTALL.md`.

## What problem this solves

Two failure modes, both specific to running several agents against one repository:

1. **One agent destroys another's uncommitted work.** Whole-tree git operations — `git stash`,
   `git reset --hard`, `git clean`, `git checkout -- <path>` — do not respect the notion that
   different parts of the working tree belong to different agents. A stash with no pathspec captures
   everyone's changes; an incomplete restore discards them with no error and no trace in `git log`.
   The tree simply moves backwards, and the agents that were mid-task have no way to notice.

2. **A closed issue describes code that is not in the repository.** An agent reports success, writes
   a detailed close-reason naming the functions it added, and the code is not there — lost to the
   first failure mode, or never written. Because the close-reason reads as evidence, the gap
   propagates: later issues get filed against the phantom code, and a test written to cover it
   "fixes" something that was never broken.

Neither is caught by tests. Both are cheap to catch mechanically.

## Design principles

- **Instructions are advisory; hooks are enforcement.** A rule that must not break under pressure
  belongs in a hook, not only in a markdown file. Agents comply with instructions most of the time,
  which is precisely why the exceptions are expensive.
- **A hook blocks the model, never the user.** You can always run the same command yourself. So an
  over-blocking hook costs one round trip, while a missing hook can cost a day's work — err toward
  over-blocking.
- **Every hook exits 0.** A hook that can break a session is worse than the problem it guards.
  Denials are expressed as JSON on stdout, not as a non-zero exit.
- **Fail loudly, never silently.** A check that passes when it cannot actually verify anything is
  worse than no check: it manufactures confidence. Where a script cannot tell "nothing to verify"
  from "verification impossible", it reports the difference.

## Components and wiring

`bd-verify-artifacts.sh` is **not** a hook. It is a command-line tool, invoked by the session-end
sweep or run by hand.

| Script | Invoked by | When |
|---|---|---|
| `bd-board` | not a hook - called manually | - |
| `guard-git.sh` | `PreToolUse`, `if: Bash(git *)` | before every git command |
| `require-artifacts-block.sh` | `PreToolUse`, `if: Bash(<tracker> close *)` | before every issue close |
| `subagent-integrity.sh start` | `SubagentStart` | a subagent begins |
| `subagent-integrity.sh stop` | `SubagentStop` | a subagent ends |
| `session-close-sweep.sh` | `SessionEnd` | the session ends |
| `bd-verify-artifacts.sh` | not a hook - called by the sweep, or manually | - |

### `bd-board`

`bd-board` is a CLI that reports which beads are ready to be worked, separating them into 4 buckets:
* READY NOW - this bucket of beads are not blocked and can be worked on immediately.
* IN FLIGHT - this bucket of beads shows which beads are actively being worked (marked as "in_progress").
* READY NEXT - this bucket of beads shows which could (logically) be worked next. They are often blocked by the beads in "READY NOW".
* NEEDS REVIEW - this bucket of beads identifies beads that require a human to review and either accept or decline them.

Each bucket groups the beads under their respective epics/milestones for clarity.

### `guard-git.sh`

Denies the git operations that can erase a peer's uncommitted work: any `stash`; `checkout`/`restore`
with a pathspec; `reset --hard`/`--merge`/`--keep`; `clean`; `push`/`pull`; and `--force` on anything
except `worktree`. Every denial explains the safe alternative — read committed content with
`git show HEAD:<path>`, use the read-only baseline worktree, or commit to a branch to shelve work.

Known trade-off: subcommands are matched as whole words anywhere in the command, so
`git log --grep stash` is denied too. That is deliberate. Over-blocking costs a rephrase.

### `require-artifacts-block.sh`

Refuses to close an issue whose reason does not carry a valid artifacts block (below). It **parses**
the block rather than grepping for a marker, so a malformed block is caught at close time, while the
author is still around to fix it. Commands that defer the reason to a file are allowed through and
left to the session-end sweep.

### `subagent-integrity.sh`

Snapshots the repository (`HEAD` plus a hash of `git status --porcelain`, which includes untracked
files) when a subagent starts, and compares on stop. Zero delta — no commit, no working-tree change,
no new file — emits a warning quoting the agent's own closing message, so you can tell an honest
read-only agent from a broken one at a glance.

Two limitations, both real:

- **False positives on read-only agents.** Audits, reviews and research agents are *supposed* to
  change nothing. The warning is therefore phrased as "verify the claim", not "the agent failed", and
  quotes the agent's own words. `CLAUDE_SUBAGENT_INTEGRITY_TRUST_DISCLAIMERS=1` suppresses the
  warning when an agent explicitly says it changed nothing.
- **False negatives in a shared checkout.** `git status` is tree-wide, so if agent A changes nothing
  while agent B edits a file, A's check goes silent — B's change masks A's inactivity. **This check
  is only reliable when each agent has its own worktree**, or when agents run one at a time. That is
  an independent argument for per-agent worktrees: without them, even the safety net is unreliable.

### `session-close-sweep.sh` and `bd-verify-artifacts.sh`

At session end, every closed issue's claimed artifacts are checked against the repository. Silent
when everything is present; emits a warning listing the gaps when it is not.

`bd-verify-artifacts.sh` does the work and is useful directly:

```
bd-verify-artifacts.sh                        # sweep every closed issue
bd-verify-artifacts.sh <issue-id> ...         # check specific issues, open or closed
bd-verify-artifacts.sh --ref <commit> ...     # check against a specific commit
bd-verify-artifacts.sh --ref worktree ...     # check the files on disk instead
```

**Scope.** It answers exactly one question: *did the named code land at all?* It does not check
correctness, and it does not check authorship — a symbol that was already there passes. That is the
right trade: "vanished entirely" is the failure mode a human or an auditing agent is expensive at
catching and a grep is free at catching. Correctness is the auditing agent's job.

It reports three outcomes distinctly, which matters: claims verified, claims **missing**, and blocks
that are present but **malformed**. A malformed block read as "no block" would let a broken
close-reason pass as clean.

## Two constraints worth understanding before you rely on it

### Committed vs working tree

`--ref <commit>` uses `git cat-file` and `git grep`, so it **cannot see uncommitted work**. A symbol
sitting in the working tree but not yet committed is reported as missing.

- At session end this is correct, **because** `~/.claude/CLAUDE-GIT.md` requires committing each
  task's work as soon as its gates pass. The two halves depend on each other: drop the commit rule
  and the sweep starts reporting false gaps.
- Wiring the verifier to `SubagentStop` with `--ref HEAD` would therefore be **wrong** — mid-session
  work is usually uncommitted, so every successful agent would be flagged. Use `--ref worktree`
  there.
- `--ref worktree` checks the filesystem. It is not merely permissive: a claim whose symbol is absent
  from the file on disk still fails.

### Paths are repo-relative; cwd is not

Artifacts paths are repo-relative, but `git grep` resolves a pathspec against the **caller's** working
directory. Run from a subdirectory, a naive implementation reports every claim as missing — which
looks exactly like real data loss. Both backends therefore anchor to
`git rev-parse --show-toplevel`. This is not hypothetical: a hook's working directory is not
guaranteed to be the repository root.

## The artifacts block

Every close-reason ends with a fenced `json` block. This is what makes the mechanical check possible
— a prose close-reason cannot be verified.

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
| `symbols` | no | `[]` | any greppable token: function or class names, a response field, an error slug, a migration revision. Empty asserts only that the file exists. |
| `state` | no | `"present"` | `"removed"` asserts deletion, so refactors and deletions are checkable in the same pass |

An array of records rather than an object keyed by path, so the same file can appear as both
`present` and `removed` — a renamed symbol — and so `jq` can iterate it directly.

### Why JSON and not YAML

Measured, not assumed. Issue trackers reflow long lines when they render a description, and they
strip fence markers. Raw text round-trips intact through a tracker's JSON API, so the machine path is
safe either way — but anything reading rendered output, including a human, sees the reflowed form:

| format, after reflow | result |
|---|---|
| YAML flow sequence `symbols: [a, b]` | parses |
| YAML wrapped scalar (a long path or note) | **parse error** |
| YAML wrapped block-sequence item | **parse error** |
| JSON, however mangled | parses |

YAML is only *conditionally* safe — safe as long as no scalar ever grows long enough to wrap, which
is not a constraint a template can enforce. JSON is whitespace-insensitive and immune. It is also
instantly validatable with `jq -e`, which is what lets the close-time gate reject a malformed block
instead of discovering it later.

## Tracker portability

`require-artifacts-block.sh` and `bd-verify-artifacts.sh` are an **adapter for one specific tracker
CLI**. They shell out to it to read an issue's close-reason and notes, and the close gate matches
that CLI's close command.

The instruction files are deliberately tracker-agnostic — they say "issue" and "issue tracker"
throughout. A separate instruction set names the tracker actually in use. To adapt these two hooks
to a different tracker, replace the calls that fetch an issue's reason/notes text and the
close-command pattern in `if:`; the artifacts schema, the parsing, and the verification logic are
tracker-independent.

## Operating notes

- **Never use the replace form of a tracker field update** when an append form exists. Replacing
  notes destroys another agent's findings — the same class of loss as a bad stash, in the tracker
  instead of the tree.
- **Read an issue's raw fields, not its rendered output.** Renderers reflow text, convert bullet
  characters, and insert blank lines after headers; a parser built on rendered output breaks in ways
  that look like missing data.
- **Keep triple-backticks out of shell scripts.** A script containing one truncates any copy pasted
  out of a fenced document — silently, into something that still passes a syntax check. The scripts
  here build the fence at runtime instead.
