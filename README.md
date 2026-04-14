# Carnice Local LLM

> One-command setup to run Carnice 9B locally on your machine with llama.cpp

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## What This Does

Sets up a fully local Carnice 9B inference server with:

- **Automatic hardware detection** — Metal (Apple Silicon), CUDA (NVIDIA), or CPU-only
- **Model setup** — Download pre-quantized or roll your own quantization
- **Clean wrapper** — `carnice` command starts server + hermes, kills server on exit
- **No more orphaned servers** — Server dies when you close hermes

## Requirements

- macOS (Apple Silicon or Intel) or Linux
- ~15GB free disk space
- Internet connection

## Quick Start

### 1. Clone and run setup

```bash
git clone https://github.com/bwjbuild/carnice-local-llm.git
cd carnice-local-llm
bash scripts/setup.sh
```

### 2. Start a session

```bash
carnice
```

### 3. You're in

The hermes chat uses your local Carnice 9B. Type `exit` to close — the server dies with you.

## What the Setup Does

| Step | What Happens |
|------|-------------|
| 1 | Detects OS and hardware (Metal / CUDA / CPU) |
| 2 | Installs build dependencies (git, cmake) |
| 3 | Clones and builds llama.cpp with your GPU backend |
| 4 | Downloads model (pre-quantized or custom) |
| 5 | Installs `~/.local/bin/carnice` wrapper |
| 6 | Verifies everything works |

## Choosing a Quantization

When asked, pick your quantization level:

| Level | Size | Quality | Best For |
|-------|------|---------|----------|
| **Q4_K_M** | ~5.2GB | High | **Recommended default** |
| Q3_K_M | ~3.3GB | Medium | Less RAM |
| Q5_K_M | ~4.8GB | Very High | More quality |
| Q6_K | ~5.5GB | Near-perfect | Best quality without full FP16 |
| Q8_0 | ~7.0GB | Best | Full quality (large file) |
| Q2_K | ~2.8GB | Low | Memory-constrained |

## Model Options

### Option A — Pre-quantized (fastest)
Download the Q4_K_M GGUF directly (~5.2GB).

### Option B — Custom quantization
1. Download base FP16 model (~18GB)
2. Quantize to your chosen level

## Project Structure

```
carnice-local-llm/
├── SKILL.md                    # Full skill documentation
├── scripts/
│   └── setup.sh               # Automated setup script
└── references/
    └── carnice-wrapper.sh     # Reference wrapper template
```

## Manual Installation

If you prefer to do it step-by-step:

### 1. Install llama.cpp

**macOS (recommended — use Homebrew):**
```bash
brew install llama.cpp
```

Binary installed at: `/opt/homebrew/bin/llama-server`

**Linux/Windows (build from source):**
```bash
git clone https://github.com/ggml-org/llama.cpp.git ~/llama.cpp
cd ~/llama.cpp

# Apple Silicon
make LLAMA_METAL=1

# NVIDIA GPU
make LLAMA_CUDA=1

# CPU-only
make
```

Binary lands at: `~/llama.cpp/build/bin/llama-server`

### 2. Download model

```bash
mkdir -p ~/llama-models
# Download from https://huggingface.co/kai-os/Carnice-9b-GGUF
# Place Carnice-9b-Q4_K_M.gguf in ~/llama-models/
```

### 3. Install wrapper

```bash
mkdir -p ~/.local/bin
cat > ~/.local/bin/carnice << 'EOF'
#!/bin/sh
# Carnice wrapper: starts llama-server before hermes, kills it when hermes exits

# On macOS with Homebrew:
SERVER_BIN="/opt/homebrew/bin/llama-server"
# On Linux/Windows with source build:
# SERVER_BIN="$HOME/llama.cpp/build/bin/llama-server"

MODEL="$HOME/llama-models/carnice-9b-q4_k_m.gguf"
HOST="127.0.0.1"
PORT="8080"
THREADS="8"
LOGDIR="$HOME/.local/share/carnice"
LOGFILE="$LOGDIR/llama-server.log"

mkdir -p "$LOGDIR"
pkill -f "llama-server.*${PORT}" 2>/dev/null
sleep 1

$SERVER_BIN \
    -m "$MODEL" \
    --host "$HOST" \
    --port "$PORT" \
    -t "$THREADS" \
    --reasoning off \
    >> "$LOGFILE" 2>&1 &

LLAMA_PID=$!

hermes -p carnice "$@"
HERMES_EXIT=$?

kill $LLAMA_PID 2>/dev/null

exit $HERMES_EXIT
EOF

chmod +x ~/.local/bin/carnice
export PATH="$HOME/.local/bin:$PATH"
```

### 4. Run

```bash
carnice
```

## Troubleshooting

**`carnice: command not found`**
```bash
export PATH="$HOME/.local/bin:$PATH"
```

**Model fails to load**
```bash
tail -f ~/.local/share/carnice/llama-server.log
```

**Out of memory**
- Use a smaller quantization (Q3_K_M or Q2_K)
- Reduce threads in the wrapper script

**Port already in use**
```bash
pkill -f "llama-server.*8080"
```

## Uninstall

```bash
# Kill server
pkill -f "llama-server.*8080"

# Remove model
rm -rf ~/llama-models/carnice-9b*.gguf

# Remove wrapper
rm ~/.local/bin/carnice

# Remove logs
rm -rf ~/.local/share/carnice
```

## License

MIT
