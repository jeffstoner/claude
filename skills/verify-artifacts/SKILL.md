---
name: verify-artifacts
description: Sanity-check that every closed issue's artifacts claims (files, symbols) actually exist in the repository, against HEAD, a named branch, or the working tree. Use before merging a body of work to the default branch, when a close reason looks doubtful, or at any point the user wants to know whether closed work really landed.
---

# Verifying artifacts claims

`bd-verify-artifacts.sh` answers one question: does the code a closed issue claims exist at the
given ref? It does not judge correctness (that is the audit) or authorship. The merge-to-default
prompt runs it automatically against the branch being merged; this skill is for running it at any
other moment.

1. Pick the ref. `HEAD` is the current branch; name a branch to check what a merge would bring in;
   `worktree` checks the files on disk, including uncommitted work.

   ```bash
   ~/.claude/hooks/bd-verify-artifacts.sh                          # every closed issue, against HEAD
   ~/.claude/hooks/bd-verify-artifacts.sh --ref <branch>           # against a branch about to be merged
   ~/.claude/hooks/bd-verify-artifacts.sh --ref worktree           # against the files on disk
   ~/.claude/hooks/bd-verify-artifacts.sh <issue-id> ...           # specific issues, open or closed
   ~/.claude/hooks/bd-verify-artifacts.sh --text-file <path>       # a block held in a file (tracking off)
   ```

   Run it from inside the repository. Exit 0 means every claim held; exit 1 means at least one did
   not. The last line is the summary: issues scanned, claims checked, failed, malformed, without a
   block.

2. Read each finding. `MISSING` is a file or symbol the issue claims but the ref lacks.
   `NOT-REMOVED` is a symbol claimed deleted that is still there. `MALFORMED` is an artifacts block
   that does not parse, which counts as a failure because a checker that reads a broken block as
   absent passes silently.

3. Report every finding to the user before doing anything else. Name the issue id, the path and the
   symbol. A `MISSING` against `HEAD` while `--ref worktree` passes means the work is uncommitted;
   say so rather than calling it lost.

4. For a genuine gap, the remedy is the user's call. The options, in order of preference: the work
   is on another branch (check `git branch --contains` and the worktrees); the work is recoverable
   (`git-recovery` skill); the claim is wrong and the issue should be reopened and its notes
   appended with a corrected block (`bd update <id> --append-notes`, never `--notes`). Do not
   reopen or edit issues without being asked.

5. "Without a block" issues are not checked. Issues closed before the artifacts convention existed
   land here; they are a coverage gap, not a failure. Mention the count if it is non-zero.
