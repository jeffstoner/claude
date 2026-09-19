---
name: git-recovery
description: Recover uncommitted or lost git work (a dropped stash, a bad reset, a vanished file, a subagent's work that is not in the tree) from unreachable objects before re-deriving it. Use when work that should exist is missing from the repository.
---

# Recovering lost work

Uncommitted work that appears lost is usually still in the object store. Check before re-deriving.

1. List unreachable commits (dropped stashes and reset-away commits live here):

   ```bash
   git fsck --unreachable --no-reflogs | grep commit
   ```

2. Inspect candidates, newest first:

   ```bash
   for c in $(git fsck --unreachable --no-reflogs | awk '/commit/{print $3}'); do
     git log -1 --format='%h %ci %s' "$c"
   done | sort -k2,3 -r
   git show <sha> --stat
   git diff HEAD <sha> -- <path>
   ```

3. Also check the reflog for each branch and for HEAD: `git reflog show --all | head -50`.

4. Unreachable blobs (a file that was `git add`ed but never committed) can be listed with
   `git fsck --lost-found`; they land in `.git/lost-found/other/` and can be inspected with
   `git show <blob-sha>`.

5. Recover onto your task branch, never onto the default branch. Cherry-pick a whole commit, or
   pull a single file out of it (the guard blocks pathspec checkouts, so use `git show`):

   ```bash
   git switch -c fix/<issue-id>-recovered
   git cherry-pick <sha>                 # whole commit
   git show <sha>:<path> > <path>        # one file
   ```

6. **Still diff the recovery against a re-derivation.** The recovered version may predate refactors
   HEAD has since absorbed.

7. Record what happened. If work was lost to a tree operation, that is exactly the failure the
   learnings directory exists for.
