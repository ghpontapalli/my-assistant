#!/bin/bash
# My Assistant service control: start, stop, status, load, unload

LABELS=("com.my-assistant.omniroute" "com.my-assistant.tts" "com.my-assistant.stt" "com.my-assistant.portal" "com.my-assistant.open-portal")
PLIST_DIR="$HOME/Library/LaunchAgents"

case "${1:-}" in
  load)
    for label in "${LABELS[@]}"; do
      launchctl load "$PLIST_DIR/$label.plist" 2>/dev/null && echo "loaded: $label"
    done
    ;;
  unload)
    for label in "${LABELS[@]}"; do
      launchctl unload "$PLIST_DIR/$label.plist" 2>/dev/null && echo "unloaded: $label"
    done
    ;;
  start)
    for label in "${LABELS[@]}"; do
      launchctl kickstart -k "gui/$(id -u)/$label" 2>/dev/null && echo "started: $label"
    done
    ;;
  stop)
    for label in "${LABELS[@]}"; do
      launchctl stop "gui/$(id -u)/$label" 2>/dev/null && echo "stopped: $label"
    done
    ;;
  status)
    for label in "${LABELS[@]}"; do
      if launchctl print "gui/$(id -u)/$label" >/dev/null 2>&1; then
        echo "$label: running"
      else
        echo "$label: stopped"
      fi
    done
    ;;
  status-compact)
    # One-line summary for the menu-bar app: "portal ● ollama ● omni ○ voice ○ docker ○"
    out=""
    for label in "${LABELS[@]}"; do
      short="${label##*.}"   # e.g. "portal", "tts", "stt", "omniroute" → "omni" etc
      case "$short" in
        omniroute) short="omni" ;;
        tts|stt)   short="voice" ;;
        open-portal) short="portal-open" ;;
      esac
      if launchctl print "gui/$(id -u)/$label" >/dev/null 2>&1; then
        out="$out $short ●"
      else
        out="$out $short ○"
      fi
    done
    echo "$out" | sed 's/^ *//'
    ;;
  control)
    # Build and run the macOS menu-bar control app
    if [ ! -f control/PithagorasControl ]; then
      echo "Building menu-bar app..."
      swiftc control/Control.swift -o control/PithagorasControl -framework AppKit 2>/dev/null
    fi
    killall PithagorasControl 2>/dev/null
    LIFECYCLE_SCRIPT="$0" control/PithagorasControl &
    ;;
  setup)
    # Run the hardware-aware TUI setup wizard
    exec node setup.js
    ;;
  *)
    echo "Usage: $0 {load|unload|start|stop|status|status-compact|control|setup}"
    echo "  load   - register all agents (auto-starts on login)"
    echo "  start  - kick all running services now"
    echo "  stop   - stop all services (keeps them registered)"
    echo "  unload - stop and unregister (disables auto-start)"
    echo "  status - show what is running"
    echo "  status-compact - one-line summary for menu-bar app"
    echo "  control - build & run the menu-bar control app"
    echo "  setup  - run hardware-aware TUI model wizard"
    exit 1
    ;;
esac
