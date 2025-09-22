#!/bin/bash
set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting ComfyUI initialization...${NC}"

# Function to download a file if it doesn't exist
download_if_not_exists() {
    local url=$1
    local dest=$2
    local filename=$(basename "$dest")

    if [ ! -f "$dest" ]; then
        echo -e "${YELLOW}Downloading $filename...${NC}"
        wget -q --show-progress -O "$dest" "$url" || {
            echo -e "${RED}Failed to download $filename${NC}"
            rm -f "$dest"
        }
    else
        echo -e "${GREEN}$filename already exists, skipping download${NC}"
    fi
}

# Check if running on RunPod
if [ ! -z "$RUNPOD_POD_ID" ]; then
    echo -e "${GREEN}Running on RunPod (Pod ID: $RUNPOD_POD_ID)${NC}"

    # Set up RunPod-specific configurations
    if [ ! -z "$RUNPOD_VOLUME_ID" ]; then
        echo -e "${GREEN}Using RunPod network volume${NC}"

        # Create symlinks for persistent storage if using network volume
        if [ -d "/runpod-volume" ]; then
            echo -e "${YELLOW}Setting up persistent storage symlinks...${NC}"

            # Create directories on network volume if they don't exist
            mkdir -p /runpod-volume/ComfyUI/models
            mkdir -p /runpod-volume/ComfyUI/output
            mkdir -p /runpod-volume/ComfyUI/input
            mkdir -p /runpod-volume/ComfyUI/custom_nodes

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
        fi
    fi
fi

# Install popular custom nodes if they don't exist
echo -e "${YELLOW}Checking custom nodes...${NC}"
cd /workspace/ComfyUI/custom_nodes

# List of popular custom nodes to install
declare -a custom_nodes=(
    "https://github.com/Kosinkadink/ComfyUI-AnimateDiff-Evolved"
    "https://github.com/cubiq/ComfyUI_IPAdapter_plus"
    "https://github.com/Fannovel16/comfyui_controlnet_aux"
    "https://github.com/BlenderNeko/ComfyUI_ADV_CLIP_emb"
    "https://github.com/jags111/efficiency-nodes-comfyui"
    "https://github.com/pythongosssss/ComfyUI-WD14-Tagger"
    "https://github.com/rgthree/rgthree-comfy"
    "https://github.com/ssitu/ComfyUI_UltimateSDUpscale"
    "https://github.com/Suzie1/ComfyUI_Comfyroll_CustomNodes"
    "https://github.com/crystian/ComfyUI-Crystools"
)

for repo_url in "${custom_nodes[@]}"; do
    repo_name=$(basename "$repo_url" .git)
    if [ ! -d "$repo_name" ]; then
        echo -e "${YELLOW}Installing custom node: $repo_name${NC}"
        git clone "$repo_url" || echo -e "${RED}Failed to clone $repo_name${NC}"

        # Install requirements if they exist
        if [ -f "$repo_name/requirements.txt" ]; then
            pip install -r "$repo_name/requirements.txt" --quiet || echo -e "${RED}Failed to install requirements for $repo_name${NC}"
        fi
    fi
done

# Download some popular models if specified via environment variable
if [ "$DOWNLOAD_MODELS" = "true" ]; then
    echo -e "${YELLOW}Downloading popular models...${NC}"

    # Create model directories
    mkdir -p /workspace/ComfyUI/models/checkpoints
    mkdir -p /workspace/ComfyUI/models/vae
    mkdir -p /workspace/ComfyUI/models/loras
    mkdir -p /workspace/ComfyUI/models/upscale_models

    # Download a lightweight SD model for testing (SD 1.5)
    download_if_not_exists \
        "https://huggingface.co/runwayml/stable-diffusion-v1-5/resolve/main/v1-5-pruned-emaonly.safetensors" \
        "/workspace/ComfyUI/models/checkpoints/v1-5-pruned-emaonly.safetensors"

    # Download VAE
    download_if_not_exists \
        "https://huggingface.co/stabilityai/sd-vae-ft-mse-original/resolve/main/vae-ft-mse-840000-ema-pruned.safetensors" \
        "/workspace/ComfyUI/models/vae/vae-ft-mse-840000-ema-pruned.safetensors"

    # Download an upscaler
    download_if_not_exists \
        "https://huggingface.co/uwg/upscaler/resolve/main/ESRGAN/ESRGAN_4x.pth" \
        "/workspace/ComfyUI/models/upscale_models/ESRGAN_4x.pth"
fi

# Update ComfyUI if specified
if [ "$AUTO_UPDATE" = "true" ]; then
    echo -e "${YELLOW}Updating ComfyUI...${NC}"
    cd /workspace/ComfyUI
    git pull || echo -e "${RED}Failed to update ComfyUI${NC}"
    pip install -r requirements.txt --upgrade --quiet || echo -e "${RED}Failed to update requirements${NC}"
fi

# Create a simple workflow file if it doesn't exist
if [ ! -f "/workspace/ComfyUI/workflows/default.json" ]; then
    mkdir -p /workspace/ComfyUI/workflows
    cat > /workspace/ComfyUI/workflows/default.json << 'EOF'
{
    "last_node_id": 1,
    "last_link_id": 0,
    "nodes": [],
    "links": [],
    "groups": [],
    "config": {},
    "version": 0.4
}
EOF
fi

# Change to ComfyUI directory
cd /workspace/ComfyUI

# Set up command line arguments
ARGS="--listen 0.0.0.0 --port 8188"

# Add preview method if specified
if [ ! -z "$COMFYUI_PREVIEW_METHOD" ]; then
    ARGS="$ARGS --preview-method $COMFYUI_PREVIEW_METHOD"
fi

# Enable auto-launch in browser if not disabled
if [ "$DISABLE_AUTO_LAUNCH" != "true" ]; then
    ARGS="$ARGS"
else
    ARGS="$ARGS --disable-auto-launch"
fi

# Add CPU mode if no GPU is available
if ! command -v nvidia-smi &> /dev/null || ! nvidia-smi &> /dev/null; then
    echo -e "${YELLOW}No GPU detected, running in CPU mode${NC}"
    ARGS="$ARGS --cpu"
fi

# Add custom args from environment variable
if [ ! -z "$COMFYUI_ARGS" ]; then
    ARGS="$ARGS $COMFYUI_ARGS"
fi

echo -e "${GREEN}Starting ComfyUI with args: $ARGS${NC}"
echo -e "${GREEN}ComfyUI will be available at http://0.0.0.0:8188${NC}"

# Start ComfyUI
exec python main.py $ARGS