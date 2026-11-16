#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# Pithagoras — Assistant Lifecycle Controller
#
# One control for the whole stack. Sessions are "on" while you use
# Pithagoras and "off" the moment you stop.
#
#   login        start the core stack (portal + Ollama + OmniRoute + Docker). Voice OFF.
#   logout       stop everything (voice + portal + Ollama + OmniRoute + Docker).
#   voice on     start whisper (STT) + audiocpp (TTS) — enter voice mode
#   voice off    stop whisper + audiocpp — back to chat
#   docker on|off
#   status       show what's running
#
# Voice is OFF by default. It only exists while you're in voice mode.
# ─────────────────────────────────────────────────────────────
set -euo pipefail

UID_NUM="$(id -u)"
GUI="gui/$UID_NUM"
LA="$HOME/Library/LaunchAgents"
STT="com.my-assistant.stt"
TTS="com.my-assistant.tts"
PORTAL="com.my-assistant.portal"
DOCKER="com.my-assistant.docker"
OLLAMA="com.user.ollama"

# --- OmniRoute (the LLM router the portal connects through) ---------------
OMNIROUTE_BIN="${OMNIROUTE_BIN:-omniroute}"
OMNIROUTE_PORT="${OMNIROUTE_PORT:-20128}"
OMNIROUTE_LOG="/tmp/pithagoras-logs/omniroute.log"

GREEN=$'\033[0;32m'; RED=$'\033[0;31m'; CYAN=$'\033[0;36m'; NC=$'\033[0m'
say() { printf "${GREEN}✔${NC} %s\n" "$*"; }
no()  { printf "${RED}✖${NC} %s\n" "$*"; }
info(){ printf "${CYAN}[i]${NC} %s\n" "$*"; }

# A standard macOS notification — shows when the stack or a service starts or
# stops, whether the call came from the menu-bar button or a terminal. The
# title/message are passed as argv so apostrophes/quotes in the text are safe.
notify() {
  local title="${1:-Pithagoras}" msg="${2:-}"
  [ -n "$msg" ] || return 0
  osascript -e 'on run argv
    display notification (item 2 of argv) with title (item 1 of argv)
  end run' "$title" "$msg" >/dev/null 2>&1 || true
}

running() { launchctl print "$GUI/$1" 2>/dev/null | grep -q "state = running"; }

# whisper/audiocpp listen on fixed local ports; used to confirm a job truly
# came up (launchd's own "state = running" lags and is unreliable for these).
STT_PORT=8082
TTS_PORT=8081

# ── Voice: whisper (STT) + audiocpp (TTS) ──────────────────────
voice_on() {
  for a in "$STT" "$TTS"; do
    if running "$a"; then info "$a already up"; continue; fi
    # Register the agent (idempotent). bootstrap only *loads* the job — it does
    # not run it — so we must kickstart it ourselves; otherwise voice "starts"
    # silently with the ports never coming up.
    launchctl bootstrap "$GUI" "$LA/$a.plist" 2>/dev/null \
      || launchctl load "$LA/$a.plist" 2>/dev/null || true
    launchctl kickstart "$GUI/$a" 2>/dev/null || launchctl start "$a" 2>/dev/null || true
    # Confirm the port is actually listening before claiming success.
    port="$STT_PORT"; [ "$a" = "$TTS" ] && port="$TTS_PORT"
    up=no
    for _ in $(seq 1 30); do
      if curl -s -m 2 -o /dev/null "http://127.0.0.1:$port/"; then up=yes; break; fi
      sleep 1
    done
    if [ "$up" = yes ]; then say "$a started (port $port)"; else no "$a started but port $port not up — check model files / launchd logs"; fi
  done
}
voice_off() {
  for a in "$TTS" "$STT"; do
    if running "$a"; then
      launchctl bootout "$GUI/$a" 2>/dev/null || launchctl unload "$LA/$a.plist" 2>/dev/null
      say "$a stopped"
    else info "$a already off"; fi
  done
}

# ── Docker ──────────────────────────────────────────────────────
docker_on()  { pgrep -x "Docker Desktop" >/dev/null && info "Docker already up" || { open -a Docker && say "Docker started"; }; }
docker_off() { osascript -e 'quit app "Docker"' 2>/dev/null && say "Docker quit" || pgrep -x "Docker Desktop" >/dev/null || info "Docker not running"; }

# ── OmniRoute: the LLM router the portal connects through ──────────
# The menu-bar button runs as a launchd/login session and does NOT inherit your
# interactive shell's PATH, so the Homebrew node + omniroute binary can be
# missing. ensure_path() puts the usual locations up front.
ensure_path() {
  export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:${HOME}/.local/bin:${PATH:-}"
}
port_open() { nc -z 127.0.0.1 "$1" 2>/dev/null; }

omni_on() {
  ensure_path
  mkdir -p "$(dirname "$OMNIROUTE_LOG")"
  if port_open "$OMNIROUTE_PORT"; then info "omniroute already up on :$OMNIROUTE_PORT"; return; fi
  if ! command -v "$OMNIROUTE_BIN" >/dev/null 2>&1; then
    no "$OMNIROUTE_BIN not found on PATH (checked /opt/homebrew/bin etc.) — install it or set OMNIROUTE_BIN"; return
  fi
  info "starting omniroute on :$OMNIROUTE_PORT"
  # --daemon auto-restarts on crash; --no-open keeps the button quiet. The
  # trailing & guarantees the command never blocks this script.
  nohup $OMNIROUTE_BIN serve --daemon --no-open --port "$OMNIROUTE_PORT" </dev/null >"$OMNIROUTE_LOG" 2>&1 &
  disown 2>/dev/null || true
  for _ in $(seq 1 60); do
    if port_open "$OMNIROUTE_PORT"; then say "omniroute up (:$OMNIROUTE_PORT)"; return; fi
    sleep 0.5
  done
  no "omniroute did not come up on :$OMNIROUTE_PORT — check $OMNIROUTE_LOG"
}

omni_off() {
  ensure_path
  if ! port_open "$OMNIROUTE_PORT"; then info "omniroute already stopped"; return; fi
  info "stopping omniroute"
  omniroute stop --port "$OMNIROUTE_PORT" >/dev/null 2>&1 || pkill -f "omniroute" 2>/dev/null || true
  for _ in $(seq 1 10); do port_open "$OMNIROUTE_PORT" || { say "omniroute stopped"; return; }; sleep 0.5; done
  info "omniroute stop requested on :$OMNIROUTE_PORT"
}

# ── Full stack ──────────────────────────────────────────────────
login() {
  info "Bringing the Pithagoras stack up (voice stays OFF)…"
  docker_on
  # OmniRoute first: the portal routes model calls through it, so it must be
  # listening before the portal (re)starts — this is the fix for "Start
  # Pithagoras" coming up but "connect" failing after a reboot.
  omni_on
  if ! running "$PORTAL"; then launchctl bootstrap "$GUI" "$LA/$PORTAL.plist" 2>/dev/null || launchctl load "$LA/$PORTAL.plist" 2>/dev/null; say "portal up"; else info "portal already up"; fi
  # Give OmniRoute a beat, then (re)start the portal so it connects cleanly.
  sleep 1
  launchctl kickstart "$GUI/$PORTAL" 2>/dev/null || true
  # Ollama + env agent
  launchctl bootstrap "$GUI" "$LA/$OLLAMA.plist" 2>/dev/null || true
  launchctl bootstrap "$GUI" "$LA/com.user.ollama.env.plist" 2>/dev/null || true
  info "Done. Portal + Ollama + OmniRoute are up. Voice is OFF — run 'voice on' when you enter voice mode."
}
logout() {
  info "Tearing everything down…"
  voice_off
  if running "$PORTAL"; then launchctl bootout "$GUI/$PORTAL" 2>/dev/null || true; say "portal stopped"; fi
  launchctl bootout "$GUI/$OLLAMA" 2>/dev/null || true
  pkill -x ollama 2>/dev/null && say "ollama stopped" || true
  omni_off
  docker_off
  info "All services stopped."
}

status() {
  echo "  Pithagoras stack status"
  echo "  ───────────────────────"
  for a in "$PORTAL" "$OLLAMA" "$STT" "$TTS"; do
    if running "$a"; then printf "  ${GREEN}●${NC} %-22s running\n" "$a"; else printf "  ${RED}○${NC} %-22s off\n" "$a"; fi
  done
  pgrep -x "Docker Desktop" >/dev/null && printf "  ${GREEN}●${NC} %-22s running\n" "Docker Desktop" || printf "  ${RED}○${NC} %-22s off\n" "Docker Desktop"
  if port_open "$OMNIROUTE_PORT"; then printf "  ${GREEN}●${NC} %-22s running (:%s)\n" "OmniRoute" "$OMNIROUTE_PORT"; else printf "  ${RED}○${NC} %-22s off\n" "OmniRoute"; fi
}

cmd="${1:-}"; sub="${2:-}"
case "$cmd" in
  login)
    login
    notify "Pithagoras" "Started — portal, Ollama + OmniRoute are up. Voice is off."
    ;;
  logout|stop)
    logout
    notify "Pithagoras" "Stopped — all services are off."
    ;;
  voice)
    if [ "$sub" = "on" ]; then
      voice_on
      notify "Voice ON" "Speech in + out agents started."
    elif [ "$sub" = "off" ]; then
      voice_off
      notify "Voice OFF" "Speech agents stopped — back to chat."
    else
      echo "usage: assistant.sh voice on|off"; exit 1
    fi
    ;;
  docker)
    if [ "$sub" = "on" ]; then
      docker_on
      notify "Docker" "Docker Desktop started."
    elif [ "$sub" = "off" ]; then
      docker_off
      notify "Docker" "Docker Desktop stopped."
    else
      echo "usage: assistant.sh docker on|off"; exit 1
    fi
    ;;
  omni)
    if [ "$sub" = "on" ]; then
      omni_on
      notify "OmniRoute" "Router is up on :$OMNIROUTE_PORT."
    elif [ "$sub" = "off" ]; then
      omni_off
      notify "OmniRoute" "Router stopped."
    else
      echo "usage: assistant.sh omni on|off"; exit 1
    fi
    ;;
status)    status ;;
  status-compact) printf 'portal %s ollama %s omni %s voice %s docker %s\n' \
    "$(running "$PORTAL" && echo ● || echo ○)" \
    "$(running "$OLLAMA" && echo ● || echo ○)" \
    "$(port_open "$OMNIROUTE_PORT" && echo ● || echo ○)" \
    "$(( running "$STT" || running "$TTS" ) && echo ● || echo ○)" \
    "$(pgrep -x 'Docker Desktop' >/dev/null && echo ● || echo ○)" ;;
  *)            echo "Usage: assistant.sh {login|logout|omni on|omni off|voice on|voice off|docker on|docker off|status}"; exit 1 ;;
esac
