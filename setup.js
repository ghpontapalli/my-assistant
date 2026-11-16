#!/usr/bin/env node
// My Assistant — Hardware-aware setup wizard (TUI)
// Run: node setup.js  (or from the repo root: npm run setup)
//
// Detects your Mac's RAM and CPU, recommends the best Ollama model,
// checks Ollama connectivity, optionally pulls the model, and writes
// a config.json that the portal can read.

const readline = require("readline");
const os = require("os");
const fs = require("fs");
const path = require("path");

// ── Helpers ────────────────────────────────────────────────────────────────
const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
const ask = (q) => new Promise((res) => rl.question(q, res));
const pick = async (label, options, def = 0) => {
  console.log(`\n${label}`);
  options.forEach((o, i) => console.log(`  [${i + 1}] ${o.label}${o.note ? `  (${o.note})` : ""}`));
  console.log(`  [q] quit`);
  const ans = (await ask(`  Choose (default ${def + 1}): `)).trim();
  if (ans === "q") process.exit(0);
  const n = parseInt(ans) || def + 1;
  return options[Math.min(n - 1, options.length - 1)];
};

const c = {
  dim:    (s) => `\x1b[2m${s}\x1b[0m`,
  bold:   (s) => `\x1b[1m${s}\x1b[0m`,
  green:  (s) => `\x1b[32m${s}\x1b[0m`,
  cyan:   (s) => `\x1b[36m${s}\x1b[0m`,
  yellow: (s) => `\x1b[33m${s}\x1b[0m`,
};

// ── Hardware detection ─────────────────────────────────────────────────────
function detectHardware() {
  const totalMemGB = Math.round(os.totalmem() / 1024 / 1024 / 1024);
  const cpus = os.cpus() || [];
  const cores = cpus.length;
  const osName = os.type() === "Darwin" ? "macOS" : os.type() === "Linux" ? "Linux" : "Windows";
  const osVer = os.release();
  console.log(`\n${c.bold("Hardware detected:")}`);
  console.log(`  OS:        ${osName} ${osVer}`);
  console.log(`  RAM:       ${totalMemGB} GB`);
  console.log(`  Cores:     ${cores}`);
  return { totalMemGB, cores, osName, osVer };
}

// ── Model catalog ──────────────────────────────────────────────────────────
// Tiers map RAM → recommended Ollama model. Sizes are approximate.
const MODELS = [
  {
    label: "tinyllama:1.1b",
    note: "fastest, fits 2GB RAM",
    context: 2048,
    minRam: 2,
    useCase: "Light tasks, quick responses, low-end devices",
  },
  {
    label: "phi3:mini",
    note: "balanced, fits 8GB RAM",
    context: 4096,
    minRam: 4,
    useCase: "General coding, reasoning, chat — good default",
  },
  {
    label: "llama3:8b",
    note: "powerful, needs 16GB+ RAM",
    context: 8192,
    minRam: 12,
    useCase: "Complex coding, long context, multi-step reasoning",
  },
  {
    label: "llama3:8b-instruct-q4_K_M",
    note: "quantized, fits 8GB RAM",
    context: 8192,
    minRam: 8,
    useCase: "Complex coding on 8GB machines (slower than 16GB)",
  },
  {
    label: "mistral:7b",
    note: "fast, fits 8GB RAM",
    context: 8192,
    minRam: 8,
    useCase: "Fast coding, good balance of speed/quality",
  },
  {
    label: "qwen2:7b",
    note: "multilingual, fits 8GB RAM",
    context: 32768,
    minRam: 8,
    useCase: "Multilingual tasks, long context",
  },
  {
    label: "qwen-32k",
    note: "32K context, fits 16GB RAM",
    context: 32768,
    minRam: 12,
    useCase: "Long documents, large codebases",
  },
  {
    label: "qwen-64k",
    note: "64K context, fits 32GB RAM",
    context: 65536,
    minRam: 24,
    useCase: "Very long context, large projects",
  },
];

function recommendModel(hw) {
  const fit = MODELS.filter((m) => m.minRam <= hw.totalMemGB);
  if (!fit.length) {
    console.log(c.yellow(`\n⚠  Your ${hw.totalMemGB}GB RAM is very low for local LLMs.`));
    console.log(c.dim("   Consider using a cloud API (OpenAI, Anthropic) or add more RAM."));
    return MODELS[0];
  }
  return fit.sort((a, b) => b.minRam - a.minRam)[0];
}

// ── Main ───────────────────────────────────────────────────────────────────
async function main() {
  console.log(c.bold("\n╔══════════════════════════════════════╗"));
  console.log(c.bold("║   My Assistant Setup Wizard          ║"));
  console.log(c.bold("║   Hardware-aware model selection     ║"));
  console.log(c.bold("╚══════════════════════════════════════╝"));

  // 1. Detect hardware
  const hw = detectHardware();

  // 2. Ask user to pick or auto-select
  const auto = await ask(`\nAuto-select best model for your ${hw.totalMemGB}GB RAM? [Y/n] `).trim().toLowerCase();
  let model;

  if (auto !== "n") {
    model = recommendModel(hw);
    console.log(c.green(`\n✓ Auto-selected: ${model.label}  (context: ${model.context} tokens, needs ${model.minRam}GB RAM)`));
    console.log(c.dim(`  Use case: ${model.useCase}`));
  } else {
    const options = MODELS.map((m) => ({
      label: m.label,
      note: `${m.minRam}GB+ RAM, ${m.context} ctx — ${m.useCase}`,
    }));
    const defIdx = Math.max(0, MODELS.indexOf(recommendModel(hw)));
    model = (await pick("Select your Ollama model:", options, defIdx)).label;
    model = MODELS.find((m) => m.label === model) || MODELS[1];
    console.log(c.green(`\n✓ Selected: ${model.label}`));
  }

  // 3. Ollama check
  console.log(`\n${c.bold("Ollama check:")}`);
  const ollamaOk = await checkOllama();
  if (!ollamaOk) {
    console.log(c.yellow("  ⚠  Ollama not detected. Install it from https://ollama.com and start it."));
    const proceed = await ask(`\n  Continue anyway? [y/N] `).trim().toLowerCase();
    if (proceed !== "y") {
      console.log(c.dim("\n  Exiting. Install Ollama first: brew install ollama"));
      process.exit(0);
    }
  } else {
    console.log(c.green("  ✓ Ollama found at http://127.0.0.1:11434"));
  }

  // 4. Pull model
  const pull = await ask(`\nPull ${model.label} now? [Y/n] `).trim().toLowerCase();
  if (pull !== "n") {
    console.log(c.dim(`  Running: ollama pull ${model.label}`));
    try {
      const { execSync } = require("child_process");
      execSync(`ollama pull ${model.label}`, { stdio: "inherit" });
      console.log(c.green(`  ✓ ${model.label} pulled successfully`));
    } catch (e) {
      console.log(c.yellow(`  ⚠  Pull failed: ${e.message}`));
      console.log(c.dim(`  You can run 'ollama pull ${model.label}' manually later.`));
    }
  }

  // 5. Write config
  const config = {
    model: model.label,
    context_length: model.context,
    hardware: `${hw.totalMemGB}GB RAM, ${hw.cores} cores, ${hw.osName}`,
    ollama: {
      url: "http://127.0.0.1:11434",
      enabled: true,
    },
    created_at: new Date().toISOString(),
  };

  const configDir = path.join(process.cwd(), "config");
  if (!fs.existsSync(configDir)) fs.mkdirSync(configDir, { recursive: true });
  const configPath = path.join(configDir, "sample-config.json");
  fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
  console.log(c.green(`\n✓ Config written to ${configPath}`));

  // 6. Setup complete
  console.log(`\n${c.bold("──────────────────────────────────────")}`);
  console.log(c.bold("  Setup complete!"));
  console.log(`\n  Next steps:`);
  console.log(`  1. Run the main setup script: ${c.cyan("./scripts/setup.sh")}`);
  console.log(`  2. Open the web portal: ${c.cyan("http://127.0.0.1:4100")}`);
  console.log(`  3. Start chatting or coding with your agent`);
  console.log(`\n  To change your model later, just re-run: ${c.cyan("node setup.js")}`);
  console.log(c.dim(`\n  Your model: ${model.label}  |  Context: ${model.context} tokens`));
  console.log(c.dim(`  Hardware: ${hw.totalMemGB}GB RAM, ${hw.cores} cores`));
  console.log(c.bold("──────────────────────────────────────\n"));

  rl.close();
}

// ── Ollama check ───────────────────────────────────────────────────────────
async function checkOllama() {
  try {
    const http = require("http");
    return new Promise((resolve) => {
      const req = http.get("http://127.0.0.1:11434/api/tags", (res) => {
        res.resume();
        resolve(true);
      });
      req.on("error", () => resolve(false));
      req.setTimeout(3000, () => { req.destroy(); resolve(false); });
    });
  } catch {
    return false;
  }
}

main();
