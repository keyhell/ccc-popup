# ccc-popup

A macOS notification popup for [Claude Code](https://claude.ai/code) that shows a native dialog when Claude needs your attention — with a one-click button to jump straight to Terminal.

## How it works

Claude Code fires a `Notification` hook whenever it needs user input. `ccc-popup` registers itself as that hook and displays a native macOS dialog:

- **Ignore** — dismiss and do nothing
- **Open Terminal** — bring Terminal.app to the foreground so you can respond

The dialog includes the name of the working directory so you know which project Claude is waiting on.

## Requirements

- macOS
- Python 3 (pre-installed on macOS)
- [Claude Code](https://claude.ai/code)

## Install

```sh
git clone https://github.com/your-username/ccc-popup
cd ccc-popup
./ccc-popup.sh install
```

Then **restart Claude Code** for the hook to take effect.

## Uninstall

```sh
./ccc-popup.sh uninstall
```

This removes `~/.claude/popup.sh` and strips the hook entry from `~/.claude/settings.json`.

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

## License

MIT
