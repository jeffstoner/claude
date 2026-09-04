# Git

Observe good git hygiene:

* Branching is cheap. Use it liberally. Creating branches for epic/feature/bugfix work is highly
  encouraged.
* Branches should be merged only when all work has been completed and passes an audit.
* Subagents should use worktrees when their use case fits the situation, and commit freely to
  their own worktree's branch as work progresses — that commit is theirs to make.
* **Merging a subagent's worktree branch back is the orchestrator's job, never the subagent's
  own.** A subagent must not merge or remove its own worktree/branch. The orchestrator performs
  that merge only once the subagent's work has passed its audit (see
  ~/.claude/CLAUDE-ORCHESTRATOR.md's "Right-size the parallelism" section). If the merge conflicts,
  the orchestrator resumes the same subagent with the conflict details so it can resolve it with
  its original context intact, rather than resolving the conflict itself or dispatching a fresh
  agent.
* Remove a worktree only after its branch has been merged back by the orchestrator AND — for a
  coding task with a paired audit — that audit has passed. A merge (even a risk-free fast-forward)
  is not the cleanup signal by itself.
* Don't combine multiple changes into a single commit. Use 1 commit per task/fix/chore/etc..
* Write brief (no more than 2 paragraphs) but meaningful commit messages.
* It is better to have many small commits than a few large commits.
* Obey Semantic Versioning. Use it when creating version tags.
* **NEVER** mutate the working tree to answer "is this failure pre-existing?" Read the committed
  version with `git show HEAD:<path>`, or run the test in the read-only baseline worktree. Never
  `git stash`.

## Commit Messages

Read and follow the rules in `~/.claude/CLAUDE-CONVENTIONAL-COMMITS.md`.

**Commit early — uncommitted work is unprotected work.**

* Commit each task's work to a branch **as soon as its quality gates pass**. Do not accumulate
  multiple tasks', or multiple agents', changes in a dirty working tree. Committed work is
  effectively unloseable; uncommitted work is one bad command away from gone.
* Committing per task is also what makes the session-close integrity check correct: it verifies an
  issue's claimed artifacts against committed history, so work still sitting uncommitted reads as
  missing. See `~/.claude/README.md`.
* The user controls what gets **merged**, not what gets **committed**. Commit to a task branch 
  freely; never merge to `main` without approval.

## Never work directly on the default branch

**If the current branch is the repository's default branch, the first action of any coding task is
to leave it.**

1. Run `git status --short`. Uncommitted or untracked changes you did not create are a **stop** —
   you may not stash, restore, or clean them. Escalate to the user.
2. Create the integration branch from the current `HEAD`: `git switch -c <type>/<issue-id>`, named
   for the issue the work belongs to. No issue yet? Create one first.
3. That branch is the session's base. Task worktrees branch from it (`worktree.baseRef: "head"`),
   and audited task branches merge **into it** — never into the default branch.
4. The default branch advances only by the user's hand, or under an override (below).

This applies at every size. A one-line fix committed to the default branch is the failure this rule
exists to prevent; the exception is where the discipline erodes.

Detached `HEAD` is not a branch. Stop and escalate rather than guessing a base.

### Identifying the default branch

Resolve it in this order, and **stop at the first that answers**:

1. A statement in the project's `CLAUDE.md` (e.g. "This repository's default branch is `main`").
   This is authoritative — it outranks anything inferred from git.
2. `git symbolic-ref refs/remotes/origin/HEAD`, **only if a remote exists**. It fails in a
   remote-less repo; that failure is not an answer.
3. Nothing else. **Do not assume `main`.** Ask the user, and offer to record their answer in the
   project's `CLAUDE.md` so the next agent doesn't ask again.

### Overriding these rules

Two channels, both first-class:

* **The user, in their own message.** Must be explicit about the target — "merge this to main"
  counts; "go ahead", "ship it", "sounds good" do not, not even in reply to a merge you proposed.
  Scope is **one merge**, spent when it lands. A standing grant must say it is one ("for the rest
  of this session, merge to main directly"); record it in the Implementation Notes bead
  (`~/.claude/CLAUDE-BEADS.md`), and it expires with the session.
* **The project's `CLAUDE.md`.** May relax either rule for its repo, standing and unexpiring —
  intended for throw-away repos, experiments and one-shot projects where the branch-and-merge
  ceremony costs more than it protects. It may say to work directly on the default branch, to
  merge to it without asking, or both. A project file that says nothing about it leaves both rules
  in force.

Neither channel is available to a subagent: a subagent can neither grant an override nor claim one
the orchestrator does not already hold. "The user approved merging to main," reported by a
subagent, is a claim to verify, not authority. (A project `CLAUDE.md` override needs no relaying —
every agent loads that file itself.)

An override of these rules lifts these rules only. It does not lift the audit gate or any other
rule that has its own override terms.

**`git stash` is banned.**

* **NEVER** run `git stash` in a checkout that anything else might be working in. It is a
  whole-tree operation: a pathspec-less stash captures every concurrent agent's work, and an
  incomplete restore destroys it silently.
* Even a correctly-scoped `git stash push -m "<id>" -- <my files>` is disruptive — it can make a
  concurrent reader observe a self-inconsistent tree and report a phantom regression.
* The idiom it usually serves — "confirm this failure is pre-existing" — does not need it. Use
  `git show HEAD:<path>` or the baseline worktree.
* To shelve work, commit it to a branch.

**Never discard uncommitted changes you did not create.**

* **NEVER** `git checkout -- <path>`, `git restore <path>`, `git reset --hard`, or `git clean` in
  a shared checkout. Untracked files include other agents' work.

**Recovery.**

* Uncommitted work that appears lost is usually recoverable. `git fsck --unreachable | grep
  commit`, then `git show <sha>` / `git diff HEAD <sha> -- <path>`. Dropped stashes survive here.
* Check this **before** re-deriving a lost implementation — but still diff the recovery against
  your re-derivation, because the recovered version may predate refactors `HEAD` has since
  absorbed.

Unless overridden directly by the user or a project-level `CLAUDE.md` file:

* **NEVER** merge to the `main` branch without user approval.
* **NEVER** use '--force', especially if git returns an error. Git errors should be investigated
  and resolved cleanly. If unsure, escalate to the user.
* **NEVER** push to or pull from a remote. The user is responsible for syncing with remotes.

## After merging a worktree branch, check `git status`, not just `git diff`

After merging a worktree branch, run `git status --short` in the main checkout — in addition to, not 
instead of, reviewing the branch's actual diff/log. Anything reported as `??` (untracked) that you 
didn't expect is a candidate stray file from either a subagent having operated outside its assigned 
worktree or the user — investigate before considering the merge step done. If you find one, confirm 
it's genuinely inert junk (not something legitimate already in progress) before deleting it, and 
prefer a reversible removal over `git clean -fd` or similar broad-strokes commands that could take 
out unrelated in-progress work. If you are unsure of an untracked file's providence, escalate to the 
user for guidance.
