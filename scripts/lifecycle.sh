#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# Pithagoras — Lifecycle Manager
# Manages backend services (Ollama, OmniRoute) alongside the
# Pithagoras server. Starts them before the server, stops them
# when the server exits (logout, shutdown, Ctrl-C).
#
# All config comes from .env — NO secrets stored here.
# Generic: works for any user on any machine.
#
# Usage:
#   ./scripts/lifecycle.sh start    — start services + server (foreground)
#   ./scripts/lifecycle.sh start-bg — start everything in background
#   ./scripts/lifecycle.sh stop     — stop everything
#   ./scripts/lifecycle.sh status   — show what's running
# ─────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PID_DIR="/tmp/pithagoras-pids"
LOG_DIR="/tmp/pithagoras-logs"

# ── Load .env (ALL config lives there — never here) ────────
if [[ -f "$PROJECT_DIR/.env" ]]; then
  set -a; source "$PROJECT_DIR/.env"; set +a
else
  echo "⚠  No .env found at $PROJECT_DIR/.env"
  echo "   Run:  cp .env.example .env  and fill in your settings."
  exit 1
fi

# Config from .env with safe defaults
OMNIROUTE_PORT="${OMNIROUTE_PORT:-20128}"
OMNIROUTE_KEY="${OMNIROUTE_KEY:-}"
PITHAGORAS_PORT="${PORT:-4100}"
export OLLAMA_FLASH_ATTENTION="${OLLAMA_FLASH_ATTENTION:-1}"
ENABLE_OLLAMA="${ENABLE_OLLAMA:-true}"
ENABLE_OMNIROUTE="${ENABLE_OMNIROUTE:-true}"
OPEN_BROWSER="${OPEN_BROWSER:-true}"

# ── Helpers ─────────────────────────────────────────────────
GREEN='\033[0;32m' RED='\033[0;31m' YELLOW='\033[1;33m' CYAN='\033[0;36m' NC='\033[0m'
log()  { echo -e "${GREEN}[✔]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✖]${NC} $*"; }
info() { echo -e "${CYAN}[i]${NC} $*"; }

mkdir -p "$PID_DIR" "$LOG_DIR"

save_pid() { echo "$2" > "$PID_DIR/$1.pid"; }
read_pid() { cat "$PID_DIR/$1.pid" 2>/dev/null || echo ""; }
clear_pid() { rm -f "$PID_DIR/$1.pid"; }

is_running() {
  local pid
  pid="$(read_pid "$1")"
  [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

wait_for_port() {
  local port=$1 name=$2 max=${3:-30} i=0
  while ! curl -sf "http://localhost:$port" >/dev/null 2>&1 && \
        ! curl -sf "http://localhost:$port/v1/models" >/dev/null 2>&1; do
    sleep 1; i=$((i + 1))
    if [[ $i -ge $max ]]; then
      err "$name did not respond on port $port within ${max}s"
      return 1
    fi
  done
  log "$name is ready on port $port"
}

wait_for_http() {
  local url=$1 name=$2 max=${3:-30} i=0
  while ! curl -sf "$url" >/dev/null 2>&1; do
    sleep 1; i=$((i + 1))
    [[ $i -ge $max ]] && { err "$name not reachable at $url within ${max}s"; return 1; }
  done
}

# ── Start Ollama ────────────────────────────────────────────
start_ollama() {
  [[ "$ENABLE_OLLAMA" != "true" ]] && { info "Ollama disabled (ENABLE_OLLAMA≠true)"; return 0; }
  command -v ollama &>/dev/null || { warn "ollama not found — skipping"; return 0; }

  if pgrep -x ollama >/dev/null 2>&1; then
    log "Ollama already running"
    save_pid "ollama" "$(pgrep -x ollama | head -1)"
  else
    warn "Starting Ollama..."
    ollama serve > "$LOG_DIR/ollama.log" 2>&1 &
    save_pid "ollama" "$!"
    sleep 2
    if pgrep -x ollama >/dev/null 2>&1; then
      log "Ollama started (log: $LOG_DIR/ollama.log)"
    else
      err "Ollama failed to start"; return 1
    fi
  fi
}

# ── Start OmniRoute ────────────────────────────────────────
start_omniroute() {
  [[ "$ENABLE_OMNIROUTE" != "true" ]] && { info "OmniRoute disabled (ENABLE_OMNIROUTE≠true)"; return 0; }
  [[ -z "$OMNIROUTE_KEY" ]] && { warn "OMNIROUTE_KEY not set in .env — skipping OmniRoute"; return 0; }
  command -v npx &>/dev/null || { err "npx not found — install Node.js"; return 1; }

  if curl -sf "http://localhost:$OMNIROUTE_PORT/v1/models" \
       -H "Authorization: Bearer $OMNIROUTE_KEY" >/dev/null 2>&1; then
    log "OmniRoute already running on port $OMNIROUTE_PORT"
  else
    warn "Starting OmniRoute (this can take 30-45s)..."
    cd "$PROJECT_DIR"
    nohup npx --prefix "$PROJECT_DIR" omniroute serve --no-open --port "$OMNIROUTE_PORT" > "$LOG_DIR/omniroute.log" 2>&1 &
    save_pid "omniroute" "$!"
    if wait_for_port "$OMNIROUTE_PORT" "OmniRoute" 60; then
      log "OmniRoute started (log: $LOG_DIR/omniroute.log)"
    else
      warn "OmniRoute may still be starting — check $LOG_DIR/omniroute.log"
    fi
  fi
}

# ── Start Pithagoras Server ────────────────────────────────
start_server_fg() {
  cd "$PROJECT_DIR"
  log "Starting Pithagoras server (foreground)..."
  # Open browser after a delay
  if [[ "$OPEN_BROWSER" == "true" ]]; then
    ( sleep 5 && open_browser ) &
  fi
  node core/server/dist/index.js
}

start_server_bg() {
  if pgrep -f "core/server/dist/index.js" >/dev/null 2>&1; then
    log "Pithagoras server already running"
    return 0
  fi
  cd "$PROJECT_DIR"
  nohup node core/server/dist/index.js > "$LOG_DIR/server.log" 2>&1 &
  save_pid "server" "$!"
  sleep 3
  if wait_for_http "http://localhost:$PITHAGORAS_PORT/api/auth/status" "Pithagoras" 15; then
    log "Pithagoras server started on port $PITHAGORAS_PORT"
  else
    warn "Server may still be starting — check $LOG_DIR/server.log"
  fi
}

# ── Open Browser ───────────────────────────────────────────
open_browser() {
  local url="http://localhost:$PITHAGORAS_PORT"
  if [[ "$(uname)" == "Darwin" ]]; then
    open "$url" 2>/dev/null || true
  elif command -v xdg-open &>/dev/null; then
    xdg-open "$url" 2>/dev/null || true
  elif command -v wslview &>/dev/null; then
    wslview "$url" 2>/dev/null || true
  fi
}

# ── Stop Everything ─────────────────────────────────────────
stop_all() {
  info "Stopping Pithagoras services..."

  # Stop server
  local server_pid
  server_pid="$(read_pid server)"
  if [[ -n "$server_pid" ]] && kill -0 "$server_pid" 2>/dev/null; then
    kill -TERM "$server_pid" 2>/dev/null
    # Wait for graceful shutdown (server has its own 10s timeout)
    local i=0
    while kill -0 "$server_pid" 2>/dev/null && [[ $i -lt 12 ]]; do
      sleep 1; i=$((i + 1))
    done
    log "Pithagoras server stopped"
  else
    # Try by process name
    pkill -f "core/server/dist/index.js" 2>/dev/null && log "Pithagoras server stopped" || true
  fi
  clear_pid "server"

  # Stop OmniRoute
  local omni_pid
  omni_pid="$(read_pid omniroute)"
  if [[ -n "$omni_pid" ]] && kill -0 "$omni_pid" 2>/dev/null; then
    kill -TERM "$omni_pid" 2>/dev/null; sleep 1
    kill -9 "$omni_pid" 2>/dev/null || true
    log "OmniRoute stopped"
  else
    pkill -f "omniroute" 2>/dev/null && log "OmniRoute stopped" || true
  fi
  clear_pid "omniroute"

  # Stop Ollama (only if we started it)
  if [[ "${STOP_OLLAMA:-true}" == "true" ]]; then
    local ollama_pid
    ollama_pid="$(read_pid ollama)"
    if [[ -n "$ollama_pid" ]] && kill -0 "$ollama_pid" 2>/dev/null; then
      kill -TERM "$ollama_pid" 2>/dev/null
      log "Ollama stopped"
    else
      pkill -x ollama 2>/dev/null && log "Ollama stopped" || true
    fi
    clear_pid "ollama"
  fi

  log "All services stopped."
}

# ── Trap: Stop on exit (logout, shutdown, Ctrl-C) ──────────
cleanup_on_exit() {
  echo ""
  info "Received exit signal — cleaning up..."
  stop_all
  exit 0
}

# ── Status ──────────────────────────────────────────────────
show_status() {
  echo ""
  echo "  Pithagoras Service Status"
  echo "  ─────────────────────────"

  # Ollama
  if pgrep -x ollama >/dev/null 2>&1; then
    log "Ollama:      running"
  else
    err "Ollama:      not running"
  fi

  # OmniRoute
  if [[ -n "${OMNIROUTE_KEY:-}" ]] && curl -sf "http://localhost:$OMNIROUTE_PORT/v1/models" \
       -H "Authorization: Bearer $OMNIROUTE_KEY" >/dev/null 2>&1; then
    log "OmniRoute:   running (port $OMNIROUTE_PORT)"
  else
    err "OmniRoute:   not running"
  fi

  # Pithagoras
  if curl -sf "http://localhost:$PITHAGORAS_PORT/api/auth/status" >/dev/null 2>&1; then
    log "Pithagoras:  running (port $PITHAGORAS_PORT)"
  else
    err "Pithagoras:  not running"
  fi

  echo ""
  echo "  Logs: $LOG_DIR/"
  echo ""
}

# ── Main ────────────────────────────────────────────────────
case "${1:-}" in
  start)
    echo ""
    echo "  🚀 Starting Pithagoras..."
    echo "  ─────────────────────────"
    echo ""
    trap cleanup_on_exit SIGTERM SIGINT SIGHUP EXIT
    start_ollama
    start_omniroute
    echo "─────────────────────────────────────────────"
    start_server_fg
    ;;

  start-bg)
    echo ""
    echo "  🚀 Starting Pithagoras (background)..."
    echo "  ────────────────────────────────────────"
    echo ""
    start_ollama
    start_omniroute
    start_server_bg
    [[ "$OPEN_BROWSER" == "true" ]] && open_browser
    echo ""
    log "All services running in background!"
    echo "  Portal:  http://localhost:$PITHAGORAS_PORT"
    echo "  Logs:    $LOG_DIR/"
    echo "  Stop:    $SCRIPT_DIR/lifecycle.sh stop"
    echo ""
    ;;

  stop)
    stop_all
    ;;

  status)
    show_status
    ;;

  *)
    echo "Pithagoras Lifecycle Manager"
    echo ""
    echo "Usage: $0 {start|start-bg|stop|status}"
    echo ""
    echo "  start      Start all services (foreground, stops on Ctrl-C/logout)"
    echo "  start-bg   Start all services in background, open browser"
    echo "  stop       Stop all services"
    echo "  status     Show what is running"
    echo ""
    echo "Config: All settings come from .env (copy .env.example → .env)"
    exit 1
    ;;
esac
