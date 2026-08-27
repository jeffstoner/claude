# Hooks

Instructions are advisory; hooks are enforcement. Any rule that must not be broken under
pressure belongs in a `PreToolUse` hook, not only in this file.

Note the division of labour: a hook blocks **the model**. The user can always run the same
command themselves with `!` in the prompt. So a hook that over-blocks costs a round trip; a
missing hook can cost a day's work.


## Guard Git

The `Guard Git` is a hook that helps prevent dangerous git commands from landing the repo, potentially
destroying work.

**`~/.claude/settings.json`** — merge into the existing file, do not replace it (the current file
has `model`, `enabledPlugins`, `extraKnownMarketplaces`, `tui`, `skipWorkflowUsageWarning` and no
`hooks` key):

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "if": "Bash(git *)",
            "command": "~/.claude/hooks/guard-git.sh",
            "timeout": 10,
            "statusMessage": "Checking git safety"
          }
        ]
      }
    ]
  },
  "worktree": {
    "baseRef": "head",
    "symlinkDirectories": ["node_modules", ".venv", "api/.venv"]
  }
}
```

### Notes

Known trade-off: `uses()` matches the subcommand word anywhere, so `git log --grep stash` is
blocked. That is deliberate — over-blocking costs a rephrase, under-blocking cost three
implementations.


##  A `SubagentStop` integrity hook + a `SessionEnd` sweep.

Two complementary checks:

- **`SubagentStart` → `SubagentStop`** (early warning): snapshot the repo when a subagent starts,
  re-check when it stops. Zero delta — no commit, no working-tree change, no new untracked file —
  emits a `systemMessage`. An agent that reports success while changing nothing can be a sign of
  misbehaving agents.
- **`SessionEnd`** (the actual net): run `bd-verify-artifacts.sh` over every closed issue. This 
  checks what is in the issues against what is actually in the code. While this doesn't address
  correctness of the code, it does help ensure that what the agent says it added/removed from the
  code was actually added/removed from the code.

```json
{
  "hooks": {
    "SubagentStart": [
      { "hooks": [ { "type": "command", "command": "~/.claude/hooks/subagent-integrity.sh start", "timeout": 10 } ] }
    ],
    "SubagentStop": [
      { "hooks": [ { "type": "command", "command": "~/.claude/hooks/subagent-integrity.sh stop", "timeout": 10 } ] }
    ],
    "SessionEnd": [
      { "hooks": [ { "type": "command", "command": "~/.claude/hooks/session-close-sweep.sh", "timeout": 60 } ] }
    ]
  }
}
```

### Notes

**Verified behaviour** (synthetic payloads piped to the script):

| Case | Result |
|---|---|
| Subagent changes nothing | ⚠ warning emitted |
| Subagent modifies a tracked file | silent |
| Subagent creates only an **untracked** file | silent — correct, new test files are untracked until committed |
| No baseline (hook installed mid-session) | silent |
| `CLAUDE_SKIP_SUBAGENT_INTEGRITY=1` | silent |
| Two concurrent `agent_id`s | 2 separate baselines, both cleaned up on stop — no cross-talk |
| Warning payload | valid JSON with `systemMessage` + `suppressOutput` |
| Exit code, always | 0 — never blocks a session |

**Two limitations you should know before adopting it:**

1. **False positives on read-only agents.** Audits, reviews and forensic agents are *supposed* to
   produce no delta — this session ran six of them. The message is therefore phrased as "verify the
   claim", not "the agent failed", and there is an env-var opt-out. The hook cannot know intent
   from its payload.
2. **False *negatives* in a shared checkout — and this is the more interesting one.** Tested
   directly: with agents A and B running in parallel, A changes nothing but B modifies a file, A's
   check goes *silent* because `git status` is tree-wide and B's change masks A's inactivity. So
   **this check is only reliable when each agent has its own worktree** (or agents are serialized).
   That is an independent argument for `## Multi-Agent Isolation`, arrived at from a different
   direction: without worktrees, even the safety net is unreliable.

**Payload fields — confirmed by probe on 2026-08-27, not guessed.** A temporary
`cat >> /tmp/subagent-probe.jsonl` hook on both events, plus one trivial subagent, gave:

| Event | Fields |
|---|---|
| `SubagentStart` | `agent_id`, `agent_type`, `cwd`, `hook_event_name`, `prompt_id`, `session_id`, `transcript_path` |
| `SubagentStop` | the above **+** `agent_transcript_path`, `background_tasks`, `last_assistant_message`, `permission_mode`, `session_crons`, `stop_hook_active` |

Two things follow:

- **`agent_id` is the pairing key.** It was byte-identical across START and STOP for the same
  subagent (`af39e1b72a3a10c56`). `session_id` is shared by *every* subagent in the session and must
  not be used — keying on it would make parallel subagents overwrite each other's baseline.
- **`SubagentStop` carries `last_assistant_message`** — the agent's own final report. The hook now
  quotes the first 240 characters of it in the warning, so the read-only-vs-broken call is
  immediate instead of requiring a trip to the transcript. This is why the warning is *informative*
  rather than a classifier: surfacing the evidence beats guessing at intent.

  ## Require Artifacts/Abset block

  This check ties in to the `CLAUDE-CODE-FLOW.md` where an agent closing a ticket must include one of 2
  blocks that detail what was done. **Important scoping:** this answers exactly one question — *did 
  the named code land at all?* It does not check correctness, and it does not check authorship (a 
  symbol that was already there passes). That is fine: "vanished entirely" is precisely the failure 
  mode an audit agent is expensive at catching and a grep is free at catching.

```json
{
  "matcher": "Bash",
  "hooks": [
    {
      "type": "command",
      "if": "Bash(bd close *)",
      "command": "~/.claude/hooks/require-artifacts-block.sh",
      "timeout": 10
    }
  ]
}
```

### Notes

- Parse `bd show <id> --json` and read `.[0].close_reason` and `.[0].notes`, **not** the rendered
  output. `bd show` reflows text, converts `- ` bullets to `•`, and inserts a blank line after a
  header — changes that may be misinterpreted.
- `bd update --notes` **replaces**; `--append-notes` appends. Always append notes, never replace.
