#!/usr/bin/env bash
# tests/hooks.sh -- pipe synthetic hook payloads into the hook scripts and assert
# on the decision they print. Run: bash tests/hooks.sh
set -u
HOOKS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
F='```'

# ---- helpers -----------------------------------------------------------------
check() { # name expected actual
  if [ "$2" = "$3" ]; then echo "PASS $1"; pass=$((pass+1))
  else echo "FAIL $1 (expected $2 got $3)"; fail=$((fail+1)); fi
}
decide() { # stdin: hook stdout -> deny|ask|ctx|block|allow
  local out; out="$(cat)"
  [ -z "$out" ] && { echo allow; return; }
  printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // .decision
    // (if .hookSpecificOutput.additionalContext then "ctx" else "allow" end)'
}
run() { # name expected payload script [script-args]
  local name="$1" exp="$2" payload="$3" script="$4"; shift 4
  check "$name" "$exp" "$(printf '%s' "$payload" | "$HOOKS/$script" "$@" 2>/dev/null | decide)"
}
mkrepo() { # name -> path (git repo on main with one commit)
  local d="$TMP/$1"; mkdir -p "$d"
  git -C "$d" init -q -b main
  git -C "$d" config user.email t@t.t; git -C "$d" config user.name t; git -C "$d" config commit.gpgsign false
  printf 'x\n' > "$d/f.txt"; git -C "$d" add -A; git -C "$d" commit -qm "chore(gg-0): init"
  printf '%s' "$d"
}
# payload builders
pbash()  { jq -nc --arg cwd "$1" --arg c "$2" --arg a "${3:-}" \
  '{tool_name:"Bash",cwd:$cwd,tool_input:{command:$c}} + (if $a!="" then {agent_id:"a1",agent_type:$a} else {} end)'; }
pedit()  { jq -nc --arg cwd "$1" --arg f "$2" --arg o "$3" --arg n "$4" \
  '{tool_name:"Edit",cwd:$cwd,tool_input:{file_path:$f,old_string:$o,new_string:$n}}'; }
pwrite() { jq -nc --arg cwd "$1" --arg f "$2" --arg c "$3" \
  '{tool_name:"Write",cwd:$cwd,tool_input:{file_path:$f,content:$c}}'; }
pagent() { jq -nc --arg cwd "$1" --arg t "${2:-}" \
  '{tool_name:"Agent",cwd:$cwd,tool_input:({prompt:"x"} + (if $t!="" then {subagent_type:$t} else {} end))}'; }
pstop()  { jq -nc --arg cwd "$1" --arg t "$2" --arg m "$3" --argjson a "$4" \
  '{cwd:$cwd,agent_id:"a9",agent_type:$t,last_assistant_message:$m,stop_hook_active:$a,agent_transcript_path:"/nonexistent"}'; }
# per-script shorthands (R = current scratch repo)
g()   { run "git: $1" "$2" "$(pbash "$R" "$3" "${4:-}")" guard-git.sh; }
b()   { run "bd: $1" "$2" "$(pbash "$R" "$3" "${4:-}")" guard-bd.sh; }
e()   { run "edit[$1]: $2" "$3" "$4" guard-edit.sh "$1"; }
eb()  { e "$1" "$2" "$3" "$(pbash "$R" "$4")"; }

# ---- guard-git.sh --------------------------------------------------------------
R="$(mkrepo git)"
g "status" allow 'git status --short'
g "stash" deny 'git stash'
g "log --grep stash (documented over-block)" deny 'git log --grep stash'
g "reset --hard" deny 'git reset --hard'
g "clean" deny 'git clean -fd'
g "push" deny 'git push'
g "checkout -- a" deny 'git checkout -- a'
g "worktree remove --force" deny 'git worktree remove --force x'
g "worktree add -f" allow 'git worktree add -f ../w feat/x'
g "commit on main, default unknown" deny 'git commit -m "feat(x): y"'
g "merge on main, default unknown" ask 'git merge feat/gg-1'
g "merge --abort" allow 'git merge --abort'
g "merge-base" allow 'git merge-base main feat/gg-1'
printf 'Default branch: main\n' > "$R/CLAUDE.md"
g "commit on declared default" deny 'git commit -m "feat(x): y"'
g "merge on declared default" ask 'git merge feat/gg-1'
printf 'Policy: commit-on-default allowed\nPolicy: merge-to-default allowed\n' >> "$R/CLAUDE.md"
g "commit on default, policy relaxed" allow 'git commit -m "feat(x): y"'
g "merge on default, policy relaxed" allow 'git merge feat/gg-1'
rm -f "$R/CLAUDE.md"
g "switch -c bad name" deny 'git switch -c mybranch'
g "switch -c good name" allow 'git switch -c feat/gg-2'
g "worktree add -b bad name" deny 'git worktree add ../w -b foo'
g "branch -D" deny 'git branch -D x'
g "tag non-semver" deny 'git tag v1.2'
g "tag semver" allow 'git tag v1.2.0'
g "tag -l" allow 'git tag -l'
g "subagent merge" deny 'git merge x' coder
g "subagent worktree remove" deny 'git worktree remove ../w' coder
g "subagent branch -d" deny 'git branch -d x' coder
g "subagent worktree list" allow 'git worktree list' coder
git -C "$R" worktree add -q "$TMP/wt1" -b feat/gg-5
printf 'y\n' > "$TMP/wt1/g.txt"; git -C "$TMP/wt1" add -A; git -C "$TMP/wt1" commit -qm "feat(gg-5): g"
g "worktree remove unmerged" deny "git worktree remove $TMP/wt1"
git -C "$R" merge -q feat/gg-5
g "worktree remove merged" allow "git worktree remove $TMP/wt1"
git -C "$R" switch -q -c feat/gg-9
g "cc: scoped" allow 'git commit -m "feat(gg-1): add"'
g "cc: no scope" deny 'git commit -m "feat: add"'
g "cc: not conventional" deny 'git commit -m "added"'
g "cc: add && commit -am" allow 'git add . && git commit -am "fix(gg-1): t"'
g "cc: subject > 72" deny "git commit -m \"feat(gg-1): $(printf 'x%.0s' $(seq 70))\""
g "cc: heredoc" allow $'git commit -m "$(cat <<\'EOF\'\nfeat(gg-1): s\n\nbody\nEOF\n)"'
g "cc: heredoc ! without footer" deny $'git commit -m "$(cat <<\'EOF\'\nfeat(gg-1)!: x\n\nbody\nEOF\n)"'
g "cc: heredoc ! with footer" allow $'git commit -m "$(cat <<\'EOF\'\nfeat(gg-1)!: x\n\nbody\n\nBREAKING CHANGE: api\nEOF\n)"'
g "cc: amend --no-edit" allow 'git commit --amend --no-edit'
g "cc: unknown type" deny 'git commit -m "wip(gg-1): x"'
g "literal: subject mentions refactor" allow 'git commit -m "refactor(gg-9): clean up imports"'
g "literal: subject mentions push" allow 'git commit -m "feat(gg-9): add push notifications"'
g "literal: heredoc body mentions stash" allow $'git commit -F - <<\'EOF\'\ntest(gg-9): cover shelving\n\nReplaces the old stash-based flow.\nEOF'
g "literal: heredoc body mentions checkout" allow $'git commit -F - <<\'EOF\'\nfix(gg-9): tidy\n\nThe checkout page now loads.\nEOF'
g "literal: subagent heredoc body mentions git merge" allow $'git commit -F - <<\'EOF\'\nfeat(gg-9): x\n\nThis runs before git merge happens.\nEOF' coder
g "literal: heredoc body mentions -f" allow $'git commit -F - <<\'EOF\'\nfix(gg-9): x\n\nDrop the -f flag from rm.\nEOF'
g "literal: bd note mentions git stash" allow $'bd update gg-9 --append-notes "$(cat <<\'EOF\'\nAvoided git stash per the rules.\nEOF\n)"'
g "literal: real stash after quoted message" deny 'git commit -m "fix(gg-9): x" && git stash'
g "literal: real stash after quoted heredoc" deny $'bd update gg-9 --append-notes "$(cat <<\'EOF\'\nnote\nEOF\n)" && git stash'
git -C "$R" switch -q --detach
g "commit on detached HEAD" deny 'git commit -m "feat(gg-1): x"'

# merge into the default branch: the ask prompt carries the artifacts sweep of the
# branch being merged, so the user judges the whole body of work with the findings in view
M="$(mkrepo mergesweep)"; mkdir -p "$M/.beads" "$M/bin"
printf 'Default branch: main\n' > "$M/CLAUDE.md"
printf 'done\n%sjson\n{"artifacts":[{"path":"src/m.py","symbols":["hello_sym"]}]}\n%s\n' "$F" "$F" > "$M/close.txt"
cat > "$M/bin/bd" <<'STUB'
#!/usr/bin/env bash
# test stub: `bd list --status=closed --json` answers with one closed issue whose close reason is ../close.txt
here="$(cd "$(dirname "$0")/.." && pwd)"
[ "${1:-}" = list ] || exit 0
jq -nc --rawfile r "$here/close.txt" '[{id:"gg-3", notes:"", close_reason:$r}]'
STUB
chmod +x "$M/bin/bd"
# the fixtures (stub, CLAUDE.md, close.txt) stay untracked: `add -A` would commit them
# on the task branch and the switch back to main would remove them
git -C "$M" switch -q -c feat/gg-3; mkdir -p "$M/src"; printf 'def hello_sym(): pass\n' > "$M/src/m.py"
git -C "$M" add src; git -C "$M" commit -qm "feat(gg-3): add hello_sym"
git -C "$M" switch -q -c feat/gg-4 main; printf 'def other(): pass\n' > "$M/o.py"
git -C "$M" add o.py; git -C "$M" commit -qm "feat(gg-4): unrelated"
git -C "$M" switch -q main
ms() { # name expected-decision command grep-pattern
  local out; out="$(pbash "$M" "$3" | PATH="$M/bin:$PATH" "$HOOKS/guard-git.sh" 2>/dev/null)"
  check "merge sweep: $1" "$2" "$(printf '%s' "$out" | decide)"
  check "merge sweep: $1 reason $4" yes "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' | grep -qE "$4" && echo yes || echo no)"
}
ms "branch carrying the claim" ask 'git merge feat/gg-3' '1 claim\(s\) checked, 0 failed'
ms "branch lacking the claim" ask 'git merge feat/gg-4' 'INTEGRITY SWEEP.*FAILED|MISSING.*hello_sym'
ms "--no-ff and -m before the ref" ask 'git merge --no-ff -m "merge it" feat/gg-3' '0 failed'
ms "unresolvable ref" ask 'git merge nosuchbranch' 'SKIPPED'
printf 'Policy: no issue tracker\n' >> "$M/CLAUDE.md"
ms "tracker off says nothing" ask 'git merge feat/gg-4' '^Merging/rebasing INTO the default branch .main.\. The default branch is main\. Approving'


# ---- guard-bd.sh ---------------------------------------------------------------
b "update --notes" deny 'bd update gg-1 --notes "x"'
b "update --append-notes" allow 'bd update gg-1 --append-notes "x"'
b "inline substitution" deny 'bd update gg-1 --design="$(bd show gg-1 --json | jq .d)"'
b "cat substitution" allow 'bd update gg-1 --design="$(cat f.txt)"'
b "nested bd show does not mask update --notes" deny 'bd update gg-1 --notes "$(bd show gg-2 --json | jq -r .notes) extra"'
b "nested bd show in --design=" deny 'bd update gg-1 --design="$(bd show gg-1 --json)"'
b "--status=closed" deny 'bd update gg-1 --status=closed'
b "subagent close" deny 'bd close gg-1 --reason-file r.md' coder
b "close" allow 'bd close gg-1 --reason-file r.md'
b "edit" deny 'bd edit gg-1'
b "label add human" ask 'bd label add gg-1 human'
b "show" allow 'bd show gg-1'
b "echo bd --notes" allow 'echo bd --notes'
b "literal: append-notes heredoc mentions --notes" allow $'bd update gg-9 --append-notes "$(cat <<\'EOF\'\nNever use --notes; it replaces.\nEOF\n)"'
b "literal: nested bd show in double quotes still visible" deny 'bd update gg-9 --design="$(bd show gg-1 --json)"'
# Rule 6 in guard-bd.sh is dormant (commented out); uncomment these with it.
# b "create work bead without --acceptance" deny 'bd create "Leaf" -t task --parent gg-1'
# b "create work bead with --acceptance" allow 'bd create "Leaf" -t task --acceptance "1. given x when y then z"'
# b "create epic without --acceptance" allow 'bd create "Epic" -t epic'
# b "create decision without --acceptance" allow 'bd create "Approve spec" -t decision -l human'

# ---- guard-edit.sh -------------------------------------------------------------
R="$(mkrepo edit)"; mkdir -p "$R/src" "$R/tests"; : > "$R/src/mod.py"; : > "$R/tests/test_mod.py"
e global "add TODO" deny "$(pedit "$R" "$R/src/mod.py" 'a' $'a\n# TODO: x')"
e global "add FIXME:" deny "$(pedit "$R" "$R/src/mod.py" 'a' 'FIXME: later')"
e global "TODO count unchanged" allow "$(pedit "$R" "$R/src/mod.py" '# TODO: a' '# TODO: b')"
e global "prose mentioning todos" allow "$(pedit "$R" "$R/src/mod.py" 'a' 'Never write TODOs. TodoWrite. todo_list')"
e global "write new file with // TODO" deny "$(pwrite "$R" "$R/new.js" '// TODO fix')"
printf 'Policy: todo-comments allowed\n' > "$R/CLAUDE.md"
e global "write TODO, policy relaxed" allow "$(pwrite "$R" "$R/new.js" '// TODO fix')"
rm -f "$R/CLAUDE.md"
e coder "edit test file" deny "$(pedit "$R" "$R/tests/test_mod.py" a b)"
e coder "edit src file" allow "$(pedit "$R" "$R/src/mod.py" a b)"
e coder "write _test.go" deny "$(pwrite "$R" "$R/pkg/foo_test.go" x)"
eb coder "redirect into tests/" deny 'echo x > tests/test_new.py'
eb coder "run pytest" allow 'pytest tests/ -q 2>&1 | tail -5'
eb coder "sed -i test file" deny 'sed -i s/a/b/ tests/test_mod.py'
e coder "literal: subagent append-notes heredoc mentions tests path" allow "$(pbash "$R" $'bd update gg-9 --append-notes "$(cat <<\'EOF\'\nInput -> output; see tests/test_x.py\nEOF\n)"' coder)"
e coder "literal: subagent redirect into tests/" deny "$(pbash "$R" 'echo x > tests/test_new.py' coder)"
O="$TMP/outside/scratch"; mkdir -p "$O"
e coder "write scratch file outside repo" allow "$(pwrite "$R" "$O/notes.md" x)"
printf 'Test-paths: src/**/*_spec.rb\n' > "$R/CLAUDE.md"
e coder "write Test-paths match" deny "$(pwrite "$R" "$R/src/a/b_spec.rb" x)"
e coder "write Test-paths ** zero depth" deny "$(pwrite "$R" "$R/src/a_spec.rb" x)"
e coder "write Test-paths ** two deep" deny "$(pwrite "$R" "$R/src/a/b/c_spec.rb" x)"
e coder "write Test-paths wrong root" allow "$(pwrite "$R" "$R/lib/a_spec.rb" x)"
e coder "write Test-paths suffix mismatch" allow "$(pwrite "$R" "$R/src/a_spec.rbx" x)"
e tester "write Test-paths match" allow "$(pwrite "$R" "$R/src/a/b_spec.rb" x)"
e tester "write Test-paths ** two deep" allow "$(pwrite "$R" "$R/src/a/b/c_spec.rb" x)"
rm -f "$R/CLAUDE.md"
e tester "edit test file" allow "$(pedit "$R" "$R/tests/test_mod.py" a b)"
e tester "edit src file" ask "$(pedit "$R" "$R/src/mod.py" a b)"
eb tester "git add && commit" allow 'git add tests && git commit -m "test(gg-1): x"'
eb tester "redirect into src/" ask 'echo x > src/mod.py'
e tester "write scratch file outside repo" allow "$(pwrite "$R" "$O/bd_notes.md" x)"
eb tester "heredoc redirect outside repo" allow $'cat > '"$O"$'/commit_msg.txt <<EOF\ntest(gg-1): x\nEOF'
eb tester "redirect into tests/" allow 'echo x > tests/test_new.py'
e tester "write src file (absolute, in repo)" ask "$(pwrite "$R" "$R/src/mod.py" x)"
eb auditor "git commit" deny 'git commit -m x'
eb auditor "git log && diff" allow 'git log --oneline && git diff main...HEAD'
eb auditor "bd update" deny 'bd update gg-1 --append-notes x'
eb auditor "bd show" allow 'bd show gg-1 --json'
eb auditor "redirect to file" deny 'pytest > out.txt'
eb auditor "pipe to tail" allow 'pytest -q 2>&1 | tail'
eb auditor "redirect to /dev/null" allow 'ls >/dev/null 2>&1'
eb surveyor "git commit" deny 'git commit -m x'
eb surveyor "bd show" allow 'bd show gg-1 --json'
eb surveyor "grep -rn" allow 'grep -rn "def foo" src/'
eb spec-auditor "bd create" deny 'bd create "x" -t task'
eb spec-auditor "redirect to file" deny 'bd show gg-1 > spec.txt'
eb spec-auditor "bd list --json | jq" allow 'bd list --parent gg-1 --json | jq .'

# ---- guard-dispatch.sh ---------------------------------------------------------
R="$(mkrepo dispatch)"
TODO_PL="$(jq -nc --arg cwd "$R" '{tool_name:"TodoWrite",cwd:$cwd,tool_input:{}}')"
run "dispatch: TodoWrite without .beads" allow "$TODO_PL" guard-dispatch.sh
mkdir -p "$R/.beads"
run "dispatch: TodoWrite with .beads" deny "$TODO_PL" guard-dispatch.sh
run "dispatch: Agent general-purpose" deny "$(pagent "$R" general-purpose)" guard-dispatch.sh
run "dispatch: Agent no subagent_type" deny "$(pagent "$R")" guard-dispatch.sh
run "dispatch: Agent coder" allow "$(pagent "$R" coder)" guard-dispatch.sh
run "dispatch: Agent Explore" allow "$(pagent "$R" Explore)" guard-dispatch.sh
run "dispatch: Agent surveyor" allow "$(pagent "$R" surveyor)" guard-dispatch.sh
run "dispatch: Agent spec-auditor" allow "$(pagent "$R" spec-auditor)" guard-dispatch.sh
printf 'Policy: no issue tracker\n' > "$R/CLAUDE.md"
run "dispatch: TodoWrite, tracker off" allow "$TODO_PL" guard-dispatch.sh

# ---- learnings-context.sh ------------------------------------------------------
L="$(mkrepo learn)"; mkdir -p "$L/learnings"; printf '# x\n' > "$L/learnings/x.md"
LPL="$(jq -nc --arg cwd "$L" '{cwd:$cwd,session_id:"s1"}')"
run "learnings: SessionStart with entries" ctx "$LPL" learnings-context.sh SessionStart
run "learnings: SessionStart without dir" allow "$(jq -nc --arg cwd "$R" '{cwd:$cwd,session_id:"s1"}')" learnings-context.sh SessionStart
rm -f "${TMPDIR:-/tmp}"/claude-learnings-nudge-*
run "learnings: PostToolUseFailure first" ctx "$LPL" learnings-context.sh PostToolUseFailure
run "learnings: PostToolUseFailure rate-limited" allow "$LPL" learnings-context.sh PostToolUseFailure

# ---- post-merge-status.sh ------------------------------------------------------
R="$(mkrepo merge)"; : > "$R/stray"
run "post-merge: untracked present" ctx "$(pbash "$R" 'git merge feat/x')" post-merge-status.sh
run "post-merge: --abort" allow "$(pbash "$R" 'git merge --abort')" post-merge-status.sh
rm -f "$R/stray"
run "post-merge: clean tree" allow "$(pbash "$R" 'git merge feat/x')" post-merge-status.sh

# ---- require-artifacts-block.sh ------------------------------------------------
A="$TMP/art"; mkdir -p "$A"
printf 'Done.\n\n%sjson\n{"artifacts":[{"path":"src/m.py","symbols":["hello_sym"]}]}\n%s\n' "$F" "$F" > "$A/good.md"
printf 'Done, no block.\n' > "$A/bad.md"
run "artifacts: --reason-file valid" allow "$(pbash "$A" 'bd close gg-1 --reason-file good.md')" require-artifacts-block.sh
run "artifacts: --reason-file no block" deny "$(pbash "$A" 'bd close gg-1 --reason-file bad.md')" require-artifacts-block.sh
run "artifacts: --reason-file missing" allow "$(pbash "$A" 'bd close gg-1 --reason-file nope.md')" require-artifacts-block.sh
run "artifacts: inline --reason" deny "$(pbash "$A" 'bd close gg-1 --reason "done"')" require-artifacts-block.sh

# ---- bd-verify-artifacts.sh ----------------------------------------------------
V="$(mkrepo verify)"; mkdir -p "$V/src"; printf 'def hello_sym():\n    pass\n' > "$V/src/m.py"
cp "$A/good.md" "$V/good.txt"
printf '%sjson\n{"artifacts":[{"path":"src/m.py","symbols":["nope_sym"]}]}\n%s\n' "$F" "$F" > "$V/bad.txt"
out="$(cd "$V" && "$HOOKS/bd-verify-artifacts.sh" --ref worktree --text-file "$V/good.txt")"; rc=$?
check "verify: existing symbol exits 0" 0 "$rc"
out="$(cd "$V" && "$HOOKS/bd-verify-artifacts.sh" --ref worktree --text-file "$V/bad.txt")"; rc=$?
check "verify: missing symbol exits 1" 1 "$rc"
check "verify: missing symbol reports MISSING" yes "$(printf '%s' "$out" | grep -q MISSING && echo yes || echo no)"
# several blocks (a resumed agent appends another) are folded in order: every claim
# is checked, and the last record for a path+symbol wins
vt() { # name expected-rc block1-json block2-json [grep-pattern]
  printf 'first\n%sjson\n%s\n%s\nsecond\n%sjson\n%s\n%s\n' "$F" "$3" "$F" "$F" "$4" "$F" > "$V/multi.txt"
  out="$(cd "$V" && "$HOOKS/bd-verify-artifacts.sh" --ref worktree --text-file "$V/multi.txt")"; rc=$?
  check "verify: $1" "$2" "$rc"
  [ -n "${5:-}" ] && check "verify: $1 reports $5" yes "$(printf '%s' "$out" | grep -q "$5" && echo yes || echo no)"
}
printf 'def other_sym():\n    pass\n' > "$V/src/n.py"
vt "two blocks, both checked" 0 \
  '{"artifacts":[{"path":"src/m.py","symbols":["hello_sym"]}]}' \
  '{"artifacts":[{"path":"src/n.py","symbols":["other_sym"]}]}' '2 claim(s) checked'
vt "earlier claim not restated is still checked" 1 \
  '{"artifacts":[{"path":"src/m.py","symbols":["gone_sym"]}]}' \
  '{"artifacts":[{"path":"src/m.py","symbols":["hello_sym"]}]}' 'MISSING.*gone_sym'
vt "later removed record overrides earlier present" 0 \
  '{"artifacts":[{"path":"src/m.py","symbols":["gone_sym"]}]}' \
  '{"artifacts":[{"path":"src/m.py","symbols":["gone_sym"],"state":"removed"},{"path":"src/m.py","symbols":["hello_sym"]}]}'
vt "later present record overrides earlier removed" 0 \
  '{"artifacts":[{"path":"src/m.py","symbols":["hello_sym"],"state":"removed"}]}' \
  '{"artifacts":[{"path":"src/m.py","symbols":["hello_sym"]}]}'
vt "malformed block ahead of a good one" 1 \
  '{"artifacts":[{"path":"src/m.py","symbols":["hello_sym"]}' \
  '{"artifacts":[{"path":"src/m.py","symbols":["hello_sym"]}]}' 'MALFORMED'

# ---- subagent-integrity.sh stop ------------------------------------------------
S="$(mkrepo stop)"; mkdir -p "$S/src"; printf 'def hello_sym():\n    pass\n' > "$S/src/m.py"
git -C "$S" add -A; git -C "$S" commit -qm "feat(gg-1): add thing"
run "stop: coder, no block in commit body" block "$(pstop "$S" coder 'Done.' false)" subagent-integrity.sh stop
run "stop: coder, ESCALATION" allow "$(pstop "$S" coder 'ESCALATION: blocked' false)" subagent-integrity.sh stop
run "stop: coder, stop_hook_active" allow "$(pstop "$S" coder 'Done.' true)" subagent-integrity.sh stop
printf 'feat(gg-1): add thing\n\n%sjson\n{"artifacts":[{"path":"src/m.py","symbols":["hello_sym"]}]}\n%s\n' "$F" "$F" > "$TMP/msg"
git -C "$S" commit -q --amend -F "$TMP/msg"
run "stop: coder, valid block" allow "$(pstop "$S" coder 'Done.' false)" subagent-integrity.sh stop
sed -i 's/hello_sym/nope_sym/' "$TMP/msg"; git -C "$S" commit -q --amend -F "$TMP/msg"
run "stop: coder, block names missing symbol" block "$(pstop "$S" coder 'Done.' false)" subagent-integrity.sh stop
run "stop: auditor skipped" allow "$(pstop "$S" auditor 'Done.' false)" subagent-integrity.sh stop
run "stop: surveyor skipped" allow "$(pstop "$S" surveyor 'Done.' false)" subagent-integrity.sh stop
run "stop: spec-auditor skipped" allow "$(pstop "$S" spec-auditor 'Done.' false)" subagent-integrity.sh stop
# claims are verified in the agent's own worktree (payload cwd), never the main checkout
W="$(mkrepo stopwt)"; git -C "$W" switch -q -c feat/gg-7
WT="$W/.claude/worktrees/agent-a9"; git -C "$W" worktree add -q "$WT" -b worktree-agent-a9
mkdir -p "$WT/src"; printf 'def only_in_worktree(): pass\n' > "$WT/src/gate_only.py"
printf 'feat(gg-7): add gate_only\n\n%sjson\n{"artifacts":[{"path":"src/gate_only.py","symbols":["only_in_worktree"]}]}\n%s\n' "$F" "$F" > "$TMP/wtmsg"
git -C "$WT" add -A; git -C "$WT" commit -q -F "$TMP/wtmsg"
mkdir -p "$W/learnings"; printf '# lesson\n' > "$W/learnings/gg-7-note.md"
git -C "$W" add learnings; git -C "$W" commit -qm "docs(gg-7): record a lesson"
run "stop: coder, cwd is own worktree" allow "$(pstop "$WT" coder 'Done.' false)" subagent-integrity.sh stop
run "stop: coder, cwd is main checkout with same-scoped commit" block "$(pstop "$W" coder 'Done.' false)" subagent-integrity.sh stop
printf '# more\n' >> "$WT/src/gate_only.py"
sed -i 's/add gate_only/claim not_there/; s/only_in_worktree/not_there/' "$TMP/wtmsg"
git -C "$WT" add -A; git -C "$WT" commit -q -F "$TMP/wtmsg"
out="$(pstop "$WT" coder 'Done.' false | "$HOOKS/subagent-integrity.sh" stop 2>/dev/null)"
check "stop: coder, worktree block names missing symbol" block "$(printf '%s' "$out" | decide)"
check "stop: reason names the missing symbol" yes "$(printf '%s' "$out" | jq -r '.reason // ""' | grep -q not_there && echo yes || echo no)"

# the issue id is read from the agent's transcript; a project prefix may itself contain
# hyphens (pdf-service-jqy), and a truncated id (pdf-service) finds no bead and blocks
B="$(mkrepo hyphen)"; mkdir -p "$B/.beads" "$B/bin" "$B/src"; printf 'def hello_sym():\n    pass\n' > "$B/src/m.py"
printf 'note\n%sjson\n{"artifacts":[{"path":"src/m.py","symbols":["hello_sym"]}]}\n%s\n' "$F" "$F" > "$B/notes.txt"
printf 'pdf-service-jqy\n' > "$B/want"
cat > "$B/bin/bd" <<'STUB'
#!/usr/bin/env bash
# test stub: answers `bd show <id> --json` for exactly the id in ../want, else nothing
here="$(cd "$(dirname "$0")/.." && pwd)"
[ "${1:-}" = show ] && [ "${2:-}" = "$(cat "$here/want")" ] || exit 0
jq -nc --arg id "$2" --rawfile n "$here/notes.txt" '[{id:$id, notes:$n, close_reason:""}]'
STUB
chmod +x "$B/bin/bd"
printf 'bd show pdf-service-jqy\nbd update pdf-service-jqy --append-notes x\n' > "$B/transcript"
ptx() { jq -nc --arg cwd "$1" --arg tp "$2" \
  '{cwd:$cwd,agent_id:"a9",agent_type:"coder",last_assistant_message:"Done.",stop_hook_active:false,agent_transcript_path:$tp}'; }
out="$(ptx "$B" "$B/transcript" | PATH="$B/bin:$PATH" "$HOOKS/subagent-integrity.sh" stop 2>/dev/null)"
check "stop: hyphenated project prefix in bead id" allow "$(printf '%s' "$out" | decide)"

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
