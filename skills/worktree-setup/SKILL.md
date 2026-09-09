---
name: worktree-setup
description: Git worktrees for multi-agent work — how the harness-created agent worktrees under .claude/worktrees/ work, how to find and clean them, the read-only baseline worktree, and venv/node_modules sharing. Use when preparing to dispatch agents, locating an agent's branch, or when a worktree lacks dependencies.
---

# Worktrees for concurrent agents

One worktree per concurrent agent: each gets its own index, working tree and HEAD, so a stash,
checkout or reset in one cannot reach another. Agents see each other's work only through commits
merged into the integration branch; a new worktree branches from that branch's HEAD at the moment it
is created.

## Agent worktrees are created by the harness

The `tester` and `coder` agents declare `isolation: worktree`. On dispatch the harness creates
`.claude/worktrees/agent-<id>/` from the current HEAD on a generated branch and makes it the agent's
working directory. **Do not create a second worktree for such an agent and do not pass `isolation`
in the dispatch.** An agent with two worktrees works in one while its cwd is the other.

Find an agent's worktree and branch after it stops:

```bash
git worktree list --porcelain
# worktree /repo/.claude/worktrees/agent-abc123
# HEAD <sha>
# branch refs/heads/<generated-name>
git -C /repo/.claude/worktrees/agent-abc123 log -1 --format=%s   # type(<bead-id>): ...
```

The commit scope carries the bead id; the generated branch name does not. Merge that branch into
the integration branch after the audit, then remove the worktree and delete the branch with `-d`:

```bash
git merge <generated-name>
git worktree remove .claude/worktrees/agent-abc123      # the guard confirms the branch is merged
git branch -d <generated-name>
```

Remove only after the bead is closed: a resumed agent keeps its working directory, and resume is how
audit findings and merge conflicts go back to the agent that wrote the change. An agent worktree
left with no commits is harmless; remove it in the same pass.

`settings.json` must have `worktree.baseRef: "head"`. The default (`fresh`) branches from
`origin/<default-branch>`, silently omitting local commits.

## Hand-rolled worktrees (fallback only)

For an agent type without `isolation`, or for your own use:

```bash
git worktree add ../wt-<issue-id> -b <type>/<issue-id>      # from the current HEAD
git merge <type>/<issue-id>                                   # after the audit
git worktree remove ../wt-<issue-id>
```

The `<type>/<issue-id>` naming rule applies to branches you or an agent create by hand, not to the
harness's generated names.

## The baseline worktree

Keep one read-only worktree pinned at the integration branch's HEAD and never modify it. It is the
replacement for `git stash` when asking "is this failure pre-existing?": run the test there.

```bash
git worktree add --detach ../wt-baseline HEAD
git -C ../wt-baseline checkout --detach <new-head>    # after each merge into the integration branch
```

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
