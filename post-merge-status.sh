#!/usr/bin/env bash
# ~/.claude/hooks/post-merge-status.sh
# PostToolUse(Bash), if: Bash(git merge *)
#
# After a merge, report untracked files in the checkout. An unexpected `??` is a
# candidate stray from a subagent that operated outside its worktree, or the
# user's in-progress work -- investigate before calling the merge done, prefer a
# reversible removal, never `git clean`. Silent when there are none.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/policy-lib.sh"

read_payload
[ -z "$cmd" ] && exit 0
printf '%s' "$cmd" | grep -qE '(^|[[:space:]])merge([[:space:]]|$)' || exit 0
printf '%s' "$cmd" | grep -qE -- '--abort' && exit 0
in_repo || exit 0

strays="$(git -C "$cwd" status --short 2>/dev/null | grep '^??' || true)"
[ -z "$strays" ] && exit 0

add_context "PostToolUse" "POST-MERGE CHECK — untracked files present in the checkout after the merge:
$strays
Anything you did not expect is a candidate stray file from a subagent that operated outside its worktree, or the user's own work in progress. Investigate before considering the merge done. If it is genuinely inert junk, remove it reversibly (move it aside, or 'rm' the single file) — never 'git clean'. If its provenance is unclear, ask the user."
exit 0
