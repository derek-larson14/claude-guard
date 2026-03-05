---
description: Set up Claude Guard — interactive first-time configuration
allowed-tools: Read, Glob, Grep, Bash, AskUserQuestion, Edit, Write
---

# Claude Guard Setup

**Claude Code only.** macOS and Linux.

Interactive setup. Walks through hook registration, deny list, and verification.

## Finding Guard Scripts

Look for claude-guard.sh in this order:
1. Plugin cache: `find ~/.claude/plugins/cache -path "*/claude-guard/*/claude-guard.sh" | head -1`
2. Local repo: search `~/Github/claude-guard/`, `~/Projects/claude-guard/`, `~/code/claude-guard/`

Set `GUARD_DIR` to the directory containing the found script.

If not found anywhere, tell the user to install the plugin:
```
/plugin marketplace add derek-larson14/claude-guard
/plugin install claude-guard@claude-guard
```
Then try `/claude-guard:setup` again.

## Step 1: Verify hooks are registered

Read `~/.claude/settings.json`. Check if `hooks.PreToolUse` contains an entry matching `claude-guard`.

If hooks are already registered, tell the user and skip to Step 2.

If not registered, use AskUserQuestion:
"Where should Claude Guard hooks be registered?"
- Global (~/.claude/settings.json) (Recommended) -- applies to all projects
- Project (.claude/settings.json) -- only this project

Register the hooks by editing the chosen settings file. The PreToolUse hook should match `Bash|Read|Edit|Write|Grep|Glob` and run the claude-guard.sh dispatcher. The PostToolUse hook should match `*` and run audit-log.sh.

## Step 2: Recommended deny list

Use AskUserQuestion:
"Add recommended deny list to block dangerous commands at the permissions level?"
- Yes (Recommended) -- adds sqlite3, clipboard, browser debug port, keychain blocking
- No -- skip

If yes, append these to `permissions.deny` (deduplicate against existing):
```json
[
  "Bash(sqlite3 *)",
  "Bash(security dump-keychain*)",
  "Bash(security find-generic-password*)",
  "Bash(security find-internet-password*)",
  "Bash(security export*)",
  "Bash(pbpaste)",
  "Bash(pbpaste *)",
  "Bash(pbcopy)",
  "Bash(pbcopy *)",
  "Bash(*remote-debugging-port*)",
  "Bash(*remote-debugging-pipe*)",
  "Bash(*remote-debugging-address*)"
]
```

Also remove `pbpaste`/`pbcopy` from `permissions.allow` if present.

## Step 3: Verify

Run a quick test:
```bash
echo '{"tool_name":"Read","tool_input":{"file_path":"~/.ssh/id_rsa"}}' | $GUARD_DIR/claude-guard.sh
```
Verify it returns a deny. Report success or failure.

## Step 4: Summary

Print what was configured: which guards are on, what deny rules were added, where the scripts live. Mention `/claude-guard:configure` to change individual guard settings.
