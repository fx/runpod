#!/bin/bash
set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting ComfyUI initialization...${NC}"

# Function to install Python packages efficiently
install_python_packages() {
    echo -e "${YELLOW}Installing Python dependencies...${NC}"

    # Check for network volume and use it for caching
    if [ -d "/runpod" ]; then
        # Use network volume for persistent cache across pod restarts
        CACHE_DIR="/runpod/cache"
        export PIP_CACHE_DIR="$CACHE_DIR/pip"
        export TORCH_HOME="$CACHE_DIR/torch"
        export HF_HOME="$CACHE_DIR/huggingface"
        export XDG_CACHE_HOME="$CACHE_DIR"

        mkdir -p "$PIP_CACHE_DIR" "$TORCH_HOME" "$HF_HOME"
        echo -e "${GREEN}Using network volume for caching: $CACHE_DIR${NC}"
    else
        # Fallback to local cache
        CACHE_DIR="/workspace/venv-cache"
        if [ -d "$CACHE_DIR" ]; then
            export PIP_CACHE_DIR="$CACHE_DIR/pip"
            mkdir -p "$PIP_CACHE_DIR"
        fi
    fi

    # Check if PyTorch and torchvision are already installed
    if python -c "import torch; import torchvision; print(f'PyTorch {torch.__version__}, torchvision {torchvision.__version__}')" 2>/dev/null; then
        echo -e "${GREEN}PyTorch and torchvision are already installed${NC}"
    else
        echo -e "${YELLOW}Installing PyTorch with CUDA support...${NC}"
        pip install --no-cache-dir torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu129
    fi

    # Ensure xformers is installed
    if ! python -c "import xformers" 2>/dev/null; then
        echo -e "${YELLOW}Installing xformers...${NC}"
        pip install --no-cache-dir xformers --index-url https://download.pytorch.org/whl/cu129
    fi

    # Install ComfyUI requirements if not already installed
    if [ ! -f "/workspace/.comfyui_requirements_installed" ]; then
        echo -e "${YELLOW}Installing ComfyUI requirements...${NC}"
        cd /workspace/ComfyUI
        pip install --no-cache-dir -r requirements.txt

        # Install additional packages
        echo -e "${YELLOW}Installing additional packages...${NC}"
        # Install builder requirements
        pip install --no-cache-dir -r /workspace/requirements-builder.txt
        # Install additional packages that might not be in requirements.txt
        pip install --no-cache-dir \
            opencv-python-headless \
            imageio \
            imageio-ffmpeg \
            transformers \
            safetensors \
            accelerate \
            Pillow \
            scipy


        touch /workspace/.comfyui_requirements_installed
        echo -e "${GREEN}Python dependencies installed successfully${NC}"
    else
        echo -e "${GREEN}Python dependencies already installed${NC}"
    fi
}

# Function to load configuration from file or URL
load_config() {
    local config_source="$1"

    if [ -z "$config_source" ]; then
        return 1
    fi

    echo -e "${YELLOW}Loading configuration from: $config_source${NC}"

    # Check if it's a URL
    if [[ "$config_source" == http* ]]; then
        # Download config from URL
        wget -q -O /tmp/config.yaml "$config_source" || {
            echo -e "${RED}Failed to download config from $config_source${NC}"
            return 1
        }
        config_file="/tmp/config.yaml"
    elif [ -f "$config_source" ]; then
        # Use local file
        config_file="$config_source"
    elif [ -f "/workspace/configs/${config_source}.yaml" ]; then
        # Try name.yaml format
        config_file="/workspace/configs/${config_source}.yaml"
    elif [ -f "/workspace/${config_source}" ]; then
        # Try in workspace
        config_file="/workspace/${config_source}"
    else
        echo -e "${RED}Config file not found: $config_source${NC}"
        return 1
    fi

    # Parse YAML and export environment variables (including COMFYUI_CONFIG_FILE)
    python3 -c "
import sys
import os
from pathlib import Path

# Add lib directory to path for config_loader
sys.path.insert(0, '/workspace/lib')

try:
    # Try to use config_loader_hiyapyco for inheritance support
    try:
        from config_loader_hiyapyco import ConfigLoader
    except ImportError:
        # Fallback to simple loader if HiYaPyCo is not available
        from config_loader_simple import ConfigLoader

    config_path = Path(sys.argv[1])

    # If it's a config in the configs directory, use the loader
    if config_path.suffix == '.yaml':
        loader = ConfigLoader(config_path.parent)
        config_name = config_path.stem
        config = loader.load_config(config_name)
    else:
        # Fallback to regular YAML loading
        import yaml
        with open(config_path, 'r') as f:
            config = yaml.safe_load(f)
except (ImportError, ModuleNotFoundError) as e:
    # Fallback if no config_loader is available
    import yaml
    with open(sys.argv[1], 'r') as f:
        config = yaml.safe_load(f)

# Export environment variables from config
# IMPORTANT: Don't override variables that are already set (from RunPod template)
env_vars = config.get('env_vars', {})
for key, value in env_vars.items():
    # Only export if not already set in environment
    if key not in os.environ:
        print(f'export {key}=\"{value}\"')
    else:
        print(f'# Keeping existing {key}={os.environ[key]} (not overriding with {value})')

# Store config name (always export this)
print(f\"export CONFIG_NAME={config.get('name', 'custom')}\")

# Always export the config file path for builder.py
print(f'export COMFYUI_CONFIG_FILE=\"{sys.argv[1]}\"')
" "$config_file" > /tmp/config_env.sh

    if [ -f "/tmp/config_env.sh" ]; then
        source /tmp/config_env.sh
        echo -e "${GREEN}Configuration loaded successfully${NC}"
        return 0
    fi

    return 1
}

# Check if this is the first run
FIRST_RUN=false
if [ -f "/workspace/.first_run" ]; then
    FIRST_RUN=true
    rm /workspace/.first_run
    echo -e "${YELLOW}First run detected - will install all dependencies${NC}"
fi

# Load configuration from various sources
# Priority: 1. COMFYUI_CONFIG_URL, 2. COMFYUI_CONFIG_FILE, 3. CONFIG_NAME, 4. Pre-baked config, 5. Base config
CONFIG_LOADED=false
if [ ! -z "$COMFYUI_CONFIG_URL" ]; then
    load_config "$COMFYUI_CONFIG_URL" && CONFIG_LOADED=true
elif [ ! -z "$COMFYUI_CONFIG_FILE" ]; then
    load_config "$COMFYUI_CONFIG_FILE" && CONFIG_LOADED=true
elif [ ! -z "$CONFIG_NAME" ]; then
    echo -e "${YELLOW}Loading config: $CONFIG_NAME${NC}"
    load_config "$CONFIG_NAME" && CONFIG_LOADED=true
elif [ -f "/workspace/config.yaml" ]; then
    # Pre-baked config
    load_config "/workspace/config.yaml" && CONFIG_LOADED=true
else
    # Default to base config
    load_config "base" && CONFIG_LOADED=true
fi

if [ "$CONFIG_LOADED" = false ]; then
    echo -e "${RED}Warning: Failed to load configuration, continuing with defaults${NC}"
fi

# Install Python packages on first run or if requested
if [ "$FIRST_RUN" = true ] || [ "$FORCE_REINSTALL" = "true" ]; then
    install_python_packages
fi

# Check if running on RunPod
if [ ! -z "$RUNPOD_POD_ID" ]; then
    echo -e "${GREEN}Running on RunPod (Pod ID: $RUNPOD_POD_ID)${NC}"

    # Check if HuggingFace token is available (set via RunPod template)
    if [ ! -z "$HF_TOKEN" ]; then
        echo -e "${GREEN}HuggingFace token configured${NC}"
    fi

    # Set up RunPod-specific configurations
    # Check if /runpod directory exists (network volume is mounted)
    if [ -d "/runpod" ]; then
        echo -e "${GREEN}Using RunPod network volume${NC}"
        echo -e "${YELLOW}Setting up persistent storage symlinks...${NC}"

        # Create organized cache structure on network volume
        mkdir -p /runpod/cache/{pip,torch,huggingface,models}
        mkdir -p /runpod/ComfyUI/{models,output,input,custom_nodes}

        # Create model subdirectories for better organization
        mkdir -p /runpod/ComfyUI/models/{checkpoints,clip,clip_vision,controlnet,diffusers,embeddings,gligen,hypernetworks,loras,style_models,unet,upscale_models,vae,vae_approx}

        # Create subdirectories for organized model storage by base model type
        mkdir -p /runpod/ComfyUI/models/diffusion_models/{flux,sd3,pixart}
        mkdir -p /runpod/ComfyUI/models/checkpoints/{sd15,sdxl,pony,anime}
        mkdir -p /runpod/ComfyUI/models/loras/{flux,sd15,sdxl,pony}
        mkdir -p /runpod/ComfyUI/models/controlnet/{sd15,sdxl,flux}
        mkdir -p /runpod/ComfyUI/models/vae/{sd15,sdxl,flux}

        # Simply remove and symlink directories - no need to preserve state in ephemeral containers
        # Helper function to safely replace directory with symlink
        replace_with_symlink() {
            local src=$1
            local target=$2
            local name=$3

            # If it's already a symlink pointing to the right place, skip
            if [ -L "$src" ] && [ "$(readlink -f "$src")" = "$(readlink -f "$target")" ]; then
                echo -e "${GREEN}$name already correctly symlinked${NC}"
                return
            fi

            # We don't check for mount points anymore - we ALWAYS want symlinks when /runpod exists

            # Remove existing directory/file/symlink
            # We ALWAYS want to use network storage when available
            if [ -e "$src" ] || [ -L "$src" ]; then
                echo -e "${YELLOW}Removing existing $name to create symlink${NC}"
                rm -rf "$src" 2>/dev/null || {
                    echo -e "${RED}Failed to remove $src, trying with umount${NC}"
                    umount "$src" 2>/dev/null || true
                    rm -rf "$src" 2>/dev/null || true
                }
            fi

            # Create the symlink
            ln -sf "$target" "$src"
            echo -e "${GREEN}Created symlink for $name${NC}"
        }

        # Models directory
        replace_with_symlink "/workspace/ComfyUI/models" "/runpod/ComfyUI/models" "models directory"

        # Output directory
        replace_with_symlink "/workspace/ComfyUI/output" "/runpod/ComfyUI/output" "output directory"

        # Input directory
        replace_with_symlink "/workspace/ComfyUI/input" "/runpod/ComfyUI/input" "input directory"

        # Custom nodes directory
        replace_with_symlink "/workspace/ComfyUI/custom_nodes" "/runpod/ComfyUI/custom_nodes" "custom_nodes directory"

        # Set cache environment variables for this session
        export PIP_CACHE_DIR="/runpod/cache/pip"
        export TORCH_HOME="/runpod/cache/torch"
        export HF_HOME="/runpod/cache/huggingface"
        export XDG_CACHE_HOME="/runpod/cache"

        echo -e "${GREEN}Network volume setup complete with organized cache structure${NC}"
    fi
else
    echo -e "${YELLOW}Not running on RunPod - using local storage${NC}"
fi

# Apply configuration using builder tool
if [ ! -z "$COMFYUI_CONFIG_FILE" ]; then
    echo -e "${YELLOW}Applying configuration from: $COMFYUI_CONFIG_FILE${NC}"

    # Debug: Show environment
    echo -e "${YELLOW}DOWNLOAD_MODELS=$DOWNLOAD_MODELS${NC}"
    echo -e "${YELLOW}INSTALL_NODES=$INSTALL_NODES${NC}"

    # Install nodes from config
    if [ "$INSTALL_NODES" != "false" ]; then
        echo -e "${YELLOW}Installing nodes from config...${NC}"
        python /workspace/builder.py install-nodes --config "$COMFYUI_CONFIG_FILE" || {
            echo -e "${RED}Warning: Some nodes failed to install${NC}"
        }
    fi

    # Download models if requested
    if [ "$DOWNLOAD_MODELS" = "true" ]; then
        echo -e "${YELLOW}Downloading models from config...${NC}"
        python /workspace/builder.py download --config "$COMFYUI_CONFIG_FILE" || {
            echo -e "${RED}Warning: Some models failed to download${NC}"
        }
    fi
else
    echo -e "${YELLOW}No configuration file to apply (COMFYUI_CONFIG_FILE not set)${NC}"
    echo -e "${YELLOW}DOWNLOAD_MODELS=$DOWNLOAD_MODELS but no config file to process${NC}"
fi

# Auto-update ComfyUI if requested
if [ "$AUTO_UPDATE" = "true" ]; then
    echo -e "${YELLOW}Updating ComfyUI...${NC}"
    cd /workspace/ComfyUI
    git pull || echo -e "${RED}Failed to update ComfyUI${NC}"

    # Update requirements if changed
    pip install -r requirements.txt --upgrade
fi

# Detect GPU and set appropriate flags
COMFYUI_GPU_FLAGS=""
if nvidia-smi &> /dev/null; then
    echo -e "${GREEN}GPU detected${NC}"
    nvidia-smi --query-gpu=name,memory.total --format=csv

    # Get GPU memory in MB
    GPU_MEM=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -1)

    # Auto-configure based on GPU memory unless overridden
    if [ -z "$COMFYUI_ARGS" ]; then
        if [ "$GPU_MEM" -ge 40000 ]; then
            echo -e "${GREEN}High VRAM GPU detected (${GPU_MEM}MB) - using highvram mode${NC}"
            COMFYUI_GPU_FLAGS="--highvram"
        elif [ "$GPU_MEM" -ge 20000 ]; then
            echo -e "${GREEN}Normal VRAM GPU detected (${GPU_MEM}MB) - using default mode${NC}"
            COMFYUI_GPU_FLAGS=""
        elif [ "$GPU_MEM" -ge 8000 ]; then
            echo -e "${YELLOW}Low VRAM GPU detected (${GPU_MEM}MB) - using normalvram mode${NC}"
            COMFYUI_GPU_FLAGS="--normalvram"
        else
            echo -e "${YELLOW}Very low VRAM GPU detected (${GPU_MEM}MB) - using lowvram mode${NC}"
            COMFYUI_GPU_FLAGS="--lowvram"
        fi
    fi
else
    echo -e "${YELLOW}No GPU detected, running in CPU mode${NC}"
    COMFYUI_GPU_FLAGS="--cpu"
fi

# Set preview method
PREVIEW_FLAGS=""
if [ ! -z "$COMFYUI_PREVIEW_METHOD" ]; then
    PREVIEW_FLAGS="--preview-method $COMFYUI_PREVIEW_METHOD"
fi

# Combine all arguments
FINAL_ARGS="$COMFYUI_GPU_FLAGS $PREVIEW_FLAGS $COMFYUI_ARGS $COMFYUI_CONFIG_ARGS"

# Change to ComfyUI directory
cd /workspace/ComfyUI

# Start ComfyUI (explicitly use venv Python)
echo -e "${GREEN}Starting ComfyUI with args: $FINAL_ARGS${NC}"
exec /opt/venv/bin/python main.py --listen 0.0.0.0 --port 8188 --disable-auto-launch $FINAL_ARGS