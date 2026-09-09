#!/usr/bin/env bash
# ~/.claude/hooks/policy-lib.sh -- sourced by the hook scripts, not run directly.
#
# Shared helpers: hook JSON responses, the project's policy lines, default-branch
# resolution. Every function is safe outside a git work tree (returns empty/false).
#
# PROJECT POLICY LINES. A project's CLAUDE.md (repo root, or .claude/CLAUDE.md) may
# carry these exact lines. They are the machine-readable override channel -- free
# prose cannot be honoured by a script.
#
#   Default branch: main
#   Policy: commit-on-default allowed
#   Policy: merge-to-default allowed
#   Policy: todo-comments allowed
#   Policy: no issue tracker
#   Test-paths: src/**/*_test.rs          (may repeat; extends the tester's allowed set)

# ---- hook responses ---------------------------------------------------------
# PreToolUse decisions. Each prints one JSON object and exits 0.
deny() {
  jq -nc --arg r "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}
ask() {
  jq -nc --arg r "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}'
  exit 0
}
# Inject text into the model's context from a non-decision event (SessionStart,
# SubagentStart, PostToolUse, PostToolUseFailure). $1 = event name, $2 = text.
add_context() {
  jq -nc --arg e "$1" --arg c "$2" \
    '{hookSpecificOutput:{hookEventName:$e,additionalContext:$c}}'
}

# ---- payload ---------------------------------------------------------------
# read_payload: stdin -> $payload, plus the common fields every hook wants.
read_payload() {
  payload="$(cat 2>/dev/null || true)"
  cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
  cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null || true)"
  tool="$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null || true)"
  agent_id="$(printf '%s' "$payload" | jq -r '.agent_id // empty' 2>/dev/null || true)"
  agent_type="$(printf '%s' "$payload" | jq -r '.agent_type // empty' 2>/dev/null || true)"
  [ -n "$cwd" ] && [ -d "$cwd" ] || cwd="$PWD"
}
# True when the tool call was made by a subagent, not the main session.
# (PreToolUse payloads from inside a subagent carry agent_id -- documented.)
is_subagent() { [ -n "${agent_id:-}" ]; }

# ---- repository ------------------------------------------------------------
repo_root() { git -C "${cwd:-$PWD}" rev-parse --show-toplevel 2>/dev/null; }
in_repo()   { git -C "${cwd:-$PWD}" rev-parse --is-inside-work-tree >/dev/null 2>&1; }
# Current branch name; empty when HEAD is detached or not a repo.
current_branch() { git -C "${cwd:-$PWD}" symbolic-ref --short -q HEAD 2>/dev/null; }

# ---- policy ----------------------------------------------------------------
policy_files() {
  local root; root="$(repo_root)" || return 0
  [ -f "$root/CLAUDE.md" ] && printf '%s\n' "$root/CLAUDE.md"
  [ -f "$root/.claude/CLAUDE.md" ] && printf '%s\n' "$root/.claude/CLAUDE.md"
  return 0
}
# policy_has "<name>"  e.g. policy_has "merge-to-default allowed"
policy_has() {
  local f
  for f in $(policy_files); do
    grep -qiE "^[[:space:]]*Policy:[[:space:]]*$1[[:space:]]*$" "$f" 2>/dev/null && return 0
  done
  return 1
}
# Test-paths: globs declared by the project, one per line.
policy_test_paths() {
  local f
  for f in $(policy_files); do
    grep -iE "^[[:space:]]*Test-paths:[[:space:]]*" "$f" 2>/dev/null | sed -E 's/^[[:space:]]*Test-paths:[[:space:]]*//'
  done
  return 0
}
# Does the project use an issue tracker? A .beads dir means beads, unless switched off.
tracker_active() {
  local root; root="$(repo_root)" || return 1
  [ -d "$root/.beads" ] || return 1
  policy_has "no issue tracker" && return 1
  return 0
}

# Default branch, resolved in the order the git rules prescribe, stopping at the
# first that answers: project CLAUDE.md line, then origin/HEAD only if a remote
# exists. Prints nothing when unknown -- never assumes "main".
default_branch() {
  local f name
  for f in $(policy_files); do
    name="$(grep -iE '^[[:space:]]*Default branch:[[:space:]]*' "$f" 2>/dev/null | head -1 \
      | sed -E 's/^[[:space:]]*Default branch:[[:space:]]*`?([^` ]+)`?.*/\1/')"
    [ -n "$name" ] && { printf '%s' "$name"; return 0; }
  done
  if [ -n "$(git -C "${cwd:-$PWD}" remote 2>/dev/null)" ]; then
    name="$(git -C "${cwd:-$PWD}" symbolic-ref --short -q refs/remotes/origin/HEAD 2>/dev/null)"
    [ -n "$name" ] && { printf '%s' "${name#origin/}"; return 0; }
  fi
  return 1
}
# Branch names that are probably a default branch when the real one is unknown.
looks_like_default() { printf '%s' "$1" | grep -qxE 'main|master|trunk|develop'; }

# ---- shell command helpers ---------------------------------------------------
# Split a compound shell command into segments on && || ; | and newlines. Crude:
# quoted separators are split too. Good enough for policy checks; the commit
# message parser reads the whole command instead.
split_segments() { printf '%s\n' "$1" | sed -E 's/(&&|\|\||;|\|)/\n/g'; }

# git_subcmd "<segment>": the first non-option word after `git`, skipping the
# global options that take a value (-C, -c, --git-dir, --work-tree, --namespace).
git_subcmd() {
  local seg="$1" tok skip=0 seen=0
  for tok in $seg; do
    if [ "$seen" -eq 0 ]; then [ "$tok" = "git" ] && seen=1; continue; fi
    if [ "$skip" -eq 1 ]; then skip=0; continue; fi
    case "$tok" in
      -C|-c|--git-dir|--work-tree|--namespace) skip=1 ;;
      -*) ;;
      *) printf '%s' "$tok"; return 0 ;;
    esac
  done
  return 1
}
# git_args "<segment>": everything after the subcommand.
git_args() {
  local seg="$1" sub; sub="$(git_subcmd "$seg")" || return 1
  printf '%s' "$seg" | sed -E "s/^.*[[:space:]]${sub}([[:space:]]|$)//"
}
# Does the segment invoke git as a command word (not inside a path)?
is_git_segment() { printf '%s' "$1" | grep -qE '(^|[[:space:]({])git([[:space:]]|$)'; }
