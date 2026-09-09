#!/usr/bin/env bash
# ~/.claude/hooks/require-artifacts-block.sh
# PreToolUse(Bash), if: Bash(bd close *)
#
# Rejects `bd close` unless the reason carries a VALID fenced json block with an
# "artifacts" array. Validating (not just grepping for a marker) is the concrete
# payoff of choosing JSON: a malformed block is caught at close time, when the
# author is still present, instead of surfacing in the session-close sweep.
set -uo pipefail

payload="$(cat 2>/dev/null || true)"
cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)" || exit 0
[ -z "$cmd" ] && exit 0
# Defensive: settings gates this with `if: Bash(bd close *)`, but never act on
# anything that is not a bd close.
printf '%s' "$cmd" | grep -qE '(^|[;&|[:space:]])bd([[:space:]]+-[^[:space:]]+)*[[:space:]]+(close|done)([[:space:]]|$)' || exit 0

deny() {
  jq -nc --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",
    permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

FENCE="$(printf '%0.s`' 1 2 3)"

GUIDE="Close-reasons must end with a fenced json block (${FENCE}json ... ${FENCE}):

${FENCE}json
{\"artifacts\":[
  {\"path\":\"api/src/pkg/mod.py\",\"symbols\":[\"NewClass\",\"new_func\"]},
  {\"path\":\"api/tests/test_new.py\",\"symbols\":[]},
  {\"path\":\"api/src/pkg/old.py\",\"symbols\":[\"Gone\"],\"state\":\"removed\"}
]}
${FENCE}

path is repo-relative; symbols defaults to [] (asserts the file exists); state
defaults to "present" ("removed" asserts deletion). This is what makes the
session-close integrity check possible -- a prose-only close-reason cannot be
verified, which is how work silently goes missing. Tip: use
'bd close <id> --reason-file <path>' so you never have to shell-escape the JSON."

# --reason-file <path>: validate the file's content when it is readable from the
# hook's cwd. `-` (stdin) or an unreadable path is allowed through and left to
# the session-close sweep.
text="$cmd"
rf="$(printf '%s' "$cmd" | grep -oE -- '--reason-file[[:space:]=]+[^[:space:]]+' | head -1 | sed -E 's/^--reason-file[[:space:]=]+//; s/^["\x27]//; s/["\x27]$//')"
if [ -n "$rf" ]; then
  [ "$rf" = "-" ] && exit 0
  cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)"; [ -d "${cwd:-}" ] || cwd="$PWD"
  [ "${rf#/}" = "$rf" ] && rf="$cwd/$rf"
  [ -r "$rf" ] || exit 0
  text="$(cat "$rf")"
fi

# Pull the json block out of the text and actually parse it.
# Same awk fence-extraction as bd-verify-artifacts.sh -- one parser, not two.
blk="$(printf '%s\n' "$text" | awk -v F="$FENCE" '
  $0 ~ F "[[:space:]]*json[[:space:]]*$" { inb=1; next }
  inb && index($0, F)                    { exit }
  inb                                    { print }
')"

if [ -z "$blk" ]; then
  deny "BLOCKED: no fenced json artifacts block found in the close reason.

$GUIDE"
fi
if ! printf '%s' "$blk" | jq -e 'has("artifacts") and (.artifacts | type == "array")' >/dev/null 2>&1; then
  deny "BLOCKED: the json block is malformed, or has no \"artifacts\" array. Parse error from jq:
$(printf '%s' "$blk" | jq . 2>&1 | head -3)

$GUIDE"
fi
if ! printf '%s' "$blk" | jq -e '[.artifacts[] | has("path")] | all and length > 0' >/dev/null 2>&1; then
  deny "BLOCKED: every artifacts entry needs a \"path\", and the array must not be empty.

$GUIDE"
fi
exit 0
