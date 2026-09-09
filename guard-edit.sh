#!/usr/bin/env bash
# ~/.claude/hooks/guard-edit.sh  [global|coder|tester|auditor]
#
# global (default; registered in settings.json, matcher Edit|Write|NotebookEdit|MultiEdit):
#   The TODO ban. Deny an edit that ADDS a TODO/FIXME comment marker. Work still
#   to be done goes to the issue tracker (or, with tracking off, is reported to
#   the user) -- never left undiscoverable in the code. Counted as a delta, so
#   editing a file that already has TODOs is fine. Comment-marker forms only
#   (`# TODO`, `// FIXME:`, `TODO:`) so prose, TodoWrite, todo_list don't match.
#   Relaxed by the project CLAUDE.md line: Policy: todo-comments allowed
#
# coder / tester (agent-scoped, declared in the agent's frontmatter, matcher
# Edit|Write|NotebookEdit|MultiEdit|Bash):
#   The role split. The coder may not write test files; the tester may write
#   only test files. Tests and implementation are written by different agents,
#   always. Edit/Write are checked by path; Bash is checked heuristically for
#   redirections and file commands aimed at a test path (accepted false negatives).
#   The tester side asks instead of denying, because some languages keep tests in
#   source files (Rust #[cfg(test)], doctests); a project can extend the test set
#   with CLAUDE.md lines: Test-paths: <glob>
#
# auditor (agent-scoped, matcher Bash):
#   An auditor changes nothing. Edit/Write are removed by disallowedTools; this
#   catches the Bash routes: redirections, tee, sed -i, git/bd mutations.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/policy-lib.sh"

role="${1:-global}"
read_payload

file="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null)"
root="$(repo_root || printf '%s' "$cwd")"
rel="$file"; [ -n "$file" ] && rel="${file#"$root"/}"

# ---- test-path classification -----------------------------------------------
TEST_RE='(^|/)(tests?|__tests__|spec|fixtures|testdata)/|(^|/)test_[^/]+\.py$|_test\.(go|py|rs|ts|js|c|cc|cpp)$|\.(spec|test)\.[cm]?[jt]sx?$|Tests?\.(java|cs|kt|scala|swift)$|(^|/)conftest\.py$|(^|/)test_[^/]+\.(sh|bash)$'
glob_to_re() { printf '%s' "$1" | sed -E 's/[.+^$(){}|]/\\&/g; s/\*\*\//(.*\/)?/g; s/\*\*/.*/g; s/\*/[^\/]*/g; s/\?/./g'; }
is_test_path() {
  local p="$1" g
  printf '%s' "$p" | grep -qE "$TEST_RE" && return 0
  while IFS= read -r g; do
    [ -z "$g" ] && continue
    printf '%s' "$p" | grep -qE "^$(glob_to_re "$g")$" && return 0
  done < <(policy_test_paths)
  return 1
}

# ---- TODO ban (global) ---------------------------------------------------------
TODO_RE='((#|//|/\*|<!--|--|;|\*)[[:space:]]*(TODO|FIXME)\b|\b(TODO|FIXME):)'
count_todos() { grep -cE "$TODO_RE" 2>/dev/null || true; }
todo_check() {
  policy_has "todo-comments allowed" && return 0
  local before=0 after=0
  case "$tool" in
    Edit)
      before="$(printf '%s' "$payload" | jq -r '.tool_input.old_string // ""' | count_todos)"
      after="$(printf '%s'  "$payload" | jq -r '.tool_input.new_string // ""' | count_todos)" ;;
    MultiEdit)
      before="$(printf '%s' "$payload" | jq -r '[.tool_input.edits[]?.old_string // ""] | join("\n")' | count_todos)"
      after="$(printf '%s'  "$payload" | jq -r '[.tool_input.edits[]?.new_string // ""] | join("\n")' | count_todos)" ;;
    Write)
      [ -f "$file" ] && before="$(count_todos < "$file")"
      after="$(printf '%s' "$payload" | jq -r '.tool_input.content // ""' | count_todos)" ;;
    NotebookEdit)
      after="$(printf '%s' "$payload" | jq -r '.tool_input.new_source // ""' | count_todos)" ;;
    *) return 0 ;;
  esac
  if [ "${after:-0}" -gt "${before:-0}" ]; then
    deny "BLOCKED: this edit adds a TODO/FIXME comment. Never leave work-to-be-done as a code comment — it is undiscoverable. Create an issue in the tracker (or update an existing one) with enough context and direction to finish the work; with issue tracking off, report the remaining work to the user before you stop. (A project may relax this with the CLAUDE.md line 'Policy: todo-comments allowed'.)"
  fi
}

# ---- Bash heuristics -----------------------------------------------------------
# Strip harmless redirections, then look for a write.
bash_writes() {
  printf '%s' "$1" | sed -E 's/2>&1//g; s/&?>[[:space:]]*\/dev\/null//g; s/2>[[:space:]]*\/dev\/null//g; s/<\(//g' \
    | grep -qE '(>|\btee\b|\bsed[[:space:]]+(-[a-zA-Z]*i|--in-place)|\b(cp|mv|rm|touch|mkdir|install|ln)\b|\bpython[0-9.]*[[:space:]]+-c\b.*open\()'
}
# Any test-looking path token in the command?
bash_mentions_test_path() {
  local tok
  for tok in $(printf '%s' "$1" | tr -d '"'"'" | tr '[:space:]' '\n'); do
    case "$tok" in -*|"") continue ;; esac
    is_test_path "$tok" && return 0
  done
  return 1
}

# ---- role checks ---------------------------------------------------------------
case "$role" in
  global)
    todo_check
    ;;
  coder)
    case "$tool" in
      Edit|Write|NotebookEdit|MultiEdit)
        [ -n "$rel" ] && is_test_path "$rel" && \
          deny "BLOCKED: you are the coder; '$rel' is a test file. A coding agent NEVER writes or modifies tests — tests are written by the tester agent, always. If a test is wrong, say so in your notes/report with the specific assertion and why; the orchestrator routes it. Make the tests pass by changing the implementation." ;;
      Bash)
        bash_writes "$cmd" && bash_mentions_test_path "$cmd" && \
          deny "BLOCKED: this command appears to write to a test path. The coder never creates or modifies tests; report the problem with the test instead." ;;
    esac
    ;;
  tester)
    case "$tool" in
      Edit|Write|NotebookEdit|MultiEdit)
        if [ -n "$rel" ] && ! is_test_path "$rel"; then
          ask "You are the tester; '$rel' does not look like a test file. The tester writes ONLY tests (and test fixtures/config) — never implementation. If this language keeps tests inside source files, the project can declare them with a CLAUDE.md line 'Test-paths: <glob>'. Approve only if this file genuinely is test code."
        fi ;;
      Bash)
        if bash_writes "$cmd" && ! bash_mentions_test_path "$cmd" \
           && ! printf '%s' "$cmd" | grep -qE '(^|[[:space:]({])(git|bd)([[:space:]]|$)'; then
          ask "This command appears to write outside the test paths. The tester writes only tests. Approve only if the target is test code or scratch output."
        fi ;;
    esac
    ;;
  auditor)
    [ "$tool" = "Bash" ] || exit 0
    if printf '%s' "$cmd" | grep -qE '(^|[[:space:]({])git[[:space:]]+(-[^[:space:]]+[[:space:]]+)*(add|commit|merge|rebase|cherry-pick|reset|checkout|switch|restore|rm|mv|stash|worktree|branch[[:space:]]+-|tag|push|pull|clean)\b'; then
      deny "BLOCKED: the auditor changes nothing. Read-only git only (log, show, diff, status, grep, blame). Report findings; the orchestrator routes fixes to the original coder."
    fi
    if printf '%s' "$cmd" | grep -qE '(^|[[:space:]({])bd[[:space:]]+(-[^[:space:]]+[[:space:]]+)*(update|close|done|create|dep|label|delete|defer|supersede|human)\b'; then
      deny "BLOCKED: the auditor does not write to the tracker. Put findings in your final report; the orchestrator records them (in the bead, or as new beads for out-of-scope findings)."
    fi
    if bash_writes "$cmd"; then
      deny "BLOCKED: the auditor changes nothing in the repository — no redirections, tee, sed -i, cp/mv/rm/touch. Run tests and read code; report what you find."
    fi
    ;;
esac

exit 0
