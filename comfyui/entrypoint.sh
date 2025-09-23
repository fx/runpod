#!/bin/bash
set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting ComfyUI initialization...${NC}"

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

# Use builder.py to handle all config-based setup (nodes, models, etc.)
if [ ! -z "$COMFYUI_CONFIG_FILE" ] && [ -f "$COMFYUI_CONFIG_FILE" ]; then
    echo -e "${YELLOW}Applying configuration...${NC}"

    # Install nodes from config
    python3 /workspace/builder.py install-nodes --config "$COMFYUI_CONFIG_FILE" || {
        echo -e "${RED}Failed to install nodes${NC}"
    }

    # Download models if specified
    if [ "$DOWNLOAD_MODELS" = "true" ]; then
        python3 /workspace/builder.py download --config "$COMFYUI_CONFIG_FILE" || {
            echo -e "${RED}Failed to download models${NC}"
        }
    fi
fi

# Update ComfyUI if specified
if [ "$AUTO_UPDATE" = "true" ]; then
    echo -e "${YELLOW}Updating ComfyUI...${NC}"
    cd /workspace/ComfyUI
    git pull || echo -e "${RED}Failed to update ComfyUI${NC}"
    pip install -r requirements.txt --upgrade --quiet || echo -e "${RED}Failed to update requirements${NC}"
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