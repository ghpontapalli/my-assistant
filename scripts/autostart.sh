#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# Pithagoras — macOS auto-start/stop on login/logout/shutdown
#
# Usage:
#   ./scripts/autostart.sh install     — auto-start on login, auto-stop on logout
#   ./scripts/autostart.sh uninstall   — remove auto-start/stop
#   ./scripts/autostart.sh status      — check if installed
#
# Generic: works for any user on any machine.
# All config comes from .env — NO secrets stored in scripts.
# ─────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PLIST_LABEL="com.pithagoras.lifecycle"
PLIST_PATH="$HOME/Library/LaunchAgents/${PLIST_LABEL}.plist"

GREEN='\033[0;32m' RED='\033[0;31m' YELLOW='\033[1;33m' NC='\033[0m'
log()  { echo -e "${GREEN}[✔]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✖]${NC} $*"; }

# ── Detect a PATH that includes node, npm, npx, ollama ────
detect_path() {
  local paths="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
  [[ -d "$HOME/.local/bin" ]] && paths="$HOME/.local/bin:$paths"

  # nvm
  if [[ -d "$HOME/.nvm/versions" ]]; then
    local nvm_node
    nvm_node="$(find "$HOME/.nvm/versions/node" -maxdepth 2 -name bin -type d 2>/dev/null | sort -V | tail -1)"
    [[ -n "${nvm_node:-}" ]] && paths="$nvm_node:$paths"
  fi

  # fnm
  if [[ -d "$HOME/Library/Application Support/fnm" ]]; then
    local fnm_node
    fnm_node="$(find "$HOME/Library/Application Support/fnm/node-versions" -maxdepth 3 -name bin -type d 2>/dev/null | sort -V | tail -1)"
    [[ -n "${fnm_node:-}" ]] && paths="$fnm_node:$paths"
  fi

  # volta
  [[ -d "$HOME/.volta/bin" ]] && paths="$HOME/.volta/bin:$paths"

  echo "$paths"
}

install_agent() {
  # Pre-check
  if [[ ! -f "$PROJECT_DIR/.env" ]]; then
    err "No .env file found at $PROJECT_DIR/.env"
    echo ""
    echo "  Create it first:"
    echo "    cp .env.example .env"
    echo "    # Then edit .env and add your OMNIROUTE_KEY and other settings"
    exit 1
  fi

  if [[ "$(uname)" != "Darwin" ]]; then
    err "Auto-start is macOS only. On Linux, use systemd."
    echo ""
    echo "  Create a systemd service instead:"
    echo "    $SCRIPT_DIR/lifecycle.sh start  # in your service ExecStart"
    exit 1
  fi

  mkdir -p "$HOME/Library/LaunchAgents"
  local DETECTED_PATH
  DETECTED_PATH="$(detect_path)"

  # Verify key tools are findable
  local missing=""
  echo "$DETECTED_PATH" | tr ':' '\n' | while read -r p; do [[ -x "$p/node" ]] && exit 0; done || missing="node "
  echo "$DETECTED_PATH" | tr ':' '\n' | while read -r p; do [[ -x "$p/npx" ]] && exit 0; done || missing="${missing}npx "
  [[ -n "$missing" ]] && warn "Could not find: $missing — you may need to adjust PATH in the plist"

  # ── The plist ─────────────────────────────────────────
  # Key design:
  # - RunAtLoad=true → starts on login
  # - KeepAlive=false → does NOT restart if crashed (one-shot)
  # - lifecycle.sh start → runs foreground, traps EXIT/SIGTERM/SIGHUP
  # - On logout: macOS sends SIGTERM → trap fires → stop_all runs → clean exit
  # - On shutdown: same SIGTERM → same cleanup
  # - On reboot: same
  cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${PLIST_LABEL}</string>

    <key>ProgramArguments</key>
    <array>
        <string>${SCRIPT_DIR}/lifecycle.sh</string>
        <string>start</string>
    </array>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <false/>

    <key>StandardOutPath</key>
    <string>/tmp/pithagoras-logs/launchd.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/pithagoras-logs/launchd.log</string>

    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>${DETECTED_PATH}</string>
        <key>HOME</key>
        <string>${HOME}</string>
    </dict>
</dict>
</plist>
EOF

  # Load the agent
  launchctl unload "$PLIST_PATH" 2>/dev/null || true
  launchctl load "$PLIST_PATH"

  echo ""
  log "Pithagoras auto-start installed!"
  echo ""
  echo "  What happens now:"
  echo "  ──────────────────────────────────────────────────────"
  echo "  ✦ Login/restart  → Ollama + OmniRoute + Pithagoras start"
  echo "                     Browser opens to http://localhost:${PORT:-4100}"
  echo "  ✦ Logout         → macOS sends SIGTERM → all services stop"
  echo "  ✦ Shutdown       → macOS sends SIGTERM → all services stop"
  echo "  ✦ Force shutdown → macOS kills processes → clean on next boot"
  echo "  ──────────────────────────────────────────────────────"
  echo ""
  echo "  Plist:  $PLIST_PATH"
  echo "  Log:    /tmp/pithagoras-logs/launchd.log"
  echo ""
  echo "  Uninstall:  $0 uninstall"
  echo ""
}

uninstall_agent() {
  if [[ -f "$PLIST_PATH" ]]; then
    launchctl unload "$PLIST_PATH" 2>/dev/null || true
    rm "$PLIST_PATH"
    # Also stop running services
    "$SCRIPT_DIR/lifecycle.sh" stop 2>/dev/null || true
    log "Auto-start removed and services stopped"
  else
    warn "No launch agent found at $PLIST_PATH"
  fi
}

status_check() {
  echo ""
  echo "  Auto-start status"
  echo "  ─────────────────"

  if [[ -f "$PLIST_PATH" ]]; then
    log "Launch Agent: installed at $PLIST_PATH"
    if launchctl list "$PLIST_LABEL" 2>/dev/null | grep -q "PID"; then
      log "Launch Agent: running"
    else
      warn "Launch Agent: installed but not running"
    fi
  else
    err "Launch Agent: not installed"
    echo "  Install with: $0 install"
  fi

  echo ""
  "$SCRIPT_DIR/lifecycle.sh" status 2>/dev/null || true
}

case "${1:-}" in
  install)   install_agent ;;
  uninstall) uninstall_agent ;;
  status)    status_check ;;
  *)
    echo "Pithagoras Auto-Start Manager"
    echo ""
    echo "Usage: $0 {install|uninstall|status}"
    echo ""
    echo "  install    — auto-start on login, auto-stop on logout/shutdown"
    echo "  uninstall  — remove auto-start and stop services"
    echo "  status     — check what is installed and running"
    echo ""
    echo "Prerequisites:"
    echo "  1. cp .env.example .env"
    echo "  2. Edit .env: set OMNIROUTE_KEY and other settings"
    echo "  3. $0 install"
    exit 1
    ;;
esac
