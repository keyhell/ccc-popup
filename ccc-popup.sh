#!/bin/bash
# ccc-popup — macOS notification popup for the Claude Code CLI (https://claude.ai/code)
# Hooks into the Claude Code CLI's Notification event to surface a native dialog.
set -euo pipefail

# ── macOS guard ───────────────────────────────────────────────────────────────
if [[ "$(uname)" != "Darwin" ]]; then
  echo "error: ccc-popup requires macOS." >&2
  exit 1
fi

INSTALL_PATH="$HOME/.claude/ccc-popup.sh"
SETTINGS_PATH="$HOME/.claude/settings.json"

# ── Functions ─────────────────────────────────────────────────────────────────

cmd_popup() {
  INPUT=""
  if [ ! -t 0 ]; then
    INPUT="$(cat)"
  fi

  MESSAGE="Claude needs attention"

  if [ -n "$INPUT" ]; then
    NAME=$(/usr/bin/python3 -c '
import sys, json, os
try:
    d=json.load(sys.stdin)
    print(os.path.basename(d.get("cwd","")))
except:
    print("")
' <<< "$INPUT")

    if [ -n "$NAME" ]; then
      MESSAGE="Claude needs attention: $NAME"
    fi
  fi

  BUTTON=$(osascript <<APPLESCRIPT
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

merge_hook() {
  /usr/bin/python3 - "$SETTINGS_PATH" <<'PYEOF'
import sys, json, os

path = sys.argv[1]
settings = json.load(open(path)) if os.path.exists(path) else {}
settings.setdefault("hooks", {})
settings["hooks"].setdefault("Notification", [])

TARGET = "~/.claude/ccc-popup.sh"
already = any(
    any(h.get("command") == TARGET for h in e.get("hooks", []))
    for e in settings["hooks"]["Notification"]
)
if already:
    print("ccc-popup: Notification hook already present in settings.json")
    sys.exit(0)

settings["hooks"]["Notification"].append({
    "matcher": "",
    "hooks": [{"type": "command", "command": TARGET, "async": True}]
})

with open(path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")
print(f"ccc-popup: Notification hook added to {path}")
PYEOF
}

remove_hook() {
  if [[ ! -f "$SETTINGS_PATH" ]]; then
    echo "ccc-popup: $SETTINGS_PATH not found, nothing to update"
    return
  fi

  /usr/bin/python3 - "$SETTINGS_PATH" <<'PYEOF'
import sys, json

path = sys.argv[1]
TARGET = "~/.claude/ccc-popup.sh"

with open(path) as f:
    settings = json.load(f)

notification = settings.get("hooks", {}).get("Notification", [])
filtered = [
    e for e in notification
    if not any(h.get("command") == TARGET for h in e.get("hooks", []))
]

if len(filtered) == len(notification):
    print("ccc-popup: Notification hook not found in settings.json")
    sys.exit(0)

settings["hooks"]["Notification"] = filtered
if not settings["hooks"]["Notification"]:
    del settings["hooks"]["Notification"]
if not settings["hooks"]:
    del settings["hooks"]

with open(path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")
print(f"ccc-popup: Notification hook removed from {path}")
PYEOF
}

cmd_init() {
  local script_source
  script_source="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

  mkdir -p "$HOME/.claude"

  if [[ -f "$INSTALL_PATH" ]]; then
    echo "ccc-popup: ccc-popup.sh already installed at $INSTALL_PATH"
  else
    cp "$script_source" "$INSTALL_PATH"
    chmod +x "$INSTALL_PATH"
    echo "ccc-popup: installed → $INSTALL_PATH"
  fi

  merge_hook
  echo "ccc-popup: done. Restart Claude Code for the hook to take effect."
}

cmd_uninstall() {
  if [[ -f "$INSTALL_PATH" ]]; then
    rm "$INSTALL_PATH"
    echo "ccc-popup: removed $INSTALL_PATH"
  else
    echo "ccc-popup: $INSTALL_PATH not found, nothing to remove"
  fi

  remove_hook
}

cmd_usage() {
  echo "usage: ccc-popup.sh [install|uninstall]" >&2
  exit 1
}

# ── Dispatch ──────────────────────────────────────────────────────────────────
case "${1:-}" in
  install)   cmd_init ;;
  uninstall) cmd_uninstall ;;
  "")        cmd_popup ;;
  *)         cmd_usage ;;
esac
