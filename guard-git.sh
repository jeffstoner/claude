#!/usr/bin/env bash
# ~/.claude/hooks/guard-git.sh
# PreToolUse(Bash), if: Bash(git *)
#
# Enforces the git rules. Always exits 0; a decision is JSON on stdout. The deny
# text carries the rule, so the rule need not be in context before it is needed.
#
#  1-4  Destructive whole-tree operations (stash, checkout/restore pathspec,
#       reset --hard, clean), remote sync, --force. Shared-checkout safety.
#  5    A SUBAGENT may not merge, delete a branch, or remove a worktree. Merging
#       and cleanup are the orchestrator's actions, after the audit.
#  6    Default branch: never commit on it; merging into it asks the user (the
#       permission prompt IS the approval, scoped to one merge), and the prompt
#       carries the artifacts sweep of the branch being merged. Detached HEAD
#       is a stop.
#  7    Worktree removal only once its branch is merged; `branch -D` never.
#  8    Branch names are <type>/<issue-id> (or <type>/<slug> with tracking off).
#  9    Version tags are SemVer.
# 10    Commit messages are Conventional Commits with a scope.
#
# Project CLAUDE.md policy lines that relax these (see policy-lib.sh):
#   Default branch: <name> | Policy: commit-on-default allowed | Policy: merge-to-default allowed
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/policy-lib.sh"

read_payload
[ -z "$cmd" ] && exit 0
# Everything below except the commit-message parser matches on the command with its
# prose removed (heredoc bodies, quoted strings), so a message saying "clean up" is
# not `git clean`.
code="$(strip_literals "$cmd")"
# Only inspect git invocations. `git` must appear as a command word, not inside a path.
printf '%s' "$code" | grep -qE '(^|[;&|(){}[:space:]])git([[:space:]]|$)' || exit 0

# Does the command use this git subcommand? Matched as a whole word anywhere after
# `git`, so global options with values (`git -C /repo stash`) are covered.
# Deliberately over-inclusive: over-blocking is recoverable, destroying a peer's
# work is not.
uses() { printf '%s' "$code" | grep -qwE "$1"; }

# ---- 1. stash --------------------------------------------------------------
if uses 'stash'; then
  deny "BLOCKED: 'git stash' is banned in a shared checkout — it is a whole-tree operation that silently captures every concurrent agent's uncommitted work, and an incomplete restore destroys it with no error. To answer 'is this failure pre-existing?' use 'git show HEAD:<path>' or the read-only baseline worktree. To shelve work, commit it to a branch."
fi

# ---- 2. Discarding working-tree changes ------------------------------------
if uses 'checkout|restore' \
   && printf '%s' "$code" | grep -qE '(--[[:space:]]|--force|--hard|\.$)'; then
  deny "BLOCKED: 'git checkout/restore' with a pathspec discards uncommitted changes, which in a shared checkout may not be yours. Read the committed version with 'git show HEAD:<path>' instead."
fi

# ---- 3. Hard reset / clean -------------------------------------------------
if uses 'reset' && printf '%s' "$code" | grep -qE '\-\-hard|\-\-merge|\-\-keep'; then
  deny "BLOCKED: 'git reset --hard' (or --merge/--keep) discards uncommitted work across the whole tree. Never run this in a shared checkout."
fi
if uses 'clean'; then
  deny "BLOCKED: 'git clean' deletes untracked files — in this workflow that includes other agents' new test files, which are untracked until committed."
fi

# ---- 4. Remote sync and --force --------------------------------------------
if uses 'push|pull'; then
  deny "BLOCKED: pushing to or pulling from a remote is the user's responsibility. Report the command you would run and let the user run it."
fi
if printf '%s' "$code" | grep -qE '(--force([[:space:]]|=|$)|[[:space:]]-f([[:space:]]|$))'; then
  # The one legitimate use is `worktree add -f` (reuse a branch already checked out).
  # `worktree remove --force` destroys that worktree's uncommitted work -- the exact
  # loss this script exists to prevent -- so it is NOT exempt.
  if ! (uses 'worktree' && uses 'add'); then
    deny "BLOCKED: '--force' on a git command is banned. Investigate and resolve the underlying error cleanly, or escalate to the user. ('git worktree remove --force' discards that worktree's uncommitted work; commit it first.)"
  fi
fi

# ---- per-segment checks (5-10) ---------------------------------------------
in_repo || exit 0
branch="$(current_branch)"          # empty = detached HEAD
default="$(default_branch || true)" # empty = unknown

on_default() {
  [ -n "$branch" ] || return 1
  if [ -n "$default" ]; then [ "$branch" = "$default" ]; else looks_like_default "$branch"; fi
}
default_note() {
  if [ -n "$default" ]; then printf 'The default branch is %s.' "$default"
  else printf 'The default branch could not be determined (no "Default branch:" line in the project CLAUDE.md and no remote) and "%s" looks like one. Ask the user and record "Default branch: <name>" in the project CLAUDE.md so this is not asked again.' "$branch"; fi
}
# The merge into the default branch is the moment the user judges the whole body of
# work, so the artifacts sweep runs here and its result goes into the prompt: every
# closed issue's claims, verified against the branch being merged (bd-verify-artifacts.sh
# --ref <src>). Silent when there is no tracker to walk. The verifier is bounded so a
# slow sweep cannot time out the hook -- an erroring PreToolUse hook does not ask.
merge_sweep() { # <args of the merge segment>
  local src out rc verifier
  tracker_active || return 0
  command -v bd >/dev/null 2>&1 || return 0
  verifier="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/bd-verify-artifacts.sh"
  [ -x "$verifier" ] || return 0
  # Source ref: the last non-option word. Quoted values are already emptied ("" / '').
  src="$(printf '%s' "$1" | awk '{for(i=NF;i>=1;i--) if ($i !~ /^-/ && $i != "\"\"" && $i != "\047\047") {print $i; exit}}')"
  if [ -z "$src" ] || ! git -C "$cwd" rev-parse --verify -q "$src^{commit}" >/dev/null 2>&1; then
    printf ' Integrity sweep SKIPPED: could not identify the branch being merged. Run the verify-artifacts skill against it before approving.'
    return 0
  fi
  out="$(cd "$cwd" && timeout 6 "$verifier" --ref "$src" 2>&1)"; rc=$?
  case "$rc" in
    0)   printf ' Integrity sweep of %s: %s' "$src" "$(printf '%s\n' "$out" | tail -1)" ;;
    124) printf ' Integrity sweep of %s TIMED OUT. Run the verify-artifacts skill before approving.' "$src" ;;
    *)   printf ' ⚠ INTEGRITY SWEEP of %s FAILED — closed issues claim code that is not on that branch:\n%s\nApproving merges those gaps into the default branch; otherwise reopen the affected issues and recover the work first (git fsck --unreachable | grep commit).' "$src" "$out" ;;
  esac
}
BRANCH_RE='^[a-z][a-z0-9-]*/[A-Za-z0-9._-]+$'
SEMVER_RE='^v?[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$'

check_branch_name() {
  printf '%s' "$1" | grep -qE "$BRANCH_RE" && return 0
  deny "BLOCKED: branch name '$1' does not follow <type>/<issue-id> (e.g. feat/gg-12.1, fix/NOTICKET-typo). With issue tracking switched off use <type>/<short-slug>. Type is lowercase: feat, fix, chore, refactor, test, docs, epic, ..."
}

while IFS= read -r seg; do
  is_git_segment "$seg" || continue
  sub="$(git_subcmd "$seg")" || continue
  args="$(git_args "$seg")"

  # ---- 5. subagents do not merge, clean up, or delete -----------------------
  if is_subagent; then
    case "$sub" in
      merge)
        deny "BLOCKED: a subagent must not merge. Merging a task branch is the orchestrator's action, and only after the audit passes. Commit your work to your worktree's branch, record the artifacts block, and stop; the orchestrator merges." ;;
      worktree)
        printf '%s' "$args" | grep -qwE 'remove|prune' && \
          deny "BLOCKED: a subagent must not remove its own worktree. The orchestrator removes it after the branch is merged and the audit has passed — the worktree must survive so you can be resumed with audit findings." ;;
      branch)
        printf '%s' "$args" | grep -qE '(^|[[:space:]])(-[dD]|--delete)([[:space:]]|$)' && \
          deny "BLOCKED: a subagent must not delete branches. Branch cleanup is the orchestrator's action after merge and audit." ;;
    esac
  fi

  case "$sub" in
    # ---- 6. default branch --------------------------------------------------
    commit)
      if [ -z "$branch" ]; then
        deny "BLOCKED: HEAD is detached. Detached HEAD is not a branch; do not guess a base. Stop and escalate to the user."
      fi
      if on_default && ! policy_has "commit-on-default allowed"; then
        root="$(repo_root)"
        if [ -f "$root/.git/MERGE_HEAD" ] || [ -f "$(git -C "$cwd" rev-parse --git-dir 2>/dev/null)/MERGE_HEAD" ]; then
          ask "This commit completes a merge on the default branch '$branch'. Confirm it was an approved merge."
        fi
        deny "BLOCKED: never commit on the default branch. $(default_note) Leave it first: 'git switch -c <type>/<issue-id>' from the current HEAD, then commit there. Task worktrees branch from that integration branch and audited work merges into it; the default branch advances only by the user's hand. (A project may relax this with the CLAUDE.md line 'Policy: commit-on-default allowed'.)"
      fi
      ;;
    merge|rebase|cherry-pick)
      printf '%s' "$args" | grep -qE '(^|[[:space:]])--abort([[:space:]]|$)' && continue
      if on_default && ! policy_has "merge-to-default allowed"; then
        sweep=""; [ "$sub" = merge ] && sweep="$(merge_sweep "$args")"
        ask "Merging/rebasing INTO the default branch '$branch'. $(default_note)$sweep Approving this prompt is the user's approval for exactly this one merge. Not approved means: merge into the integration branch instead and leave the default branch to the user. (A project may relax this with 'Policy: merge-to-default allowed'.)"
      fi
      ;;
    # ---- 7. worktree removal only after merge; branch -D never ---------------
    worktree)
      if printf '%s' "$args" | grep -qwE 'remove'; then
        target="$(printf '%s' "$args" | sed -E 's/.*remove[[:space:]]+//' | awk '{for(i=1;i<=NF;i++) if ($i !~ /^-/) {print $i; exit}}')"
        if [ -n "$target" ]; then
          tpath="$target"; [ "${tpath#/}" = "$tpath" ] && tpath="$cwd/$tpath"
          wbranch="$(git -C "$cwd" worktree list --porcelain 2>/dev/null \
            | awk -v p="$(cd "$tpath" 2>/dev/null && pwd -P)" '$1=="worktree"{w=$2} $1=="branch" && w==p {sub("refs/heads/","",$2); print $2}')"
          if [ -n "$wbranch" ] && ! git -C "$cwd" branch --merged HEAD --format='%(refname:short)' 2>/dev/null | grep -qx "$wbranch"; then
            deny "BLOCKED: worktree '$target' is on branch '$wbranch', which is not merged into the current HEAD. Remove a worktree only after its branch has been merged back AND its audit has passed. A merge is not by itself the cleanup signal; the audit is."
          fi
        fi
      fi
      if printf '%s' "$args" | grep -qwE 'add'; then
        newb="$(printf '%s' "$args" | grep -oE '(^|[[:space:]])-b[[:space:]]+[^[:space:]]+' | awk '{print $2}')"
        [ -n "$newb" ] && check_branch_name "$newb"
      fi
      ;;
    branch)
      printf '%s' "$args" | grep -qE '(^|[[:space:]])-D([[:space:]]|$)' && \
        deny "BLOCKED: 'git branch -D' force-deletes an unmerged branch. Use '-d' (git refuses if unmerged) after the branch has been merged and audited."
      # Plain `git branch <name>` creates a branch.
      if [ -n "$args" ] && ! printf '%s' "$args" | grep -qE '(^|[[:space:]])-'; then
        newb="$(printf '%s' "$args" | awk '{print $1}')"
        [ -n "$newb" ] && check_branch_name "$newb"
      fi
      ;;
    # ---- 8. branch naming on creation -----------------------------------------
    switch|checkout)
      newb="$(printf '%s' "$args" | grep -oE '(^|[[:space:]])(-c|-C|-b|-B|--create)[[:space:]]+[^[:space:]]+' | awk '{print $2}')"
      [ -n "$newb" ] && check_branch_name "$newb"
      ;;
    # ---- 9. SemVer tags -------------------------------------------------------
    tag)
      if [ -n "$args" ] && ! printf '%s' "$args" | grep -qE '(^|[[:space:]])(-l|--list|-d|--delete|-v|--verify|--contains)([[:space:]]|$)'; then
        tname="$(printf '%s' "$args" | sed -E 's/-m[[:space:]]+("[^"]*"|'"'"'[^'"'"']*'"'"'|[^[:space:]]+)//g; s/-F[[:space:]]+[^[:space:]]+//g' | awk '{for(i=1;i<=NF;i++) if ($i !~ /^-/) {print $i; exit}}')"
        if [ -n "$tname" ] && printf '%s' "$tname" | grep -qE '^v?[0-9]' && ! printf '%s' "$tname" | grep -qE "$SEMVER_RE"; then
          deny "BLOCKED: tag '$tname' is not Semantic Versioning (MAJOR.MINOR.PATCH, optional -prerelease and +build, optional leading v). fix → PATCH, feat → MINOR, breaking change → MAJOR."
        fi
      fi
      ;;
  esac
done < <(split_segments "$code")

# ---- 10. Conventional Commits -----------------------------------------------
# Only when the command commits with a message we can see. Reused/edited
# messages (-C, -c, --amend --no-edit, --fixup, --squash) and editor sessions pass.
# Whether this is a commit, and which form carries the message, is read from the
# code; the message itself is read from the full command.
if printf '%s' "$code" | grep -qE '(^|[[:space:]])commit([[:space:]]|$)' \
   && ! printf '%s' "$code" | grep -qE '(^|[[:space:]])(-[cC]|--reuse-message|--reedit-message|--fixup|--squash|--no-edit)([[:space:]=]|$)'; then
  msg=""
  if printf '%s' "$code" | grep -qE '<<-?[[:space:]]*'"'"'?"?[A-Za-z_]*'"'"'?"?'; then
    # Heredoc form: git commit -m "$(cat <<'EOF' ... EOF)"
    msg="$(printf '%s\n' "$cmd" | awk '
      /<<-?[[:space:]]*['"'"'"]?[A-Za-z_]+['"'"'"]?/ && !inb { match($0, /<<-?[[:space:]]*['"'"'"]?[A-Za-z_]+/); t=substr($0,RSTART,RLENGTH); gsub(/<<-?[[:space:]]*['"'"'"]?/,"",t); tag=t; inb=1; next }
      inb && $0 ~ "^[[:space:]]*" tag "[[:space:]]*$" { exit }
      inb { print }')"
  elif printf '%s' "$code" | grep -qE '(^|[[:space:]])(-F|--file)[[:space:]=]'; then
    mf="$(printf '%s' "$cmd" | grep -oE '(-F|--file)[[:space:]=]+[^[:space:]]+' | head -1 | sed -E 's/^(-F|--file)[[:space:]=]+//')"
    [ "$mf" != "-" ] && { [ "${mf#/}" = "$mf" ] && mf="$cwd/$mf"; [ -r "$mf" ] && msg="$(cat "$mf")"; }
  else
    # First -m / --message value. Handles -m "..", -m '..', -am "..", --message=..
    msg="$(printf '%s' "$cmd" | grep -oE -- '(^|[[:space:]])(-[a-zA-Z]*m|--message)[[:space:]=]+("[^"]*"|'"'"'[^'"'"']*'"'"'|[^[:space:]]+)' | head -1 \
      | sed -E 's/^[[:space:]]*(-[a-zA-Z]*m|--message)[[:space:]=]+//; s/^"(.*)"$/\1/; s/^'"'"'(.*)'"'"'$/\1/')"
  fi
  if [ -n "$msg" ]; then
    subject="$(printf '%s\n' "$msg" | sed -E '/^[[:space:]]*$/d' | head -1)"
    TYPES='fix|feat|ci|docs|refactor|tag|chore|revert|build|perf|style|test'
    CC_GUIDE="Conventional Commits: '<type>(<scope>)!?: <subject>'. Types: fix feat ci docs refactor chore revert build perf style test (others only after confirming with the user). Scope = the issue id, or NOTICKET when there is none. Subject ≤ 72 chars, imperative, no trailing period. Body ≤ 2 short paragraphs. Footers when applicable: 'Ref: <issue>', 'Relates-to: <ids>', 'See-also: <ref>', 'Assisted-by: <model id>'. Breaking change: '!' after the scope AND a 'BREAKING CHANGE: <text>' footer."
    if ! printf '%s' "$subject" | grep -qE "^(${TYPES})\([^()[:space:]]+\)!?: [^[:space:]]"; then
      if printf '%s' "$subject" | grep -qE "^(${TYPES})(!?:| )"; then
        deny "BLOCKED: commit subject '$subject' has no scope. $CC_GUIDE"
      fi
      deny "BLOCKED: commit subject '$subject' is not a Conventional Commit. $CC_GUIDE"
    fi
    if [ "${#subject}" -gt 72 ]; then
      deny "BLOCKED: commit subject is ${#subject} chars; keep it ≤ 72. Move detail to the body. $CC_GUIDE"
    fi
    if printf '%s' "$subject" | grep -qE '^[a-z]+\([^)]+\)!:' && ! printf '%s\n' "$msg" | grep -qE '^BREAKING CHANGE:'; then
      deny "BLOCKED: subject marks a breaking change with '!' but there is no 'BREAKING CHANGE:' footer. Both are required. $CC_GUIDE"
    fi
    if printf '%s\n' "$msg" | grep -qE '^BREAKING CHANGE:' && ! printf '%s' "$subject" | grep -qE '^[a-z]+\([^)]+\)!:'; then
      deny "BLOCKED: message has a 'BREAKING CHANGE:' footer but the subject lacks '!' after the scope. Both are required. $CC_GUIDE"
    fi
  fi
fi

exit 0
