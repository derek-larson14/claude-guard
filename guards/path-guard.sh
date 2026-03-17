#!/bin/bash
# path-guard.sh — PreToolUse hook that blocks access to sensitive local data
#
# Claude Code calls this before Read, Grep, Glob, Edit, and Bash tools.
# It receives JSON on stdin with tool_name and tool_input.
#
# Categories can be toggled in claude-guard.toml under [path-guard.categories].
# Missing categories default to ON — you must explicitly disable them.
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

# For Bash: git commands don't access file contents — commit messages, tag messages,
# and log output can mention sensitive paths without it being a real file access.
# Skip all path checks for git operations to avoid false positives.
if [ "$TOOL_NAME" = "Bash" ] && echo "$CHECK_STRING" | grep -qE '^\s*git\b'; then
  exit 0
fi

HOME_DIR="$HOME"

# === CONFIG HELPERS ===
# Find config file (same resolution as claude-guard.sh dispatcher)
find_config() {
  local project="${CLAUDE_PROJECT_DIR:-.}/.claude/claude-guard.toml"
  local global="$HOME/.config/claude-guard/config.toml"
  local bundled="$(cd "$(dirname "$0")/.." && pwd)/claude-guard.toml"

  for f in "$project" "$global" "$bundled"; do
    [ -f "$f" ] && echo "$f" && return
  done
}

CONFIG_FILE=$(find_config)

# Check if a category is enabled. Defaults to ON if not specified.
# Env override: CLAUDE_GUARD_PATH_CAT_<CATEGORY>=off
category_enabled() {
  local cat_name="$1"
  # Env override (e.g. CLAUDE_GUARD_PATH_CAT_CREDENTIALS=off)
  local env_var="CLAUDE_GUARD_PATH_CAT_$(echo "$cat_name" | tr '[:lower:]-' '[:upper:]_')"
  local env_val="${!env_var:-}"
  [ "$env_val" = "off" ] && return 1
  [ "$env_val" = "on" ] && return 0

  # Check toml
  [ -z "$CONFIG_FILE" ] && return 0  # no config = all on
  local val
  val=$(awk -v sect="[path-guard.categories]" -v k="$cat_name" '
    $0 == sect { in_s=1; next }
    /^\[/ { in_s=0 }
    in_s && $1 == k {
      sub(/^[^=]*=[ \t]*/, "")
      gsub(/"/, "")
      print
      found=1
      exit
    }
    END { if (!found) print "true" }
  ' "$CONFIG_FILE")
  [ "$val" = "true" ]
}

# === DENY HELPER ===
deny() {
  jq -n --arg reason "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

check_patterns() {
  local category="$1"
  shift
  for pattern in "$@"; do
    if echo "$CHECK_STRING" | grep -qF "$pattern"; then
      deny "BLOCKED: access to sensitive path matching '$pattern'. This contains credentials, messages, browser sessions, or system secrets. Ask the user to provide this data manually if needed."
    fi
  done
}

# === CATEGORIES ===
# Each category is a named group of patterns. Categories default to ON.
# Disable in claude-guard.toml under [path-guard.categories] or via env var.

if category_enabled "credentials"; then
  check_patterns "credentials" \
    "$HOME_DIR/.ssh" \
    "$HOME_DIR/.aws" \
    "$HOME_DIR/.anthropic" \
    "$HOME_DIR/.config/gh/hosts" \
    "$HOME_DIR/.config/gcloud" \
    "$HOME_DIR/.config/rclone/rclone.conf" \
    "$HOME_DIR/.config/stripe" \
    "$HOME_DIR/.npmrc" \
    "$HOME_DIR/.docker/config.json" \
    "$HOME_DIR/.claude.json" \
    "$HOME_DIR/.kube/config" \
    "$HOME_DIR/.terraform.d/credentials" \
    "$HOME_DIR/.netrc" \
    "$HOME_DIR/.pgpass"
fi

if category_enabled "browser-sessions"; then
  check_patterns "browser-sessions" \
    "$HOME_DIR/Library/Cookies" \
    "$HOME_DIR/Library/Safari" \
    "Library/Application Support/Google/Chrome" \
    "Library/Application Support/Arc" \
    "Library/Application Support/Firefox" \
    "Library/Application Support/BraveSoftware" \
    "Library/Application Support/Microsoft Edge" \
    "Library/Application Support/Dia" \
    "$HOME_DIR/.config/google-chrome" \
    "$HOME_DIR/.config/chromium" \
    "$HOME_DIR/.mozilla/firefox" \
    "$HOME_DIR/.config/BraveSoftware"
fi

if category_enabled "messages"; then
  check_patterns "messages" \
    "$HOME_DIR/Library/Messages" \
    "$HOME_DIR/Library/Mail" \
    "Library/Application Support/Signal"
fi

if category_enabled "keychains"; then
  check_patterns "keychains" \
    "$HOME_DIR/Library/Keychains" \
    "$HOME_DIR/Library/Accounts" \
    "security dump-keychain" \
    "security find-generic-password" \
    "security find-internet-password" \
    "security export"
fi

if category_enabled "password-managers"; then
  check_patterns "password-managers" \
    "Library/Containers/com.1password" \
    "Library/Group Containers/2BUA8C4S2C.com.1password" \
    "Library/Group Containers/2BUA8C4S2C.com.agilebits" \
    "$HOME_DIR/.config/1Password" \
    "$HOME_DIR/.local/share/keyrings" \
    "$HOME_DIR/.gnupg"
fi

if category_enabled "system-data"; then
  check_patterns "system-data" \
    "Library/Group Containers/group.com.apple.mail" \
    "Library/Group Containers/group.com.apple.messages" \
    "Library/Group Containers/group.com.apple.contacts" \
    "Library/Group Containers/UBF8T346G9.com.microsoft.oneauth" \
    "Library/Group Containers/UBF8T346G9.com.microsoft.entrabroker"
fi

if category_enabled "shell-history"; then
  check_patterns "shell-history" \
    "$HOME_DIR/.bash_history" \
    "$HOME_DIR/.zsh_history" \
    "$HOME_DIR/.zsh_sessions" \
    "$HOME_DIR/.psql_history" \
    "$HOME_DIR/.python_history" \
    "$HOME_DIR/.node_repl_history" \
    "$HOME_DIR/.lesshst" \
    "$HOME_DIR/.mysql_history" \
    "$HOME_DIR/.rediscli_history"
fi

if category_enabled "claude-internals"; then
  check_patterns "claude-internals" \
    "$HOME_DIR/.claude/history.jsonl" \
    "$HOME_DIR/.claude/paste-cache" \
    "$HOME_DIR/.claude/backups" \
    "$HOME_DIR/.claude/session-env" \
    "$HOME_DIR/.claude/shell-snapshots" \
    "$HOME_DIR/.claude/file-history" \
    "$HOME_DIR/.claude/debug" \
    "$HOME_DIR/.claude/cache" \
    "$HOME_DIR/.claude/downloads"
fi

if category_enabled "clipboard"; then
  check_patterns "clipboard" \
    "pbpaste" \
    "pbcopy" \
    "the clipboard" \
    "NSPasteboard" \
    "generalPasteboard" \
    "UIPasteboard" \
    "xclip" \
    "xsel" \
    "wl-paste" \
    "wl-copy" \
    "com.generalarcade.flycut"
fi

if category_enabled "browser-hijacking"; then
  check_patterns "browser-hijacking" \
    "remote-debugging-port" \
    "remote-debugging-pipe" \
    "remote-debugging-address" \
    "RemoteDebugging" \
    "DevTools" \
    "chrome-remote-interface" \
    "puppeteer.connect" \
    "playwright.connect"
fi

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
      deny "BLOCKED: cannot modify security hooks or Claude settings. Run this from your terminal to disable guards: ~/.config/claude-guard/guard-toggle.sh off"
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
    if echo "$CHECK_STRING" | grep -qF "$line"; then
      deny "BLOCKED: access to sensitive path matching '$line'. This contains credentials, messages, browser sessions, or system secrets. Ask the user to provide this data manually if needed."
    fi
  done < "$CUSTOM_LIST"
fi

# Block .env file reads — scoped based on setup preferences.
# If .env-project-allowed marker exists (user said yes to project .env access during setup),
# only block home directory .env files. Otherwise block all .env files.
if category_enabled "credentials"; then
  GUARD_DIR="${CLAUDE_GUARD_INSTALL_DIR:-$HOME/.config/claude-guard}"
  if echo "$CHECK_STRING" | grep -qE '\.env($|[^a-zA-Z])'; then
    if ! echo "$CHECK_STRING" | grep -qF '.venv'; then
      if [ -f "$GUARD_DIR/.env-project-allowed" ]; then
        # Scoped mode: only block home directory .env files
        if echo "$CHECK_STRING" | grep -qE "^$HOME_DIR/\.[^/]*env" || echo "$CHECK_STRING" | grep -qE "cat.*$HOME_DIR/\.[^/]*env"; then
          deny "BLOCKED: home directory .env files may contain production secrets. Project .env files are allowed."
        fi
      else
        # Default: block all .env files
        deny "BLOCKED: .env files may contain credentials. Ask the user to provide specific values instead."
      fi
    fi
  fi
fi

# Allow everything else
exit 0
