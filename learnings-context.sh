#!/usr/bin/env bash
# ~/.claude/hooks/learnings-context.sh  SessionStart|SubagentStart|PostToolUseFailure
#
# Puts the project's `learnings/` directory in front of the agent at the moments
# the protocol says to consult it, without any agent having to remember to:
#
#   SessionStart (startup|resume|clear|compact)  -> protocol + file list. The
#       `compact` source matters: this is what survives context compaction.
#   SubagentStart                                -> same, for every subagent.
#   PostToolUseFailure (Bash)                    -> "grep learnings first", rate-
#       limited to once per 10 minutes per session, because this event fires on
#       EVERY non-zero exit (confirmed by probe 2026-09-08), including grep's 1.
#
# Silent when the project has no learnings/ directory. Always exits 0.
# additionalContext on SessionStart and SubagentStart confirmed by probe 2026-09-08.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/policy-lib.sh"

event="${1:-SessionStart}"
read_payload
root="$(repo_root || printf '%s' "$cwd")"
[ -d "$root/learnings" ] || exit 0

n="$(find "$root/learnings" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
[ "$n" -gt 0 ] || exit 0

case "$event" in
  SessionStart|SubagentStart)
    list="$(cd "$root/learnings" && ls -1 *.md 2>/dev/null | head -40 | sed 's/^/  - /')"
    [ "$n" -gt 40 ] && list="$list
  ... and $((n-40)) more (ls learnings/)"
    add_context "$event" "LEARNINGS: this project has $n recorded failure/fix entries in learnings/. Before working on a subsystem, and again when a test/build fails unexpectedly or you are choosing between two approaches, search them first: grep -ril \"<keyword>\" learnings/ — apply a matching fix (or say why it does not apply) before re-deriving one. After resolving a NOVEL failure that a future agent would waste real time on (environment quirk, version mismatch, silent failure mode — not a typo), add learnings/<issue-id>-<slug>.md; the entry format loads automatically when you write there.
$list"
    ;;
  PostToolUseFailure)
    sid="$(printf '%s' "$payload" | jq -r '.session_id // "nosession"' 2>/dev/null)"
    stamp="${TMPDIR:-/tmp}/claude-learnings-nudge-$(printf '%s' "$root|$sid" | sha256sum | cut -c1-16)"
    if [ -f "$stamp" ] && [ -n "$(find "$stamp" -mmin -10 2>/dev/null)" ]; then exit 0; fi
    touch "$stamp" 2>/dev/null
    add_context "$event" "A command failed. Before debugging from scratch: grep -ril \"<error keyword>\" learnings/ — this project has $n recorded failures with fixes, and the same error is never debugged twice."
    ;;
esac
exit 0
