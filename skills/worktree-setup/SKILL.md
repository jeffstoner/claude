---
name: worktree-setup
description: Set up git worktrees for multi-agent work — a hand-rolled per-task worktree, the read-only baseline worktree pinned at HEAD, and the venv/node_modules sharing rules. Use when preparing to dispatch agents or when a worktree lacks dependencies.
---

# Worktrees for concurrent agents

One worktree per concurrent agent: each gets its own index, working tree and HEAD, so a stash,
checkout or reset in one cannot reach another. The `Agent` tool's `isolation: "worktree"` does this
natively and the `coder` and `tester` agents declare it; prefer that over hand-rolling.

## Hand-rolled worktree

```bash
git worktree add ../wt-<issue-id> -b <type>/<issue-id>      # from the current HEAD
# ... agent works there, commits to its branch ...
git merge <type>/<issue-id>                                   # orchestrator, after the audit
git worktree remove ../wt-<issue-id>                          # only after the merge (the guard checks)
```

`settings.json` must have `worktree.baseRef: "head"`. The default (`fresh`) branches from
`origin/<default-branch>`, silently omitting local commits.

## The baseline worktree

Keep one read-only worktree pinned at the integration branch's HEAD and never modify it. It is the
replacement for `git stash` when asking "is this failure pre-existing?": run the test there.

```bash
git worktree add --detach ../wt-baseline HEAD
```

Re-create it after each merge into the integration branch, or `git -C ../wt-baseline checkout --detach <new-head>`.

## Dependencies

A worktree does not need its own virtualenv or `node_modules`:

1. `worktree.symlinkDirectories: ["node_modules", ".venv"]` in `settings.json` symlinks the named
   directories from the main checkout into each worktree. Whether nested paths such as `api/.venv`
   are honoured is unverified; test before relying on it.
2. Or invoke the main checkout's interpreter by absolute path with the worktree as CWD. For a
   `src`-layout Python project with `pythonpath = ["src"]` and no editable install, the venv holds
   only third-party dependencies, so imports resolve to the worktree's `src`.

## Shared test infrastructure is the real scaling limit

If each test module stands up its own container or database, N agents multiply that N times and
you will see genuine transient failures. Prefer a session-scoped service with per-test schema
isolation. Tell agents in a shared checkout not to run the full suite while others edit; with
per-agent worktrees that restriction disappears, which is most of the argument for worktrees.
