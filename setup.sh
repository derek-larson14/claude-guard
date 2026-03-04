#!/bin/bash
# setup.sh — install claude-guard security hooks for Claude Code
#
# Run this from your terminal (not from Claude). It will:
# 1. Copy guard scripts to the install directory
# 2. Add hooks to your Claude settings.json
# 3. Run the test suite to verify everything works
#
# Usage: ./setup.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEFAULT_INSTALL_DIR="$HOME/.config/claude-guard"

echo "=== Claude Guard Setup ==="
echo ""

# --- Step 1: Choose install location ---
read -rp "Install directory [$DEFAULT_INSTALL_DIR]: " INSTALL_DIR
INSTALL_DIR="${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}"

# Expand ~ if the user typed it
INSTALL_DIR="${INSTALL_DIR/#\~/$HOME}"

echo ""
echo "Installing to: $INSTALL_DIR"

# --- Step 2: Copy scripts ---
mkdir -p "$INSTALL_DIR/guards"

cp "$SCRIPT_DIR/claude-guard.sh"   "$INSTALL_DIR/"
cp "$SCRIPT_DIR/claude-guard.toml" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/audit-log.sh"      "$INSTALL_DIR/"
cp "$SCRIPT_DIR/test-guards.sh"    "$INSTALL_DIR/"
cp "$SCRIPT_DIR/guard-toggle.sh"   "$INSTALL_DIR/"
cp "$SCRIPT_DIR/guards/"*.sh       "$INSTALL_DIR/guards/"

chmod +x "$INSTALL_DIR/claude-guard.sh"
chmod +x "$INSTALL_DIR/audit-log.sh"
chmod +x "$INSTALL_DIR/test-guards.sh"
chmod +x "$INSTALL_DIR/guard-toggle.sh"
chmod +x "$INSTALL_DIR/guards/"*.sh

echo "Scripts copied."
echo ""

# --- Step 3: Choose settings file ---
GLOBAL_SETTINGS="$HOME/.claude/settings.json"
PROJECT_SETTINGS=".claude/settings.json"

echo "Where should hooks be registered?"
echo "  1) Global  ($GLOBAL_SETTINGS)"
echo "  2) Project ($PROJECT_SETTINGS in current directory)"
echo ""
read -rp "Choice [1]: " SETTINGS_CHOICE
SETTINGS_CHOICE="${SETTINGS_CHOICE:-1}"

if [ "$SETTINGS_CHOICE" = "2" ]; then
  SETTINGS_FILE="$(pwd)/$PROJECT_SETTINGS"
  mkdir -p "$(dirname "$SETTINGS_FILE")"
else
  SETTINGS_FILE="$GLOBAL_SETTINGS"
  mkdir -p "$(dirname "$SETTINGS_FILE")"
fi

echo ""
echo "Settings file: $SETTINGS_FILE"

# --- Step 4: Build hooks JSON ---
GUARD_CMD="$INSTALL_DIR/claude-guard.sh"
AUDIT_CMD="$INSTALL_DIR/audit-log.sh"

HOOKS_JSON=$(cat <<ENDJSON
{
  "PreToolUse": [
    {
      "matcher": "Bash|Read|Edit|Write|Grep|Glob",
      "hooks": [
        {
          "type": "command",
          "command": "$GUARD_CMD"
        }
      ]
    }
  ],
  "PostToolUse": [
    {
      "matcher": "*",
      "hooks": [
        {
          "type": "command",
          "command": "$AUDIT_CMD"
        }
      ]
    }
  ]
}
ENDJSON
)

# --- Step 5: Merge hooks into settings.json ---
if ! command -v jq >/dev/null 2>&1; then
  echo ""
  echo "ERROR: jq is required but not found."
  echo "Install it:"
  echo "  macOS:  brew install jq"
  echo "  Ubuntu: sudo apt install jq"
  echo "  Fedora: sudo dnf install jq"
  echo ""
  echo "Then re-run this script."
  exit 1
fi

if [ -f "$SETTINGS_FILE" ]; then
  EXISTING=$(cat "$SETTINGS_FILE")

  # Check if hooks already exist
  HAS_HOOKS=$(echo "$EXISTING" | jq 'has("hooks")' 2>/dev/null)
  if [ "$HAS_HOOKS" = "true" ]; then
    echo ""
    echo "WARNING: Your settings file already has hooks configured."
    echo "  File: $SETTINGS_FILE"
    echo ""
    echo "Options:"
    echo "  1) Merge (append Claude Guard hooks to your existing hooks)"
    echo "  2) Replace (overwrite existing hooks with Claude Guard)"
    echo "  3) Skip (don't touch hooks, I'll add them manually)"
    echo ""
    read -rp "Choice [1]: " MERGE_CHOICE
    MERGE_CHOICE="${MERGE_CHOICE:-1}"

    case "$MERGE_CHOICE" in
      2)
        MERGED=$(echo "$EXISTING" | jq --argjson hooks "$HOOKS_JSON" '.hooks = $hooks')
        echo "$MERGED" | jq '.' > "$SETTINGS_FILE"
        echo "Replaced hooks with Claude Guard config."
        ;;
      3)
        echo "Skipped hooks. Add them manually (see README)."
        SKIP_HOOKS=true
        ;;
      *)
        # Merge: append to existing PreToolUse and PostToolUse arrays
        MERGED=$(echo "$EXISTING" | jq --argjson hooks "$HOOKS_JSON" '
          .hooks.PreToolUse = (.hooks.PreToolUse // []) + $hooks.PreToolUse |
          .hooks.PostToolUse = (.hooks.PostToolUse // []) + $hooks.PostToolUse
        ')
        echo "$MERGED" | jq '.' > "$SETTINGS_FILE"
        echo "Appended Claude Guard hooks to existing config."
        ;;
    esac
  else
    MERGED=$(echo "$EXISTING" | jq --argjson hooks "$HOOKS_JSON" '.hooks = $hooks')
    echo "$MERGED" | jq '.' > "$SETTINGS_FILE"
    echo "Added hooks to existing settings."
  fi
else
  # Create new settings file with hooks
  echo "{}" | jq --argjson hooks "$HOOKS_JSON" '{hooks: $hooks}' > "$SETTINGS_FILE"
  echo "Created settings file with hooks."
fi

# --- Step 5b: Offer recommended deny list ---
echo ""
echo "Claude Guard also recommends adding a deny list to block dangerous commands"
echo "at the permissions level (before hooks even fire). This adds entries like:"
echo "  - sqlite3 (blocks direct database reads of password vaults)"
echo "  - pbpaste/pbcopy (blocks clipboard access)"
echo "  - remote-debugging-port (blocks browser session hijacking)"
echo "  - security dump-keychain (blocks macOS Keychain extraction)"
echo ""
read -rp "Add recommended deny list to settings? [Y/n]: " DENY_CHOICE
DENY_CHOICE="${DENY_CHOICE:-Y}"

if [[ "$DENY_CHOICE" =~ ^[Yy] ]]; then
  DENY_RULES='[
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
  ]'

  CURRENT=$(cat "$SETTINGS_FILE")

  # Merge: append new deny rules to existing, deduplicate
  UPDATED=$(echo "$CURRENT" | jq --argjson new_deny "$DENY_RULES" '
    .permissions.deny = ((.permissions.deny // []) + $new_deny | unique)
  ')

  # Also remove pbpaste/pbcopy from allow list if present
  UPDATED=$(echo "$UPDATED" | jq '
    .permissions.allow = ((.permissions.allow // []) | map(
      select(. != "Bash(pbpaste)" and . != "Bash(pbpaste *)" and . != "Bash(pbcopy)" and . != "Bash(pbcopy *)")
    ))
  ')

  echo "$UPDATED" | jq '.' > "$SETTINGS_FILE"
  echo "Added deny list and removed clipboard from allow list."
else
  echo "Skipped deny list. See README for manual setup."
fi

# --- Step 6: Save hooks backup for guard-toggle.sh ---
HOOKS_BACKUP="$INSTALL_DIR/.hooks-backup.json"
echo "$HOOKS_JSON" | jq '.' > "$HOOKS_BACKUP"
echo "Hooks config backed up to $HOOKS_BACKUP"

# --- Step 7: Save install metadata ---
cat > "$INSTALL_DIR/.install-meta.json" <<ENDJSON
{
  "install_dir": "$INSTALL_DIR",
  "settings_file": "$SETTINGS_FILE",
  "installed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
ENDJSON

echo ""
echo "--- Running tests ---"
echo ""

# --- Step 8: Run test suite ---
"$INSTALL_DIR/test-guards.sh"
TEST_EXIT=$?

echo ""

if [ $TEST_EXIT -eq 0 ]; then
  echo "=== Setup complete ==="
  echo ""
  echo "Claude Guard is active. Here's what's running:"
  echo "  path-guard:      ON  (blocks credential/session/clipboard access)"
  echo "  write-guard:     ON  (blocks persistence mechanisms)"
  echo "  network-guard:   OFF (enable in claude-guard.toml for autonomous sessions)"
  echo "  workspace-guard: OFF (opt-in, edit $INSTALL_DIR/claude-guard.toml)"
  echo "  audit-log:       ON  (logging to ~/.claude/logs/claude-audit.jsonl)"
  echo ""
  echo "To toggle guards on/off:  $INSTALL_DIR/guard-toggle.sh [on|off|status]"
  echo "To check from Claude:     /secure"
  echo ""
else
  echo "=== Setup complete with test failures ==="
  echo "The hooks are installed but some tests failed. Check the output above."
  echo ""
fi
