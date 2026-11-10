#!/bin/bash
set -euo pipefail

# My Assistant — one-command setup
# Clones and builds the portal, generates config, installs the VS Code extension,
# and creates launch agents for auto-start at login.

BOLD="\033[1m"
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
RESET="\033[0m"

info()  { echo -e "${GREEN}[INFO]${RESET} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${RESET} $1"; }
error() { echo -e "${RED}[ERROR]${RESET} $1"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ASSISTANT_DIR="$HOME/Documents/my-assistant-core"
DATA_DIR="$HOME/.my-assistant-data"

# ---- Check prerequisites ----
info "Checking prerequisites..."
command -v node >/dev/null 2>&1 || error "Node.js not installed. Run: brew install node"
command -v npm  >/dev/null 2>&1 || error "npm not installed."
command -v git  >/dev/null 2>&1 || error "git not installed."
command -v code >/dev/null 2>&1 || warn "VS Code CLI not found. Extension won't auto-install."
command -v audiocpp_server >/dev/null 2>&1 || warn "audiocpp_server not found. Install: brew install audio-cpp"
command -v whisper-server  >/dev/null 2>&1 || warn "whisper-server not found. Install: brew install whisper-cpp"

# ---- Clone and build core ----
if [ ! -d "$ASSISTANT_DIR" ]; then
  info "Cloning core..."
  git clone https://github.com/thecodacus/pithagoras.git "$ASSISTANT_DIR"
else
  info "Core already exists at $ASSISTANT_DIR"
fi

info "Installing dependencies..."
cd "$ASSISTANT_DIR" && npm install

info "Building..."
npm run build

# ---- Generate .env ----
info "Generating config..."
PORTAL_SECRET=$(openssl rand -hex 32)
cat > "$ASSISTANT_DIR/.env" <<EOF
PORT=4100
EXECUTOR=host
WORKSPACES_DIR=$HOME/Documents
PORTAL_DATA_DIR=$DATA_DIR
PORTAL_SECRET=$PORTAL_SECRET
PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin
EOF

mkdir -p "$DATA_DIR"

# ---- Generate audio.cpp server config ----
if [ ! -f "$HOME/models/audio-cpp/server.json" ]; then
  info "Creating TTS server config..."
  mkdir -p "$HOME/models/audio-cpp"
  cat > "$HOME/models/audio-cpp/server.json" <<EOF
{
  "host": "127.0.0.1",
  "port": 8081,
  "backend": "metal",
  "lazy_load": false,
  "max_loaded_models": 1,
  "models": [
    {
      "id": "breeze-tts-2",
      "family": "breeze_tts",
      "path": "$HOME/models/audio-cpp/Breeze-TTS-2-GGUF/breeze-tts-2-q8_0.gguf",
      "task": "tts",
      "mode": "streaming",
      "default_request_options": {
        "instruct": "A friendly, responsive assistant speaking clearly and naturally."
      }
    }
  ]
}
EOF
fi

# ---- Copy automation scripts and skill ----
info "Setting up Mac automation..."
AGENT_HOME="$ASSISTANT_DIR/data/agent-home"
mkdir -p "$AGENT_HOME/skills/mac-automation"
cp "$PROJECT_DIR/skills/mac-automation/SKILL.md" "$AGENT_HOME/skills/mac-automation/SKILL.md"
cp "$PROJECT_DIR/scripts/mac-automation.sh" "$AGENT_HOME/mac-automation.sh"
cp "$PROJECT_DIR/scripts/my-assistant.sh"   "$AGENT_HOME/my-assistant.sh"
chmod +x "$AGENT_HOME/mac-automation.sh" "$AGENT_HOME/my-assistant.sh"

# ---- Generate launch agents ----
info "Creating launch agents..."
LAUNCH_DIR="$HOME/Library/LaunchAgents"
mkdir -p "$LAUNCH_DIR"
NODE_BIN="$(command -v node)"
AUDIO_BIN="$(command -v audiocpp_server || echo /opt/homebrew/bin/audiocpp_server)"
WHISPER_BIN="$(command -v whisper-server  || echo /opt/homebrew/bin/whisper-server)"
OMNI_BIN="$(command -v omniroute || echo /opt/homebrew/bin/omniroute)"

# OmniRoute (model router)
cat > "$LAUNCH_DIR/com.my-assistant.omniroute.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>Label</key><string>com.my-assistant.omniroute</string>
    <key>ProgramArguments</key><array>
        <string>$NODE_BIN</string>
        <string>$OMNI_BIN</string>
    </array>
    <key>EnvironmentVariables</key><dict>
        <key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
    </dict>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
</dict></plist>
EOF

cat > "$LAUNCH_DIR/com.my-assistant.tts.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>Label</key><string>com.my-assistant.tts</string>
    <key>ProgramArguments</key><array>
        <string>$AUDIO_BIN</string>
        <string>--config</string>
        <string>$HOME/models/audio-cpp/server.json</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
</dict></plist>
EOF

cat > "$LAUNCH_DIR/com.my-assistant.stt.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>Label</key><string>com.my-assistant.stt</string>
    <key>ProgramArguments</key><array>
        <string>$WHISPER_BIN</string>
        <string>-m</string><string>$HOME/models/whisper/ggml-base.en.bin</string>
        <string>--host</string><string>127.0.0.1</string>
        <string>--port</string><string>8082</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
</dict></plist>
EOF

cat > "$LAUNCH_DIR/com.my-assistant.portal.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>Label</key><string>com.my-assistant.portal</string>
    <key>ProgramArguments</key><array>
        <string>$NODE_BIN</string>
        <string>$ASSISTANT_DIR/core/server/dist/index.js</string>
    </array>
    <key>WorkingDirectory</key><string>$ASSISTANT_DIR</string>
    <key>EnvironmentVariables</key><dict>
        <key>PORT</key><string>4100</string>
        <key>EXECUTOR</key><string>host</string>
        <key>WORKSPACES_DIR</key><string>$HOME/Documents</string>
        <key>PORTAL_DATA_DIR</key><string>$DATA_DIR</string>
        <key>PORTAL_SECRET</key><string>$PORTAL_SECRET</string>
        <key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
    </dict>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
</dict></plist>
EOF

cat > "$LAUNCH_DIR/com.my-assistant.open-portal.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>Label</key><string>com.my-assistant.open-portal</string>
    <key>ProgramArguments</key><array>
        <string>/bin/bash</string>
        <string>-c</string>
        <string>sleep 10 &amp;&amp; /usr/bin/open http://127.0.0.1:4100</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><false/>
</dict></plist>
EOF

# ---- Load launch agents ----
info "Loading launch agents..."
for label in com.my-assistant.omniroute com.my-assistant.tts com.my-assistant.stt com.my-assistant.portal com.my-assistant.open-portal; do
  launchctl load "$LAUNCH_DIR/$label.plist" 2>/dev/null && info "loaded: $label" || warn "could not load: $label"
done

# ---- Docker Desktop auto-start ----
info "Enabling Docker Desktop auto-start at login..."
open -a Docker 2>/dev/null || warn "Docker Desktop not found. Install from https://www.docker.com/products/docker-desktop/"

# ---- VS Code extension ----
if command -v code >/dev/null 2>&1; then
  info "Building VS Code extension..."
  cd "$PROJECT_DIR/vscode-extension"
  npx vsce package --no-dependencies 2>/dev/null
  VSIX=$(ls *.vsix 2>/dev/null | head -1)
  if [ -n "$VSIX" ]; then
    code --install-extension "$VSIX" && info "VS Code extension installed."
  fi
fi

# ---- Done ----
echo ""
echo -e "${BOLD}Setup complete!${RESET}"
echo ""
echo "Next steps:"
echo "  1. Download voice models (see README.md)"
echo "  2. Open http://127.0.0.1:4100 in your browser"
echo "  3. Set your password on first visit"
echo "  4. Configure providers in Settings → Providers"
echo "  5. Configure voice in Settings → Extensions → Voice servers"
echo "  6. Enable Docker Desktop to start at login: Docker menu → Preferences → Start at login"
