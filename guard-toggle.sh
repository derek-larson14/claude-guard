#!/bin/bash
# guard-toggle.sh — enable or disable claude-guard hooks in settings.json
#
# This script is the key UX piece: Claude CANNOT run it because path-guard
# blocks writes to settings.json and the guard scripts. Only humans can
# toggle the guards on and off.
#
# Usage:
#   guard-toggle.sh on       # restore hooks in settings.json
#   guard-toggle.sh off      # remove hooks from settings.json (scripts stay)
#   guard-toggle.sh status   # show current state

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
META_FILE="$SCRIPT_DIR/.install-meta.json"
HOOKS_BACKUP="$SCRIPT_DIR/.hooks-backup.json"

# --- Resolve settings file ---
if [ -f "$META_FILE" ]; then
  SETTINGS_FILE=$(jq -r '.settings_file' "$META_FILE" 2>/dev/null)
else
  SETTINGS_FILE="$HOME/.claude/settings.json"
fi

# --- Check dependencies ---
if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required. Install it with: brew install jq (macOS) or apt install jq (Linux)"
  exit 1
fi

# --- Helpers ---
has_hooks() {
  [ -f "$SETTINGS_FILE" ] && jq -e '.hooks' "$SETTINGS_FILE" >/dev/null 2>&1
}

show_status() {
  echo "Settings file: $SETTINGS_FILE"
  echo ""
  if has_hooks; then
    echo "Status: ON"
    echo ""
    # Show what's registered
    echo "PreToolUse hooks:"
    jq -r '.hooks.PreToolUse[]? | "  matcher: \(.matcher)  command: \(.hooks[0].command)"' "$SETTINGS_FILE" 2>/dev/null || echo "  (none)"
    echo ""
    echo "PostToolUse hooks:"
    jq -r '.hooks.PostToolUse[]? | "  matcher: \(.matcher)  command: \(.hooks[0].command)"' "$SETTINGS_FILE" 2>/dev/null || echo "  (none)"
  else
    echo "Status: OFF"
    if [ -f "$HOOKS_BACKUP" ]; then
      echo "Backup available. Restore with:  $SCRIPT_DIR/guard-toggle.sh on"
    else
      echo "No backup found. Reinstall with:  $SCRIPT_DIR/../setup.sh"
    fi
  fi
}

turn_off() {
  if ! has_hooks; then
    echo "Hooks are already off."
    exit 0
  fi

  # Back up current hooks before removing
  jq '.hooks' "$SETTINGS_FILE" > "$HOOKS_BACKUP" 2>/dev/null
  echo "Hooks backed up to $HOOKS_BACKUP"

  # Remove hooks from settings
  jq 'del(.hooks)' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"

  echo "Hooks removed from $SETTINGS_FILE"
  echo "Guard scripts are still installed at $SCRIPT_DIR"
  echo ""
  echo "Restore with:  $SCRIPT_DIR/guard-toggle.sh on"
}

turn_on() {
  if has_hooks; then
    echo "Hooks are already on."
    show_status
    exit 0
  fi

  if [ ! -f "$HOOKS_BACKUP" ]; then
    echo "ERROR: No hooks backup found at $HOOKS_BACKUP"
    echo "Reinstall with:  $SCRIPT_DIR/../setup.sh"
    exit 1
  fi

  if [ ! -f "$SETTINGS_FILE" ]; then
    mkdir -p "$(dirname "$SETTINGS_FILE")"
    echo '{}' > "$SETTINGS_FILE"
  fi

  # Restore hooks from backup
  HOOKS=$(cat "$HOOKS_BACKUP")
  jq --argjson hooks "$HOOKS" '.hooks = $hooks' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"

  echo "Hooks restored in $SETTINGS_FILE"
  echo ""
  show_status
}

# --- Main ---
ACTION="${1:-status}"

case "$ACTION" in
  on)
    turn_on
    ;;
  off)
    turn_off
    ;;
  status)
    show_status
    ;;
  *)
    echo "Usage: guard-toggle.sh [on|off|status]"
    echo ""
    echo "  on      Restore hooks in settings.json"
    echo "  off     Remove hooks from settings.json (keeps scripts)"
    echo "  status  Show current state"
    exit 1
    ;;
esac
