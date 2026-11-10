# My Assistant — Complete Setup Guide

This guide walks through every step to set up My Assistant on a fresh Mac. Follow each step in order.

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Install Homebrew and core tools](#2-install-homebrew-and-core-tools)
3. [Install voice servers](#3-install-voice-servers)
4. [Download voice models](#4-download-voice-models)
5. [Install Ollama and local models (optional)](#5-install-ollama-and-local-models-optional)
6. [Install Docker Desktop](#6-install-docker-desktop)
7. [Clone and run setup](#7-clone-and-run-setup)
8. [First login and configuration](#8-first-login-and-configuration)
9. [Configure providers (models)](#9-configure-providers-models)
10. [Configure voice mode](#10-configure-voice-mode)
11. [Install the VS Code extension](#11-install-the-vs-code-extension)
12. [Verify everything works](#12-verify-everything-works)
13. [Daily usage](#13-daily-usage)
14. [Stopping and disabling](#14-stopping-and-disabling)
15. [Troubleshooting](#15-troubleshooting)
16. [Security checklist](#16-security-checklist)

---

## 1. Prerequisites

You need:

- A Mac with Apple Silicon (M1/M2/M3/M4) recommended
- macOS 13 (Ventura) or newer
- An internet connection for the initial setup
- Admin access to your Mac (for Homebrew and launch agents)

## 2. Install Homebrew and core tools

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

## 3. Install voice servers

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

## 4. Download voice models

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

## 5. Install Ollama and local models (optional)

Ollama lets you run LLMs locally with no internet. This is optional — OmniRoute and cloud providers work without it.

```bash
# Install Ollama
brew install ollama

# Start it once to enable the background service
ollama serve &

# Pull Qwen models
ollama pull qwen-64k
ollama pull qwen-32k
```

Enable Ollama to start at login:
- Open Ollama from your Applications folder
- Go to Ollama menu bar icon → Settings
- Enable "Run at login"

## 6. Install Docker Desktop

Docker is required for the Browser extension (agent-driven web browsing).

1. Download from https://www.docker.com/products/docker-desktop/
2. Install and open it
3. Sign in with your Docker account (or create a free one)
4. Go to Docker Desktop → Settings → General
5. Enable **Start Docker Desktop when you sign in to your computer**

After this, Docker starts automatically on every login and stays signed in.

## 7. Clone and run setup

```bash
git clone https://github.com/ghpontapalli/my-assistant
cd my-assistant
chmod +x scripts/setup.sh scripts/my-assistant.sh
./scripts/setup.sh
```

The setup script does all of this automatically:
1. Clones and builds the core portal
2. Generates a secure `.env` with a random portal secret
3. Creates the audio.cpp TTS server config
4. Copies the Mac automation scripts
5. Creates launch agents for auto-start at login (OmniRoute, TTS, STT, portal, browser auto-open)
6. Launches Docker Desktop
7. Builds and installs the VS Code extension

## 8. First login and configuration

After setup completes:

1. Open http://127.0.0.1:4100 in your browser
2. You'll be asked to set a password — choose one and remember it
3. This password is stored locally on your Mac only

## 9. Configure providers (models)

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

## 10. Configure voice mode

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

## 11. Install the VS Code extension

The setup script installs it automatically. If you need to do it manually:

```bash
cd my-assistant/vscode-extension
npx vsce package --no-dependencies
code --install-extension my-assistant-0.1.0.vsix
```

Then reload VS Code (Command+Shift+P → "Reload Window"). The My Assistant icon appears in your activity bar.

## 12. Verify everything works

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

## 13. Daily usage

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

## 14. Stopping and disabling

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

## 15. Troubleshooting

### Portal won't connect to the AI
Check if OmniRoute is running:
```bash
curl -s http://127.0.0.1:20128/v1/models -H "Authorization: Bearer YOUR_KEY"
```
If it's not responding, start it:
```bash
./scripts/my-assistant.sh start
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

## 16. Security checklist

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
