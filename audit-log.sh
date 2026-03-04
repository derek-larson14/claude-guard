#!/bin/bash
# audit-log.sh — PostToolUse hook that logs tool usage to JSONL
#
# Appends one JSON line per tool invocation. Truncates long inputs.
# Register as PostToolUse hook on * (all tools).
#
# Config sources (in priority order):
#   1. CLAUDE_GUARD_AUDIT_PATH env var
#   2. [audit-log] path in claude-guard.toml
#   3. Default: ~/.claude/logs/claude-audit.jsonl

INPUT=$(cat)

# --- Find config file (same logic as dispatcher) ---
find_config() {
  local project="${CLAUDE_PROJECT_DIR:-.}/.claude/claude-guard.toml"
  local global="$HOME/.config/claude-guard/config.toml"
  local script_dir="$(cd "$(dirname "$0")" && pwd)"
  local bundled="$script_dir/claude-guard.toml"

  for f in "$project" "$global" "$bundled"; do
    [ -f "$f" ] && echo "$f" && return
  done
}

get_config_value() {
  local config="$1" section="$2" key="$3" default="$4"
  [ -z "$config" ] && echo "$default" && return
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
  ' "$config"
}

# --- Resolve log path ---
CONFIG_FILE=$(find_config)
LOG_PATH="${CLAUDE_GUARD_AUDIT_PATH:-$(get_config_value "$CONFIG_FILE" "audit-log" "path" "$HOME/.claude/logs/claude-audit.jsonl")}"

# Expand ~ to $HOME (for user-provided paths in toml or env var)
LOG_PATH="${LOG_PATH/#\~\//$HOME/}"

# Make path absolute if relative
if [[ "$LOG_PATH" != /* ]]; then
  LOG_PATH="$HOME/.claude/logs/$LOG_PATH"
fi

# Create directory if needed
mkdir -p "$(dirname "$LOG_PATH")" 2>/dev/null

# --- Extract fields ---
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // "unknown"' 2>/dev/null)
TOOL_INPUT=$(echo "$INPUT" | jq -c '.tool_input // {}' 2>/dev/null)
SESSION_ID="${CLAUDE_SESSION_ID:-unknown}"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
CWD=$(pwd)

# Truncate long inputs (> 200 chars)
if [ ${#TOOL_INPUT} -gt 200 ]; then
  INPUT_SUMMARY="${TOOL_INPUT:0:200}..."
else
  INPUT_SUMMARY="$TOOL_INPUT"
fi

# --- Append to log ---
jq -n -c \
  --arg ts "$TIMESTAMP" \
  --arg sid "$SESSION_ID" \
  --arg tool "$TOOL_NAME" \
  --arg input "$INPUT_SUMMARY" \
  --arg cwd "$CWD" \
  '{timestamp: $ts, session_id: $sid, tool: $tool, input: $input, cwd: $cwd}' \
  >> "$LOG_PATH" 2>/dev/null

exit 0
