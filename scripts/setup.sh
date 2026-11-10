#!/bin/bash
set -euo pipefail

# Pithagoras Personal Assistant — one-command setup
# Clones and builds Pithagoras, generates config, installs the VS Code extension,
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
PITHAGORAS_DIR="$HOME/Documents/pithagoras"
DATA_DIR="$HOME/.pithagoras-data"

# ---- Check prerequisites ----
info "Checking prerequisites..."

command -v node >/dev/null 2>&1 || error "Node.js is not installed. Run: brew install node"
command -v npm >/dev/null 2>&1 || error "npm is not installed."
command -v git >/dev/null 2>&1 || error "git is not installed."
command -v code >/dev/null 2>&1 || warn "VS Code CLI not found. The extension will be built but not installed automatically."

if ! command -v audiocpp_server >/dev/null 2>&1; then
  warn "audiocpp_server not found. Install audio.cpp for TTS: brew install audio-cpp"
fi
if ! command -v whisper-server >/dev/null 2>&1; then
  warn "whisper-server not found. Install whisper.cpp for STT: brew install whisper-cpp"
fi

# ---- Clone and build Pithagoras ----
if [ ! -d "$PITHAGORAS_DIR" ]; then
  info "Cloning Pithagoras..."
  git clone https://github.com/thecodacus/pithagoras.git "$PITHAGORAS_DIR"
else
  info "Pithagoras already exists at $PITHAGORAS_DIR"
fi

info "Installing Pithagoras dependencies..."
cd "$PITHAGORAS_DIR"
npm install

info "Building Pithagoras..."
npm run build

# ---- Generate .env ----
info "Generating .env..."
PORTAL_SECRET=$(openssl rand -hex 32)
cat > "$PITHAGORAS_DIR/.env" <<EOF
PORT=4100
EXECUTOR=host
WORKSPACES_DIR=$HOME/Documents
PORTAL_DATA_DIR=$DATA_DIR
PORTAL_SECRET=$PORTAL_SECRET
PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin
EOF
info ".env created with a fresh PORTAL_SECRET."

# ---- Create data directory ----
mkdir -p "$DATA_DIR"

# ---- Generate audio.cpp server config ----
if [ ! -f "$HOME/models/audio-cpp/server.json" ]; then
  info "Creating audio.cpp server config..."
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
  info "audio.cpp config created at ~/models/audio-cpp/server.json"
else
  info "audio.cpp server config already exists."
fi

# ---- Copy mac-automation script and skill ----
info "Setting up Mac automation..."
AGENT_HOME="$PITHAGORAS_DIR/data/agent-home"
mkdir -p "$AGENT_HOME/skills/mac-automation"
cp "$PROJECT_DIR/skills/mac-automation/SKILL.md" "$AGENT_HOME/skills/mac-automation/SKILL.md"
if [ -f "$PROJECT_DIR/scripts/mac-automation.sh" ]; then
  cp "$PROJECT_DIR/scripts/mac-automation.sh" "$AGENT_HOME/mac-automation.sh"
  chmod +x "$AGENT_HOME/mac-automation.sh"
fi
info "Mac automation installed."

# ---- Generate launch agents ----
info "Creating launch agents..."
LAUNCH_DIR="$HOME/Library/LaunchAgents"
mkdir -p "$LAUNCH_DIR"
NODE_BIN="$(command -v node)"
AUDIO_BIN="$(command -v audiocpp_server || echo /opt/homebrew/bin/audiocpp_server)"
WHISPER_BIN="$(command -v whisper-server || echo /opt/homebrew/bin/whisper-server)"

# TTS
cat > "$LAUNCH_DIR/com.pithagoras.tts.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.pithagoras.tts</string>
    <key>ProgramArguments</key>
    <array>
        <string>$AUDIO_BIN</string>
        <string>--config</string>
        <string>$HOME/models/audio-cpp/server.json</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
</dict>
</plist>
EOF

# STT
cat > "$LAUNCH_DIR/com.pithagoras.stt.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.pithagoras.stt</string>
    <key>ProgramArguments</key>
    <array>
        <string>$WHISPER_BIN</string>
        <string>-m</string>
        <string>$HOME/models/whisper/ggml-base.en.bin</string>
        <string>--host</string><string>127.0.0.1</string>
        <string>--port</string><string>8082</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
</dict>
</plist>
EOF

# Portal
cat > "$LAUNCH_DIR/com.pithagoras.portal.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.pithagoras.portal</string>
    <key>ProgramArguments</key>
    <array>
        <string>$NODE_BIN</string>
        <string>$PITHAGORAS_DIR/core/server/dist/index.js</string>
    </array>
    <key>WorkingDirectory</key><string>$PITHAGORAS_DIR</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PORT</key><string>4100</string>
        <key>EXECUTOR</key><string>host</string>
        <key>WORKSPACES_DIR</key><string>$HOME/Documents</string>
        <key>PORTAL_DATA_DIR</key><string>$DATA_DIR</string>
        <key>PORTAL_SECRET</key><string>$PORTAL_SECRET</string>
        <key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
    </dict>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
</dict>
</plist>
EOF

# Auto-open browser
cat > "$LAUNCH_DIR/com.pithagoras.open-portal.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.pithagoras.open-portal</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-c</string>
        <string>sleep 10 &amp;&amp; /usr/bin/open http://127.0.0.1:4100</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><false/>
</dict>
</plist>
EOF

# Copy pithagoras-auto.sh
cp "$PROJECT_DIR/scripts/pithagoras-auto.sh" "$AGENT_HOME/pithagoras-auto.sh"
chmod +x "$AGENT_HOME/pithagoras-auto.sh"

# ---- Load launch agents ----
info "Loading launch agents..."
for label in com.pithagoras.tts com.pithagoras.stt com.pithagoras.portal com.pithagoras.open-portal; do
  launchctl load "$LAUNCH_DIR/$label.plist" 2>/dev/null && info "loaded: $label" || warn "could not load: $label"
done

# ---- Build and install VS Code extension ----
if command -v code >/dev/null 2>&1; then
  info "Building VS Code extension..."
  cd "$PROJECT_DIR/vscode-extension"
  npm install 2>/dev/null || true
  npx vsce package --no-dependencies 2>/dev/null
  VSIX=$(ls *.vsix 2>/dev/null | head -1)
  if [ -n "$VSIX" ]; then
    code --install-extension "$VSIX" 2>/dev/null && info "VS Code extension installed." || warn "Could not install extension."
  else
    warn "Could not build .vsix."
  fi
else
  warn "VS Code CLI not found. Build the extension manually from vscode-extension/."
fi

# ---- Done ----
echo ""
echo -e "${BOLD}Setup complete!${RESET}"
echo ""
echo "Next steps:"
echo "  1. Download the voice models (see README.md)"
echo "  2. Open http://127.0.0.1:4100 in your browser"
echo "  3. Set your portal password on first visit"
echo "  4. Configure providers in Settings → Providers"
echo "  5. Configure Voice servers in Settings → Extensions → Voice servers"
echo ""
echo "The portal, TTS and STT servers will auto-start on your next login."
