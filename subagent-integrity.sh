#!/usr/bin/env bash
# ~/.claude/hooks/subagent-integrity.sh  start|stop
#
# Early warning for a specific failure: a subagent reports success while having
# changed nothing in the repository.
#
#   SubagentStart -> snapshot (HEAD sha + hash of `git status --porcelain`)
#   SubagentStop  -> re-snapshot; if identical, emit a systemMessage carrying the
#                    agent's own final message so the orchestrator can judge at a
#                    glance whether the claim needs verifying.
#
# Always exits 0 and never blocks. A hook that can break a session is worse than
# the problem it guards.
#
# PAYLOAD FIELDS, confirmed by probe 2026-08-27 (not guessed):
#   SubagentStart: agent_id, agent_type, cwd, hook_event_name, prompt_id,
#                  session_id, transcript_path
#   SubagentStop:  the above + agent_transcript_path, background_tasks,
#                  last_assistant_message, permission_mode, session_crons,
#                  stop_hook_active
# `agent_id` is identical across START and STOP for a given subagent, so it is the
# pairing key. `session_id` is shared by EVERY subagent and must not be used.
#
# KNOWN FALSE POSITIVE: read-only agents (audits, reviews, forensics) are supposed
# to produce no delta. The message is phrased as "verify", not "failed", and quotes
# the agent's own words so the call is instant. CLAUDE_SKIP_SUBAGENT_INTEGRITY=1
# silences it; CLAUDE_SUBAGENT_INTEGRITY_TRUST_DISCLAIMERS=1 suppresses only when
# the agent explicitly said it changed nothing.
#
# KNOWN FALSE NEGATIVE: in a shared checkout a concurrent agent's changes mask this
# agent's inactivity, because `git status` is tree-wide. Reliable only with one
# worktree per agent, or serialized agents.
set -uo pipefail

mode="${1:-stop}"
[ "${CLAUDE_SKIP_SUBAGENT_INTEGRITY:-0}" = "1" ] && exit 0

payload="$(cat 2>/dev/null || true)"
[ -z "$payload" ] && exit 0

id="$(printf '%s' "$payload" | jq -r '.agent_id // "unknown"' 2>/dev/null || echo unknown)"
atype="$(printf '%s' "$payload" | jq -r '.agent_type // "unknown"' 2>/dev/null || echo unknown)"
last="$(printf '%s' "$payload" | jq -r '.last_assistant_message // ""' 2>/dev/null || echo '')"
last="$(printf '%s' "$last" | tr '' ' ' | cut -c1-240)"
[ -z "$id" ] && id="unknown"
[ -z "$atype" ] && atype="unknown"
    
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0

dir="${TMPDIR:-/tmp}/claude-subagent-integrity"
mkdir -p "$dir" 2>/dev/null || exit 0
# Key on repo + agent_id so two repos, or two concurrent subagents, cannot collide.
key="$(printf '%s|%s' "$root" "$id" | sha256sum | cut -c1-32)"
f="$dir/$key"

snapshot() {
  local head status
  head="$(git rev-parse HEAD 2>/dev/null || echo none)"
  # --porcelain includes untracked files, which is essential: new test files are
  # untracked until committed, so "wrote only new files" must count as work.
  status="$(git status --porcelain 2>/dev/null | sha256sum | cut -d' ' -f1)"
  printf '%s %s' "$head" "$status"
}

case "$mode" in
  start)
    snapshot > "$f" 2>/dev/null
    exit 0
    ;;

  stop)
    [ -f "$f" ] || exit 0                # no baseline (hook added mid-session) -> quiet
    before="$(cat "$f" 2>/dev/null)"
    after="$(snapshot)"
    rm -f "$f" 2>/dev/null
    [ "$before" = "$after" ] || exit 0   # something changed -> nothing to say

    # Optional noise reduction, OFF by default: warn-unless-disclaimed is the safe
    # direction, so this only helps once the read-only-agent noise proves annoying.
    if [ "${CLAUDE_SUBAGENT_INTEGRITY_TRUST_DISCLAIMERS:-0}" = "1" ] \
       && printf '%s' "$last" | grep -qiE 'no (files|changes|repo|repository|code) (were |was )?(modified|changed|touched)|read-only|report only|made no changes'; then
      exit 0
    fi
    jq -nc --arg id "$id" --arg atype "$atype" --arg root "$root" --arg last "$last" '{
      systemMessage: ("⚠ Subagent " + $id + " (" + $atype
        + ") stopped with ZERO repository delta in " + $root
        + " -- no commit, no working-tree change, no new untracked file.
Its final message began: \""
        + $last
        + "\"
If that was a read-only agent (audit, review, forensics) this is expected. If it claims to have done work, VERIFY BEFORE TRUSTING IT: grep for the symbols its report names. An agent that reports work it did not do is the signature of work lost to a bad tree operation, or of a report that was never grounded in the code."),
      suppressOutput: true
    }'
    exit 0
    ;;

  *) exit 0 ;;
esac
