#!/bin/bash
# ccc-popup — macOS notification popup for the Claude Code CLI (https://claude.ai/code)
# Hooks into the Claude Code CLI's Notification event to surface a native dialog.
# Optionally also hooks into the Stop event for auto mode completion notifications.
set -euo pipefail

# ── macOS guard ───────────────────────────────────────────────────────────────
if [[ "$(uname)" != "Darwin" ]]; then
  echo "error: ccc-popup requires macOS." >&2
  exit 1
fi

VERSION="2026-04-06"
INSTALL_PATH="$HOME/.claude/ccc-popup.sh"
SETTINGS_PATH="$HOME/.claude/settings.json"
TARGET="~/.claude/ccc-popup.sh"
UPDATE_CHECK_FILE="$HOME/.claude/ccc-popup-last-check"
GITHUB_RAW_URL="https://raw.githubusercontent.com/keyhell/ccc-popup/main/ccc-popup.sh"

# ── Functions ─────────────────────────────────────────────────────────────────

_check_update() {
  local today
  today=$(date +%Y-%m-%d)
  if [[ -f "$UPDATE_CHECK_FILE" ]] && [[ "$(cat "$UPDATE_CHECK_FILE")" == "$today" ]]; then
    return
  fi
  echo "$today" > "$UPDATE_CHECK_FILE"
  local remote_version
  remote_version=$(curl -sf --max-time 5 "$GITHUB_RAW_URL" 2>/dev/null \
    | grep '^VERSION=' | head -1 | cut -d'"' -f2) || return
  if [[ -n "$remote_version" ]] && [[ "$remote_version" != "$VERSION" ]]; then
    osascript -e 'display notification "A newer version is available at github.com/keyhell/ccc-popup" with title "ccc-popup update available"' 2>/dev/null || true
  fi
}

cmd_popup() {
  _check_update &
  INPUT=""
  if [ ! -t 0 ]; then
    INPUT="$(cat)"
  fi

  MESSAGE="Claude needs attention"

  if [ -n "$INPUT" ]; then
    RESULT=$(/usr/bin/python3 -c '
import sys, json, os
try:
    d=json.load(sys.stdin)
    event = d.get("hook_event_name", "")
    name = os.path.basename(d.get("cwd",""))
    if event == "Stop":
        base = "Claude finished working"
    else:
        base = "Claude needs attention"
    print(base + (": " + name if name else ""))
except:
    print("Claude needs attention")
' <<< "$INPUT")

    if [ -n "$RESULT" ]; then
      MESSAGE="$RESULT"
    fi
  fi

  BUTTON=$(osascript <<APPLESCRIPT 2>/dev/null || true
tell application "System Events"
  activate
  set b to button returned of (display dialog "$MESSAGE" with title "Claude Code" buttons {"Ignore", "Open Terminal"} default button "Open Terminal")
end tell
return b
APPLESCRIPT
)

  if [ "$BUTTON" = "Open Terminal" ]; then
    osascript <<'APPLESCRIPT'
tell application "Terminal"
  if it is not running then
    launch
  end if
  reopen
  activate
end tell
APPLESCRIPT
  fi
}

_merge_hook_entry() {
  local event="$1"
  /usr/bin/python3 - "$SETTINGS_PATH" "$event" "$TARGET" <<'PYEOF'
import sys, json, os

path, event, target = sys.argv[1], sys.argv[2], sys.argv[3]
settings = json.load(open(path)) if os.path.exists(path) else {}
settings.setdefault("hooks", {})
settings["hooks"].setdefault(event, [])

already = any(
    any(h.get("command") == target for h in e.get("hooks", []))
    for e in settings["hooks"][event]
)
if already:
    print(f"ccc-popup: {event} hook already present in settings.json")
    sys.exit(0)

settings["hooks"][event].append({
    "matcher": "",
    "hooks": [{"type": "command", "command": target, "async": True}]
})

with open(path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")
print(f"ccc-popup: {event} hook added to {path}")
PYEOF
}

_remove_hook_entry() {
  local event="$1"
  if [[ ! -f "$SETTINGS_PATH" ]]; then
    echo "ccc-popup: $SETTINGS_PATH not found, nothing to update"
    return
  fi

  /usr/bin/python3 - "$SETTINGS_PATH" "$event" "$TARGET" <<'PYEOF'
import sys, json

path, event, target = sys.argv[1], sys.argv[2], sys.argv[3]

with open(path) as f:
    settings = json.load(f)

entries = settings.get("hooks", {}).get(event, [])
filtered = [
    e for e in entries
    if not any(h.get("command") == target for h in e.get("hooks", []))
]

if len(filtered) == len(entries):
    print(f"ccc-popup: {event} hook not found in settings.json")
    sys.exit(0)

settings["hooks"][event] = filtered
if not settings["hooks"][event]:
    del settings["hooks"][event]
if not settings["hooks"]:
    del settings["hooks"]

with open(path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")
print(f"ccc-popup: {event} hook removed from {path}")
PYEOF
}

_install_script() {
  mkdir -p "$HOME/.claude"
  if [[ -f "$INSTALL_PATH" ]]; then
    echo "ccc-popup: ccc-popup.sh already installed at $INSTALL_PATH"
  else
    local script_source
    script_source="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
    cp "$script_source" "$INSTALL_PATH"
    chmod +x "$INSTALL_PATH"
    echo "ccc-popup: installed → $INSTALL_PATH"
  fi
}

cmd_init() {
  _install_script
  _merge_hook_entry "Notification"
  _merge_hook_entry "Stop"
  echo "ccc-popup: done. Restart Claude Code for the hooks to take effect."
}

cmd_uninstall() {
  if [[ -f "$INSTALL_PATH" ]]; then
    rm "$INSTALL_PATH"
    echo "ccc-popup: removed $INSTALL_PATH"
  else
    echo "ccc-popup: $INSTALL_PATH not found, nothing to remove"
  fi

  _remove_hook_entry "Notification"
  _remove_hook_entry "Stop"
}

cmd_usage() {
  cat >&2 <<'EOF'
usage: ccc-popup.sh <command>

commands:
  install    register Notification + Stop hooks
  uninstall  remove all hooks and the installed script
EOF
  exit 1
}

# ── Dispatch ──────────────────────────────────────────────────────────────────
case "${1:-}" in
  install)   cmd_init ;;
  uninstall) cmd_uninstall ;;
  "")        cmd_popup ;;
  *)         cmd_usage ;;
esac
