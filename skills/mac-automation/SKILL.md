---
name: mac-automation
description: Use when the person asks to open a folder, open a website, open an app, compose an email, show a notification, or list folder contents on their Mac. Drives the safe scoped mac-automation.sh script.
---

# Mac Automation

The person uses My Assistant with voice mode and wants hands-free control of their Mac. A scoped shell script performs a fixed set of safe actions.

## The script

Path: `data/agent-home/mac-automation.sh`

Usage:

```bash
bash <agent-home>/mac-automation.sh <action> [argument]
```

## Actions

- `open-folder <path>` — opens a folder in Finder. The path must exist.
- `open-url <url>` — opens a URL in the default browser. URL must start with `http://` or `https://`.
- `open-app <name>` — opens an app. Allowed: Safari, Firefox, Google Chrome, Visual Studio Code, Finder, Terminal, Notes, Calendar, Mail, Slack, Spotify, WhatsApp.
- `compose-email <to|subject|body>` — opens Mail with a pre-filled draft. Pipe `|` separates recipient, subject and body.
- `notify <message>` — shows a macOS notification titled My Assistant.
- `list-folder <path>` — lists contents of a folder (defaults to home).

## How to use it

When the person asks for one of these things in voice mode, run the script with the right action and argument. Confirm what you did in one short spoken line. If the action is not in the list, say what you *can* do and offer that instead — do not try to run anything outside the script.

## Security

The script is deliberately narrow: a fixed set of actions, a whitelist of apps, URL scheme checks, and path existence checks. Do not extend it with arbitrary shell execution. If the person needs a new action, add it as a new case with the same kind of validation.
