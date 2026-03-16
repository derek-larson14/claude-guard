#!/bin/bash
# path-guard.sh — PreToolUse hook that blocks access to sensitive local data
#
# Claude Code calls this before Read, Grep, Glob, Edit, and Bash tools.
# It receives JSON on stdin with tool_name and tool_input.
#
# Philosophy: these are paths no AI agent should ever need to access.
# If you actually need something from one of these paths, copy the data
# to your working directory first (manually), then let the agent read it there.

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

# Extract the path/command to check based on tool type
case "$TOOL_NAME" in
  Read|Edit|Write)
    CHECK_STRING=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
    ;;
  Grep)
    CHECK_STRING=$(echo "$INPUT" | jq -r '.tool_input.path // empty' 2>/dev/null)
    ;;
  Glob)
    GLOB_PATH=$(echo "$INPUT" | jq -r '.tool_input.path // empty' 2>/dev/null)
    GLOB_PATTERN=$(echo "$INPUT" | jq -r '.tool_input.pattern // empty' 2>/dev/null)
    CHECK_STRING="$GLOB_PATH/$GLOB_PATTERN"
    ;;
  Bash)
    CHECK_STRING=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
    ;;
  *)
    exit 0
    ;;
esac

# If nothing to check, allow
[ -z "$CHECK_STRING" ] && exit 0

HOME_DIR="$HOME"

# === BLOCKLIST ===
BLOCKED_PATTERNS=(
  # --- Credentials & Secrets ---
  # SSH keys, AWS credentials, cloud provider tokens, API keys
  "$HOME_DIR/.ssh"
  "$HOME_DIR/.aws"
  "$HOME_DIR/.anthropic"
  "$HOME_DIR/.config/gh/hosts"
  "$HOME_DIR/.config/gcloud"
  "$HOME_DIR/.config/rclone/rclone.conf"
  "$HOME_DIR/.config/stripe"
  "$HOME_DIR/.npmrc"
  "$HOME_DIR/.docker/config.json"
  "$HOME_DIR/.claude.json"
  "$HOME_DIR/.kube/config"
  "$HOME_DIR/.terraform.d/credentials"
  "$HOME_DIR/.netrc"
  "$HOME_DIR/.pgpass"

  # --- Messages & Email (macOS) ---
  # These paths exist on macOS. Harmless to check on Linux (won't match).
  "$HOME_DIR/Library/Messages"
  "$HOME_DIR/Library/Mail"
  "Library/Application Support/Signal"

  # --- Browser Sessions (cookies = logged-in sessions) ---
  # macOS paths
  "$HOME_DIR/Library/Cookies"
  "$HOME_DIR/Library/Safari"
  "Library/Application Support/Google/Chrome"
  "Library/Application Support/Arc"
  "Library/Application Support/Firefox"
  "Library/Application Support/BraveSoftware"
  "Library/Application Support/Microsoft Edge"
  "Library/Application Support/Dia"
  # Linux paths
  "$HOME_DIR/.config/google-chrome"
  "$HOME_DIR/.config/chromium"
  "$HOME_DIR/.mozilla/firefox"
  "$HOME_DIR/.config/BraveSoftware"

  # --- Keychains & System Accounts (macOS) ---
  "$HOME_DIR/Library/Keychains"
  "$HOME_DIR/Library/Accounts"

  # --- Password Managers ---
  # macOS 1Password paths
  "Library/Containers/com.1password"
  "Library/Group Containers/2BUA8C4S2C.com.1password"
  "Library/Group Containers/2BUA8C4S2C.com.agilebits"
  # Linux password manager paths
  "$HOME_DIR/.config/1Password"
  "$HOME_DIR/.local/share/keyrings"
  "$HOME_DIR/.gnupg"

  # --- System-Level Sensitive App Data (macOS) ---
  "Library/Group Containers/group.com.apple.mail"
  "Library/Group Containers/group.com.apple.messages"
  "Library/Group Containers/group.com.apple.contacts"
  "Library/Group Containers/UBF8T346G9.com.microsoft.oneauth"
  "Library/Group Containers/UBF8T346G9.com.microsoft.entrabroker"

  # --- Shell History ---
  # Commands you've typed, database queries, Python REPL history
  "$HOME_DIR/.bash_history"
  "$HOME_DIR/.zsh_history"
  "$HOME_DIR/.zsh_sessions"
  "$HOME_DIR/.psql_history"
  "$HOME_DIR/.python_history"
  "$HOME_DIR/.node_repl_history"
  "$HOME_DIR/.lesshst"
  "$HOME_DIR/.mysql_history"
  "$HOME_DIR/.rediscli_history"

  # --- Claude Code sensitive data ---
  # History, paste cache, backups with auth tokens, session state.
  # NOT blocking: settings.json, agents/, projects/, todos/, tasks/, teams/, plans/
  "$HOME_DIR/.claude/history.jsonl"
  "$HOME_DIR/.claude/paste-cache"
  "$HOME_DIR/.claude/backups"
  "$HOME_DIR/.claude/session-env"
  "$HOME_DIR/.claude/shell-snapshots"
  "$HOME_DIR/.claude/file-history"
  "$HOME_DIR/.claude/debug"
  "$HOME_DIR/.claude/cache"
  "$HOME_DIR/.claude/downloads"

  # --- Keychain CLI commands (for Bash tool, macOS) ---
  "security dump-keychain"
  "security find-generic-password"
  "security find-internet-password"
  "security export"

  # --- Clipboard access (all vectors) ---
  # macOS clipboard
  "pbpaste"
  "pbcopy"
  # Programmatic clipboard APIs (Objective-C, Swift, cross-platform)
  "the clipboard"
  "NSPasteboard"
  "generalPasteboard"
  "UIPasteboard"
  # Linux clipboard tools
  "xclip"
  "xsel"
  "wl-paste"
  "wl-copy"

  # --- Clipboard manager storage (macOS) ---
  "com.generalarcade.flycut"

  # --- Browser debug/automation hijacking ---
  # An agent can relaunch your browser with --remote-debugging-port,
  # connect via Puppeteer/Playwright, and access every authenticated
  # session (email, bank, cloud storage) without any password prompt.
  "remote-debugging-port"
  "remote-debugging-pipe"
  "remote-debugging-address"
  "RemoteDebugging"
  "DevTools"
  "chrome-remote-interface"
  "puppeteer.connect"
  "playwright.connect"
)

# === SELF-PROTECTION (off by default) ===
# Blocks modifications to guard scripts and Claude settings.
# Off by default because hooks are snapshotted at session start.
# Even if Claude edits settings.json mid-session, the hooks don't change
# until the next session. For autonomous sessions (claude -p), the session
# is single-shot, so edits can't affect the current run.
#
# Turn this on if you want to prevent Claude from editing settings across
# sessions (e.g. agent removes hooks in session 1, session 2 starts unprotected).
# To enable: set CLAUDE_GUARD_SELF_PROTECT=on or uncomment below.
SELF_PROTECT="${CLAUDE_GUARD_SELF_PROTECT:-off}"

if [ "$SELF_PROTECT" = "on" ]; then
SELF_PROTECT_PATHS=(
  "claude-guard"
  ".claude/settings.json"
)

if [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "Write" ] || [ "$TOOL_NAME" = "Bash" ]; then
  for sp in "${SELF_PROTECT_PATHS[@]}"; do
    if echo "$CHECK_STRING" | grep -qF "$sp"; then
      if [ "$TOOL_NAME" = "Bash" ]; then
        # Allow read-only Bash commands that reference the path
        if echo "$CHECK_STRING" | grep -qE "^(cat |head |tail |less |more |wc |file |stat |ls |diff |md5 |shasum )"; then
          continue
        fi
      fi
      jq -n '{
        hookSpecificOutput: {
          hookEventName: "PreToolUse",
          permissionDecision: "deny",
          permissionDecisionReason: "BLOCKED: cannot modify security hooks or Claude settings. Run this from your terminal to disable guards: ~/.config/claude-guard/guard-toggle.sh off"
        }
      }'
      exit 0
    fi
  done
fi
fi  # end self-protect check

# === CUSTOM BLOCKLIST ===
# Load additional patterns from a user-local file.
# Default: ~/.config/claude-guard/custom-patterns.txt
# Override: CLAUDE_GUARD_CUSTOM_BLOCKLIST=/path/to/file
# Format: one pattern per line, # comments, $HOME expanded automatically.
CUSTOM_LIST="${CLAUDE_GUARD_CUSTOM_BLOCKLIST:-$HOME/.config/claude-guard/custom-patterns.txt}"
if [ -f "$CUSTOM_LIST" ]; then
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    line="${line/\$HOME/$HOME_DIR}"
    BLOCKED_PATTERNS+=("$line")
  done < "$CUSTOM_LIST"
fi

for pattern in "${BLOCKED_PATTERNS[@]}"; do
  if echo "$CHECK_STRING" | grep -qF "$pattern"; then
    jq -n \
      --arg reason "BLOCKED: access to sensitive path matching '$pattern'. This contains credentials, messages, browser sessions, or system secrets. Ask the user to provide this data manually if needed." \
      '{
        hookSpecificOutput: {
          hookEventName: "PreToolUse",
          permissionDecision: "deny",
          permissionDecisionReason: $reason
        }
      }'
    exit 0
  fi
done

# Block .env file reads — scoped based on setup preferences.
# If .env-project-allowed marker exists (user said yes to project .env access during setup),
# only block home directory .env files. Otherwise block all .env files.
GUARD_DIR="${CLAUDE_GUARD_INSTALL_DIR:-$HOME/.config/claude-guard}"
if echo "$CHECK_STRING" | grep -qE '\.env($|[^a-zA-Z])'; then
  if ! echo "$CHECK_STRING" | grep -qF '.venv'; then
    if [ -f "$GUARD_DIR/.env-project-allowed" ]; then
      # Scoped mode: only block home directory .env files
      if echo "$CHECK_STRING" | grep -qE "^$HOME_DIR/\.[^/]*env" || echo "$CHECK_STRING" | grep -qE "cat.*$HOME_DIR/\.[^/]*env"; then
        jq -n '{
          hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "deny",
            permissionDecisionReason: "BLOCKED: home directory .env files may contain production secrets. Project .env files are allowed."
          }
        }'
        exit 0
      fi
    else
      # Default: block all .env files
      jq -n '{
        hookSpecificOutput: {
          hookEventName: "PreToolUse",
          permissionDecision: "deny",
          permissionDecisionReason: "BLOCKED: .env files may contain credentials. Ask the user to provide specific values instead."
        }
      }'
      exit 0
    fi
  fi
fi

# Allow everything else
exit 0
