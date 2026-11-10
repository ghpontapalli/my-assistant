#!/bin/bash
# Mac Automation Helper for My Assistant
# Safe, scoped actions only. No arbitrary code execution.
# Usage: mac-automation.sh <action> [argument]

ACTION="$1"
ARG="$2"

case "$ACTION" in

  open-folder)
    if [ -z "$ARG" ]; then echo "Error: no folder path given"; exit 1; fi
    if [ ! -d "$ARG" ]; then echo "Error: folder not found: $ARG"; exit 1; fi
    open "$ARG"
    echo "Opened folder: $ARG"
    ;;

  open-url)
    if [ -z "$ARG" ]; then echo "Error: no URL given"; exit 1; fi
    case "$ARG" in
      http://*|https://*) ;;
      *) echo "Error: URL must start with http:// or https://"; exit 1 ;;
    esac
    open "$ARG"
    echo "Opened URL: $ARG"
    ;;

  open-app)
    ALLOWED=("Safari" "Firefox" "Google Chrome" "Visual Studio Code" "Finder" "Terminal" "Notes" "Calendar" "Mail" "Slack" "Spotify" "WhatsApp")
    FOUND=0
    for A in "${ALLOWED[@]}"; do
      if [ "$A" = "$ARG" ]; then FOUND=1; break; fi
    done
    if [ $FOUND -eq 0 ]; then
      echo "Error: app '$ARG' is not in the allowed list: ${ALLOWED[*]}"
      exit 1
    fi
    open -a "$ARG"
    echo "Opened app: $ARG"
    ;;

  compose-email)
    IFS='|' read -r TO SUBJECT BODY <<< "$ARG"
    if [ -z "$TO" ]; then echo "Error: no recipient given"; exit 1; fi
    osascript <<EOF
tell application "Mail"
  activate
  set newMsg to make new outgoing message with properties {subject:"${SUBJECT}", content:"${BODY}", visible:true}
  tell newMsg
    make new to recipient with properties {address:"${TO}"}
  end tell
end tell
EOF
    echo "Composed email to: $TO"
    ;;

  notify)
    osascript -e "display notification \"${ARG}\" with title \"My Assistant\""
    echo "Notification sent"
    ;;

  list-folder)
    if [ -z "$ARG" ]; then ARG="$HOME"; fi
    if [ ! -d "$ARG" ]; then echo "Error: folder not found: $ARG"; exit 1; fi
    ls -la "$ARG"
    ;;

  *)
    echo "Unknown action: $ACTION"
    echo "Available actions: open-folder, open-url, open-app, compose-email, notify, list-folder"
    exit 1
    ;;

esac
