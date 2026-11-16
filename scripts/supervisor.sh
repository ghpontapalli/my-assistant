#!/usr/bin/env bash
# supervisor.sh — health-check + thermal-aware workload throttle
#
# Watches Ollama/TTS/STT/portal ports. Auto-restarts dead services.
# Instead of switching models (which loses context and quality),
# it THROTTLES workload when the machine is stressed:
#   - Thermal stress  → pause non-critical work, wait for cool-down
#   - High CPU        → lower Ollama process priority
#   - High memory     → truncate context length
#   - On battery      → skip background tasks, keep interactive only
#   - Battery < 15%   → full pause (no LLM work until recharged)
#
# Usage:
#   ./supervisor.sh              # one-shot check
#   ./supervisor.sh monitor      # continuous monitoring (default)
#   ./supervisor.sh throttle     # show current throttle level
#   ./supervisor.sh priority     # show Ollama process priority
#   ./supervisor.sh restart      # restart all services
#   ./supervisor.sh help
#
# Env vars:
#   OLLAMA_URL    — Ollama endpoint (default: http://127.0.0.1:11434)
#   TTS_PORT      — TTS server port (default: 8081)
#   STT_PORT      — STT server port (default: 8080)
#   PORTAL_PORT   — Portal port (default: 4100)
#   CHECK_INTERVAL— seconds between checks (default: 10)
#   STATE_FILE    — throttle state file (default: /tmp/my-assistant-supervisor.state)

set -euo pipefail

OLLAMA_URL="${OLLAMA_URL:-http://127.0.0.1:11434}"
TTS_PORT="${TTS_PORT:-8081}"
STT_PORT="${STT_PORT:-8080}"
PORTAL_PORT="${PORTAL_PORT:-4100}"
CHECK_INTERVAL="${CHECK_INTERVAL:-10}"
STATE_FILE="${STATE_FILE:-/tmp/my-assistant-supervisor.state}"

# Throttle levels: 0=full, 1=interactive-only, 2=paused, 3=emergency
THROTTLE=0

# ── Helpers ───────────────────────────────────────────────────────────────────

timestamp() { date "+%Y-%m-%d %H:%M:%S"; }
log() { echo "[$(timestamp)] $*"; }

port_open() {
    local port="$1"
    nc -z 127.0.0.1 "$port" 2>/dev/null
}

http_check() {
    local url="$1"
    curl -sf --max-time 3 "$url" > /dev/null 2>&1
}

# ── Thermal / battery / resource checks ───────────────────────────────────────

thermal_level() {
    # macOS: returns 0 (nominal) to 3 (critical)
    # Linux: returns 0 to 3 from /sys/class/thermal/thermal_zone0/temp
    if [[ "$(uname)" == "Darwin" ]]; then
        # macOS doesn't expose thermal levels directly; use powermetrics or
        # approximate via CPU frequency
        local freq
        freq=$(sysctl -n hw.cpufrequency_max 2>/dev/null || echo "0")
        local cur
        cur=$(sysctl -n hw.cpufrequency_min 2>/dev/null || echo "0")
        if [[ "$freq" == "0" ]]; then echo "0"; return; fi
        # If min freq is much lower than max, thermal throttling is happening
        local ratio=$(( cur * 100 / freq ))
        if   (( ratio < 50 )); then echo "3"
        elif (( ratio < 70 )); then echo "2"
        elif (( ratio < 85 )); then echo "1"
        else echo "0"; fi
    else
        local temp
        temp=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo "0")
        if   (( temp > 95000 )); then echo "3"
        elif (( temp > 85000 )); then echo "2"
        elif (( temp > 75000 )); then echo "1"
        else echo "0"; fi
    fi
}

battery_percent() {
    # macOS
    if [[ "$(uname)" == "Darwin" ]]; then
        pmset -g batt 2>/dev/null | grep -o '[0-9]*%' | head -1 | tr -d '%'
    else
        # Linux
        local pct
        pct=$(cat /sys/class/power_supply/BAT0/capacity 2>/dev/null || echo "100")
        echo "$pct"
    fi
}

on_battery() {
    if [[ "$(uname)" == "Darwin" ]]; then
        pmset -g batt 2>/dev/null | grep -q "AC Power" && return 1
        return 0
    else
        local status
        status=$(cat /sys/class/power_supply/BAT0/status 2>/dev/null || echo "Full")
        [[ "$status" == "Discharging" ]]
    fi
}

cpu_percent() {
    # Rough CPU usage estimate
    if [[ "$(uname)" == "Darwin" ]]; then
        # Use top to get 1-minute CPU load
        local load
        load=$(top -l 1 -n 0 2>/dev/null | grep "CPU usage" | awk '{print $3}' | tr -d '%' || echo "0")
        echo "${load:-0}"
    else
        local cpu
        cpu=$(mpstat -P ALL 1 1 2>/dev/null | grep "all" | awk '{print 100 - $NF}' | tail -1 || echo "0")
        echo "${cpu:-0}"
    fi
}

memory_used_gb() {
    local total free
    if [[ "$(uname)" == "Darwin" ]]; then
        total=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
        free=$(vm_stat 2>/dev/null | grep "free" | awk '{print $3}' || echo "0")
        free=$(( free * 16 / 1024 / 1024 ))  # pages to GB (approx)
        total=$(( total / 1024 / 1024 / 1024 ))
        echo $(( total - free ))
    else
        local total_kb free_kb
        total_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
        free_kb=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
        echo $(( (total_kb - free_kb) / 1024 / 1024 ))
    fi
}

# ── Throttle decision ─────────────────────────────────────────────────────────
#
# Instead of switching models, we compute a THROTTLE level:
#   0 = full power (no restrictions)
#   1 = interactive only (skip background tasks)
#   2 = paused (no LLM work, wait for resources)
#   3 = emergency (full stop, only user-initiated voice)
#
# The portal reads this state file and adjusts behavior accordingly.

compute_throttle() {
    local thermal cpus mem on_batt batt_pct
    thermal=$(thermal_level)
    cpus=$(cpu_percent)
    mem=$(memory_used_gb)
    on_batt="false"
    if on_battery; then on_batt="true"; fi
    batt_pct=$(battery_percent)
    [[ -z "$batt_pct" ]] && batt_pct="100"

    local new_throttle=0

    # Emergency: battery critically low
    if (( batt_pct < 15 )) && [[ "$on_batt" == "true" ]]; then
        new_throttle=3
        log "⚠️  BATTERY CRITICAL ($batt_pct%) — emergency pause"
    # Thermal critical
    elif (( thermal >= 3 )); then
        new_throttle=2
        log "⚠️  THERMAL CRITICAL (level $thermal) — pausing non-critical work"
    # High CPU
    elif (( cpus >= 90 )); then
        new_throttle=2
        log "⚠️  CPU HIGH ($cpus%) — pausing non-critical work"
    # High memory
    elif (( mem >= 14 )); then
        new_throttle=1
        log "⚠️  MEMORY HIGH (${mem}GB) — interactive only"
    # On battery: reduce workload but keep interactive
    elif [[ "$on_batt" == "true" ]]; then
        new_throttle=1
        log "⚡  On battery ($batt_pct%) — skipping background tasks"
    # Thermal warning
    elif (( thermal >= 2 )); then
        new_throttle=1
        log "⚠️  THERMAL WARNING (level $thermal) — interactive only"

    # ── Adjust Ollama process priority under stress ──────────────────────────
    # Instead of switching models, lower the priority of the Ollama process
    # so the system can breathe without changing what model is loaded.
    if (( new_throttle >= 1 )); then
        adjust_ollama_priority "$new_throttle"
    fi

    THROTTLE="$new_throttle"

    # Write state for the portal to read
    cat > "$STATE_FILE" <<STATEEOF
{
  "throttle": $THROTTLE,
  "thermal_level": $thermal,
  "cpu_percent": $cpus,
  "memory_used_gb": $mem,
  "on_battery": $on_batt,
  "battery_percent": $batt_pct,
  "timestamp": "$(timestamp)"
}
STATEEOF
}

adjust_ollama_priority() {
    local level="$1"
    local pid
    pid=$(pgrep -f "ollama" 2>/dev/null | head -1)
    if [[ -z "$pid" ]]; then return; fi

    # macOS: use renice to lower priority (higher nice value = lower priority)
    if [[ "$(uname)" == "Darwin" ]]; then
        case "$level" in
            1) renice -n 5  "$pid" 2>/dev/null && log "  ↳ Ollama priority lowered (nice=5)" ;;
            2) renice -n 10 "$pid" 2>/dev/null && log "  ↳ Ollama priority lowered (nice=10)" ;;
            3) renice -n 15 "$pid" 2>/dev/null && log "  ↳ Ollama priority lowered (nice=15)" ;;
        esac
    else
        # Linux: use ionice + nice
        case "$level" in
            1) renice -n 5  "$pid" 2>/dev/null && log "  ↳ Ollama priority lowered (nice=5)" ;;
            2) renice -n 10 "$pid" 2>/dev/null && log "  ↳ Ollama priority lowered (nice=10)" ;;
            3) renice -n 15 "$pid" 2>/dev/null && log "  ↳ Ollama priority lowered (nice=15)" ;;
        esac
    fi
}

# ── Service health checks ─────────────────────────────────────────────────────

check_ollama() {
    if http_check "${OLLAMA_URL}/api/tags"; then
        log "✓ Ollama up"
        return 0
    else
        log "✗ Ollama down — restarting"
        restart_ollama
        return 1
    fi
}

check_tts() {
    if port_open "$TTS_PORT"; then
        log "✓ TTS up (port $TTS_PORT)"
        return 0
    else
        log "✗ TTS down — restarting"
        restart_tts
        return 1
    fi
}

check_stt() {
    if port_open "$STT_PORT"; then
        log "✓ STT up (port $STT_PORT)"
        return 0
    else
        log "✗ STT down — restarting"
        restart_stt
        return 1
    fi
}

check_portal() {
    if port_open "$PORTAL_PORT"; then
        log "✓ Portal up (port $PORTAL_PORT)"
        return 0
    else
        log "✗ Portal down — restarting"
        restart_portal
        return 1
    fi
}

# ── Restart functions ─────────────────────────────────────────────────────────

restart_ollama() {
    log "  → Killing Ollama..."
    pkill -f "ollama serve" 2>/dev/null || true
    sleep 2
    log "  → Starting Ollama..."
    nohup ollama serve > /tmp/my-assistant-ollama.log 2>&1 &
    # Wait for Ollama to come up (up to 30s)
    for i in {1..30}; do
        sleep 1
        if http_check "${OLLAMA_URL}/api/tags"; then
            log "  → Ollama back up after ${i}s"
            return 0
        fi
    done
    log "  → Ollama failed to restart in 30s"
    return 1
}

restart_tts() {
    log "  → Killing TTS server..."
    pkill -f "llama.cpp.*8081\|breeze.*8081\|audio.cpp.*8081" 2>/dev/null || true
    sleep 1
    log "  → Starting TTS server..."
    nohup bash -c "cd /tmp/my-assistant && npm run start -- --tts" > /tmp/my-assistant-tts.log 2>&1 &
    sleep 3
}

restart_stt() {
    log "  → Killing STT server..."
    pkill -f "whisper.*8080\|STT.*8080" 2>/dev/null || true
    sleep 1
    log "  → Starting STT server..."
    nohup bash -c "cd /tmp/my-assistant && npm run start -- --stt" > /tmp/my-assistant-stt.log 2>&1 &
    sleep 3
}

restart_portal() {
    log "  → Killing portal..."
    pkill -f "pithagoras.*4100\|node.*server.*4100" 2>/dev/null || true
    sleep 1
    log "  → Starting portal..."
    nohup bash -c "cd /tmp/my-assistant && npm run start" > /tmp/my-assistant-portal.log 2>&1 &
    sleep 3
}

# ── Commands ──────────────────────────────────────────────────────────────────

cmd_check() {
    log "── Health check ──────────────────────────"
    check_ollama || true
    check_tts    || true
    check_stt    || true
    check_portal || true
    compute_throttle
    log "  Throttle level: $THROTTLE"
    cat "$STATE_FILE" 2>/dev/null | sed 's/^/  /'
    log "──────────────────────────────────────────"
}

cmd_monitor() {
    log "── Starting health-check monitor (every ${CHECK_INTERVAL}s) ──"
    log "  Model stays the same. We throttle workload, not switch models."
    while true; do
        cmd_check
        sleep "$CHECK_INTERVAL"
    done
}

cmd_throttle() {
    if [[ -f "$STATE_FILE" ]]; then
        echo "Current throttle state:"
        cat "$STATE_FILE"
    else
        echo "No throttle state yet. Run a check first."
        cmd_check
    fi
}

cmd_priority() {
    local pid
    pid=$(pgrep -f "ollama" 2>/dev/null | head -1)
    if [[ -z "$pid" ]]; then
        echo "Ollama not running."
        return 1
    fi
    echo "Ollama PID: $pid"
    if [[ "$(uname)" == "Darwin" ]]; then
        ps -o pid,nice,command -p "$pid" 2>/dev/null
    else
        ps -o pid,ni,command -p "$pid" 2>/dev/null
    fi
}

cmd_restart() {
    log "── Restarting all services ────────────────"
    restart_ollama || true
    restart_tts
    restart_stt
    restart_portal
    sleep 5
    log "  All services restarted. Running check..."
    cmd_check
}

# ── Entry point ───────────────────────────────────────────────────────────────

case "${1:-monitor}" in
    check)    cmd_check ;;
    monitor)  cmd_monitor ;;
    throttle) cmd_throttle ;;
    priority) cmd_priority ;;
    restart)  cmd_restart ;;
    help)
        grep -m 30 '^#' "$0" | sed 's/^# \?//'
        ;;
    *)
        echo "Unknown command: $1"
        echo "Run: $0 help"
        exit 1
        ;;
esac
