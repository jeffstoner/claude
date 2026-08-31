# Git

Observe good git hygiene:

* Branching is cheap. Use it liberally. Creating branches for epic/feature/bugfix work is highly
  encouraged.
* Branches should be merged only when all work has been completed and passes an audit.
* Subagents should use worktrees when their use case fits the situation.
* Remove worktrees once their changes have been merged back into the main worktree AND — for a 
  coding task with a paired audit — once that audit has passed. A merge (even a risk-free 
  fast-forward) is not the cleanup signal by itself; see ~/.claude/CLAUDE-ORCHESTRATOR.md's 
  "Right-size the parallelism" section for why.
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
