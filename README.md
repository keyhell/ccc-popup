# ccc-popup

A macOS notification popup for the **Claude Code CLI** that shows a native dialog when Claude needs your attention — with a one-click button to jump straight to Terminal.

## How it works

The Claude Code CLI fires a `Notification` hook whenever it needs user input. `ccc-popup` registers itself as that hook and displays a native macOS dialog:

- **Ignore** — dismiss and do nothing
- **Open Terminal** — bring Terminal.app to the foreground so you can respond

The dialog includes the name of the working directory so you know which project Claude is waiting on.

### Auto mode notifications

When running Claude Code in auto mode (continuous autonomous execution), `ccc-popup` also hooks into the `Stop` event so you get notified when Claude finishes working. The popup message will say **"Claude finished working: \<project\>"** in that case, vs. **"Claude needs attention: \<project\>"** for regular input requests.

## Requirements

- macOS
- Python 3 (pre-installed on macOS)
- [Claude Code CLI](https://claude.ai/code) (`claude` command-line tool)

## Install

```sh
git clone https://github.com/keyhell/ccc-popup
cd ccc-popup
./ccc-popup.sh install
```

Then **restart Claude Code** for the hooks to take effect.

## Uninstall

```sh
./ccc-popup.sh uninstall
```

This removes `~/.claude/ccc-popup.sh` and strips all hook entries from `~/.claude/settings.json`.

## Manual setup

If you prefer to configure things yourself:

1. Copy `ccc-popup.sh` to `~/.claude/ccc-popup.sh` and make it executable.
2. Add the following to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/ccc-popup.sh",
            "async": true
          }
        ]
      }
    ]
  }
}
```

For auto mode notifications, also add a `Stop` hook with the same command:

```json
{
  "hooks": {
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/ccc-popup.sh",
            "async": true
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/ccc-popup.sh",
            "async": true
          }
        ]
      }
    ]
  }
}
```

## License

MIT
