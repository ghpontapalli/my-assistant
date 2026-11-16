#!/bin/bash
# Vision pipeline for My Assistant
# Sends images to Ollama's vision-language models for analysis
# Works with llava, minicpm-v, qwen-vl, and llama3.2-vision

set -euo pipefail

OLLAMA_URL="${OLLAMA_URL:-http://127.0.0.1:11434}"
VISION_MODEL="${VISION_MODEL:-llava}"
OUTPUT_DIR="${OUTPUT_DIR:-/tmp/my-assistant-vision}"

mkdir -p "$OUTPUT_DIR"

# --- Analyze an image with a vision model ---
analyze_image() {
    local image_path="$1"
    local prompt="${2:-Describe this image in detail."}
    local model="$VISION_MODEL"

    if [ ! -f "$image_path" ]; then
        echo "Error: Image file not found: $image_path" >&2
        exit 1
    fi

    # Convert to base64
    local img_base64
    img_base64=$(base64 < "$image_path" | tr -d '\n')

    echo "[vision] Analyzing: $image_path with $model"

    # Send to Ollama's vision endpoint
    local response
    response=$(curl -s "$OLLAMA_URL/api/chat" \
        -H "Content-Type: application/json" \
        -d "{
            \"model\": \"$model\",
            \"messages\": [{
                \"role\": \"user\",
                \"content\": \"$prompt\",
                \"images\": [\"$img_base64\"]
            }],
            \"stream\": false
        }" 2>/dev/null)

    # Extract the response text
    local text
    text=$(echo "$response" | python3 -c "
import sys, json
try:
    data = json.loads(sys.stdin.read())
    print(data.get('message', {}).get('content', 'No response'))
except:
    print('Failed to parse response')
" 2>/dev/null || echo "Failed to parse response")

    echo "[vision] Result:"
    echo "$text"
    return 0
}

# --- List available vision models ---
list_vision_models() {
    echo "Available vision-capable models:"
    echo ""

    # Check Ollama
    if command -v ollama &>/dev/null; then
        local models
        models=$(ollama list 2>/dev/null | grep -E "llava|minicpm|qwen.*vl|llama.*vision" || true)
        if [ -n "$models" ]; then
            echo "Installed locally:"
            echo "$models"
            echo ""
        fi
    fi

    echo "Recommended vision models for Ollama:"
    echo "  Model              | RAM | Context | Best for"
    echo "  -------------------|-----|---------|-------------------------"
    echo "  llava              | 8GB | 4096    | General image analysis"
    echo "  llava-phi3         | 4GB | 4096    | Light image analysis"
    echo "  minicpm-v          | 8GB | 8192    | Compact, good quality"
    echo "  qwen2-vl:7b        | 8GB | 8192    | Multilingual vision"
    echo "  llama3.2-vision:11b| 16GB| 8192    | Best quality (11B)"
    echo "  llama3.2-vision:90b| 64GB| 8192    | Best quality (90B, large)"
    echo ""
    echo "Pull with: ollama pull <model>"
    echo "Use with:  ./scripts/vision.sh analyze <image> [prompt]"
}

# --- Capture screenshot and analyze ---
capture_and_analyze() {
    local prompt="${1:-What do you see in this screenshot?}"
    local screenshot="$OUTPUT_DIR/screenshot_$(date +%s).png"

    # Take a screenshot
    screencapture -x "$screenshot" 2>/dev/null || {
        echo "Error: screencapture failed" >&2
        exit 1
    }

    analyze_image "$screenshot" "$prompt"
}

# --- Main ---
case "${1:-help}" in
    analyze)
        shift
        analyze_image "$@"
        ;;
    capture)
        shift
        capture_and_analyze "$@"
        ;;
    models)
        list_vision_models
        ;;
    test)
        # Create a test image and analyze it
        local test_img="$OUTPUT_DIR/test_$$.png"
        sips -s format png /System/Library/CoreServices/DefaultDesktop.heic --out "$test_img" 2>/dev/null || true
        if [ -f "$test_img" ]; then
            analyze_image "$test_img" "Describe this image."
            rm -f "$test_img"
        else
            echo "No default image available for test"
        fi
        ;;
    help)
        echo "Usage: vision.sh <command> [args]"
        echo ""
        echo "Commands:"
        echo "  analyze <image> [prompt]    Analyze an image with a vision model"
        echo "  capture [prompt]            Take a screenshot and analyze it"
        echo "  models                      List available vision models"
        echo "  test                        Run a self-test"
        echo ""
        echo "Environment variables:"
        echo "  OLLAMA_URL   (default: http://127.0.0.1:11434)"
        echo "  VISION_MODEL (default: llava)"
        echo ""
        echo "Quick start:"
        echo "  ollama pull llava"
        echo "  ./scripts/vision.sh analyze photo.jpg"
        echo "  ./scripts/vision.sh capture 'What is on my screen?'"
        ;;
    *)
        echo "Unknown command: $1"
        echo "Run: $0 help"
        exit 1
        ;;
esac
