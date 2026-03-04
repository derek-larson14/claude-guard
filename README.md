# Claude Guard

Security hooks for Claude Code. Block credential theft, network exfiltration, and persistence attacks.

**Claude Code only.** macOS and Linux. Does not work in Co-Work.

## The Problem

AI coding agents have access to your local files. That includes SSH keys, browser cookies, password manager vaults, and shell history. A prompt injection or rogue instruction can read those files and send them anywhere. Claude Guard blocks access to sensitive paths, wraps network calls in a kernel-level sandbox, and prevents agents from installing backdoors.

## What It Blocks

| Category | Examples |
|----------|----------|
| **Credentials** | SSH keys, AWS creds, API tokens, .env files, Docker config, Kubernetes config |
| **Browser sessions** | Cookies, Chrome/Arc/Firefox/Safari/Brave/Edge/Dia local storage |
| **Password managers** | 1Password, system keychains, GNOME keyring, GPG keys |
| **Clipboard** | pbpaste, pbcopy, xclip, xsel, wl-paste, NSPasteboard |
| **Shell history** | .bash_history, .zsh_history, .psql_history, .python_history |
| **Messages** | iMessage, Mail, Signal |
| **Network exfiltration** | Kernel sandbox on all Bash commands, plus pattern blocking for cookie theft, reverse shells, scp/rsync |
| **Persistence** | LaunchAgents, crontab, systemd user services, shell rc files, SSH authorized_keys |
| **Browser hijacking** | Blocks `--remote-debugging-port`, Puppeteer/Playwright connect, Chrome DevTools Protocol |
| **Self-modification** | Optional: blocks agent from editing guard scripts or settings.json (off by default) |

## Install

```
/plugin marketplace add derek-larson14/claude-guard
/plugin install claude-guard
```

Then run setup from inside Claude:

```
/claude-guard:setup
```

Setup walks you through hook registration, recommended deny list, and verification. All through interactive prompts, no terminal needed.

## How It Works

One dispatcher (`claude-guard.sh`) registered as a single PreToolUse hook. It runs four guards in sequence. First deny wins. One audit logger registered as PostToolUse on all tools.

```
Claude Code tool call
  -> claude-guard.sh (dispatcher)
    -> path-guard.sh     (blocks sensitive file reads)
    -> write-guard.sh    (blocks writes to dangerous locations)
    -> workspace-guard.sh (optional: scopes to project dir)
    -> network-guard.sh  (sandboxes or blocks network from Bash)
  -> audit-log.sh (logs the call to JSONL)
```

## Commands

```
/claude-guard:setup        # interactive first-time setup
/claude-guard:scan         # full security audit and report
/claude-guard:configure    # view status and change guard settings
/claude-guard:toggle       # turn all guards on or off
/claude-guard:toggle off   # turn guards off
/claude-guard:toggle on    # turn guards back on
```

**Setup** walks through hook registration, recommended deny list, and verification. Run this once after installing.

**Scan** checks hook registration, guard config, permission rules, and the audit log. Surfaces any gaps or misconfigurations.

**Configure** shows current guard status and lets you interactively enable/disable individual guards, switch network-guard between sandbox and pattern mode, set up workspace-guard, and change the audit log path.

**Toggle** turns all guards on or off at once by editing the hooks in settings.json. Saves a backup so you can turn them back on.

## Guards

### path-guard

Blocks access to paths no AI agent should touch. SSH keys, cloud credentials, browser cookie stores, password managers, clipboard APIs, shell history, keychain CLI commands. Also blocks `.env` files while allowing `.venv` directories.

### write-guard

Blocks writes to locations that enable persistence or privilege escalation. LaunchAgents/LaunchDaemons (macOS), systemd user services (Linux), shell rc files (.zshrc, .bashrc), SSH authorized_keys, /etc/.

### network-guard

Three modes:
- **sandbox** (macOS only): wraps every Bash command in `sandbox-exec` to block all network at the kernel level.
- **pattern** (cross-platform): blocks weaponized patterns (curl sending cookies, netcat, ssh -i, Python HTTP server, osascript, scp/rsync to remote hosts) but allows normal network access.
- **off**: pattern checks still run as defense-in-depth but no sandbox wrapping.

### workspace-guard

Optional. Restricts Read/Write/Edit/Grep/Glob to the project directory. Useful for locked-down automated scripts.

## Configuration

Guards are configured through `claude-guard.toml`. Use `/claude-guard:secure configure` to change settings interactively, or edit the file directly:

- **Plugin bundled config**: lives alongside the guard scripts in the plugin cache
- **Project override**: `.claude/claude-guard.toml` in your project directory (survives plugin updates)

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
allowed_roots = ""  # colon-separated paths

[audit-log]
enabled = true
path = "~/.claude/logs/claude-audit.jsonl"
```

Environment variable overrides work for any guard: set `CLAUDE_GUARD_PATH_GUARD=off` to disable path-guard for a single session.

## Limitations

**Pattern matching is not perfect.** A determined attacker can encode payloads, use alternative tools, or construct commands that bypass string matching. The sandbox mode on macOS is the strongest defense since it operates at the kernel level.

**Bash commands are hard to fully analyze.** Write-guard and path-guard check for blocked strings in Bash commands, but shell is a rich language. Nested subshells, variable expansion, and encoded strings can evade pattern checks.

**workspace-guard does not cover Bash.** It only applies to Read/Write/Edit/Grep/Glob.

**Network sandbox is macOS only.** On Linux, network-guard falls back to pattern mode.

**This is defense-in-depth, not a guarantee.** Use it as one layer in your security posture. Review what Claude does. Check the audit log.

## Platform Support

| Platform | Status |
|----------|--------|
| macOS | Full support. Sandbox mode uses kernel-level network blocking. |
| Linux | Pattern mode for network guard. All other guards work. |

## Contributing

Issues and PRs welcome.

## About

Built by [Derek Larson](https://dtlarson.com). MIT License.
