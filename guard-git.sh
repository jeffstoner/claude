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
  deny "BLOCKED: 'git stash' is banned in a shared checkout — it is a whole-tree operation that silently sweeps up every concurrent agent's uncommitted work. To answer 'is this failure pre-existing?' use the read-only baseline worktree or 'git show HEAD:<path>'. To shelve work, commit it to a branch."
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
