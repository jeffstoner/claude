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

Notes on the above:

- `if: "Bash(git *)"` uses permission-rule syntax to avoid spawning the hook for non-git
  commands. The script re-checks anyway, so the `if` is an optimisation, not the guard.
- `PreToolUse` denials **must** use `hookSpecificOutput.permissionDecision`. The older
  `decision: "block"` is deprecated for this event and will not reliably block.
- `symlinkDirectories`: `node_modules` and `.venv` match the documented examples (bare directory
  names). Whether a **nested** path like `api/.venv` is honoured is unverified — test it, and if
  it isn't, fall back to the absolute-interpreter approach, which is verified.
- Known trade-off: `uses()` in the script matches the subcommand word anywhere, so 
  `git log --grep stash` is blocked. That is deliberate — over-blocking costs a rephrase, 
  under-blocking cost three implementations.
