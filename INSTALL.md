# Installation

These instructions assume a **global** install: the instruction files land in `~/.claude/` and the
hook scripts in `~/.claude/hooks/`, so they apply to every project. If you install them elsewhere —
per-project, or under a different config root — every path in this document and in the
`settings.json` block below must be adjusted accordingly. That is your responsibility; nothing here
resolves paths dynamically.

For what these components do and why they are built this way, see `README.md`.

## Prerequisites

| Requirement | Used by | Notes |
|---|---|---|
| `bash` | all hooks | Scripts use `bash`-specific syntax (`mapfile`, `[[`-free but arrays). |
| `git` | `guard-git.sh`, `subagent-integrity.sh`, `bd-verify-artifacts.sh` | Hooks exit 0 silently outside a git work tree. |
| `jq` | all hooks | Parses the hook payload on stdin and builds the JSON responses. |
| An issue-tracker CLI | `require-artifacts-block.sh`, `bd-verify-artifacts.sh` | These two are an **adapter for one specific tracker**. See "Tracker portability" in `README.md` before installing them against a different tracker. |

## 1. Place the instruction files

```
~/.claude/CLAUDE.md
~/.claude/CLAUDE-CODE-FLOW.md
~/.claude/CLAUDE-GIT.md
~/.claude/CLAUDE-ORCHESTRATOR.md
~/.claude/CLAUDE-LEARNINGS.md
~/.claude/CLAUDE-CONVENTIONAL-COMMITS.md
```

`~/.claude/CLAUDE.md` is the entry point and references the others by absolute-ish path
(`~/.claude/CLAUDE-*.md`). If you rename or relocate any of them, update those references — a bare
filename is ambiguous once an agent is working inside a project that has files of its own.

## 2. Place the hook scripts

```
~/.claude/hooks/guard-git.sh
~/.claude/hooks/require-artifacts-block.sh
~/.claude/hooks/subagent-integrity.sh
~/.claude/hooks/session-close-sweep.sh
~/.claude/hooks/bd-verify-artifacts.sh
```

## 3. Make them executable — this step is not optional

```bash
chmod +x ~/.claude/hooks/*.sh
ls -l ~/.claude/hooks/*.sh    # confirm the x bit on all five
```

**Why this matters more than it looks.** `session-close-sweep.sh` guards on
`[ -x "$verifier" ] || exit 0`. If `bd-verify-artifacts.sh` is not executable, the session-end sweep
exits 0 and does nothing at all — it looks installed, reports no problems, and never checks
anything. The hooks invoked directly from `settings.json` fail in a similarly quiet way: a
non-executable script errors instead of guarding, and a `PreToolUse` hook that errors does not deny.

## 4. Merge the hook registrations into `~/.claude/settings.json`

**Merge — do not replace.** Your existing file has other keys, and an existing `hooks` object may
already have entries. Preserve them; add to the arrays rather than overwriting them. A malformed
`settings.json` **silently disables every setting in that file**, so validate afterwards (step 5).

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
          },
          {
            "type": "command",
            "if": "Bash(bd close *)",
            "command": "~/.claude/hooks/require-artifacts-block.sh",
            "timeout": 10,
            "statusMessage": "Checking close-reason artifacts"
          }
        ]
      }
    ],
    "SubagentStart": [
      {
        "hooks": [
          { "type": "command", "command": "~/.claude/hooks/subagent-integrity.sh start", "timeout": 10 }
        ]
      }
    ],
    "SubagentStop": [
      {
        "hooks": [
          { "type": "command", "command": "~/.claude/hooks/subagent-integrity.sh stop", "timeout": 10 }
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          { "type": "command", "command": "~/.claude/hooks/session-close-sweep.sh", "timeout": 60 }
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

Notes on the above:

- **`matcher`** applies to tool events only. `SubagentStart`, `SubagentStop` and `SessionEnd` are not
  tool events, so they take no matcher.
- **`if:`** uses permission-rule syntax to avoid spawning a hook for commands it does not care about.
  It is an optimisation, not the guard — each script re-checks its own input.
- **`if: "Bash(bd close *)"`** is tracker-specific. Change `bd close` to whatever your tracker's
  close command is, and see "Tracker portability" in `README.md`.
- **Denials must use `hookSpecificOutput.permissionDecision`.** The scripts already do. The older
  `decision: "block"` form is deprecated for `PreToolUse` and will not reliably block.
- **`worktree.baseRef: "head"`** matters. The default (`fresh`) branches a new worktree from
  `origin/<default-branch>`, silently omitting local commits — the wrong base for this workflow.
- **`worktree.symlinkDirectories`** avoids giving every worktree its own dependency tree. Bare
  directory names such as `node_modules` and `.venv` match the documented form. Whether a **nested**
  path such as `api/.venv` is honoured is **unverified** — test it before relying on it, and if it is
  not, fall back to invoking the main checkout's interpreter by absolute path with the worktree as
  the working directory, which is verified to work.

## 5. Verify the install

```bash
# a. Syntax and permissions
for f in ~/.claude/hooks/*.sh; do bash -n "$f" && echo "OK $f"; done
ls -l ~/.claude/hooks/*.sh

# b. settings.json is valid and the hooks are registered
jq -e '.hooks.PreToolUse[].hooks[].command' ~/.claude/settings.json
jq -e '.hooks.SessionEnd[].hooks[].command'  ~/.claude/settings.json

# c. The git guard denies a dangerous command and allows a safe one
echo '{"tool_input":{"command":"git stash"}}'      | ~/.claude/hooks/guard-git.sh   # -> deny JSON
echo '{"tool_input":{"command":"git status -s"}}'  | ~/.claude/hooks/guard-git.sh   # -> no output

# d. The verifier runs (from inside any git repo)
~/.claude/hooks/bd-verify-artifacts.sh --ref HEAD
```

Then prove the hooks actually fire in a session: run a harmless `git status` (the guard should be
consulted) and attempt a close without an artifacts block (it should be denied).

**If a hook does not fire** but the script works when piped by hand and `jq -e` passes, the settings
watcher has not picked up the change — it only watches directories that already had a settings file
when the session started. Open `/hooks` once to reload, or restart the session.

## 6. Disabling

- **Per hook**: remove its entry from `~/.claude/settings.json`.
- **All hooks**: `"disableAllHooks": true`.
- **Subagent integrity only, without editing settings**:
  - `CLAUDE_SKIP_SUBAGENT_INTEGRITY=1` — silences it entirely.
  - `CLAUDE_SUBAGENT_INTEGRITY_TRUST_DISCLAIMERS=1` — stays quiet when an agent explicitly reports
    that it changed nothing (useful once read-only agents make the warning noisy).
