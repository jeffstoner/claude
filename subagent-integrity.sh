#!/usr/bin/env bash
# ~/.claude/hooks/subagent-integrity.sh  start|stop
#
# Two checks on subagents, both keyed on the payload's agent_type:
#
# A. ARTIFACTS GATE (coder, tester) -- on stop, the agent must have recorded an
#    artifacts JSON block for its issue, and every claim in it must be true on
#    disk (bd-verify-artifacts.sh --ref worktree). Otherwise the stop is BLOCKED
#    with the reason, so the author fixes it while its context is intact. This
#    upgrades "a claim was written" to "the claim is true", and mechanizes the
#    tracking-off rule too: with no .beads/, the block is read from the last
#    commit's body. Claims are verified in the agent's OWN worktree (the payload's
#    cwd), never in another checkout. Escape hatch: a final message beginning "ESCALATION:" (the
#    10-attempt limit, a false premise, foreign uncommitted changes) passes.
#    stop_hook_active is honoured, so the gate blocks at most once.
#
# B. ZERO-DELTA WARNING (everything else) -- snapshot HEAD + `git status
#    --porcelain` at start, compare at stop; identical means the agent changed
#    nothing, and its success report needs verifying. Read-only agent types
#    (auditor, Explore, Plan, ...) are skipped: zero delta is their correct
#    behaviour, and warning on them was the documented false positive.
#
# Always exits 0 and never breaks a session.
#
# PAYLOAD FIELDS, confirmed by probe (2026-08-27, re-confirmed 2026-09-08):
#   SubagentStart: agent_id, agent_type, cwd, hook_event_name, prompt_id,
#                  session_id, transcript_path
#   SubagentStop:  the above + agent_transcript_path, last_assistant_message,
#                  permission_mode, stop_hook_active
# `agent_id` pairs START with STOP; `session_id` is shared by every subagent.
#
# KNOWN FALSE NEGATIVE (B): in a shared checkout a concurrent agent's changes mask
# this agent's inactivity. Reliable only with one worktree per agent.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/policy-lib.sh"

mode="${1:-stop}"
[ "${CLAUDE_SKIP_SUBAGENT_INTEGRITY:-0}" = "1" ] && exit 0

read_payload
[ -z "$payload" ] && exit 0
id="${agent_id:-unknown}"; atype="${agent_type:-unknown}"
last="$(printf '%s' "$payload" | jq -r '.last_assistant_message // ""' 2>/dev/null | tr '\n' ' ' | cut -c1-240)"

case "$atype" in auditor|Explore|Plan|claude-code-guide|statusline-setup) exit 0 ;; esac

in_repo || exit 0
root="$(repo_root)" || exit 0

dir="${TMPDIR:-/tmp}/claude-subagent-integrity"
mkdir -p "$dir" 2>/dev/null || exit 0
key="$(printf '%s|%s' "$root" "$id" | sha256sum | cut -c1-32)"
f="$dir/$key"

snapshot() {
  printf '%s %s' "$(git -C "$root" rev-parse HEAD 2>/dev/null || echo none)" \
    "$(git -C "$root" status --porcelain 2>/dev/null | sha256sum | cut -d' ' -f1)"
}
block_stop() {
  jq -nc --arg r "$1" '{decision:"block", reason:$r}'
  exit 0
}

# ---- A. artifacts gate ----------------------------------------------------------
artifacts_gate() {
  case "$atype" in coder|tester) ;; *) return 0 ;; esac
  [ "$(printf '%s' "$payload" | jq -r '.stop_hook_active // false')" = "true" ] && return 0
  printf '%s' "$last" | grep -qE '^[[:space:]]*ESCALATION:' && return 0
  verifier="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/bd-verify-artifacts.sh"
  [ -x "$verifier" ] || return 0

  # Which checkout? The agent's own. The payload's cwd IS the agent's worktree
  # (.claude/worktrees/agent-<agent_id> under isolation: worktree, confirmed by probe
  # 2026-09-10), and $root is that worktree's top level. Never go looking in other
  # worktrees: the main checkout may carry a commit scoped to the same issue (the
  # orchestrator recording a learnings entry for it), and verifying there reported
  # true claims as MISSING.
  wt="$root"
  # Which issue? Most-used bead id in the agent's own transcript, else the scope of
  # the worktree's last commit (type(id): ...). The harness-generated branch name
  # carries no id.
  transcript="$(printf '%s' "$payload" | jq -r '.agent_transcript_path // ""')"
  issue=""
  if [ -r "$transcript" ]; then
    issue="$(grep -oE 'bd (show|update|close) +[A-Za-z][A-Za-z0-9]*-[0-9A-Za-z.]+' "$transcript" 2>/dev/null \
      | awk '{print $3}' | sort | uniq -c | sort -rn | head -1 | awk '{print $2}')"
  fi
  if [ -z "$issue" ]; then
    issue="$(git -C "$wt" log -1 --format=%s 2>/dev/null | sed -nE 's/^[a-z]+\(([^)]+)\)!?:.*/\1/p')"
    [ "$issue" = "NOTICKET" ] && issue=""
  fi

  if [ -d "$root/.beads" ] && ! policy_has "no issue tracker"; then
    if [ -z "$issue" ]; then
      block_stop "STOP BLOCKED ($atype): could not determine which issue you worked on. Run 'bd show <id>' for your issue, then 'bd update <id> --append-notes \"\$(cat <path>)\"' with a description of the work for human review ending in the fenced json artifacts block, then stop. If you are stopping WITHOUT completing the task, begin your final message with 'ESCALATION:' and say why."
    fi
    out="$(cd "$wt" && "$verifier" --ref worktree "$issue" 2>&1)"; rc=$?
    where="issue $issue's notes"
  else
    body="$(git -C "$wt" log -1 --format=%B 2>/dev/null)"
    tmp="$(mktemp "${TMPDIR:-/tmp}/claude-artifacts.XXXXXX")"; printf '%s\n' "$body" > "$tmp"
    out="$(cd "$wt" && "$verifier" --ref worktree --text-file "$tmp" 2>&1)"; rc=$?
    rm -f "$tmp"
    where="the last commit's message body (issue tracking is off, so the block lives there)"
  fi

  if printf '%s' "$out" | grep -qE 'no issues found|not a git repo|jq required'; then
    block_stop "STOP BLOCKED ($atype): could not read issue $issue from the tracker to verify your artifacts block ($out). Confirm the issue id, make sure 'bd show $issue' works from your worktree, and that your notes carry the artifacts block. If stopping without completing, begin your final message with 'ESCALATION:'."
  fi
  if printf '%s' "$out" | grep -qE '(^| )[1-9][0-9]* without a block'; then
    block_stop "STOP BLOCKED ($atype): no artifacts block found in $where. Before stopping, record a description of the work for human review ending in a fenced json block:
{\"artifacts\":[{\"path\":\"<repo-relative>\",\"symbols\":[\"<greppable token>\"]},{\"path\":\"<test file>\",\"symbols\":[]}]}
(symbols defaults to [] = file exists; state \"removed\" asserts deletion.) With beads: 'bd update <id> --append-notes \"\$(cat <path>)\"' (never --notes). Without beads: put it in the commit body and amend on your task branch. If you are stopping WITHOUT completing the task, begin your final message with 'ESCALATION:' and say why."
  fi
  if [ "$rc" -ne 0 ]; then
    block_stop "STOP BLOCKED ($atype): the artifacts block in $where claims code that is not on disk:
$out
Either the work is not there (check 'git status', commit it) or the claim is wrong (correct the block). Every block in the notes is checked and the last record for a path+symbol wins: if an earlier block's claim is stale because you renamed or dropped that symbol, append a new block with {\"path\":..., \"symbols\":[\"<old>\"], \"state\":\"removed\"}; never rewrite the earlier one. Fix it now, while you still know which. If stopping without completing, begin your final message with 'ESCALATION:'."
  fi
  return 0
}

case "$mode" in
  start)
    snapshot > "$f" 2>/dev/null
    exit 0 ;;
  stop)
    artifacts_gate
    # ---- B. zero-delta warning ----
    [ -f "$f" ] || exit 0                # no baseline (hook added mid-session) -> quiet
    before="$(cat "$f" 2>/dev/null)"; after="$(snapshot)"; rm -f "$f" 2>/dev/null
    [ "$before" = "$after" ] || exit 0   # something changed -> nothing to say
    if [ "${CLAUDE_SUBAGENT_INTEGRITY_TRUST_DISCLAIMERS:-0}" = "1" ] \
       && printf '%s' "$last" | grep -qiE 'no (files|changes|repo|repository|code) (were |was )?(modified|changed|touched)|read-only|report only|made no changes'; then
      exit 0
    fi
    jq -nc --arg id "$id" --arg atype "$atype" --arg root "$root" --arg last "$last" '{
      systemMessage: ("⚠ Subagent " + $id + " (" + $atype
        + ") stopped with ZERO repository delta in " + $root
        + " -- no commit, no working-tree change, no new untracked file.
Its final message began: \"" + $last + "\"
If that was a read-only task this is expected. If it claims to have done work, VERIFY BEFORE TRUSTING IT: grep for the symbols its report names. An agent that reports work it did not do is the signature of work lost to a bad tree operation, or of a report that was never grounded in the code."),
      suppressOutput: true }'
    exit 0 ;;
  *) exit 0 ;;
esac
