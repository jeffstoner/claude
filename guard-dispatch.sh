#!/usr/bin/env bash
# ~/.claude/hooks/guard-dispatch.sh
# PreToolUse, matcher: Agent|TodoWrite|TaskCreate|TaskUpdate
#
# Two rules that only bite in a project using the issue tracker (a .beads/ dir,
# not switched off by 'Policy: no issue tracker'):
#
#  1. No shadow trackers. TodoWrite / TaskCreate lists die with the session and
#     are invisible to other agents and to the audit. All task tracking goes
#     through bd.
#  2. Coding work goes through the role agents. Dispatching a generic agent
#     (general-purpose, claude) for implementation bypasses the tester/coder/
#     auditor split and the agent-scoped hooks that enforce it. Read-only agents
#     (Explore, Plan, ...) and custom agents pass.
#
# Agent tool_input fields confirmed by probe 2026-09-08: description, prompt,
# subagent_type (plus optional isolation, model, run_in_background).
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/policy-lib.sh"

read_payload
tracker_active || exit 0

case "$tool" in
  TodoWrite|TaskCreate|TaskUpdate)
    deny "BLOCKED: this project tracks work in beads. Do not use TodoWrite/TaskCreate or markdown checklists — they are invisible to other agents and to the audit, and die with the session. Use 'bd create' / 'bd update <id> --append-notes' / 'bd dep add'. (A project may switch tracking off with the CLAUDE.md line 'Policy: no issue tracker'.)"
    ;;
  Agent)
    stype="$(printf '%s' "$payload" | jq -r '.tool_input.subagent_type // "general-purpose"' 2>/dev/null)"
    case "$stype" in
      general-purpose|claude|"")
        deny "BLOCKED: in a beads project, implementation work is dispatched to the role agents, not to a generic agent: 'tester' writes the tests for an issue, 'coder' implements it in its own worktree, 'auditor' audits it read-only. Each carries its own rules and its own guard hooks. Use subagent_type: tester | coder | auditor, or Explore/Plan for read-only research."
        ;;
    esac
    ;;
esac
exit 0
