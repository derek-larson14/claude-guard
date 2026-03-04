#!/bin/bash
# network-guard.sh — blocks or sandboxes network access from Bash commands
#
# Three modes:
#   sandbox (macOS): wraps Bash commands in sandbox-exec to block ALL outbound
#                    at kernel level. curl, python, compiled binaries, everything.
#   pattern (cross-platform): regex blocklist for weaponized network patterns
#   off: no network restrictions (pattern checks still run as defense-in-depth)
#
# Env vars (set by dispatcher):
#   CLAUDE_GUARD_NETWORK_MODE: "sandbox" | "pattern" | "off"

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

# Only applies to Bash
[ "$TOOL_NAME" != "Bash" ] && exit 0

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

MODE="${CLAUDE_GUARD_NETWORK_MODE:-sandbox}"

deny() {
  jq -n \
    --arg reason "$1" \
    '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: $reason
      }
    }'
  exit 0
}

# === PATTERN CHECKS ===
# These run in ALL modes (including sandbox) as defense-in-depth.
# Patterns that are dangerous enough to block outright, not just sandbox.

# curl sending cookies (session hijacking)
if echo "$COMMAND" | grep -qE 'curl\s+.*(-b|--cookie)\s'; then
  deny "BLOCKED by network-guard: 'curl -b/--cookie' sends browser cookies, enabling session hijacking."
fi

# Reverse shell tools
if echo "$COMMAND" | grep -qE '\b(nc|ncat|netcat)\b'; then
  deny "BLOCKED by network-guard: netcat detected. Common reverse shell tool."
fi

# SSH with key file (exfiltrating stolen keys)
if echo "$COMMAND" | grep -qE 'ssh\s+.*-i\s'; then
  deny "BLOCKED by network-guard: 'ssh -i' uses a key file. Possible credential exfiltration."
fi

# Python HTTP server (data exfiltration endpoint)
if echo "$COMMAND" | grep -qE 'python3?\s+.*-m\s+(http\.server|SimpleHTTPServer)'; then
  deny "BLOCKED by network-guard: Python HTTP server can serve as a data exfiltration endpoint."
fi

# osascript (AppleScript: can do anything including network and UI automation)
if echo "$COMMAND" | grep -qE '\bosascript\b'; then
  deny "BLOCKED by network-guard: osascript can execute arbitrary AppleScript including network access and UI automation."
fi

# scp/rsync to remote host (data exfiltration)
if echo "$COMMAND" | grep -qE '\b(scp|rsync)\b.*:'; then
  deny "BLOCKED by network-guard: scp/rsync to remote host detected. Possible data exfiltration."
fi

# If mode is "off" or "pattern", pattern checks above are all we do
[ "$MODE" = "off" ] && exit 0
[ "$MODE" = "pattern" ] && exit 0

# === SANDBOX MODE (macOS only) ===
if [ "$MODE" = "sandbox" ]; then
  # Check if sandbox-exec is available (macOS only)
  if ! command -v sandbox-exec >/dev/null 2>&1; then
    # On Linux, fall back to pattern mode (already checked above)
    exit 0
  fi

  # Wrap the command in sandbox-exec to block all network at kernel level.
  # Uses jq @sh for proper shell quoting of the original command.
  SANDBOX_PROFILE='(version 1)(allow default)(deny network*)'

  jq -n \
    --arg cmd "$COMMAND" \
    --arg profile "$SANDBOX_PROFILE" \
    '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "allow",
        updatedInput: {
          command: ("sandbox-exec -p \u0027" + $profile + "\u0027 /bin/bash -c " + ($cmd | @sh))
        }
      }
    }'
  exit 0
fi

exit 0
