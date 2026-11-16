# My Assistant — Complete Setup Guide

This guide walks through every step to set up My Assistant on a fresh Mac. Follow each step in order.

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Hardware-aware model selection (TUI wizard)](#2-hardware-aware-model-selection-tui-wizard)
3. [Install Homebrew and core tools](#3-install-homebrew-and-core-tools)
4. [Install voice servers](#4-install-voice-servers)
5. [Download voice models](#5-download-voice-models)
6. [Install Ollama and local models (optional)](#6-install-ollama-and-local-models-optional)
7. [Install Docker Desktop](#7-install-docker-desktop)
8. [Clone and run setup](#8-clone-and-run-setup)
9. [First login and configuration](#9-first-login-and-configuration)
10. [Configure providers (models)](#10-configure-providers-models)
11. [Configure voice mode](#11-configure-voice-mode)
12. [Install the VS Code extension](#12-install-the-vs-code-extension)
13. [macOS menu-bar control app](#13-macos-menu-bar-control-app)
14. [Streaming TTS](#14-streaming-tts)
15. [Health-check supervisor](#15-health-check-supervisor)
16. [Vision / image input](#16-vision--image-input)
17. [Verify everything works](#17-verify-everything-works)
18. [Daily usage](#18-daily-usage)
19. [Stopping and disabling](#19-stopping-and-disabling)
20. [Configuration reference](#20-configuration-reference)
21. [Troubleshooting](#21-troubleshooting)
22. [Security checklist](#22-security-checklist)

---

## 1. Prerequisites

You need:

- A Mac with Apple Silicon (M1/M2/M3/M4) recommended
- macOS 13 (Ventura) or newer
- An internet connection for the initial setup
- Admin access to your Mac (for Homebrew and launch agents)

## 2. Hardware-aware model selection (TUI wizard)

Before or after the full setup, you can run the interactive wizard to pick the best Ollama model for your Mac:

```bash
node setup.js
```

The wizard:

1. **Detects your hardware** — RAM and CPU core count.
2. **Recommends a model** — from 8 options, filtered by your RAM.
3. **Checks Ollama connectivity** — confirms `http://127.0.0.1:11434` is reachable.
4. **Optionally pulls the model** — if Ollama is running and the model isn't installed.
5. **Writes a sample config** — `config/sample-config.json` for the portal to read.

| RAM | Recommended model | Context | Use case |
|-----|------------------|---------|----------|
| < 8 GB | `tinyllama:1.1b` | 2,048 | Light tasks, quick responses |
| 8 GB | `phi3:mini` | 4,096 | General coding, reasoning, chat |
| 16 GB | `llama3:8b` | 8,192 | Complex coding, multi-step reasoning |
| 8 GB (alt) | `mistral:7b` | 8,192 | Fast coding, speed/quality balance |
| 8 GB (alt) | `qwen2:7b` | 32,768 | Multilingual tasks, long context |
| 16 GB | `qwen-32k` | 32,768 | Long documents, large codebases |
| 32 GB | `qwen-64k` | 65,536 | Very long context, large projects |

> **Tip:** For `qwen3` models, use `context_length: 32768` and `OLLAMA_FLASH_ATTENTION=1` for best performance. Quantized `q4_K_M` or `q8_0` variants fit better in limited RAM.

## 3. Install Homebrew and core tools

Open Terminal and run:

```bash
# Install Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Add Homebrew to your PATH (Apple Silicon)
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"

# Install core tools
brew install node git
```

Verify:
```bash
node --version    # should show v18 or higher
git --version
```

## 4. Install voice servers

My Assistant uses two local servers for voice mode:

```bash
# Speech recognition (STT) — whisper.cpp
brew install whisper-cpp

# Speech synthesis (TTS) — audio.cpp
brew install audio-cpp
```

Verify they're installed:
```bash
which whisper-server
which audiocpp_server
```

## 5. Download voice models

These models run fully on your Mac. No internet needed after download.

### Whisper STT model (~150MB)

```bash
mkdir -p ~/models/whisper
curl -L https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin \
  -o ~/models/whisper/ggml-base.en.bin
```

### Breeze TTS model (~5GB)

```bash
mkdir -p ~/models/audio-cpp/Breeze-TTS-2-GGUF
```

Download `breeze-tts-2-q8_0.gguf` from HuggingFace and place it at:
```
~/models/audio-cpp/Breeze-TTS-2-GGUF/breeze-tts-2-q8_0.gguf
```

The setup script creates the server config (`server.json`) automatically. If you want to create it manually, see `config/server.json.template` in this repo.

## 6. Install Ollama and local models (optional)

Ollama lets you run LLMs locally with no internet. This is optional — OmniRoute and cloud providers work without it.

```bash
# Install Ollama
brew install ollama

# Start it once to enable the background service
ollama serve &

# Pull recommended models
ollama pull qwen-64k
ollama pull qwen-32k
```

Enable Ollama to start at login:
- Open Ollama from your Applications folder
- Go to Ollama menu bar icon → Settings
- Enable "Run at login"

## 7. Install Docker Desktop

Docker is required for the Browser extension (agent-driven web browsing).

1. Download from https://www.docker.com/products/docker-desktop/
2. Install and open it
3. Sign in with your Docker account (or create a free one)
4. Go to Docker Desktop → Settings → General
5. Enable **Start Docker Desktop when you sign in to your computer**

After this, Docker starts automatically on every login and stays signed in.

## 8. Clone and run setup

```bash
git clone https://github.com/ghpontapalli/my-assistant
cd my-assistant
chmod +x scripts/setup.sh scripts/my-assistant.sh
./scripts/setup.sh
```

The setup script does all of this automatically:
1. Runs the hardware-aware TUI wizard (`node setup.js`)
2. Clones and builds the core portal
3. Generates a secure `.env` with a random portal secret
4. Creates the audio.cpp TTS server config
5. Copies the Mac automation scripts
6. Creates launch agents for auto-start at login (OmniRoute, TTS, STT, portal, browser auto-open)
7. Launches Docker Desktop
8. Builds and installs the VS Code extension

## 9. First login and configuration

After setup completes:

1. Open http://127.0.0.1:4100 in your browser
2. You'll be asked to set a password — choose one and remember it
3. This password is stored locally on your Mac only

## 10. Configure providers (models)

Go to **Settings → Providers** in the portal. Your setup already includes OmniRoute as the default provider. Here's how to add more:

### OmniRoute (default, already configured)

OmniRoute runs locally at `127.0.0.1:20128` and routes to the best available model automatically. It's already set up by the setup script.

To use specific models through OmniRoute, select any of these in the model picker:
- `auto/best-coding` — best for coding tasks
- `auto/best-fast` — quick responses
- `auto/best-reasoning` — deep thinking
- `opencode-go/deepseek-v4-pro` — DeepSeek
- `opencode-go/qwen3.7-max` — Qwen
- `opencode-go/claude-haiku-5-5` — Claude
- `opencode-go/grok-4.6` — Grok

### OpenRouter (cloud, many free models)

1. Get an API key at https://openrouter.ai
2. In the portal: Settings → Providers → OpenRouter → paste your key
3. Free models available: nemotron-3.5-lightning, inkling-2-small, gemma-4-26b

### Ollama (local, already configured if installed)

If you installed Ollama and pulled models, select:
- `ollama/qwen-64k:latest`
- `ollama/qwen-32k:latest`

These run fully offline with no API key.

### NVIDIA NIM (cloud)

1. Get an API key at https://build.nvidia.com
2. Add it through Settings → Providers

### Switching models

At any time:
- Go to Settings → Defaults and pick a model, or
- Type `/model` in any chat to switch mid-conversation

## 11. Configure voice mode

Go to **Settings → Extensions → Voice servers** and enter:

| Field | Value |
|---|---|
| Speech recognition URL | `http://127.0.0.1:8082/inference` |
| Speech recognition model | `whisper-1` |
| Input language | (leave empty for auto-detect) |
| Speech synthesis URL | `http://127.0.0.1:8081/v1/audio/speech` |
| Speech synthesis model | `breeze-tts-2` |
| Speech engine | `audio.cpp` |

Click **Save**, then click **Use for voice mode**.

The microphone button in the chat now activates. Click it and start talking.

## 12. Install the VS Code extension

The setup script installs it automatically. If you need to do it manually:

```bash
cd my-assistant/vscode-extension
npx vsce package --no-dependencies
code --install-extension my-assistant-0.1.0.vsix
```

Then reload VS Code (Command+Shift+P → "Reload Window"). The My Assistant icon appears in your activity bar.

## 13. macOS menu-bar control app

A menu-bar status item (`control/Control.swift`) shows live status of all services and lets you start/stop them without a terminal:

```
  ●  🌐  Portal
  ●  🧠  Ollama
  ●  🔀  OmniRoute
  ●  🎤  Voice
  ○  🐳  Docker

  ▶  Start Pithagoras
  ⏻  Stop Pithagoras
  🎤  Voice ON
  🔇  Voice OFF
  ↻  Refresh status
  ────
  Quit control
```

- **Green dot** = running. **Grey dot** = stopped.
- **Build & run:** `./scripts/my-assistant.sh control`
- **The script path is configurable** via the `LIFECYCLE_SCRIPT` env variable.
- **Quit:** click "Quit control" in the menu, or `killall PithagorasControl`.

## 14. Streaming TTS

The streaming TTS pipeline feeds LLM output to the TTS engine incrementally,
reducing perceived latency from "wait for whole response" to "start speaking
at first sentence."

```bash
# Speak a text string directly
./scripts/stream-tts.sh speak "Hello world. How are you today?"

# Stream a full LLM response
./scripts/stream-tts.sh stream "Explain quantum computing in simple terms"

# Self-test
./scripts/stream-tts.sh test
```

**How it works:** Ollama streams tokens via `/api/chat` with `stream: true`.
Each token is accumulated into a buffer. When a sentence boundary is hit
(`.`, `!`, `?`, `\n`), the chunk is sent to the TTS engine, which returns
audio. All audio chunks are concatenated and played via `afplay`.

**Env vars:** `TTS_URL`, `TTS_MODEL`, `VOICE`, `OLLAMA_URL`, `OLLAMA_MODEL`.

## 15. Health-check supervisor

A background monitor that watches Ollama, TTS, STT, and the portal for
liveness. If any service dies, it restarts it. Instead of switching models
(which loses context and quality), it **throttles workload** under resource
stress — the model stays the same, only the load changes.

```bash
./scripts/supervisor.sh check      # one-shot health check
./scripts/supervisor.sh monitor    # continuous monitoring (default)
./scripts/supervisor.sh throttle   # show current throttle level
./scripts/supervisor.sh priority   # show Ollama process priority
./scripts/supervisor.sh restart    # restart all services
```

**Throttle levels (not model switches):**

| Level | Condition | Action |
|-------|-----------|--------|
| 0 | Normal | Full power, no restrictions |
| 1 | On battery / CPU \u2265 70% / Thermal warning | Interactive only, skip background tasks |
| 2 | CPU \u2265 90% / Thermal critical / Memory \u2265 14GB | Pause non-critical LLM work |
| 3 | Battery < 15% | Full pause, only voice input until recharged |

**Process priority adjustment** (instead of model swap):

| Throttle | Ollama nice | Effect |
|----------|------------|--------|
| 1 | 5 | Lower priority, system can breathe |
| 2 | 10 | Heavy throttling |
| 3 | 15 | Near-zero priority, only when idle |

**Why not switch models?** Switching loses conversation context, changes
the assistant's voice/style, and can take minutes to reload a large model.
Throttling keeps quality constant while protecting the machine.

**Env vars:** `OLLAMA_URL`, `TTS_PORT`, `STT_PORT`, `PORTAL_PORT`, `CHECK_INTERVAL`, `STATE_FILE`.

## 16. Vision / image input

The assistant can understand images through vision-capable Ollama models.

**Pull a vision model first:**

```bash
ollama pull llava
# or: ollama pull minicpm-v
```

**Usage:**

```bash
# Analyze an image
./scripts/vision.sh analyze photo.jpg "What is in this image?"

# Capture a screenshot and analyze it
./scripts/vision.sh capture "What is on my screen?"

# List available vision models
./scripts/vision.sh models

# Self-test
./scripts/vision.sh test
```

**Vision model reference:**

| Model | RAM | Context | Best for |
|-------|-----|---------|----------|
| `llava` | 12GB | 4096 | General image analysis |
| `llava-phi3` | 8GB | 4096 | Light image analysis |
| `qwen2-vl:7b` | 12GB | 8192 | Multilingual vision + OCR |
| `minicpm-v` | 8GB | 8192 | Compact, good quality |

**Env vars:** `VISION_MODEL`, `OLLAMA_URL`.

## 17. Verify everything works

Run the status check:

```bash
./scripts/my-assistant.sh status
```

You should see all services running:
```
com.my-assistant.omniroute: running
com.my-assistant.tts: running
com.my-assistant.stt: running
com.my-assistant.portal: running
```

Test each service:

```bash
# Check OmniRoute
curl -s http://127.0.0.1:20128/v1/models -H "Authorization: Bearer YOUR_KEY" | head -5

# Check TTS
curl -s http://127.0.0.1:8081/v1/models | head -5

# Check STT
curl -s http://127.0.0.1:8082/ -o /dev/null -w "%{http_code}"

# Check portal
curl -s http://127.0.0.1:4100 -o /dev/null -w "%{http_code}"
```

## 18. Daily usage

### From a cold boot (after setup is done)
1. Log in to your Mac
2. Wait ~15 seconds — all services start automatically
3. Browser opens to http://127.0.0.1:4100
4. Enter your password
5. Open VS Code and click the My Assistant icon, or just use the browser

### Voice mode
Click the microphone button in any chat and talk. Push-to-talk is supported.

### Mac automation
Just ask in the chat:
- "Open my Documents folder"
- "Open GitHub in the browser"
- "Open VS Code"
- "Open WhatsApp"
- "Compose an email to john@example.com about the project update"

Allowed apps: Safari, Firefox, Google Chrome, Visual Studio Code, Finder, Terminal, Notes, Calendar, Mail, Slack, Spotify, WhatsApp

### Switching models
Type `/model` in any chat to switch models on the fly.

## 19. Stopping and disabling

```bash
# Check what's running
./scripts/my-assistant.sh status

# Stop all services (they'll restart on next login)
./scripts/my-assistant.sh stop

# Start all services again
./scripts/my-assistant.sh start

# Disable auto-start permanently
./scripts/my-assistant.sh unload

# Re-enable auto-start
./scripts/my-assistant.sh load
```

## 20. Configuration reference

All config lives in `.env` at the top of the cloned core. Key variables:

| Variable | Default | Purpose |
|----------|---------|---------|
| `PORT` | `4100` | Portal port |
| `EXECUTOR` | `host` | Executor mode (`host` or `container`) |
| `WORKSPACES_DIR` | `~/Documents` | Workspace directory |
| `PORTAL_DATA_DIR` | `~/.my-assistant-data` | Data directory |
| `PORTAL_SECRET` | *(random)* | Session cookie secret |
| `STOP_ON_LOGOUT` | `false` | Whether to stop services on logout |
| `LIFECYCLE_SCRIPT` | `scripts/my-assistant.sh` | Path to control script (menu-bar app) |

The wizard also writes `config/sample-config.json` with your model selection:

```json
{
  "model": "qwen-32k",
  "context_length": 32768,
  "hardware": {
    "ram_gb": 16,
    "cpu_cores": 8
  },
  "ollama": {
    "url": "http://127.0.0.1:11434",
    "enabled": true
  }
}
```

## 21. Troubleshooting

### Ollama not running
```bash
brew services start ollama
# or
ollama serve &
```

### Portal not starting
```bash
# Check the launch agent
launchctl print gui/$(id -u)/com.my-assistant.portal
# Check the log
tail -f ~/.my-assistant-data/portal.log
```

### Menu-bar app not showing
```bash
./scripts/my-assistant.sh control
# or rebuild manually
swiftc control/Control.swift -o control/PithagorasControl -framework AppKit
killall PithagorasControl 2>/dev/null
LIFECYCLE_SCRIPT="$PWD/scripts/my-assistant.sh" control/PithagorasControl &
```

### Model too slow
Re-run the TUI wizard to pick a smaller model:
```bash
node setup.js
```
Or manually pull a smaller model:
```bash
ollama pull tinyllama:1.1b
```

### Voice mode doesn't hear me
Check if the STT server is running:
```bash
curl -s http://127.0.0.1:8082/ -o /dev/null -w "%{http_code}"
```
Should return `200`. If not, restart it.

### Voice mode doesn't speak
Check if the TTS server is running:
```bash
curl -s http://127.0.0.1:8081/v1/models | head -5
```
Should show the breeze-tts-2 model. If not, make sure the model file exists at `~/models/audio-cpp/Breeze-TTS-2-GGUF/breeze-tts-2-q8_0.gguf`.

### Browser extension not working
Make sure Docker Desktop is running. Check with:
```bash
docker info
```
If Docker isn't running, open Docker Desktop from Applications.

### VS Code extension shows blank panel
Reload VS Code (Command+Shift+P → "Reload Window"). If still blank, make sure the portal is running at http://127.0.0.1:4100.

### All services stopped after reboot
Make sure launch agents are loaded:
```bash
./scripts/my-assistant.sh load
./scripts/my-assistant.sh status
```

### "permission denied" when running scripts
```bash
chmod +x scripts/setup.sh scripts/my-assistant.sh scripts/mac-automation.sh
```

## 22. Security checklist

- [x] All servers bind to `127.0.0.1` only — nothing exposed to your network
- [x] No API keys stored in the repository — `.gitignore` blocks `.env`, `auth.json`, `credentials.json`, `*.key`, `*.pem`
- [x] Portal requires a password you choose at first run
- [x] Voice models run fully locally — no audio leaves your machine
- [x] Mac automation uses a fixed whitelist of allowed apps only
- [x] URL validation prevents `javascript:` or non-http schemes
- [x] Folder paths are checked for existence before opening
- [x] The VS Code extension embeds the portal over localhost only
- [x] API keys are stored locally in pi's config (`~/.pi/agent/models.json`), never in this repo
- [x] The portal secret is generated randomly during setup with `openssl rand -hex 32`

**What you should keep private (not in this repo):**
- Your OmniRoute API key
- Your OpenRouter API key
- Your NVIDIA API key
- Your portal password
- Your `~/.pi/agent/models.json` file (contains your actual keys)
- Your `~/.omniroute/.env` file (contains encryption keys)
