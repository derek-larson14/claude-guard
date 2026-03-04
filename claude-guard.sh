#!/bin/bash
# claude-guard.sh — single PreToolUse dispatcher for all security guards
#
# Architecture: one hook entry point prevents updatedInput race conditions
# when multiple guards match the same tool. Guards run sequentially;
# first deny wins. updatedInput from network-guard is returned last.
#
# Config: claude-guard.toml (project > global > bundled)
# Env overrides: CLAUDE_GUARD_<NAME>=off disables individual guards

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GUARD_DIR="$SCRIPT_DIR/guards"

# --- Config file resolution ---
find_config() {
  local project="${CLAUDE_PROJECT_DIR:-.}/.claude/claude-guard.toml"
  local global="$HOME/.config/claude-guard/config.toml"
  local bundled="$SCRIPT_DIR/claude-guard.toml"

  for f in "$project" "$global" "$bundled"; do
    [ -f "$f" ] && echo "$f" && return
  done
}

CONFIG_FILE=$(find_config)

# --- TOML helpers ---
get_config() {
  local section="$1" key="$2" default="${3:-}"
  [ -z "$CONFIG_FILE" ] && echo "$default" && return
  awk -v sect="[$section]" -v k="$key" -v def="$default" '
    $0 == sect { in_s=1; next }
    /^\[/ { in_s=0 }
    in_s && $1 == k {
      sub(/^[^=]*=[ \t]*/, "")
      gsub(/"/, "")
      print
      found=1
      exit
    }
    END { if (!found) print def }
  ' "$CONFIG_FILE"
}

is_enabled() {
  local name="$1"
  # Env override: CLAUDE_GUARD_PATH_GUARD=off (or =on to force-enable)
  local env_var="CLAUDE_GUARD_$(echo "$name" | tr '[:lower:]-' '[:upper:]_')"
  local env_val="${!env_var:-}"
  [ "$env_val" = "off" ] && return 1
  [ "$env_val" = "on" ] && return 0

  [ "$(get_config "$name" "enabled" "true")" = "true" ]
}

# --- Read stdin once ---
INPUT=$(cat)
UPDATED_INPUT=""

# --- Run a guard ---
run_guard() {
  local guard="$1"
  [ -x "$guard" ] || return 0

  local output
  output=$(echo "$INPUT" | "$guard")

  [ -z "$output" ] && return 0

  # Deny -> output and short-circuit
  if echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; then
    echo "$output"
    exit 0
  fi

  # updatedInput -> save for final response
  if echo "$output" | jq -e '.hookSpecificOutput.updatedInput' >/dev/null 2>&1; then
    UPDATED_INPUT="$output"
  fi
}

# --- Pass config to guards via env vars ---
export CLAUDE_GUARD_NETWORK_MODE="${CLAUDE_GUARD_NETWORK_MODE:-$(get_config "network-guard" "mode" "sandbox")}"
export CLAUDE_GUARD_ALLOW_PERSISTENCE="${CLAUDE_GUARD_ALLOW_PERSISTENCE:-$(get_config "write-guard" "allow_persistence" "false")}"
export CLAUDE_GUARD_ALLOWED_ROOTS="${CLAUDE_GUARD_ALLOWED_ROOTS:-$(get_config "workspace-guard" "allowed_roots" "${CLAUDE_PROJECT_DIR:-$(pwd)}")}"

# --- Run guards sequentially ---
is_enabled "path-guard"      && run_guard "$GUARD_DIR/path-guard.sh"
is_enabled "write-guard"     && run_guard "$GUARD_DIR/write-guard.sh"
is_enabled "workspace-guard" && run_guard "$GUARD_DIR/workspace-guard.sh"
is_enabled "network-guard"   && run_guard "$GUARD_DIR/network-guard.sh"

# --- Return updatedInput if any guard set one ---
[ -n "$UPDATED_INPUT" ] && echo "$UPDATED_INPUT"

exit 0
