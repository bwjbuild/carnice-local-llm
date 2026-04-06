---
name: carnice-local-llm
description: Set up Carnice 9B locally with llama.cpp — builds llama-server, downloads/quantizes the model, installs the carnice wrapper, and starts a session. One command to get a fully local LLM inference server.
version: 1.0.0
author: Nous Research / Orchestra
license: MIT
dependencies: [git, cmake, build-essential]
metadata:
  hermes:
    tags: [llama.cpp, local LLM, carnice, inference, GGUF, quantization, Apple Silicon, Metal, CUDA]
---

# Carnice Local LLM Setup

## When to Use This Skill

Use this skill when you want to:
- Run Carnice 9B locally on your machine (macOS or Linux)
- Set up an OpenAI-compatible llama-server endpoint for hermes
- Choose your own quantization level (Q2_K through Q8_0)
- Have llama-server auto-killed when you close the hermes session

## Prerequisites

- macOS (Apple Silicon or Intel) or Linux
- ~15GB free disk space
- Internet connection for downloading model (~5-10GB)
- `git` installed

## Setup Steps

Run the setup with:
```bash
hermes skills run carnice-local-llm setup
```

The setup will guide you through these steps:

### Step 1: Detect Environment

The skill auto-detects:
- **OS**: macOS or Linux
- **Hardware**: Apple Silicon (Metal), NVIDIA GPU (CUDA), or CPU-only
- **Build tools**: git, cmake, compiler

### Step 2: Install Build Dependencies

**macOS:**
```bash
xcode-select --install
brew install git cmake
```

**Linux (Ubuntu/Debian):**
```bash
sudo apt update && sudo apt install -y build-essential git cmake
```

### Step 3: Build llama.cpp

```bash
# Clone if not present
git clone https://github.com/ggml-org/llama.cpp.git ~/llama.cpp

cd ~/llama.cpp

# Build with appropriate backend
# Apple Silicon (Metal):
make LLAMA_METAL=1

# NVIDIA GPU (CUDA):
make LLAMA_CUDA=1

# CPU-only:
make
```

Binary lands at: `~/llama.cpp/build/bin/llama-server`

### Step 4: Download Model

Choose one:

**Option A — Pre-quantized model (fastest):**
Download the Carnice 9B Q4_K_M GGUF (~5.2GB) directly:
```bash
mkdir -p ~/llama-models
huggingface-cli download kai-os/Carnice-9b-Q4_K_M-GGUF carnice-9b-q4_k_m.gguf \
    --local-dir ~/llama-models \
    --token $HF_TOKEN
```

**Option B — Custom quantization:**
1. Download base model:
```bash
mkdir -p ~/llama-models
huggingface-cli download kai-os/Carnice-9b carnice-9b-f16.gguf \
    --local-dir ~/llama-models \
    --token $HF_TOKEN
```

2. Quantize to your chosen level:
```bash
~/llama.cpp/build/bin/llama-quantize \
    ~/llama-models/carnice-9b-f16.gguf \
    ~/llama-models/carnice-9b-<LEVEL>.gguf \
    <LEVEL>
```

Quantization levels:
| Level | Size | Quality | Recommended For |
|-------|------|---------|----------------|
| Q2_K | ~2.8GB | Low | Memory-constrained devices |
| Q3_K_M | ~3.3GB | Medium | Balanced |
| Q4_K_M | ~4.1GB | High | **Recommended default** |
| Q5_K_M | ~4.8GB | Very High | Quality focused |
| Q6_K | ~5.5GB | Near-perfect | Near-original quality |
| Q8_0 | ~7.0GB | Best | Maximum quality (large file) |

### Step 5: Install the carnice Wrapper

The wrapper script at `~/.local/bin/carnice`:
1. Starts llama-server on `localhost:8080`
2. Redirects server logs to `~/.local/share/carnice/llama-server.log`
3. Waits for hermes to exit
4. Kills the server automatically

```bash
mkdir -p ~/.local/bin
cat > ~/.local/bin/carnice << 'EOF'
#!/bin/sh
SERVER_BIN="$HOME/llama.cpp/build/bin/llama-server"
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
```

### Step 6: Verify

```bash
# Test the wrapper
carnice --version 2>&1 | head -5

# Or check server logs
tail -f ~/.local/share/carnice/llama-server.log
```

## Usage

### Starting a carnice session
```bash
carnice
```

This will:
1. Start llama-server on `http://127.0.0.1:8080`
2. Launch hermes with the carnice profile
3. When you type `exit`, kill the server automatically

### Checking server logs
```bash
tail -f ~/.local/share/carnice/llama-server.log
```

### Killing server manually
```bash
pkill -f "llama-server.*8080"
```

## Troubleshooting

**"Command not found: carnice"**
```bash
export PATH="$HOME/.local/bin:$PATH"
```

**Model fails to load**
- Check `~/.local/share/carnice/llama-server.log` for errors
- Ensure Metal/CUDA build was used for your hardware

**Server not starting**
- Kill any existing processes: `pkill -f "llama-server.*8080"`
- Check port availability: `lsof -i :8080`

**Out of memory**
- Use a smaller quantization (Q3_K_M or Q2_K)
- Reduce threads: edit `THREADS` in the wrapper script

## Uninstall

```bash
# Remove server
pkill -f "llama-server.*8080"

# Remove model
rm -rf ~/llama-models/carnice-9b*.gguf

# Remove wrapper
rm ~/.local/bin/carnice

# Remove logs
rm -rf ~/.local/share/carnice
```
