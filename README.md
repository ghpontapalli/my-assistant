# My Assistant

**A private, always-on AI assistant for macOS** — powered by a voice-first,
hardware-aware, model-routed agent that lives on your own machine. No cloud
dependency, no data leaves your laptop.

> **One click → a working AI copilot.** Hardware-aware model selection,
> voice in and out, routed to the right model, and a macOS menu-bar toggle.

---

## What it is

My Assistant is a thin, opinionated wrapper on top of the [Pithagoras](https://github.com/thecodacus/pithagoras)
agent core (a pi coding agent with a web portal). It adds:

- **Voice mode** — speak to it (browser Whisper STT) and hear it back (Breeze TTS).
- **Ollama integration** — run a local LLM entirely on your machine.
- **Hardware-aware model selection** — a TUI wizard that picks the best model for your RAM.
- **OmniRoute** — a model router that picks the right model per task.
- **Self-hosted portal** — the agent's web UI, auto-started on boot.
- **VS Code extension** — chat with it from inside VS Code.
- **macOS control app** — a menu-bar icon to start/stop services without a terminal.
- **macOS automation** — open folders, apps, URLs, emails, and send notifications.
- **Multi-provider routing** — one provider per provider type (OpenAI, Anthropic, …).
- **TUI-based setup wizard** — a guided, interactive setup in your terminal.

---

## Why it exists

Running an AI assistant on a laptop should not require:
- spinning up a cloud VM,
- configuring a dozen environment variables by hand,
- choosing the right model by trial and error, or
- opening a terminal every time you want to toggle it on or off.

My Assistant collapses all of that into **one command + a menu-bar icon**:

1. Clone the repo.
2. Run the setup script (or the TUI wizard first to pick a model).
3. Start it from the menu-bar app — or just use the web portal.

Done.

---

## Architecture

```
┌──────────────────────┐    ┌───────────────────┐    ┌────────────────────┐
│  Your Voice / Text   │───▶│  Pithagoras portal │───▶│  OmniRoute router  │
│  (browser / VS Code) │◀───│  (web UI, port 4100)│◀───│  (model router)     │
└──────────────────────┘    └───────────────────┘    └─────────┬──────────┘
          │                    │                                │
          │                    ▼                                ▼
          │            ┌──────────────┐              ┌───────────────────┐
          │            │  Pi agent    │              │  Provider pool    │
          │            │  (coding agent)│             │  OpenAI / Anthropic│
          │            └──────────────┘              │  Ollama / OpenRouter│
          │                                          └───────────────────┘
          ▼
   ┌──────────────────────────────────┐
   │  Breeze TTS 2  (spoken replies)  │
   └──────────────────────────────────┘

   ┌──────────────────────────────────┐
   │  macOS Control App               │
   │  (menu-bar icon, start/stop)     │
   └──────────────────────────────────┘
```

### Components

- **Pithagoras portal** — the agent's web UI, auto-started by a LaunchAgent on
  login. Talks to OmniRoute for model routing.
- **Ollama** — a local LLM runtime. Runs `qwen`, `llama`, `phi3`, or any Ollama model.
- **OmniRoute** — a model router that picks the right model per task (a small
  model for quick tasks, a large model for complex reasoning, a vision model
  for images).
- **Whisper STT** — browser-based speech-to-text (no separate server needed
  for STT; the portal serves the VAD model locally).
- **Breeze TTS** — a local text-to-speech server using the Breeze TTS 2 model
  with Metal (GPU) acceleration.
- **VS Code extension** — a lightweight chat panel that talks to the portal.
- **macOS control app** — a menu-bar status item that shows live status of all
  services and lets you start/stop them without a terminal.
- **mac-automation skill** — a safe, scoped helper that can open folders, apps,
  URLs, emails, and send notifications — **no arbitrary code execution**.

---

## Hardware-aware model selection

The TUI setup wizard (`setup.js`) detects your Mac's RAM and CPU, then recommends
the best Ollama model for your hardware:

| RAM | Recommended model | Context | Use case |
|-----|------------------|---------|----------|
| < 8 GB | `tinyllama:1.1b` | 2,048 | Light tasks, quick responses |
| 8 GB | `phi3:mini` | 4,096 | General coding, reasoning, chat |
| 16 GB | `llama3:8b` | 8,192 | Complex coding, multi-step reasoning |
| 8 GB (alt) | `mistral:7b` | 8,192 | Fast coding, speed/quality balance |
| 8 GB (alt) | `qwen2:7b` | 32,768 | Multilingual tasks, long context |
| 16 GB | `qwen-32k` | 32,768 | Long documents, large codebases |
| 32 GB | `qwen-64k` | 65,536 | Very long context, large projects |

> **Tip:** For `qwen3` models, use `context_length: 32768` and
> `OLLAMA_FLASH_ATTENTION=1` for best performance. Quantized `q4_K_M` or `q8_0`
> variants fit better in limited RAM.

The wizard also checks if Ollama is running, can pull the model for you, and
writes a `config/sample-config.json` that the portal reads.

---

## Quick start

### 1. Clone the repo

```bash
git clone https://github.com/ghpontapalli/my-assistant.git
cd my-assistant
```

### 2. (Optional) Run the TUI wizard to pick a model

```bash
node setup.js
```

This detects your hardware, recommends a model, checks Ollama connectivity,
optionally pulls the model, and writes a sample config.

### 3. Run the main setup script

```bash
./scripts/setup.sh
```

This:
- clones the Pithagoras core into `~/Documents/my-assistant-core`,
- runs `npm install` and `npm run build`,
- generates a `.env` with a random portal secret,
- creates TTS/STT server configs,
- installs the VS Code extension,
- creates LaunchAgents for all 5 services.

### 4. Start the assistant

Open the macOS menu-bar app (the CPU icon) and click **▶ Start Pithagoras**,
or run:

```bash
./scripts/my-assistant.sh start
```

Open the web portal: **http://127.0.0.1:4100**

---

## macOS Control App

A menu-bar status item (`control/Control.swift`) shows live status of all 5
services and lets you start/stop them without a terminal:

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

- **Green dot** next to a service = running. **Grey dot** = stopped.
- **Build:** `swiftc control/Control.swift -o control/PithagorasControl`
- **Run:** `./control/PithagorasControl &`
- **The script path is configurable** via the `LIFECYCLE_SCRIPT` environment variable.

---

## Advanced features

### Streaming TTS

Instead of waiting for the full LLM response before starting to speak, the
assistant pipes LLM output through a sentence-boundary chunker and feeds audio
chunks to the TTS engine as they arrive. This cuts perceived latency from
"wait for whole response" to "start speaking at first sentence."

**Usage:**

```bash
# Speak a text string directly
./scripts/stream-tts.sh speak "Hello world. How are you today?"

# Stream a full LLM response
./scripts/stream-tts.sh stream "Explain quantum computing in simple terms"

# Self-test
./scripts/stream-tts.sh test
```

| Variable | Default | Description |
|----------|---------|-------------|
| `TTS_URL` | `http://127.0.0.1:8081/v1/audio/speech` | TTS endpoint |
| `TTS_MODEL` | `breeze-tts-2` | TTS model name |
| `VOICE` | `default` | Voice to use |
| `OLLAMA_MODEL` | `qwen-32k` | Model to stream from |

### Health-check supervisor

A background monitor that watches Ollama, TTS, STT, and the portal for
liveness. If any service dies, it restarts it. It also switches to a
lighter-weight model when thermal throttling or low battery is detected.

| Condition | Action |
|-----------|--------|
| Thermal level \u2265 2 | Switch to `tinyllama:1.1b` (lightest) |
| CPU \u2265 80% | Switch to `phi3:mini` |
| Memory \u2265 12GB used | Switch to `phi3:mini` |
| On battery power | Switch to `mistral:7b` |
| Default | Stay on current model (`qwen-32k`) |

**Usage:**

```bash
./scripts/supervisor.sh check      # one-shot health check
./scripts/supervisor.sh monitor    # continuous monitoring
./scripts/supervisor.sh model      # show recommended model
./scripts/supervisor.sh restart    # restart all services
```

### Vision / image input

The assistant can understand images through vision-capable Ollama models.

| Model | RAM | Context | Best for |
|-------|-----|---------|----------|
| `llava` | 12GB | 4096 | General image analysis |
| `llava-phi3` | 8GB | 4096 | Light image analysis |
| `qwen2-vl:7b` | 12GB | 8192 | Multilingual vision + OCR |
| `minicpm-v` | 8GB | 8192 | Compact, good quality |

**Usage:**

```bash
./scripts/vision.sh analyze photo.jpg "What is in this image?"
./scripts/vision.sh capture "What is on my screen?"  # screenshot + analyze
./scripts/vision.sh models                             # list available models
./scripts/vision.sh test                               # self-test
```

---

## Project structure

```
my-assistant/
├── README.md              ← this file (human-facing overview)
├── SETUP.md               ← step-by-step setup guide (16 sections)
├── LICENSE
├── .gitignore
│
├── setup.js               ← TUI wizard (hardware-aware model selection)
│
├── scripts/
│   ├── setup.sh           ← one-command setup (clones core, builds, configures)
│   ├── my-assistant.sh    ← start/stop all services via LaunchAgents
│   ├── mac-automation.sh  ← safe, scoped macOS automation helper
│   ├── stream-tts.sh      ← streaming TTS pipeline
│   ├── supervisor.sh      ← health-check + thermal-aware model selector
│   └── vision.sh          ← image analysis via vision models
│
├── control/
│   └── Control.swift      ← macOS menu-bar app source
│
├── config/
│   ├── server.json.template  ← TTS server config template
│   └── sample-config.json    ← sample hardware-aware config
│
├── vscode-extension/      ← VS Code chat panel extension
│   ├── package.json
│   ├── extension.js
│   └── icon.svg
│
└── skills/
    └── mac-automation/
        └── SKILL.md       ← skill definition for the agent
```

---

## Voice mode

Voice mode is **off by default**. To enable it:

1. Start the Breeze TTS server (handled by the setup script / menu-bar app).
2. Open the portal and click the microphone button.
3. Speak — the browser's Whisper model transcribes your speech.
4. The agent responds, and Breeze TTS speaks the reply back.

### Voice style

The assistant speaks in a warm, witty, companion-style voice:

- **1–3 sentences per reply** — short, punchy, no long paragraphs.
- **No markdown, no code dumps, no raw URLs** in spoken replies.
- **Gentle humor** — a light touch of sarcasm or banter.
- **Always ends with a question or suggestion** — keeps the conversation flowing.

---

## OmniRoute (model router)

OmniRoute picks the right model per task:

- **Quick tasks** → small, fast model (`tinyllama`, `phi3`).
- **Complex reasoning** → large model (`llama3:8b`, `qwen-32k`).
- **Vision** → a vision-capable model.
- **Voice** → a fast, low-latency model.

The router is managed as a LaunchAgent (`com.my-assistant.omniroute`).

---

## macOS automation

The `mac-automation` skill is a **safe, scoped helper**. It can:

- Open a folder in Finder.
- Open a URL in a browser (Safari, Firefox, Chrome, VS Code).
- Open an app from a whitelist of 12 common apps.
- Compose an email in Mail.
- Send a notification.
- List folder contents.

**It cannot execute arbitrary code.** The whitelist is:

> Safari, Firefox, Google Chrome, Visual Studio Code, Finder, Terminal,
> Notes, Calendar, Mail, Slack, Spotify, WhatsApp

---

## Multi-provider routing

My Assistant supports one provider per provider type:

- **OpenAI** — for cloud-based tasks.
- **Anthropic** — for Claude models.
- **Ollama** — for local LLMs.
- **OpenRouter** — for access to many models via a single API.

Provider keys are stored in `~/.pi/agent/auth.json` (never committed to git).

---

## Configuration

All configuration lives in `.env` (auto-generated by `setup.sh`):

| Variable | Default | Purpose |
|----------|---------|---------|
| `PORT` | `4100` | Portal port |
| `EXECUTOR` | `host` | Executor mode (`host` or `container`) |
| `WORKSPACES_DIR` | `~/Documents` | Workspace directory |
| `PORTAL_DATA_DIR` | `~/.my-assistant-data` | Data directory |
| `PORTAL_SECRET` | *(random)* | Session cookie secret |
| `STOP_ON_LOGOUT` | `false` | Whether to stop services on logout |
| `LIFECYCLE_SCRIPT` | `scripts/my-assistant.sh` | Path to the control script |

---

## Security

- **Single password auth** — the portal uses one password (not multi-tenant).
- **Tailscale-friendly** — designed to run behind Tailscale or localhost.
- **Host executor** — runs pi as a child process with your full permissions.
- **Scoped automation** — `mac-automation.sh` has a whitelist, no arbitrary code.
- **No cloud dependency** — everything runs locally. Ollama, Breeze TTS, and
  the portal are all on your machine.
- **`.env` is git-ignored** — secrets never reach the repo.

---

## Troubleshooting

### Ollama not found

```bash
brew install ollama
ollama serve &
```

### Portal not starting

Check the LaunchAgent logs:

```bash
./scripts/my-assistant.sh status
log stream --predicate 'subsystem == "com.my-assistant.portal"'
```

### Menu-bar app not showing

Rebuild and relaunch:

```bash
swiftc control/Control.swift -o control/PithagorasControl
killall PithagorasControl 2>/dev/null
./control/PithagorasControl &
```

### Voice not working

1. Ensure the Breeze TTS server is running: `./scripts/my-assistant.sh status`
2. Check browser microphone permissions (click the lock icon in the address bar).
3. Make sure no other app is using the microphone.

### Model too slow

Re-run the TUI wizard to pick a smaller model:

```bash
node setup.js
```

Or manually pull a smaller model:

```bash
ollama pull tinyllama:1.1b
```

---

## License

Apache-2.0 — see [LICENSE](./LICENSE).
