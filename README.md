# My Assistant — Personal AI Assistant Setup

A complete, self-contained setup that turns [Pithagoras](https://github.com/thecodacus/pithagoras) into a hands-free personal AI assistant on your Mac — with voice mode, a VS Code extension, Mac automation, and auto-start at login.

## What you get

- **Voice mode** using local Whisper (STT) and audio.cpp / Breeze-TTS (TTS) — fully offline, no API keys
- **My Assistant portal** auto-starts at login and opens in your browser
- **VS Code extension** with a My Assistant chat panel in the sidebar
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

# Breeze TTS model (~5GB) — from HuggingFace
mkdir -p ~/models/audio-cpp/Breeze-TTS-2-GGUF
# Download breeze-tts-2-q8_0.gguf from:
# https://huggingface.co/models?search=breeze-tts-2-gguf
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
1. Clones and builds My Assistant
2. Generates the `.env` config with your workspace path
3. Creates the audio.cpp TTS server config (`server.json`)
4. Installs the VS Code extension
5. Creates launch agents for auto-start at login
6. Registers everything with `launchctl`

## Provider setup

Pithagoras uses pi's `models.json` to define providers. After running the setup script, you configure providers through the portal at **Settings → Providers**, or by editing `~/.pi/agent/models.json` directly. Here's how each one is set up:

### OmniRoute (local router gateway)

OmniRoute is a local model router that aggregates multiple providers behind a single OpenAI-compatible endpoint. It runs on `127.0.0.1:20128`.

**Configuration:**

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

The `auto/*` routes pick the best available model automatically. The `opencode-go/*` routes proxy to specific models like DeepSeek, Qwen, Kimi, GLM, Grok, and more (see the full list below).

**To use:** Set your OmniRoute API key in the provider config, or through **Settings → Providers** in the portal. Then pick `auto/best-coding` or `auto/best-fast` as your default model.

### OpenRouter (cloud, many free models)

OpenRouter gives access to hundreds of models through a single API key. Many models have free tiers.

**Setup:**

1. Get an API key at [openrouter.ai](https://openrouter.ai)
2. In the portal: **Settings → Providers → OpenRouter** → paste your key
3. Or set `OPENROUTER_API_KEY` in your `.env` file

**Notable free models available:**

| Model | Context | Use case |
|---|---|---|
| `openrouter/nvidia/nemotron-3.5-lightning:free` | 1M tokens | Fast coding |
| `openrouter/thinkingmachines/inkling-2-small:free-*` | 1M tokens | Reasoning |
| `openrouter/nvidia/nemotron-3-ultra-550b-a55b:free` | 1M tokens | Heavy reasoning |
| `openrouter/cohere/north-mini-code:free` | 256K tokens | Code |
| `openrouter/google/gemma-4-26b-a4b-it:free` | 262K tokens | General chat |

Image generation, transcription, video generation, and embedding models are also available through OpenRouter.

### DeepSeek (via OmniRoute opencode-go routes)

DeepSeek models are accessed through OmniRoute's `opencode-go` routes, which proxy to DeepSeek's API. No separate key needed beyond the OmniRoute key.

**Available DeepSeek models:**

| Model | Context | Notes |
|---|---|---|
| `opencode-go/deepseek-v4-pro` | 1M tokens | Best DeepSeek, multi-effort: none/low/high/max |
| `opencode-go/deepseek-v4-flash` | 1M tokens | Fast variant, multi-effort |
| `opencode-go/deepseek-v4-flash-vision-exp` | 1M tokens | Vision capable, experimental |
| `opencode-go/deepseek-v4.1-flash` | 1M tokens | Latest flash |
| `opencode-go/deepseek-flash` | 1M tokens | Alias for V4.1 Flash |
| `opencode-go/deepseek-coder-6.7b-instruct` | 128K tokens | Via NVIDIA build |

**To use:** Select any `opencode-go/deepseek-*` model in the portal's model picker. Effort levels are set by appending `-low`, `-high`, `-max` etc. to the model name.

### Qwen (via Ollama, fully local)

Qwen models run locally through Ollama on `127.0.0.1:11434`. No API key, no network calls.

**Setup:**

```bash
# Install Ollama first
ollama pull qwen-64k
ollama pull qwen-32k
```

**Configuration:**

```json
{
  "ollama": {
    "baseUrl": "http://127.0.0.1:11434/v1",
    "api": "openai-completions",
    "apiKey": "ollama",
    "compat": {
      "supportsDeveloperRole": false,
      "supportsReasoningEffort": false
    },
    "models": [
      {
        "id": "qwen-64k:latest",
        "contextWindow": 262144,
        "input": ["text", "image"],
        "reasoning": true
      },
      {
        "id": "qwen-32k:latest",
        "contextWindow": 262144,
        "input": ["text", "image"],
        "reasoning": true
      }
    ]
  }
}
```

**To use:** Select `ollama/qwen-64k:latest` or `ollama/qwen-32k:latest` in the model picker. These support text and image input, and reasoning.

### NVIDIA NIM (cloud, build.nvidia.com)

NVIDIA's NIM API provides access to many open models hosted on build.nvidia.com. Models include Llama, Mistral, Gemma, Nemotron, and more, all at `128K` context.

**Setup:** Requires a NVIDIA API key from [build.nvidia.com](https://build.nvidia.com). Add it through **Settings → Providers** or directly in `models.json`.

**Notable models:**

| Model | Use case |
|---|---|
| `nvidia/nvidia/nemotron-3.5-lightning-30b-a3b` | Fast coding |
| `nvidia/nvidia/nemotron-3-ultra-550b-a55b` | Heavy reasoning |
| `nvidia/nvidia/nemotron-3-nano-omni-30b-a3b-reasoning` | Reasoning |
| `nvidia/meta/llama-3.2-90b-vision-instruct` | Vision |
| `nvidia/openai/gpt-oss-20b` | Open weights, 400K context |
| `nvidia/mistralai/mistral-large-4-1t-a52b` | Large general |
| `nvidia/z-ai/glm-5.3-flash` | Fast GLM, 1M context |

### Other models via opencode-go routes

OmniRoute's `opencode-go` routes provide access to many more models without separate API keys:

| Model | Provider | Context |
|---|---|---|
| `opencode-go/gpt-6-luna` | OpenAI | 1.05M |
| `opencode-go/gpt-5.6-luna` | OpenAI | 1.05M |
| `opencode-go/claude-haiku-5-5` | Anthropic | 1M |
| `opencode-go/grok-4.6` | xAI | 500K |
| `opencode-go/grok-4.7` | xAI | 500K |
| `opencode-go/glm-5.2` | Zhipu | 1M |
| `opencode-go/kimi-k3` | Moonshot | 1M |
| `opencode-go/qwen3.7-max` | Alibaba | 1M |
| `opencode-go/qwen3.8-max` | Alibaba | 1M |
| `opencode-go/mimo-v2.6-pro` | Xiaomi | 1M |
| `opencode-go/minimax-m3` | MiniMax | 1M |
| `opencode-go/hy3-preview` | Tencent | 262K |
| `opencode-go/longcat-2.0` | LongCat | 1M |
| `opencode-go/space-bunny` | Space Bunny | 1M |

## Voice server setup

The Voice servers extension connects to your local STT and TTS servers. Configure it in the portal at **Settings → Extensions → Voice servers**:

| Field | Value |
|---|---|
| Speech recognition URL | `http://127.0.0.1:8082/inference` |
| Speech recognition model | `whisper-1` |
| Input language | (empty for auto-detect) |
| Speech synthesis URL | `http://127.0.0.1:8081/v1/audio/speech` |
| Speech synthesis model | `breeze-tts-2` |
| Speech engine | `audio.cpp` |

Click **Save**, then **Use for voice mode**. The microphone button in the chat activates.

## Usage

### After a cold boot
1. Log in to your Mac — all services start automatically
2. Browser opens automatically at `http://127.0.0.1:4100`
3. Enter your password (set during setup)
4. Open VS Code — click the Pithagoras icon in the activity bar

### Voice mode
In any Pithagoras chat, click the microphone button and talk. The assistant hears you through Whisper and replies through Breeze TTS. Push-to-talk is supported.

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
# Check status
./scripts/pithagoras-auto.sh status

# Stop everything
./scripts/pithagoras-auto.sh stop

# Start everything
./scripts/pithagoras-auto.sh start

# Disable auto-start (won't launch on next login)
./scripts/pithagoras-auto.sh unload

# Re-enable auto-start
./scripts/pithagoras-auto.sh load
```

## Project structure

```
pithagoras-assistant/
├── README.md                 # This file
├── LICENSE                    # Apache 2.0
├── config/
│   └── server.json.template   # audio.cpp TTS server config template
├── launch-agents/             # macOS LaunchAgent plist templates
│   ├── com.pithagoras.portal.plist
│   ├── com.pithagoras.tts.plist
│   ├── com.pithagoras.stt.plist
│   └── com.pithagoras.open-portal.plist
├── scripts/
│   ├── setup.sh               # one-command setup
│   └── pithagoras-auto.sh    # start / stop / status
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

## Credits

Built on [Pithagoras](https://github.com/thecodacus/pithagoras) by thecodacus, which wraps the [pi coding agent](https://pi.dev) by Earendil Works. Voice models from [whisper.cpp](https://github.com/ggml-org/whisper.cpp) and [audio.cpp](https://github.com/ggml-org/audio.cpp).

## License

Apache 2.0
