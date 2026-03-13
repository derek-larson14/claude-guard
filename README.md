# Claude Guard

Security hooks for Claude Code. Blocks access to credentials, browser sessions, keychains, messages, and clipboard. Sandboxes network from Bash. Prevents persistence attacks.

Built by [Derek Larson](https://dtlarson.com). Read the backstory: [Keys to the Castle](https://dtlarson.com/keys-to-the-castle).

## Install

**Step 1:** Add the marketplace source

```
/plugin marketplace add derek-larson14/claude-guard
```

**Step 2:** Install the plugin

```
/plugin install claude-guard@claude-guard
```

Then run setup:

```
/claude-guard:setup
```

Setup walks you through hook registration, deny list, and verification.

## What It Blocks

**Credentials** — SSH keys, AWS creds, API tokens, .env files, Docker/Kubernetes config

**Browser sessions** — Cookies and local storage for Chrome, Arc, Firefox, Safari, Brave, Edge, Dia

**Password managers** — 1Password vaults, system keychains, GNOME keyring, GPG keys

**Messages and email** — iMessage, Mail, Signal databases

**Clipboard** — pbpaste, pbcopy, xclip, xsel

**Shell history** — .bash_history, .zsh_history, .psql_history, .python_history

**Network exfiltration** — Kernel-level sandbox on all Bash commands (macOS), plus pattern blocking for cookie theft, reverse shells, scp/rsync

**Persistence** — LaunchAgents, crontab, systemd services, shell rc files, SSH authorized_keys

**Browser hijacking** — `--remote-debugging-port`, Puppeteer/Playwright connect, Chrome DevTools Protocol

## How It Works

One dispatcher registered as a PreToolUse hook. Four guards run in sequence. First deny wins.

```
Tool call → claude-guard.sh (dispatcher)
  → path-guard.sh      blocks sensitive file reads
  → write-guard.sh     blocks dangerous writes
  → workspace-guard.sh optional: scopes to project dir
  → network-guard.sh   sandboxes or blocks network
  → audit-log.sh       logs to JSONL
```

**Network guard** has three modes: `sandbox` (macOS, kernel-level network blocking on all Bash), `pattern` (cross-platform, blocks weaponized patterns), or `off` (pattern checks still run as defense-in-depth).

**Workspace guard** is optional. Restricts Read/Write/Edit/Grep/Glob to your project directory. Useful for locked-down automated scripts.

## Commands

```
/claude-guard:setup        # first-time setup
/claude-guard:scan         # full security audit
/claude-guard:configure    # view/change guard settings
/claude-guard:toggle       # turn all guards on or off
```

## Configuration

Guards configured through `claude-guard.toml`. Use `/claude-guard:configure` or edit directly:

```toml
[path-guard]
enabled = true

[write-guard]
enabled = true

[network-guard]
enabled = true
mode = "pattern"  # "sandbox" | "pattern" | "off"

[workspace-guard]
enabled = false
allowed_roots = ""

[audit-log]
enabled = true
path = "~/.claude/logs/claude-audit.jsonl"
```

Project override: `.claude/claude-guard.toml`.

## Per-Session Overrides

Every guard can be toggled per session via environment variables.

**Enable or disable any guard:**
```bash
CLAUDE_GUARD_NETWORK_GUARD=on   # force-enable (even if disabled in config)
CLAUDE_GUARD_PATH_GUARD=off     # disable for this session only
```

**Override specific settings:**
```bash
CLAUDE_GUARD_NETWORK_MODE=sandbox              # switch network mode
CLAUDE_GUARD_ALLOWED_ROOTS="/path/a:/path/b"   # restrict workspace to these dirs
```

**Example: autonomous coding agent with locked-down permissions**
```bash
CLAUDE_GUARD_NETWORK_GUARD=on \
CLAUDE_GUARD_NETWORK_MODE=sandbox \
CLAUDE_GUARD_WORKSPACE_GUARD=on \
CLAUDE_GUARD_ALLOWED_ROOTS="$HOME/Github/my-app:$HOME/Github/my-lib" \
claude -p "fix the scroll bug" --dangerously-skip-permissions
```

This allows running different agents with different security profiles from the same machine, without changing your defaults.

## Limitations

Pattern matching is not perfect. A determined attacker can encode payloads or construct commands that bypass string matching. The sandbox mode on macOS is the strongest defense — it operates at the kernel level.

Bash commands are hard to fully analyze. Nested subshells, variable expansion, and encoded strings can evade pattern checks. Workspace guard doesn't cover Bash (only Read/Write/Edit/Grep/Glob). Network sandbox is macOS only — Linux falls back to pattern mode.

This is defense-in-depth, not a guarantee. Use it as one layer. Check the audit log.

## Platform Support

| Platform | Status |
|----------|--------|
| macOS | Full support (kernel-level network sandbox) |
| Linux | Pattern mode for network guard. Everything else works. |

## Contributing

Issues and PRs welcome.

## License

MIT
