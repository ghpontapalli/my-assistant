#!/bin/bash
# Pithagoras service control: start, stop, status, load, unload

LABELS=("com.pithagoras.tts" "com.pithagoras.stt" "com.pithagoras.portal" "com.pithagoras.open-portal")
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
  *)
    echo "Usage: $0 {load|unload|start|stop|status}"
    echo "  load   - register all agents (auto-starts on login)"
    echo "  start  - kick all running services now"
    echo "  stop   - stop all services (keeps them registered)"
    echo "  unload - stop and unregister (disables auto-start)"
    echo "  status - show what is running"
    exit 1
    ;;
esac
