# My Assistant — Personal AI Assistant

A complete, self-contained setup that gives you a hands-free personal AI assistant on your Mac — with voice mode, a VS Code extension, Mac automation, multi-provider model routing, and auto-start at login.

Built on the [pi coding agent](https://pi.dev) and its web portal.

## What you get

- **Voice mode** using local Whisper (STT) and audio.cpp / Breeze-TTS (TTS) — fully offline, no API keys
- **Portal** auto-starts at login and opens in your browser
- **VS Code extension** with a chat panel in the sidebar
- **Mac automation** — open folders, apps, websites, compose emails by voice
- **Multi-provider model routing** through OmniRoute, OpenRouter, Ollama, NVIDIA, and DeepSeek
- **One-command setup** script

## Prerequisites

| Tool | Install |
|---|---|
| macOS (Apple Silicon recommended) | — |
| [Homebrew](https://brew.sh) | `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"` |
| [Node.js](https://nodejs.org) 18+ | `brew install node` |
| [whisper.cpp](https://github.com/ggml-org/whisper.cpp) | `brew install whisper-cpp` |
| [audio.cpp](https://github.com/ggml-org/audio.cpp) | `brew install audio-cpp` |
| [Docker Desktop](https://www.docker.com/products/docker-desktop/) | Download and install |
| [VS Code or Cursor](https://code.visualstudio.com) | Download and install |
| [Ollama](https://ollama.com) (optional, for local models) | `brew install ollama` or download |

## Models

### Voice models

```bash
# Whisper STT model (base English, ~150MB)
mkdir -p ~/models/whisper
curl -L https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin \
  -o ~/models/whisper/ggml-base.en.bin

# Breeze TTS model (~5GB)
mkdir -p ~/models/audio-cpp/Breeze-TTS-2-GGUF
# Download breeze-tts-2-q8_0.gguf from HuggingFace
# and place it at ~/models/audio-cpp/Breeze-TTS-2-GGUF/breeze-tts-2-q8_0.gguf
```

### Ollama models (optional, for local LLM)

```bash
ollama pull qwen-64k
ollama pull qwen-32k
```

## Quick setup

```bash
git clone https://github.com/ghpontapalli/my-assistant
cd my-assistant
./scripts/setup.sh
```

The setup script:
1. Clones and builds the core portal
2. Generates the `.env` config with your workspace path
3. Creates the audio.cpp TTS server config
4. Installs the VS Code extension
5. Creates launch agents for auto-start at login
6. Registers everything with `launchctl`
7. Launches Docker Desktop

## Docker

Docker Desktop is required for the Browser extension (agent-driven browsing). The setup script launches Docker, but you need to:

1. Sign in to Docker Desktop once after install
2. Enable **Start at login** in Docker Desktop preferences

After that, Docker starts automatically on every login and stays signed in. No manual login needed.

## Provider setup

My Assistant uses pi's `models.json` to define providers. Configure them through the portal at **Settings → Providers**, or by editing `~/.pi/agent/models.json` directly.

### OmniRoute (local router gateway)

A local model router that aggregates multiple providers behind a single OpenAI-compatible endpoint at `127.0.0.1:20128`.

```json
{
  "omniroute": {
    "baseUrl": "http://127.0.0.1:20128/v1",
    "api": "openai-completions",
    "apiKey": "sk-YOUR-OMNIROUTE-KEY",
    "models": [
      { "id": "auto/best-coding", "contextWindow": 1050000 },
      { "id": "auto/best-reasoning", "contextWindow": 1050000 },
      { "id": "auto/best-fast", "contextWindow": 1050000 },
      { "id": "auto/best-vision", "contextWindow": 1050000 },
      { "id": "auto/best-chat", "contextWindow": 1050000 },
      { "id": "auto/best-coding-fast", "contextWindow": 1050000 },
      { "id": "auto/pro-coding", "contextWindow": 1050000 },
      { "id": "auto/pro-reasoning", "contextWindow": 1050000 }
    ]
  }
}
```

The `auto/*` routes pick the best available model automatically. The `opencode-go/*` routes proxy to specific models like DeepSeek, Qwen, Kimi, GLM, Grok, and more.

### OpenRouter (cloud, many free models)

Access to hundreds of models through a single API key. Many have free tiers.

1. Get an API key at [openrouter.ai](https://openrouter.ai)
2. In the portal: **Settings → Providers → OpenRouter** → paste your key
3. Or set `OPENROUTER_API_KEY` in your `.env` file

**Notable free models:**

| Model | Context | Use case |
|---|---|---|
| `openrouter/nvidia/nemotron-3.5-lightning:free` | 1M | Fast coding |
| `openrouter/thinkingmachines/inkling-2-small:free-*` | 1M | Reasoning |
| `openrouter/nvidia/nemotron-3-ultra-550b-a55b:free` | 1M | Heavy reasoning |
| `openrouter/cohere/north-mini-code:free` | 256K | Code |
| `openrouter/google/gemma-4-26b-a4b-it:free` | 262K | General chat |

### DeepSeek (via OmniRoute opencode-go routes)

Accessed through OmniRoute's `opencode-go` routes. No separate key needed beyond the OmniRoute key.

| Model | Context | Notes |
|---|---|---|
| `opencode-go/deepseek-v4-pro` | 1M | Best DeepSeek, multi-effort |
| `opencode-go/deepseek-v4-flash` | 1M | Fast variant, multi-effort |
| `opencode-go/deepseek-v4.1-flash` | 1M | Latest flash |
| `opencode-go/deepseek-v4-flash-vision-exp` | 1M | Vision capable, experimental |

Select any `opencode-go/deepseek-*` model in the model picker. Effort levels: append `-low`, `-high`, `-max`.

### Qwen (via Ollama, fully local)

Runs locally through Ollama at `127.0.0.1:11434`. No API key, no network calls.

```bash
ollama pull qwen-64k
ollama pull qwen-32k
```

```json
{
  "ollama": {
    "baseUrl": "http://127.0.0.1:11434/v1",
    "api": "openai-completions",
    "apiKey": "ollama",
    "compat": { "supportsDeveloperRole": false, "supportsReasoningEffort": false },
    "models": [
      { "id": "qwen-64k:latest", "contextWindow": 262144, "input": ["text", "image"], "reasoning": true },
      { "id": "qwen-32k:latest", "contextWindow": 262144, "input": ["text", "image"], "reasoning": true }
    ]
  }
}
```

### NVIDIA NIM (cloud, build.nvidia.com)

Open models hosted on build.nvidia.com. Requires a NVIDIA API key.

| Model | Use case |
|---|---|
| `nvidia/nvidia/nemotron-3.5-lightning-30b-a3b` | Fast coding |
| `nvidia/nvidia/nemotron-3-ultra-550b-a55b` | Heavy reasoning |
| `nvidia/meta/llama-3.2-90b-vision-instruct` | Vision |
| `nvidia/openai/gpt-oss-20b` | Open weights, 400K context |

### Other models via opencode-go routes

| Model | Provider | Context |
|---|---|---|
| `opencode-go/gpt-6-luna` | OpenAI | 1.05M |
| `opencode-go/claude-haiku-5-5` | Anthropic | 1M |
| `opencode-go/grok-4.6` | xAI | 500K |
| `opencode-go/glm-5.2` | Zhipu | 1M |
| `opencode-go/kimi-k3` | Moonshot | 1M |
| `opencode-go/qwen3.7-max` | Alibaba | 1M |
| `opencode-go/mimo-v2.6-pro` | Xiaomi | 1M |
| `opencode-go/minimax-m3` | MiniMax | 1M |

## Voice server setup

Configure in the portal at **Settings → Extensions → Voice servers**:

| Field | Value |
|---|---|
| Speech recognition URL | `http://127.0.0.1:8082/inference` |
| Speech recognition model | `whisper-1` |
| Speech synthesis URL | `http://127.0.0.1:8081/v1/audio/speech` |
| Speech synthesis model | `breeze-tts-2` |
| Speech engine | `audio.cpp` |

Click **Save**, then **Use for voice mode**.

## Usage

### After a cold boot
1. Log in to your Mac — all services start automatically
2. Browser opens automatically at `http://127.0.0.1:4100`
3. Enter your password (set on first visit)
4. Open VS Code — click the My Assistant icon in the activity bar

### Voice mode
Click the microphone button in any chat and talk. The assistant hears you through Whisper and replies through Breeze TTS.

### Mac automation (by voice or text)
Just ask:
- "Open my Documents folder"
- "Open GitHub in the browser"
- "Open VS Code"
- "Compose an email to john@example.com"
- "Open WhatsApp"
- "Show me a notification when done"

**Allowed apps:** Safari, Firefox, Google Chrome, Visual Studio Code, Finder, Terminal, Notes, Calendar, Mail, Slack, Spotify, WhatsApp

### Service control
```bash
./scripts/my-assistant.sh status     # check what's running
./scripts/my-assistant.sh start      # start everything
./scripts/my-assistant.sh stop       # stop everything
./scripts/my-assistant.sh unload     # disable auto-start
./scripts/my-assistant.sh load       # re-enable auto-start
```

## Project structure

```
my-assistant/
├── README.md
├── LICENSE                    # Apache 2.0
├── scripts/
│   ├── setup.sh               # one-command setup
│   ├── my-assistant.sh        # start / stop / status
│   └── mac-automation.sh      # safe Mac automation actions
├── skills/
│   └── mac-automation/
│       └── SKILL.md           # agent skill for Mac control
└── vscode-extension/          # installable .vsix panel extension
    ├── extension.js
    ├── package.json
    └── icon.svg
```

## Security notes

- All servers bind to `127.0.0.1` only — nothing is exposed to your network
- Mac automation uses a fixed whitelist of allowed apps and validates all inputs
- The portal requires a password you choose at first run
- Voice models run fully locally — no audio leaves your machine
- The VS Code extension embeds the portal in a webview over localhost only
- API keys are stored locally in pi's config, never transmitted except to the provider

## License

Apache 2.0
