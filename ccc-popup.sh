#!/bin/bash
# ccc-popup — macOS notification popup for the Claude Code CLI (https://claude.ai/code)
# Hooks into the Claude Code CLI's Notification event to surface a native dialog.
# Optionally also hooks into the Stop event for auto mode completion notifications.
set -euo pipefail

# ── macOS guard ───────────────────────────────────────────────────────────────
if [[ "$(uname)" != "Darwin" ]]; then
  echo "ccc-popup: requires macOS" >&2
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
  local tmp
  tmp=$(mktemp) || return
  if ! curl -sf --max-time 10 "$GITHUB_RAW_URL" -o "$tmp" 2>/dev/null; then
    rm -f "$tmp"
    return
  fi
  local remote_version
  remote_version=$(grep '^VERSION=' "$tmp" | head -1 | cut -d'"' -f2)
  if [[ -z "$remote_version" ]] || [[ "$remote_version" == "$VERSION" ]]; then
    rm -f "$tmp"
    return
  fi
  # Only update if remote is newer (YYYY-MM-DD sorts lexicographically)
  if [[ "$remote_version" < "$VERSION" ]]; then
    rm -f "$tmp"
    return
  fi
  # Only auto-update the installed copy, not a script run from elsewhere
  local self
  self=$(realpath "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")
  local target_real
  target_real=$(realpath "$INSTALL_PATH" 2>/dev/null || echo "$INSTALL_PATH")
  if [[ "$self" != "$target_real" ]]; then
    rm -f "$tmp"
    osascript -e 'display notification "A newer version is available at github.com/keyhell/ccc-popup" with title "ccc-popup"' 2>/dev/null || true
    return
  fi
  # Stage the update; apply on next invocation to avoid replacing ourselves mid-execution
  chmod +x "$tmp"
  mv "$tmp" "${INSTALL_PATH}.pending"
  osascript -e "display notification \"Update to $remote_version ready — takes effect on next run\" with title \"ccc-popup\"" 2>/dev/null || true
}

cmd_popup() {
  # Apply a staged update from a previous run (notify after dialog so the banner isn't hidden)
  local _updated_version=""
  if [[ -f "${INSTALL_PATH}.pending" ]]; then
    _updated_version=$(grep '^VERSION=' "${INSTALL_PATH}.pending" | head -1 | cut -d'"' -f2) || true
    mv "${INSTALL_PATH}.pending" "$INSTALL_PATH" 2>/dev/null || true
  fi
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
except Exception:
    print("Claude needs attention")
' <<< "$INPUT") || true

    if [ -n "$RESULT" ]; then
      MESSAGE="$RESULT"
    fi
  fi

  if [[ -n "$_updated_version" ]]; then
    MESSAGE="$MESSAGE

[updated to $_updated_version]"
  fi

  BUTTON=$(osascript - "$MESSAGE" <<'APPLESCRIPT' 2>/dev/null || true
on run argv
  set msg to item 1 of argv
  tell application "System Events"
    activate
    set b to button returned of (display dialog msg with title "Claude Code" buttons {"Ignore", "Open Terminal"} default button "Open Terminal")
  end tell
  return b
end run
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
    print(f"ccc-popup: {event.lower()} hook already present in settings.json")
    sys.exit(0)

settings["hooks"][event].append({
    "matcher": "",
    "hooks": [{"type": "command", "command": target, "async": True}]
})

with open(path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")
print(f"ccc-popup: {event.lower()} hook added to {path}")
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
    print(f"ccc-popup: {event.lower()} hook not found in settings.json")
    sys.exit(0)

settings["hooks"][event] = filtered
if not settings["hooks"][event]:
    del settings["hooks"][event]
if not settings["hooks"]:
    del settings["hooks"]

with open(path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")
print(f"ccc-popup: {event.lower()} hook removed from {path}")
PYEOF
}

_install_script() {
  mkdir -p "$HOME/.claude"
  local script_source
  script_source="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  if [[ -f "$INSTALL_PATH" ]]; then
    local installed_version
    installed_version=$(grep '^VERSION=' "$INSTALL_PATH" | head -1 | cut -d'"' -f2)
    if [[ "$installed_version" == "$VERSION" ]]; then
      echo "ccc-popup: $VERSION already installed at $INSTALL_PATH"
      return
    fi
    cp "$script_source" "$INSTALL_PATH"
    chmod +x "$INSTALL_PATH"
    echo "ccc-popup: updated $installed_version → $VERSION"
    return
  fi
  cp "$script_source" "$INSTALL_PATH"
  chmod +x "$INSTALL_PATH"
  echo "ccc-popup: installed $VERSION → $INSTALL_PATH"
}

cmd_init() {
  _install_script
  _merge_hook_entry "Notification"
  _merge_hook_entry "Stop"
  echo "ccc-popup: done — restart Claude Code for hooks to take effect"
}

cmd_uninstall() {
  if [[ -f "$INSTALL_PATH" ]]; then
    rm "$INSTALL_PATH"
    echo "ccc-popup: removed $INSTALL_PATH"
  else
    echo "ccc-popup: $INSTALL_PATH not found, nothing to remove"
  fi

  if [[ -f "$UPDATE_CHECK_FILE" ]] || [[ -f "${INSTALL_PATH}.pending" ]]; then
    rm -f "$UPDATE_CHECK_FILE" "${INSTALL_PATH}.pending"
    echo "ccc-popup: cleaned up update files"
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
