# Claude Guard

Per-session security for Claude Code. Allow agents the access they need, and nothing more.

```bash
# Locked-down coding agent: no network, can only touch this one repo.
CLAUDE_GUARD_NETWORK_MODE=sandbox \
CLAUDE_GUARD_WORKSPACE_GUARD=on \
CLAUDE_GUARD_ALLOWED_ROOTS="$HOME/Github/my-app" \
claude -p "fix the scroll bug" --dangerously-skip-permissions
```

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

## How It Works

Using a PreToolUse hook, four guards run in sequence, the first deny blocks the action.

```
Tool call → claude-guard.sh (dispatcher)
  → path-guard.sh      blocks sensitive file reads
  → write-guard.sh     blocks dangerous writes
  → workspace-guard.sh optional: scopes to project dir
  → network-guard.sh   sandboxes or blocks network
  → audit-log.sh       logs to JSONL
```

**Path guard** blocks reads to credentials, browser sessions, keychains, clipboard, shell history, and more. Patterns are organized into categories that can be individually toggled in `claude-guard.toml` or via env vars. All categories default to ON if not specified, so removing config makes things stricter, not looser.

**Network guard** has three modes: `sandbox` (macOS, kernel-level network blocking on all Bash), `pattern` (cross-platform, blocks weaponized patterns), or `off` (pattern checks still run as defense-in-depth).

**File write sandbox** uses the same `sandbox-exec` mechanism as network sandbox. Set `CLAUDE_GUARD_SANDBOX_DENY_WRITE` to block Bash writes to specific directories, with `CLAUDE_GUARD_SANDBOX_ALLOW_WRITE` for exceptions. Activates automatically when deny-write paths are set, independent of network mode. Combined with workspace guard, this gives kernel-level write protection for Bash and hook-level protection for file tools.

**Workspace guard** is optional. Restricts Read/Write/Edit/Grep/Glob to your project directory. Useful for locked-down automated scripts.

## Per-Session Overrides

Defualt settings can be overridden by putting environment variables inline before the `claude` command. 

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

# Path guard category overrides (turn individual categories on/off)
CLAUDE_GUARD_PATH_CAT_CREDENTIALS=off      # allow credential file access
CLAUDE_GUARD_PATH_CAT_CLIPBOARD=off        # allow clipboard access
CLAUDE_GUARD_PATH_CAT_BROWSER_SESSIONS=off # allow browser data access
# Categories: credentials, browser-sessions, messages, keychains,
#   password-managers, system-data, shell-history, claude-internals,
#   clipboard, browser-hijacking
```

## Commands

```
/claude-guard:setup        # first-time setup
/claude-guard:scan         # full security audit
/claude-guard:configure    # view/change guard settings
/claude-guard:toggle       # turn all guards on or off
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

## Configuration

Guards configured through `claude-guard.toml`. Use `/claude-guard:configure` or edit directly:

```toml
[path-guard]
enabled = true

# Toggle path guard categories individually. All default to ON if omitted.
[path-guard.categories]
credentials = true         # SSH, AWS, API tokens, .env, Docker/K8s config
browser-sessions = true    # Chrome, Arc, Firefox, Safari, Brave, Edge, Dia
messages = true            # iMessage, Mail, Signal
keychains = true           # macOS Keychains, Accounts, security CLI
password-managers = true   # 1Password, GNOME keyring, GPG
system-data = true         # macOS Group Containers (mail, messages, contacts)
shell-history = true       # .bash_history, .zsh_history, .psql_history
claude-internals = true    # .claude/history, backups, paste-cache
clipboard = true           # pbpaste/pbcopy, xclip, xsel
browser-hijacking = true   # --remote-debugging-port, Puppeteer/Playwright

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

## Audit Log

Every tool call is logged to `~/.claude/logs/claude-audit.jsonl` - you can see what each session touched, when, and whether a guard blocked it.

## Self-Protection

For single-shot autonomous sessions (`claude -p`), hooks are snapshotted at session start. Even if the agent edits config mid-session, the running hooks don't change, and there's no second session to exploit. Turn self-protect on if you run interactive sessions where an agent could disable guards in one conversation and exploit the next.

Self-protect blocks writes to guard scripts, `claude-guard.toml`, and `.claude/settings.json`.

```bash
# Enable via env var
CLAUDE_GUARD_SELF_PROTECT=on claude

# Or set it in your shell profile for all sessions
export CLAUDE_GUARD_SELF_PROTECT=on
```

## Limitations

Pattern matching is not perfect. A determined attacker can encode payloads or construct commands that bypass string matching. The sandbox modes on macOS are the strongest defense — they operate at the kernel level via `sandbox-exec`.

Workspace guard covers file tools (Read/Write/Edit/Grep/Glob) but not Bash. Use `CLAUDE_GUARD_SANDBOX_DENY_WRITE` for kernel-level file write protection on Bash commands. Without it, Bash can write to any path on the filesystem.

Kernel-level sandbox (`sandbox-exec`) is macOS only. Linux falls back to pattern mode for network and has no file write sandbox.

This is defense-in-depth, not a guarantee.

## Platform Support

| Platform | Status |
|----------|--------|
| macOS | Full support (kernel-level network + file write sandbox) |
| Linux | Pattern mode for network guard, no file write sandbox. Everything else works. |

## Contributing

Issues and PRs welcome.

## License

MIT
