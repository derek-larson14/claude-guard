# Claude Guard

Per-session security for Claude Code. Give each agent the access it needs, nothing more.

```bash
# Locked-down coding agent: no network, can only touch this one repo.
CLAUDE_GUARD_NETWORK_MODE=sandbox \
CLAUDE_GUARD_WORKSPACE_GUARD=on \
CLAUDE_GUARD_ALLOWED_ROOTS="$HOME/Github/my-app" \
claude -p "fix the scroll bug" --dangerously-skip-permissions
```

Different sessions get different permissions. No need to spin up another machine or configure a container. Just set env vars.

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

Setup asks about your environment and configures the right protections.

## Audit Log

Every tool call is logged to `~/.claude/logs/claude-audit.jsonl`. For scheduled/autonomous agents, this is your compliance paper trail. See what each session touched, when, and whether any guard blocked it.

## Per-Session Overrides

Every guard can be overridden by putting environment variables inline before the `claude` command. They only apply to that one process and disappear when it exits.

```bash
# This Claude session has network sandboxing and workspace restriction.
# The next one won't, unless you set these again.
CLAUDE_GUARD_NETWORK_GUARD=on \
CLAUDE_GUARD_NETWORK_MODE=sandbox \
CLAUDE_GUARD_WORKSPACE_GUARD=on \
CLAUDE_GUARD_ALLOWED_ROOTS="$HOME/Github/my-app:$HOME/Github/my-lib" \
claude -p "fix the scroll bug" --dangerously-skip-permissions
```

File write sandbox example:
```bash
# Agent can write to any repo, but exec/ is kernel-locked except scratch/build/.
# Even python/node scripts spawned by Bash inherit this restriction.
CLAUDE_GUARD_NETWORK_MODE=sandbox \
CLAUDE_GUARD_SANDBOX_DENY_WRITE="$HOME/Github/exec" \
CLAUDE_GUARD_SANDBOX_ALLOW_WRITE="$HOME/Github/exec/scratch/build" \
claude -p "build the feature" --dangerously-skip-permissions
```

**Available overrides:**
```bash
CLAUDE_GUARD_NETWORK_GUARD=on       # force-enable (even if disabled in config)
CLAUDE_GUARD_PATH_GUARD=off         # disable for this session only
CLAUDE_GUARD_NETWORK_MODE=sandbox   # switch network mode
CLAUDE_GUARD_ALLOWED_ROOTS="/a:/b"  # restrict workspace to these dirs
CLAUDE_GUARD_SANDBOX_DENY_WRITE="/protected/path"     # kernel-block Bash writes to path
CLAUDE_GUARD_SANDBOX_ALLOW_WRITE="/protected/path/ok"  # exception within denied path
```

## What It Blocks

**Credentials** — SSH keys, AWS creds, API tokens, .env files, Docker/Kubernetes config

**Browser sessions** — Cookies and local storage for Chrome, Arc, Firefox, Safari, Brave, Edge, Dia

**Password managers** — 1Password vaults, system keychains, GNOME keyring, GPG keys

**Messages and email** — iMessage, Mail, Signal databases

**Clipboard** — pbpaste, pbcopy, xclip, xsel

**Shell history** — .bash_history, .zsh_history, .psql_history, .python_history

**Network exfiltration** — Kernel-level sandbox on all Bash commands (macOS), plus pattern blocking for cookie theft, reverse shells, scp/rsync

**File write sandbox** — Kernel-level restriction on which directories Bash can write to (macOS). Covers all child processes: python, node, compiled binaries. Set deny/allow paths per session to lock an agent to specific directories

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

**File write sandbox** uses the same `sandbox-exec` mechanism as network sandbox. Set `CLAUDE_GUARD_SANDBOX_DENY_WRITE` to block Bash writes to specific directories, with `CLAUDE_GUARD_SANDBOX_ALLOW_WRITE` for exceptions. Activates automatically when deny-write paths are set, independent of network mode. Combined with workspace guard, this gives kernel-level write protection for Bash and hook-level protection for file tools.

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

## Limitations

Pattern matching is not perfect. A determined attacker can encode payloads or construct commands that bypass string matching. The sandbox modes on macOS are the strongest defense — they operate at the kernel level via `sandbox-exec`.

Workspace guard covers file tools (Read/Write/Edit/Grep/Glob) but not Bash. Use `CLAUDE_GUARD_SANDBOX_DENY_WRITE` for kernel-level file write protection on Bash commands. Without it, Bash can write to any path on the filesystem.

Kernel-level sandbox (`sandbox-exec`) is macOS only. Linux falls back to pattern mode for network and has no file write sandbox.

This is defense-in-depth, not a guarantee. Use it as one layer. Check the audit log.

## Platform Support

| Platform | Status |
|----------|--------|
| macOS | Full support (kernel-level network + file write sandbox) |
| Linux | Pattern mode for network guard, no file write sandbox. Everything else works. |

## Contributing

Issues and PRs welcome.

## License

MIT
