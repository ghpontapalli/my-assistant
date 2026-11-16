#!/bin/bash
# Health-check supervisor for My Assistant
# Monitors all services, adapts model selection to battery/thermal state,
# and falls back to a smaller model when resources are constrained.

set -euo pipefail

OLLAMA_URL="${OLLAMA_URL:-http://127.0.0.1:11434}"
TTS_PORT="${TTS_PORT:-8081}"
STT_PORT="${STT_PORT:-8082}"
PORTAL_PORT="${PORTAL_PORT:-4100}"
CHECK_INTERVAL="${CHECK_INTERVAL:-15}"
STATE_FILE="${STATE_FILE:-/tmp/my-assistant-supervisor.state}"

# --- Thermal-aware model selection ---
# Maps thermal state to the appropriate model
get_recommended_model() {
    local thermal_state
    thermal_state=$(sysctl -n machdep.xcpm.cpu_thermal_level 2>/dev/null || echo "0")
    local battery_plugged
    battery_plugged=$(pmset -g batt | grep -o 'AC Power\|Battery Power' | head -1 || echo "AC Power")
    local cpu_load
    cpu_load=$(top -l 1 -n 0 | awk '/CPU usage/{print $3}' | tr -d '%' 2>/dev/null || echo "0")
    local mem_used
    mem_used=$(vm_stat | awk '/Pages active/ || /Pages wired/ {active+=$4; wired+=$4} END {print int((active+wired)*4096/1024/1024/1024)}')

    echo "[supervisor] Thermal: $thermal_state | Battery: $battery_plugged | CPU: ${cpu_load}% | Mem: ${mem_used}GB"

    # Thermal emergency — switch to smallest model
    if [ "$thermal_state" -ge 2 ] 2>/dev/null; then
        echo "tinyllama:1.1b"
        return
    fi

    # High CPU load — fall back to smaller model
    if [ "${cpu_load}" -ge 80 ] 2>/dev/null; then
        echo "phi3:mini"
        return
    fi

    # Low memory — fall back
    if [ "${mem_used}" -ge 12 ] 2>/dev/null; then
        echo "phi3:mini"
        return
    fi

    # On battery — use lighter model to save power
    if [ "$battery_plugged" = "Battery Power" ]; then
        echo "mistral:7b"
        return
    fi

    # Default — use the full model
    echo "qwen-32k"
}

# --- Check if a port is listening ---
port_open() {
    local port="$1"
    lsof -i :"$port" -sTCP:LISTEN 2>/dev/null | grep -q LISTEN
}

# --- Check if Ollama daemon is running ---
ollama_alive() {
    curl -s --max-time 3 "$OLLAMA_URL/api/tags" 2>/dev/null | grep -q "name"
}

# --- Start Ollama if needed ---
start_ollama() {
    if ollama_alive; then
        return 0
    fi
    echo "[supervisor] Ollama not running — starting..."
    if command -v ollama &>/dev/null; then
        ollama serve &
        sleep 2
        return $([ -f "$STATE_FILE" ] && grep -q "running" "$STATE_FILE" || echo 0)
    fi
    return 1
}

# --- Ensure the correct model is loaded ---
ensure_model() {
    local desired_model
    desired_model=$(get_recommended_model)
    echo "[supervisor] Recommended model: $desired_model"

    # Check if the model is already loaded
    local loaded
    loaded=$(curl -s --max-time 5 "$OLLAMA_URL/api/ps" 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.loads(sys.stdin.read())
    for m in data.get('models', []):
        name = m.get('name', '')
        print(name)
except:
    pass
" 2>/dev/null || true)

    if echo "$loaded" | grep -qF "$desired_model"; then
        echo "[supervisor] Model $desired_model is already loaded"
        echo "$desired_model" > /tmp/my-assistant-active-model
        return 0
    fi

    # Check if the model is pulled
    local model_exists
    model_exists=$(curl -s --max-time 5 "$OLLAMA_URL/api/tags" 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.loads(sys.stdin.read())
    names = [m.get('name','') for m in data.get('models', [])]
    target = sys.argv[1]
    # Match by base name (ignore quantization suffix)
    for n in names:
        if n.startswith(target):
            print('yes')
            sys.exit(0)
    print('no')
except:
    print('no')
" "$desired_model" 2>/dev/null || echo "no")

    if [ "$model_exists" = "yes" ]; then
        echo "[supervisor] Pulling model $desired_model..."
        ollama pull "$desired_model" 2>/dev/null || true
        echo "[supervisor] Model pulled"
    else
        echo "[supervisor] Model $desired_model not found — trying to pull..."
        ollama pull "$desired_model" 2>/dev/null || true
    fi

    # Load the model
    ollama run "$desired_model" "warmup" &>/dev/null &
    sleep 3

    echo "$desired_model" > /tmp/my-assistant-active-model
    echo "[supervisor] Model $desired_model loaded"
}

# --- Full health check cycle ---
health_check() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[supervisor $timestamp] === Health check ==="

    # 1. Check Ollama
    if ollama_alive; then
        echo "  ✓ Ollama is running"
    else
        echo "  ✗ Ollama is NOT running"
        start_ollama || echo "  ✗ Failed to start Ollama"
    fi

    # 2. Check TTS
    if port_open "$TTS_PORT"; then
        echo "  ✓ TTS server is running (port $TTS_PORT)"
    else
        echo "  ✗ TTS server is NOT running"
        echo "  → Start with: ./scripts/my-assistant.sh start"
    fi

    # 3. Check STT
    if port_open "$STT_PORT"; then
        echo "  ✓ STT server is running (port $STT_PORT)"
    else
        echo "  ✗ STT server is NOT running"
        echo "  → Start with: ./scripts/my-assistant.sh start"
    fi

    # 4. Check Portal
    if port_open "$PORTAL_PORT"; then
        echo "  ✓ Portal is running (port $PORTAL_PORT)"
    else
        echo "  ✗ Portal is NOT running"
        echo "  → Start with: ./scripts/my-assistant.sh start"
    fi

    # 5. Thermal-aware model selection
    ensure_model

    # 6. Write state
    cat > "$STATE_FILE" <<EOF
last_check=$timestamp
ollama=$(ollama_alive && echo "up" || echo "down")
tts=$(port_open "$TTS_PORT" && echo "up" || echo "down")
stt=$(port_open "$STT_PORT" && echo "up" || echo "down")
portal=$(port_open "$PORTAL_PORT" && echo "up" || echo "down")
active_model=$(cat /tmp/my-assistant-active-model 2>/dev/null || echo "unknown")
EOF
}

# --- Main ---
case "${1:-monitor}" in
    check)
        health_check
        ;;
    monitor)
        echo "[supervisor] Monitoring all services every ${CHECK_INTERVAL}s. Ctrl+C to stop."
        trap 'echo ""; echo "[supervisor] Stopped."; exit 0' INT
        while true; do
            health_check
            echo ""
            sleep "$CHECK_INTERVAL"
        done
        ;;
    model)
        echo "[supervisor] Current recommended model:"
        get_recommended_model
        ;;
    restart)
        echo "[supervisor] Restarting all services..."
        SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
        "$SCRIPT_DIR/my-assistant.sh" stop 2>/dev/null || true
        sleep 2
        "$SCRIPT_DIR/my-assistant.sh" start 2>/dev/null || true
        ;;
    help)
        echo "Usage: supervisor.sh <command>"
        echo ""
        echo "Commands:"
        echo "  check      Run one health check cycle"
        echo "  monitor    Run continuous monitoring (default)"
        echo "  model      Show the recommended model for current thermal state"
        echo "  restart    Restart all services"
        echo ""
        echo "Environment variables:"
        echo "  OLLAMA_URL    (default: http://127.0.0.1:11434)"
        echo "  TTS_PORT      (default: 8081)"
        echo "  STT_PORT      (default: 8082)"
        echo "  PORTAL_PORT   (default: 4100)"
        echo "  CHECK_INTERVAL (default: 15s)"
        ;;
    *)
        echo "Unknown command: $1"
        echo "Run: $0 help"
        exit 1
        ;;
esac
