# Installation

These instructions assume a **global** install under `~/.claude/`, so everything applies to every
project. If you install elsewhere, adjust every path below and in the `settings.json` block; nothing
resolves paths dynamically except the hook scripts finding each other (they source `policy-lib.sh`
and call `bd-verify-artifacts.sh` from their own directory, so keep them together).

For what these components do and why, see `README.md`.

## Prerequisites

| Requirement | Used by | Notes |
|---|---|---|
| `bash` | all hooks | Scripts use `bash` arrays and `mapfile`. |
| `git` | most hooks | Hooks exit 0 silently outside a git work tree. |
| `jq` | all hooks | Parses the hook payload and builds the JSON responses. |
| An issue-tracker CLI (`bd`) | `guard-bd.sh`, `require-artifacts-block.sh`, `bd-verify-artifacts.sh`, `subagent-integrity.sh` | These are an **adapter for beads**. See "Tracker portability" in `README.md`. |
| Claude Code ≥ 2.1 | agents, rules, `--agent` | Custom agents with frontmatter `hooks`, `~/.claude/rules/` with `paths:`, `claude --agent`. |

## 1. Layout

```
~/.claude/CLAUDE.md                       the only always-loaded instruction file
~/.claude/agents/orchestrator.md
~/.claude/agents/coder.md
~/.claude/agents/tester.md
~/.claude/agents/auditor.md
~/.claude/rules/learnings.md              path-scoped: loads only when touching learnings/**
~/.claude/skills/git-recovery/SKILL.md    on demand
~/.claude/skills/worktree-setup/SKILL.md  on demand
~/.claude/skills/verify-artifacts/SKILL.md on demand
~/.claude/hooks/policy-lib.sh             sourced by every hook; not a hook itself
~/.claude/hooks/guard-git.sh
~/.claude/hooks/guard-bd.sh
~/.claude/hooks/guard-edit.sh
~/.claude/hooks/guard-dispatch.sh
~/.claude/hooks/require-artifacts-block.sh
~/.claude/hooks/subagent-integrity.sh
~/.claude/hooks/learnings-context.sh
~/.claude/hooks/post-merge-status.sh
~/.claude/hooks/bd-verify-artifacts.sh    CLI, called by the merge prompt, the stop gate and the skill
```

**Warning:** the `cp CLAUDE.md` line below **overwrites** any existing `~/.claude/CLAUDE.md` without
prompting. If you already have one, back it up first and merge your content into the new file
afterwards:

```bash
[ -f ~/.claude/CLAUDE.md ] && cp ~/.claude/CLAUDE.md ~/.claude/CLAUDE.md.bak
```

From the repo root:

```bash
mkdir -p ~/.claude/agents ~/.claude/rules ~/.claude/skills ~/.claude/hooks
cp CLAUDE.md ~/.claude/CLAUDE.md
cp agents/*.md ~/.claude/agents/
cp rules/*.md ~/.claude/rules/
cp -r skills/git-recovery skills/worktree-setup skills/verify-artifacts ~/.claude/skills/
cp *.sh ~/.claude/hooks/
```

**Upgrading from the previous layout** (`~/.claude/CLAUDE-*.md` rule files): remove them. Their
content now lives in the agent bodies, the hook messages, the rule file and the skills. Leaving them
in place costs nothing at runtime (nothing imports them) but invites confusion.

```bash
rm -f ~/.claude/CLAUDE-{BEADS,CODE-FLOW,CONVENTIONAL-COMMITS,GIT,LEARNINGS,ORCHESTRATOR}.md
```

## 2. Make the hooks executable — this step is not optional

```bash
chmod +x ~/.claude/hooks/*.sh
ls -l ~/.claude/hooks/*.sh
```

A non-executable `PreToolUse` hook errors instead of guarding, and an erroring hook does not deny.
`guard-git.sh` (the merge-prompt sweep) and `subagent-integrity.sh` guard on
`[ -x bd-verify-artifacts.sh ]` and silently skip the check if it is not executable.

## 3. Merge the hook registrations into `~/.claude/settings.json`

**Merge, do not replace.** Preserve your other keys and any existing `hooks` entries. A malformed
`settings.json` silently disables every setting in that file, so validate afterwards (step 5).

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "if": "Bash(git *)", "command": "~/.claude/hooks/guard-git.sh", "timeout": 10, "statusMessage": "Checking git rules" },
          { "type": "command", "if": "Bash(bd *)", "command": "~/.claude/hooks/guard-bd.sh", "timeout": 10, "statusMessage": "Checking tracker rules" },
          { "type": "command", "if": "Bash(bd close *)", "command": "~/.claude/hooks/require-artifacts-block.sh", "timeout": 10, "statusMessage": "Checking close-reason artifacts" }
        ]
      },
      {
        "matcher": "Edit|Write|NotebookEdit|MultiEdit",
        "hooks": [
          { "type": "command", "command": "~/.claude/hooks/guard-edit.sh", "timeout": 10 }
        ]
      },
      {
        "matcher": "Agent|TodoWrite|TaskCreate|TaskUpdate",
        "hooks": [
          { "type": "command", "command": "~/.claude/hooks/guard-dispatch.sh", "timeout": 10 }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "if": "Bash(git merge *)", "command": "~/.claude/hooks/post-merge-status.sh", "timeout": 10 }
        ]
      }
    ],
    "PostToolUseFailure": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "~/.claude/hooks/learnings-context.sh PostToolUseFailure", "timeout": 10 }
        ]
      }
    ],
    "SessionStart": [
      {
        "hooks": [
          { "type": "command", "command": "~/.claude/hooks/learnings-context.sh SessionStart", "timeout": 10 }
        ]
      }
    ],
    "SubagentStart": [
      {
        "hooks": [
          { "type": "command", "command": "~/.claude/hooks/subagent-integrity.sh start", "timeout": 10 },
          { "type": "command", "command": "~/.claude/hooks/learnings-context.sh SubagentStart", "timeout": 10 }
        ]
      }
    ],
    "SubagentStop": [
      {
        "hooks": [
          { "type": "command", "command": "~/.claude/hooks/subagent-integrity.sh stop", "timeout": 60 }
        ]
      }
    ]
  },
  "worktree": {
    "baseRef": "head",
    "symlinkDirectories": ["node_modules", ".venv"]
  }
}
```

Notes:

- **`matcher`** applies to tool events only. `SessionStart`, `SubagentStart` and `SubagentStop`
  take none.
- **`if:`** uses permission-rule syntax and matches each subcommand of a compound command
  (`cd x && git merge y` matches `Bash(git *)`). It is an optimisation; each script re-checks its
  own input.
- **`if: "Bash(bd *)"`** and **`Bash(bd close *)`** are tracker-specific; see "Tracker portability" in
  `README.md`.
- The **agent-scoped** hooks (the coder/tester path split, the auditor's write-deny) are declared in
  the agent files' frontmatter and need no registration here.
- **`worktree.baseRef: "head"`** matters. The default (`fresh`) branches a new worktree from
  `origin/<default-branch>`, silently omitting local commits.
- **`worktree.symlinkDirectories`**: whether nested paths such as `api/.venv` are honoured is
  unverified.

## 4. Start orchestrated sessions as the orchestrator

The orchestrator's rules live in its agent body, which becomes the main session's system prompt and
therefore survives context compaction. Two ways:

```bash
claude --agent orchestrator
```

or, per project, `"agent": "orchestrator"` in the project's `.claude/settings.json`. A plain session
still has every global hook; it simply lacks the orchestration judgement rules and cannot dispatch
the role agents' restrictions on itself.

## 5. Verify the install

```bash
# a. Syntax and permissions
for f in ~/.claude/hooks/*.sh; do bash -n "$f" && echo "OK $f"; done
ls -l ~/.claude/hooks/*.sh

# b. settings.json is valid and the hooks are registered
jq -e '.hooks.PreToolUse[].hooks[].command' ~/.claude/settings.json
jq -e '.hooks.SubagentStop[].hooks[].command' ~/.claude/settings.json

# c. The guards decide correctly when piped by hand
echo '{"tool_input":{"command":"git stash"},"cwd":"'"$PWD"'"}' | ~/.claude/hooks/guard-git.sh   # -> deny JSON
echo '{"tool_input":{"command":"git status -s"},"cwd":"'"$PWD"'"}' | ~/.claude/hooks/guard-git.sh # -> no output
echo '{"tool_input":{"command":"bd update x --notes y"}}' | ~/.claude/hooks/guard-bd.sh          # -> deny JSON

# d. The full hook test suite (from this repo)
bash tests/hooks.sh
```

Then prove the hooks fire in a session: run a harmless `git status` (the guard is consulted), try
`git commit` on your default branch (denied with the rule), and confirm `/agents` lists
`orchestrator`, `coder`, `tester` and `auditor`.

**If a hook does not fire** but the script works when piped by hand and `jq -e` passes, the settings
watcher has not picked up the change. Open `/hooks` once to reload, or restart the session.

## 6. bd-board

Copy `bd-board` into a directory on your PATH, such as `~/.local/bin`. Requires Python 3. Skip if
you are not using `beads`.

## 7. PRIME.md

`PRIME.md` overrides `bd prime`'s output, whose default text contradicts this workflow in places.
Copy it to the `.beads` directory of each repo that uses beads. Skip otherwise.

## 8. Disabling

- **Per hook**: remove its entry from `~/.claude/settings.json`.
- **All hooks**: `"disableAllHooks": true`.
- **Per project**: the policy lines in the project `CLAUDE.md` (see `README.md`): `Default branch:`,
  `Policy: commit-on-default allowed`, `Policy: merge-to-default allowed`,
  `Policy: todo-comments allowed`, `Policy: no issue tracker`, `Test-paths:`.
- **Subagent integrity only, without editing settings**:
  - `CLAUDE_SKIP_SUBAGENT_INTEGRITY=1` silences both the zero-delta warning and the artifacts gate.
  - `CLAUDE_SUBAGENT_INTEGRITY_TRUST_DISCLAIMERS=1` stays quiet when an agent explicitly reports
    that it changed nothing.
