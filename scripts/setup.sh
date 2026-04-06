#!/bin/bash
# Carnice Local LLM - Automated Setup Script
# Run: bash ~/.hermes/skills/mlops/inference/carnice-local-llm/scripts/setup.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
echo_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Detect OS
detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        OS="linux"
    else
        echo_error "Unsupported OS: $OSTYPE"
        exit 1
    fi
    echo_info "Detected OS: $OS"
}

# Detect hardware
detect_hardware() {
    if [[ "$OS" == "macos" ]]; then
        if sysctl -n machdep.cpu.brand_string | grep -qi "apple"; then
            HW="apple_silicon"
            BACKEND="LLAMA_METAL=1"
            echo_info "Detected: Apple Silicon (Metal)"
        else
            HW="intel"
            BACKEND=""
            echo_info "Detected: Intel Mac (CPU-only)"
        fi
    else
        # Linux - check for NVIDIA
        if command -v nvidia-smi &> /dev/null; then
            HW="nvidia"
            BACKEND="LLAMA_CUDA=1"
            echo_info "Detected: NVIDIA GPU (CUDA)"
        else
            HW="cpu"
            BACKEND=""
            echo_info "Detected: Linux (CPU-only)"
        fi
    fi
}

# Check prerequisites
check_prereqs() {
    echo_info "Checking prerequisites..."

    local missing=()

    if ! command -v git &> /dev/null; then
        missing+=("git")
    fi

    if ! command -v cmake &> /dev/null; then
        missing+=("cmake")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo_warn "Missing tools: ${missing[*]}"
        if [[ "$OS" == "macos" ]]; then
            echo_info "Installing via Homebrew..."
            if ! command -v brew &> /dev/null; then
                echo_error "Homebrew not found. Install from https://brew.sh"
                exit 1
            fi
            brew install ${missing[@]}
        else
            echo_info "Installing via apt..."
            sudo apt update && sudo apt install -y ${missing[@]}
        fi
    fi

    echo_success "Prerequisites satisfied"
}

# Build llama.cpp
build_llama() {
    local llama_dir="$HOME/llama.cpp"
    local build_dir="$llama_dir/build"

    if [[ -f "$llama_dir/build/bin/llama-server" ]]; then
        echo_warn "llama.cpp already built at $llama_dir/build/bin/llama-server"
        read -p "Rebuild? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo_info "Skipping build"
            return
        fi
    fi

    echo_info "Building llama.cpp with: ${BACKEND:-CPU-only}"

    if [[ ! -d "$llama_dir" ]]; then
        echo_info "Cloning llama.cpp..."
        git clone https://github.com/ggml-org/llama.cpp.git "$llama_dir"
    fi

    cd "$llama_dir"
    make clean 2>/dev/null || true

    if [[ -n "$BACKEND" ]]; then
        make -j$(nproc) $BACKEND
    else
        make -j$(nproc)
    fi

    if [[ ! -f "$llama_dir/build/bin/llama-server" ]]; then
        echo_error "Build failed - llama-server not found"
        exit 1
    fi

    echo_success "llama.cpp built successfully"
}

# Download model
download_model() {
    local model_dir="$HOME/llama-models"
    mkdir -p "$model_dir"

    echo_info "Model download options:"
    echo "  1) Pre-quantized Carnice 9B Q4_K_M (~5.2GB) - Recommended"
    echo "  2) Base FP16 model + custom quantization"
    echo "  3) Skip (model already exists)"
    read -p "Select option (1/2/3): " choice

    case $choice in
        1)
            echo_info "Downloading Carnice 9B Q4_K_M..."
            if command -v huggingface-cli &> /dev/null; then
                HF_TOKEN="${HF_TOKEN:-}"
                huggingface-cli download kai-os/Carnice-9B-Q4_K_M-GGUF carnice-9b-q4_k_m.gguf \
                    --local-dir "$model_dir" \
                    $([ -n "$HF_TOKEN" ] && echo "--token $HF_TOKEN")
            else
                echo_error "huggingface-cli not found. Install with: pip install huggingface_hub"
                exit 1
            fi
            MODEL_FILE="$model_dir/carnice-9b-q4_k_m.gguf"
            ;;
        2)
            download_base_and_quantize
            ;;
        3)
            # Find existing model
            local existing=$(ls "$model_dir"/carnice-9b*.gguf 2>/dev/null | head -1)
            if [[ -n "$existing" ]]; then
                MODEL_FILE="$existing"
                echo_info "Using existing model: $MODEL_FILE"
            else
                echo_error "No existing model found. Please select option 1 or 2."
                exit 1
            fi
            ;;
        *)
            echo_error "Invalid choice"
            exit 1
            ;;
    esac

    if [[ ! -f "$MODEL_FILE" ]]; then
        echo_error "Model download failed: $MODEL_FILE not found"
        exit 1
    fi

    echo_success "Model ready: $MODEL_FILE"
}

# Download base and quantize
download_base_and_quantize() {
    local model_dir="$HOME/llama-models"
    local base_file="$model_dir/carnice-9b-f16.gguf"

    echo_info "Available quantization levels:"
    echo "  Q2_K - ~2.8GB (lowest quality, max compression)"
    echo "  Q3_K_M - ~3.3GB (medium quality)"
    echo "  Q4_K_M - ~4.1GB (recommended)"
    echo "  Q5_K_M - ~4.8GB (high quality)"
    echo "  Q6_K - ~5.5GB (very high quality)"
    echo "  Q8_0 - ~7.0GB (best quality, largest)"
    read -p "Select quantization (Q4_K_M): " quant

    # Detect number of threads
    local threads=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 8)

    # Download base model
    if [[ ! -f "$base_file" ]]; then
        echo_info "Downloading Carnice 9B base model (~18GB)..."
        if command -v huggingface-cli &> /dev/null; then
            HF_TOKEN="${HF_TOKEN:-}"
            huggingface-cli download kai-os/Carnice-9b carnice-9b-f16.gguf \
                --local-dir "$model_dir" \
                $([ -n "$HF_TOKEN" ] && echo "--token $HF_TOKEN")
        else
            echo_error "huggingface-cli not found. Install with: pip install huggingface_hub"
            exit 1
        fi
    fi

    if [[ ! -f "$base_file" ]]; then
        echo_error "Base model download failed"
        exit 1
    fi

    # Quantize
    local out_file="$model_dir/carnice-9b-${quant,,}.gguf"
    echo_info "Quantizing to ${quant^^} (using $threads threads)..."

    "$HOME/llama.cpp/build/bin/llama-quantize" \
        "$base_file" \
        "$out_file" \
        "${quant:-Q4_K_M}"

    MODEL_FILE="$out_file"
}

# Install carnice wrapper
install_wrapper() {
    local wrapper="$HOME/.local/bin/carnice"
    local model_name=$(basename "$MODEL_FILE" .gguf)
    local threads=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 8)

    mkdir -p "$(dirname "$wrapper")"

    echo_info "Installing carnice wrapper to $wrapper"

    cat > "$wrapper" << EOF
#!/bin/sh
# Carnice wrapper - auto-generated by carnice-local-llm skill
# Starts llama-server, runs hermes, kills server on exit

SERVER_BIN="\$HOME/llama.cpp/build/bin/llama-server"
MODEL="\$HOME/llama-models/${model_name}.gguf"
HOST="127.0.0.1"
PORT="8080"
THREADS="${threads}"
LOGDIR="\$HOME/.local/share/carnice"
LOGFILE="\$LOGDIR/llama-server.log"

mkdir -p "\$LOGDIR"
pkill -f "llama-server.*\${PORT}" 2>/dev/null
sleep 1

\$SERVER_BIN \\
    -m "\$MODEL" \\
    --host "\$HOST" \\
    --port "\$PORT" \\
    -t "\$THREADS" \\
    --reasoning off \\
    >> "\$LOGFILE" 2>&1 &

LLAMA_PID=\$!

hermes -p carnice "\$@"
HERMES_EXIT=\$?

kill \$LLAMA_PID 2>/dev/null

exit \$HERMES_EXIT
EOF

    chmod +x "$wrapper"

    # Ensure ~/.local/bin is in PATH for interactive shells
    local shell_rc=""
    if [[ -f "$HOME/.zshrc" ]]; then
        shell_rc="$HOME/.zshrc"
    elif [[ -f "$HOME/.bashrc" ]]; then
        shell_rc="$HOME/.bashrc"
    fi

    if [[ -n "$shell_rc" ]] && ! grep -q '~/.local/bin' "$shell_rc"; then
        echo "" >> "$shell_rc"
        echo '# Added by carnice-local-llm skill' >> "$shell_rc"
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$shell_rc"
        echo_success "Added ~/.local/bin to PATH in $shell_rc"
        echo_info "Run 'source $shell_rc' or restart your terminal"
    fi

    echo_success "Wrapper installed"
}

# Verify installation
verify() {
    echo_info "Verifying installation..."

    # Check wrapper exists
    if [[ ! -x "$HOME/.local/bin/carnice" ]]; then
        echo_error "Wrapper not found or not executable"
        exit 1
    fi

    # Check model exists
    if [[ ! -f "$MODEL_FILE" ]]; then
        echo_error "Model not found: $MODEL_FILE"
        exit 1
    fi

    # Check llama-server exists
    if [[ ! -f "$HOME/llama.cpp/build/bin/llama-server" ]]; then
        echo_error "llama-server not found"
        exit 1
    fi

    echo ""
    echo_success "Installation verified!"
    echo ""
    echo "To start a carnice session, run:"
    echo "  ${GREEN}carnice${NC}"
    echo ""
    echo "Server logs at: ~/.local/share/carnice/llama-server.log"
    echo ""
    echo "NOTE: If 'carnice: command not found', run:"
    echo "  source ~/.bashrc  # or ~/.zshrc"
    echo "Or add ~/.local/bin to your PATH manually"
}

# Main
main() {
    echo "=========================================="
    echo "  Carnice Local LLM Setup"
    echo "=========================================="
    echo ""

    detect_os
    detect_hardware
    check_prereqs
    build_llama
    download_model
    install_wrapper
    verify
}

main "$@"
