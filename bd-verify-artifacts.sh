#!/usr/bin/env bash
# ~/.claude/hooks/bd-verify-artifacts.sh  [--ref <git-ref>|worktree] [issue-id ...]
#
# Verifies that every symbol an issue CLAIMS to have added actually exists in the
# repository. Answers exactly one question -- "did this work land at all?" -- the
# failure mode where a closed issue describes code that is not there. It does NOT
# check correctness
# (that is the audit agent's job) and it does NOT check authorship: a symbol that
# was already present passes.
#
# --ref <git-ref>  check the named commit (default HEAD). Correct only once the
#                  work is COMMITTED -- against uncommitted work it reports a
#                  false MISSING, because git cannot see the working tree.
# --ref worktree    check the files on disk instead. Use this whenever the work
#                  may not be committed yet: a close-time gate, or a per-subagent
#                  check mid-session.
#
# With issue ids: checks those, open or closed.
# With none: sweeps every CLOSED issue in one `bd list --json` call (~1.5s/114
# issues). Open-but-reported-done work is NOT swept -- name it explicitly.
#
# CONTRACT: the close-reason (or notes) contains a fenced json block (three
# backticks + the word json) holding an "artifacts" array. JSON rather than YAML
# because bd's renderer reflows long lines, which breaks YAML wrapped scalars and
# block-sequence items (verified) but cannot break JSON. Shape:
#
#     {
#       "artifacts": [
#         { "path": "api/src/owasp_aggregator/auth/resolver.py",
#           "symbols": ["ProjectNotInScopeError", "require_project_scope"] },
#         { "path": "api/tests/auth/test_project_scope_enforcement.py", "symbols": [] },
#         { "path": "api/src/owasp_aggregator/legacy.py",
#           "symbols": ["OldThing"], "state": "removed" }
#       ]
#     }
#
# NOTE: no triple-backtick appears anywhere in this file, deliberately -- it would
# terminate the markdown fence of any document this script is embedded in, silently
# truncating the copy someone pastes out.
#
#   path     required. Repo-relative.
#   symbols  optional, default []. Empty asserts only that the file exists.
#   state    optional, default "present". Use "removed" to assert deletion, so
#            refactors and deletions are checkable in the same pass.
set -uo pipefail

ref="HEAD"
[ "${1:-}" = "--ref" ] && { ref="$2"; shift 2; }

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "not a git repo" >&2; exit 0; }
command -v jq >/dev/null 2>&1 || { echo "jq required" >&2; exit 0; }
root="$(git rev-parse --show-toplevel)"

# Two backends. Paths in an artifacts block are repo-relative, so BOTH modes must
# resolve them against the repo root rather than the caller's cwd -- `git grep`
# treats a pathspec as relative to cwd, so running this from a subdirectory would
# silently report every claim MISSING (observed, and it looks exactly like real
# data loss). Hence `git -C "$root"` and "$root/$1".
if [ "$ref" = "worktree" ]; then
  path_exists()  { [ -f "$root/$1" ]; }
  file_has_sym() { grep -q -F -- "$2" "$root/$1" 2>/dev/null; }
else
  path_exists()  { git -C "$root" cat-file -e "$ref:$1" 2>/dev/null; }
  file_has_sym() { git -C "$root" grep -q -F -- "$2" "$ref" -- "$1" 2>/dev/null; }
fi

# Built, not literal, so this file contains no triple-backtick (see NOTE above).
FENCE="$(printf '%0.s`' 1 2 3)"

# Emit NDJSON {path,symbols,state} for the first fenced json block carrying "artifacts".
extract_artifacts() {
  local text n i blk
  text="$(cat)"
  n=$(printf '%s\n' "$text" | grep -cE "^[[:space:]]*${FENCE}[[:space:]]*json" || true)
  i=0
  while [ "$i" -lt "$n" ]; do
    i=$((i+1))
    blk="$(printf '%s\n' "$text" | awk -v want="$i" -v F="$FENCE" '
      $0 ~ "^[[:space:]]*" F "[[:space:]]*json[[:space:]]*$" { c++; if (c==want) { inb=1; next } }
      inb && $0 ~ "^[[:space:]]*" F "[[:space:]]*$" { exit }
      inb { print }
    ')"
    printf '%s' "$blk" | jq -e 'has("artifacts")' >/dev/null 2>&1 || continue
    printf '%s' "$blk" | jq -c '.artifacts[] | {
      path: .path, symbols: (.symbols // []), state: (.state // "present")
    }' 2>/dev/null
    return 0
  done
}

if [ "$#" -eq 0 ]; then
  gathered="$(bd list --status=closed --json 2>/dev/null \
    | jq -c '.[] | {id, text: ((.close_reason // "") + "\n" + (.notes // ""))}' 2>/dev/null)"
else
  gathered="$(for id in "$@"; do
    bd show "$id" --json 2>/dev/null \
      | jq -c '.[0] | {id, text: ((.close_reason // "") + "\n" + (.notes // ""))}' 2>/dev/null
  done)"
fi
[ -z "$gathered" ] && { echo "no issues found"; exit 0; }

fail=0 checked=0 noblock=0 seen=0 malformed=0

while IFS= read -r row; do
  [ -z "$row" ] && continue
  id="$(printf '%s' "$row" | jq -r '.id')"
  text="$(printf '%s' "$row" | jq -r '.text')"
  seen=$((seen+1))

  records="$(printf '%s' "$text" | extract_artifacts)"
  if [ -z "$records" ]; then
    # Distinguish "no block" from "block present but unparseable" -- a malformed
    # block that read as absent is how a checker silently passes.
    if printf '%s\n' "$text" | grep -qE "^[[:space:]]*${FENCE}[[:space:]]*json"; then
      if ! printf '%s\n' "$text" | grep -q '"artifacts"'; then
        noblock=$((noblock+1))
      else
        malformed=$((malformed+1))
        printf 'MALFORMED   %-16s has an "artifacts" key but the json block does not parse\n' "$id"
        fail=$((fail+1))
      fi
    else
      noblock=$((noblock+1))
    fi
    continue
  fi

  while IFS= read -r rec; do
    [ -z "$rec" ] && continue
    path="$(printf '%s' "$rec"  | jq -r '.path')"
    state="$(printf '%s' "$rec" | jq -r '.state')"
    if ! path_exists "$path"; then
      [ "$state" = "present" ] && {
        printf 'MISSING     %-16s %s -- file absent at %s\n' "$id" "$path" "$ref"; fail=$((fail+1)); }
      continue
    fi
    mapfile -t syms < <(printf '%s' "$rec" | jq -r '.symbols[]?')
    if [ "${#syms[@]}" -eq 0 ]; then checked=$((checked+1)); continue; fi
    for sym in "${syms[@]}"; do
      [ -z "$sym" ] && continue
      checked=$((checked+1))
      if file_has_sym "$path" "$sym"; then
        [ "$state" = "removed" ] && {
          printf 'NOT-REMOVED %-16s %s: %s still present at %s\n' "$id" "$path" "$sym" "$ref"; fail=$((fail+1)); }
      else
        [ "$state" = "present" ] && {
          printf 'MISSING     %-16s %s: %s NOT FOUND at %s\n' "$id" "$path" "$sym" "$ref"; fail=$((fail+1)); }
      fi
    done
  done <<< "$records"
done <<< "$gathered"

printf '%d issue(s) scanned, %d claim(s) checked, %d failed, %d malformed, %d without a block.\n' \
  "$seen" "$checked" "$fail" "$malformed" "$noblock"
[ "$fail" -gt 0 ] && exit 1
exit 0
