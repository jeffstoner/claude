#!/usr/bin/env bash
# ~/.claude/hooks/guard-bd.sh
# PreToolUse(Bash), if: Bash(bd *)
#
# Enforces the beads usage rules that used to live in prose:
#  1. `bd update --notes` REPLACES the notes field, destroying other agents'
#     findings. Only `--append-notes` is allowed.
#  2. Bead fields must not be rebuilt through inline command substitution --
#     keep the text on disk and use --*-file (or `$(cat <file>)`, which is the
#     one blessed substitution).
#  3. `bd edit` opens $EDITOR and blocks the agent.
#  4. A subagent never closes an issue (the audit gates the close, and the
#     orchestrator performs it), including the `--status=closed` back door.
#  5. Labelling an implementation bead `human` is almost always a mistake:
#     `bd human respond` CLOSES the bead it answers. Decisions get their own bead.
#
# The artifacts-block contract on `bd close` is require-artifacts-block.sh's job.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/policy-lib.sh"

read_payload
[ -z "$cmd" ] && exit 0
printf '%s' "$cmd" | grep -qE '(^|[;&|(){}[:space:]])bd([[:space:]]|$)' || exit 0

while IFS= read -r seg; do
  printf '%s' "$seg" | grep -qE '(^|[[:space:]({])bd([[:space:]]|$)' || continue
  # Subcommand = first non-option word after the FIRST `bd` token. Anchoring on the
  # first, not the last, matters: `bd update x --notes "$(bd show y)"` must read as update.
  sub="$(printf '%s' "$seg" | awk '{for(i=1;i<=NF;i++){ if(!s){ if($i=="bd"||$i~/[({]bd$/) s=1; continue } if($i !~ /^-/){print $i; exit} }}')"

  case "$sub" in
    update)
      if printf '%s' "$seg" | grep -qE '(^|[[:space:]])--notes([=[:space:]]|$)'; then
        deny "BLOCKED: 'bd update --notes' REPLACES the whole notes field, destroying every other agent's findings. Use 'bd update <id> --append-notes \"...\"' (or --append-notes-file <path>) which appends. The same class of loss as a bad stash, in the tracker instead of the tree."
      fi
      if printf '%s' "$seg" | grep -qE '(^|[[:space:]])--status[=[:space:]]+closed([[:space:]]|$)'; then
        if is_subagent; then
          deny "BLOCKED: a subagent must not close an issue. Record your work with 'bd update <id> --append-notes' including the artifacts JSON block, then stop. The orchestrator closes it after the audit passes."
        fi
        deny "BLOCKED: closing via '--status=closed' bypasses the close-reason gate. Use 'bd close <id> --reason-file <path>' with a close-reason that ends in the fenced json artifacts block."
      fi
      # Inline substitution into a field. `$(cat <file>)` / `$(cat <<EOF` are the blessed forms.
      stripped="$(printf '%s' "$seg" | sed -E 's/\$\(cat[[:space:]]+(<<|[^)]*\))//g')"
      if printf '%s' "$stripped" | grep -q '\$('; then
        deny "BLOCKED: never rebuild a bead field through inline command substitution. Keep the text on disk and pass it whole: 'bd update <id> --design-file full-design.txt' (or --description-file, --append-notes-file), then verify with 'bd show <id>'. The only blessed substitution is \$(cat <file>)."
      fi
      ;;
    close|done)
      if is_subagent; then
        deny "BLOCKED: a subagent must not close an issue. The audit gates the close and the orchestrator performs it. Record your work with 'bd update <id> --append-notes' (including the artifacts JSON block) and stop."
      fi
      ;;
    edit)
      deny "BLOCKED: 'bd edit' opens \$EDITOR and blocks the agent. Use 'bd update <id> --<field>-file <path>' instead."
      ;;
    label)
      if printf '%s' "$seg" | grep -qE 'label[[:space:]]+add[[:space:]]+[^[:space:]]+[[:space:]]+human([[:space:]]|$)'; then
        ask "Labelling this bead 'human' means 'bd human respond' will CLOSE it when the human answers. If this is an implementation bead, do not: file a separate decision bead stating the concrete options, label THAT one 'human', and 'bd dep add <impl-bead> <decision-bead>' so the work is blocked on it. Approve only if this bead exists solely to hold the decision."
      fi
      ;;
  esac
done < <(split_segments "$cmd")

exit 0
