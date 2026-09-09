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

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
