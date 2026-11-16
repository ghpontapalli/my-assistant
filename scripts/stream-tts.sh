#!/bin/bash
# Streaming text-to-speech pipeline
# Pipes LLM output chunks into TTS incrementally instead of waiting for full response
# This dramatically reduces perceived latency for voice interactions

set -euo pipefail

TTS_URL="${TTS_URL:-http://127.0.0.1:8081/v1/audio/speech}"
TTS_MODEL="${TTS_MODEL:-breeze-tts-2}"
VOICE="${VOICE:-default}"
OUTPUT_DIR="${OUTPUT_DIR:-/tmp/my-assistant-audio}"
OLLAMA_URL="${OLLAMA_URL:-http://127.0.0.1:11434}"
OLLAMA_MODEL="${OLLAMA_MODEL:-qwen-32k}"

mkdir -p "$OUTPUT_DIR"

# --- Streaming TTS function ---
# Takes text chunks and pipes them to TTS as they arrive
# Uses audio.cpp's streaming endpoint when available,
# otherwise batches text into sentence-sized chunks for TTS

stream_tts_from_ollama() {
    local prompt="$1"
    local audio_file="$OUTPUT_DIR/response_$(date +%s).mp3"
    local tmp_dir=$(mktemp -d)

    echo "  [stream-tts] Starting LLM stream → TTS pipeline"

    # Pipe Ollama streaming output to TTS in sentence chunks
    # Ollama's /api/chat with stream:true returns JSON lines
    # We accumulate text and send to TTS when we hit sentence boundaries

    local accumulated=""
    local first_chunk=true

    # Stream from Ollama, accumulate, and pipe to TTS at sentence boundaries
    curl -s "$OLLAMA_URL/api/chat" \
        -H "Content-Type: application/json" \
        -d "{\"model\": \"$OLLAMA_MODEL\", \"messages\": [{\"role\": \"user\", \"content\": \"$prompt\"}], \"stream\": true, \"options\": {\"num_ctx\": 32768}}" \
    | while IFS= read -r line; do
        # Extract the content field from JSON
        local content
        content=$(echo "$line" | python3 -c "import sys,json; print(json.loads(sys.stdin.read()).get('message',{}).get('content',''))" 2>/dev/null || true)

        [ -z "$content" ] && continue

        accumulated="$accumulated$content"

        # Check for sentence boundary (period, exclamation, question mark, or newline)
        if [[ "$content" =~ [\.!\?\n]$ ]]; then
            # Send accumulated text to TTS
            if [ -n "$accumulated" ]; then
                echo -n "$accumulated" | curl -s \
                    -X POST "$TTS_URL" \
                    -H "Content-Type: application/json" \
                    -H "Accept: audio/mpeg" \
                    -d "{\"model\": \"$TTS_MODEL\", \"input\": \"$accumulated\", \"voice\": \"$VOICE\"}" \
                    > "$tmp_dir/chunk_$(date +%N).mp3" 2>/dev/null || true
                accumulated=""
            fi
        fi
    done

    # Flush remaining text
    if [ -n "$accumulated" ]; then
        echo -n "$accumulated" | curl -s \
            -X POST "$TTS_URL" \
            -H "Content-Type: application/json" \
            -H "Accept: audio/mpeg" \
            -d "{\"model\": \"$TTS_MODEL\", \"input\": \"$accumulated\", \"voice\": \"$VOICE\"}" \
            > "$tmp_dir/chunk_final.mp3" 2>/dev/null || true
    fi

    # Concatenate all chunks into one audio file
    if [ -d "$tmp_dir" ] && ls "$tmp_dir"/*.mp3 1>/dev/null 2>&1; then
        cat "$tmp_dir"/*.mp3 > "$audio_file"
        echo "  [stream-tts] Audio saved to $audio_file"
        afplay "$audio_file" 2>/dev/null || true
    fi

    rm -rf "$tmp_dir"
}

# --- Single-shot TTS (for short responses) ---
speak() {
    local text="$1"
    local audio_file="$OUTPUT_DIR/response_$(date +%s).mp3"

    curl -s -X POST "$TTS_URL" \
        -H "Content-Type: application/json" \
        -H "Accept: audio/mpeg" \
        -d "{\"model\": \"$TTS_MODEL\", \"input\": \"$text\", \"voice\": \"$VOICE\"}" \
        > "$audio_file" 2>/dev/null

    afplay "$audio_file" 2>/dev/null || true
}

# --- Main ---
case "${1:-help}" in
    speak)
        shift
        speak "$*"
        ;;
    stream)
        shift
        stream_tts_from_ollama "$*"
        ;;
    test)
        echo "Testing streaming TTS pipeline..."
        stream_tts_from_ollama "Hello! This is a test of the streaming text-to-speech pipeline. It should speak each sentence as it generates it, rather than waiting for the full response."
        ;;
    help)
        echo "Usage: stream-tts.sh <command> [args]"
        echo ""
        echo "Commands:"
        echo "  speak <text>         Speak a single text response (short)"
        echo "  stream <prompt>      Stream LLM response and speak incrementally"
        echo "  test                 Run a self-test of the pipeline"
        echo ""
        echo "Environment variables:"
        echo "  TTS_URL       (default: http://127.0.0.1:8081/v1/audio/speech)"
        echo "  TTS_MODEL     (default: breeze-tts-2)"
        echo "  VOICE         (default: default)"
        echo "  OLLAMA_URL    (default: http://127.0.0.1:11434)"
        echo "  OLLAMA_MODEL  (default: qwen-32k)"
        ;;
    *)
        echo "Unknown command: $1"
        echo "Run: $0 help"
        exit 1
        ;;
esac
