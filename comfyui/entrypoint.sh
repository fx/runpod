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
    if [ -d "/runpod-volume" ]; then
        # Use network volume for persistent cache across pod restarts
        CACHE_DIR="/runpod-volume/cache"
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
        pip install --no-cache-dir torch==2.2.0 torchvision==0.17.0 torchaudio==2.2.0 --index-url https://download.pytorch.org/whl/cu121
    fi

    # Ensure xformers is installed
    if ! python -c "import xformers" 2>/dev/null; then
        echo -e "${YELLOW}Installing xformers...${NC}"
        pip install --no-cache-dir xformers==0.0.24 --index-url https://download.pytorch.org/whl/cu121
    fi

    # Install ComfyUI requirements if not already installed
    if [ ! -f "/workspace/.comfyui_requirements_installed" ]; then
        echo -e "${YELLOW}Installing ComfyUI requirements...${NC}"
        cd /workspace/ComfyUI
        pip install --no-cache-dir -r requirements.txt

        # Install additional packages
        echo -e "${YELLOW}Installing additional packages...${NC}"
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
    elif [ -f "/workspace/configs/config-${config_source}.yaml" ]; then
        # Try config-name.yaml format
        config_file="/workspace/configs/config-${config_source}.yaml"
    elif [ -f "/workspace/${config_source}" ]; then
        # Try in workspace
        config_file="/workspace/${config_source}"
    else
        echo -e "${RED}Config file not found: $config_source${NC}"
        return 1
    fi

    # Export the config file path for later use
    export COMFYUI_CONFIG_FILE="$config_file"

    # Parse YAML and export environment variables
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
    if 'config-' in config_path.name and config_path.suffix == '.yaml':
        loader = ConfigLoader(config_path.parent)
        config_name = config_path.stem.replace('config-', '')
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
env_vars = config.get('env_vars', {})
for key, value in env_vars.items():
    print(f'export {key}=\"{value}\"')

# Store config name
print(f\"export CONFIG_NAME={config.get('name', 'custom')}\")
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
if [ ! -z "$COMFYUI_CONFIG_URL" ]; then
    load_config "$COMFYUI_CONFIG_URL"
elif [ ! -z "$COMFYUI_CONFIG_FILE" ]; then
    load_config "$COMFYUI_CONFIG_FILE"
elif [ ! -z "$CONFIG_NAME" ]; then
    load_config "$CONFIG_NAME"
elif [ -f "/workspace/config.yaml" ]; then
    # Pre-baked config
    load_config "/workspace/config.yaml"
else
    # Default to base config
    load_config "base"
fi

# Install Python packages on first run or if requested
if [ "$FIRST_RUN" = true ] || [ "$FORCE_REINSTALL" = "true" ]; then
    install_python_packages
fi

# Check if running on RunPod
if [ ! -z "$RUNPOD_POD_ID" ]; then
    echo -e "${GREEN}Running on RunPod (Pod ID: $RUNPOD_POD_ID)${NC}"

    # Set up RunPod-specific configurations
    if [ ! -z "$RUNPOD_VOLUME_ID" ]; then
        echo -e "${GREEN}Using RunPod network volume${NC}"

        # Create symlinks for persistent storage if using network volume
        if [ -d "/runpod-volume" ]; then
            echo -e "${YELLOW}Setting up persistent storage symlinks...${NC}"

            # Create organized cache structure on network volume
            mkdir -p /runpod-volume/cache/{pip,torch,huggingface,models}
            mkdir -p /runpod-volume/ComfyUI/{models,output,input,custom_nodes}

            # Create model subdirectories for better organization
            mkdir -p /runpod-volume/ComfyUI/models/{checkpoints,clip,clip_vision,controlnet,diffusers,embeddings,gligen,hypernetworks,loras,style_models,unet,upscale_models,vae,vae_approx}

            # Create symlinks only if they don't exist
            if [ ! -L "/workspace/ComfyUI/models" ] || [ ! -e "/workspace/ComfyUI/models" ]; then
                rm -rf /workspace/ComfyUI/models
                ln -sf /runpod-volume/ComfyUI/models /workspace/ComfyUI/models
            fi

            if [ ! -L "/workspace/ComfyUI/output" ] || [ ! -e "/workspace/ComfyUI/output" ]; then
                rm -rf /workspace/ComfyUI/output
                ln -sf /runpod-volume/ComfyUI/output /workspace/ComfyUI/output
            fi

            if [ ! -L "/workspace/ComfyUI/input" ] || [ ! -e "/workspace/ComfyUI/input" ]; then
                rm -rf /workspace/ComfyUI/input
                ln -sf /runpod-volume/ComfyUI/input /workspace/ComfyUI/input
            fi

            # Set cache environment variables for this session
            export PIP_CACHE_DIR="/runpod-volume/cache/pip"
            export TORCH_HOME="/runpod-volume/cache/torch"
            export HF_HOME="/runpod-volume/cache/huggingface"
            export XDG_CACHE_HOME="/runpod-volume/cache"

            echo -e "${GREEN}Network volume setup complete with organized cache structure${NC}"
        fi
    fi
else
    echo -e "${YELLOW}Not running on RunPod - using local storage${NC}"
fi

# Apply configuration using builder tool
if [ ! -z "$COMFYUI_CONFIG_FILE" ]; then
    echo -e "${YELLOW}Applying configuration...${NC}"

    # Install nodes from config
    if [ "$INSTALL_NODES" != "false" ]; then
        python /workspace/builder.py install-nodes --config "$COMFYUI_CONFIG_FILE" || {
            echo -e "${RED}Warning: Some nodes failed to install${NC}"
        }
    fi

    # Download models if requested
    if [ "$DOWNLOAD_MODELS" = "true" ]; then
        python /workspace/builder.py download --config "$COMFYUI_CONFIG_FILE" || {
            echo -e "${RED}Warning: Some models failed to download${NC}"
        }
    fi
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

# Start ComfyUI
echo -e "${GREEN}Starting ComfyUI with args: $FINAL_ARGS${NC}"
exec python main.py --listen 0.0.0.0 --port 8188 --disable-auto-launch $FINAL_ARGS