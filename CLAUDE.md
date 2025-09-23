# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## ⚠️ CRITICAL SECURITY RULES ⚠️

### NEVER COMMIT SECRETS TO THIS REPOSITORY

**ABSOLUTELY FORBIDDEN:**
- ❌ NEVER add, commit, or push API keys (RunPod, Docker Hub, HuggingFace, etc.)
- ❌ NEVER hardcode passwords, tokens, or credentials in any file
- ❌ NEVER include secrets in documentation, comments, or examples
- ❌ NEVER commit .env files with real credentials
- ❌ NEVER commit config files containing real API keys

**ALWAYS:**
- ✅ Use placeholders like `YOUR_API_KEY_HERE` or `<api-key>`
- ✅ Store secrets locally in `~/.runpod/config.toml` or similar local configs
- ✅ Use environment variables for runtime secrets
- ✅ Add sensitive files to `.gitignore`
- ✅ Double-check every commit for accidental secrets

**Before EVERY commit:**
1. Review all changes for any strings starting with `rpa_`, `dckr_pat_`, `hf_`, etc.
2. Check for any base64 encoded strings that might be credentials
3. Ensure no real URLs with embedded credentials
4. Verify .env files only contain examples, not real values

## Project Overview

This repository contains Docker templates for deploying various AI applications on RunPod. Each subdirectory contains a complete Docker setup optimized for RunPod deployment.

### Current Templates:
- **comfyui/**: ComfyUI with CUDA support, persistent storage, and pre-installed extensions for Stable Diffusion image generation

## Build and Deployment Commands

### Prerequisites
```bash
# Check Docker status and login
docker info  # Shows Docker daemon status, storage driver, and login status
docker info | grep Username  # Check if logged in to Docker Hub

# Login to Docker Hub if needed
docker login  # Will prompt for username and password

# Check GitHub authentication
gh auth status  # Shows GitHub login status and scopes
gh auth login  # Login to GitHub if needed
```

### Local Development
```bash
# Navigate to specific template directory
cd comfyui/

# Build Docker image locally
docker build -t runpod-comfyui:latest .

# Run with Docker Compose
docker-compose up -d

# View logs
docker logs comfyui

# Stop container
docker-compose down
```

### Building and Pushing Docker Image
```bash
# Check Docker Hub login status first
docker info | grep Username

# Build and tag image from template directory
cd comfyui/
docker build -t effekt/runpod-comfyui:latest .

# Push to Docker Hub (RunPod will pull from here)
docker push effekt/runpod-comfyui:latest

# List images to verify
docker images | grep comfyui

# Image names use the pattern: effekt/runpod-[template-name]
# For ComfyUI: effekt/runpod-comfyui

# Docker Tag Structure:
# - effekt/runpod-comfyui:base (minimal, also tagged as 'latest')
# - effekt/runpod-comfyui:flux (FLUX models)
# - effekt/runpod-comfyui:sdxl-pony (SDXL and Pony models)
# - effekt/runpod-comfyui:video (video generation models)

# Note: Docker CLI can be used for most operations since it's logged in
# To check login: docker info | grep Username
# To delete tags: Must be done via Docker Hub web interface (API requires special permissions)
```

### RunPod Deployment

#### IMPORTANT: Use runpodctl for Pod Operations

**ALWAYS use `runpodctl` for pod management operations:**
- ✅ Creating/starting pods: `runpodctl pod create`
- ✅ Stopping/terminating pods: `runpodctl pod stop`, `runpodctl pod terminate`
- ✅ Listing pods: `runpodctl pod list`
- ✅ Getting pod details: `runpodctl pod get <pod-id>`
- ✅ SSH into pods: `runpodctl pod ssh <pod-id>`
- ✅ Port forwarding: `runpodctl pod port-forward <pod-id>`

**Only use the REST API for:**
- Template management (create/list/delete templates)
- Operations not supported by runpodctl

#### Configure RunPod CLI
```bash
# Install RunPod CLI (already done)
wget -qO- cli.runpod.net | sudo bash
# Or install locally:
mkdir -p ~/.local/bin
wget https://github.com/runpod/runpodctl/releases/latest/download/runpodctl_*_linux_amd64.tar.gz
tar -xzf runpodctl_*_linux_amd64.tar.gz -C ~/.local/bin

# Configure with API key (get from https://www.runpod.io/console/user/settings)
# IMPORTANT: API keys start with "rpa_"
~/.local/bin/runpodctl config --apiKey "rpa_YOUR_API_KEY_HERE"
# Config saved to ~/.runpod/config.toml
```

#### Managing Templates via API

##### Create Template
```bash
# API endpoint: https://rest.runpod.io/v1/templates (NOT api.runpod.io)
# Get API key from: https://www.runpod.io/console/user/settings

API_KEY=$(grep apikey ~/.runpod/config.toml | cut -d'"' -f2)

curl -X POST https://rest.runpod.io/v1/templates \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "ComfyUI Minimal",
    "imageName": "effekt/runpod-comfyui:base",
    "ports": ["8188/http"],
    "volumeInGb": 20,
    "volumeMountPath": "/runpod",
    "env": {
      "CONFIG_NAME": "base",
      "DOWNLOAD_MODELS": "false",
      "AUTO_UPDATE": "false"
    }
  }'

# Note: Unsupported fields will cause errors. Valid fields:
# - name, imageName (required)
# - ports (array), volumeInGb, volumeMountPath, env (object)
# - category, containerDiskInGb, containerRegistryAuthId, readme
# NOT supported: dockerArgs, startSsh, startJupyter (added automatically)
```

##### List Templates
```bash
curl -X GET https://rest.runpod.io/v1/templates \
  -H "Authorization: Bearer ${API_KEY}"
```

##### Delete Template
```bash
curl -X DELETE https://rest.runpod.io/v1/templates/{template_id} \
  -H "Authorization: Bearer ${API_KEY}"
```

#### Deploy Pods with runpodctl

##### Get Available Templates
```bash
# Note: runpodctl doesn't support template listing, use API instead
API_KEY=$(grep apikey ~/.runpod/config.toml | cut -d'"' -f2)

# List all templates with their IDs
curl -s -X GET https://rest.runpod.io/v1/templates \
  -H "Authorization: Bearer ${API_KEY}" | python3 -m json.tool

# Get just template names and IDs
curl -s -X GET https://rest.runpod.io/v1/templates \
  -H "Authorization: Bearer ${API_KEY}" | \
  python3 -c "import json,sys; data=json.load(sys.stdin); [print(f\"{t['id']}: {t['name']}\") for t in data]"
```

##### Start a Spot Pod
```bash
# Start spot pod with specific template
# Note: --imageName is required even when using --templateId
runpodctl create pod \
  --imageName "effekt/runpod-comfyui:flux" \
  --templateId <template-id> \
  --name "comfyui-flux" \
  --gpuType "NVIDIA RTX 4090" \
  --communityCloud \
  --volumeSize 50 \
  --volumePath "/runpod" \
  --ports "8188/http" \
  --startSSH

# For FLUX specifically (template ID: xou8auq29i):
# Option 1: With network volume (RECOMMENDED - Secure Cloud)
runpodctl create pod \
  --imageName "effekt/runpod-comfyui:flux" \
  --templateId xou8auq29i \
  --name "flux-pod" \
  --gpuType "NVIDIA GeForce RTX 4090" \
  --secureCloud \
  --networkVolumeId "neowgnh06n" \
  --ports "8188/http" \
  --startSSH

# Option 2: Without network volume (Community Cloud - cheaper but no persistence)
runpodctl create pod \
  --imageName "effekt/runpod-comfyui:flux" \
  --templateId xou8auq29i \
  --name "flux-pod" \
  --gpuType "NVIDIA RTX A6000" \
  --communityCloud \
  --volumeSize 50 \
  --volumePath "/runpod" \
  --ports "8188/http" \
  --startSSH
```

##### Manage Running Pods

**⚠️ IMPORTANT: Pod Troubleshooting ⚠️**
- If a pod doesn't become ready within 15 minutes of creation, it's likely crash-looping
- **View logs in RunPod Console**: `https://console.runpod.io/pods?id=<pod_id>`
- RunPod API does NOT provide log access - you MUST use the web console
- **NEVER REMOVE PODS WITH ERRORS** - Keep them running so logs can be checked
- Only terminate pods when explicitly instructed by the user
- Common causes: missing models, incorrect config, insufficient disk space

##### When Pod Creation Fails: Availability Troubleshooting

When getting "Error: There are no longer any instances available with the requested specifications":

**1. Check GPU Availability Across Clouds:**
```bash
# Show all available GPUs with pricing
runpodctl get cloud

# Show only Secure Cloud GPUs (required for network volumes)
runpodctl get cloud --secure

# Show only Community Cloud GPUs (cheaper but no network volume support)
runpodctl get cloud --community

# Check your network volumes and their datacenters
# First get your API key from config
grep apikey ~/.runpod/config.toml  # Shows: apikey = "rpa_YOUR_KEY_HERE"

# Then use it in curl commands (replace YOUR_API_KEY with actual key)
curl -s "https://api.runpod.io/graphql?api_key=YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"query": "query { myself { networkVolumes { id name size dataCenterId } } }"}' | jq .

# List all available datacenters
curl -s "https://api.runpod.io/graphql?api_key=YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"query": "query { dataCenters { id name location } }"}' | jq .

# Create network volume in specific datacenter
curl -X POST "https://api.runpod.io/graphql?api_key=YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "query": "mutation { createNetworkVolume(input: {name: \"volume-name\", size: 50, dataCenterId: \"CA-MTL-1\"}) { id name size dataCenterId } }"
  }' | jq .
```

**2. Understanding the Problem:**
- Network volumes are tied to specific datacenters (e.g., US-TX-3)
- GPUs shown as available in Secure Cloud may not be in YOUR datacenter
- The CLI error doesn't specify which constraint is failing

**3. Decision Matrix When Creation Fails:**

| Scenario | Solution | Trade-off |
|----------|----------|-----------|
| No GPUs in network volume's datacenter | Option 1: Wait for availability<br>Option 2: Create new network volume in different datacenter<br>Option 3: Launch without network volume temporarily | 1: Delay<br>2: Re-download everything<br>3: No persistence |
| GPU type not available | Try alternative GPU types in same tier:<br>• A6000 → A5000/A4500<br>• RTX 4090 → RTX 4080/3090<br>• Check VRAM requirements | May affect performance |
| Secure Cloud full | Use Community Cloud without network volume | Lose persistent storage |

**4. Provide Clear Information to User:**
When pod creation fails, ALWAYS provide:
- Current GPU availability table (from `runpodctl get cloud --secure`)
- Network volume location (datacenter)
- Alternative options with clear trade-offs
- DO NOT repeatedly try the same command without explaining the issue

**Example Response When Creation Fails:**
```
Pod creation failed. Here's the current availability:

SECURE CLOUD (supports network volumes):
• RTX A6000: $0.33/hr (available but not in US-TX-3 where your volume is)
• RTX 4090: $0.29/hr (limited availability in US-TX-3)
• RTX A5000: $0.14/hr (available in multiple datacenters)

Your network volume is in US-TX-3. Options:
1. Wait for A6000 availability in US-TX-3
2. Use RTX A5000 instead (less VRAM but available)
3. Create new network volume in different datacenter
4. Launch in Community Cloud without persistence (immediate availability)
```

**💾 Persistent Network Volumes (CRITICAL FOR EFFICIENCY)**

**Key Requirements:**
- ⚠️ **Network volumes ONLY work with Secure Cloud** (`--secureCloud`), NOT Community Cloud
- ⚠️ **Must be created BEFORE pod deployment** - cannot attach to existing pods
- Mounted at `/runpod` and persists across pod terminations
- Saves models, venv cache, and data - eliminates repeated downloads
- **Use North American datacenters only** (US-* or CA-*) for better latency

**Creating a Network Volume:**
```bash
# Get API key
API_KEY=$(grep apikey ~/.runpod/config.toml | cut -d'"' -f2)

# Create network volume (50GB in US-TX-3 datacenter)
curl -X POST "https://api.runpod.io/graphql" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "query": "mutation {
      createNetworkVolume(input: {
        name: \"comfyui-persistent\",
        size: 50,
        dataCenterId: \"US-TX-3\"
      }) {
        id
        name
      }
    }"
  }'

# List existing network volumes
curl -X POST "https://api.runpod.io/graphql" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"query": "query { myself { networkVolumes { id name size dataCenterId } } }"}'
```

**Using Network Volume with Pod:**
```bash
# CORRECT: Secure Cloud with network volume
runpodctl create pod \
  --imageName "effekt/runpod-comfyui:base" \
  --name "pod-with-persistence" \
  --gpuType "NVIDIA GeForce RTX 4090" \
  --secureCloud \  # MUST use Secure Cloud for network volumes
  --networkVolumeId "neowgnh06n" \  # Attach the network volume
  --ports "8188/http" \
  --startSSH

# WRONG: Community Cloud doesn't support network volumes
# --communityCloud  # ❌ Will fail with network volumes
```

**Current Network Volume:**
- **ID**: `neowgnh06n` (comfyui-persistent, 50GB, US-TX-3)
- Use this for all pods to maintain persistent storage
- Cost: $0.07/GB/month = $3.50/month for 50GB
- Saves time and bandwidth by eliminating repeated model downloads

**Secure Cloud vs Community Cloud:**
- **Secure Cloud**: More expensive GPUs, supports network volumes, better availability
- **Community Cloud**: Cheaper GPUs, NO network volume support, may have less availability
- For development with frequent restarts: Use Secure Cloud + network volume
- For one-time runs: Community Cloud may be more cost-effective

```bash
# List all pods
runpodctl get pod

# Get pod details
runpodctl get pod <pod-id>

# Get SSH connection command (use when pod is ready)
runpodctl ssh connect <pod-id>

# SSH into pod (primary method for interacting with pods)
# Note: runpodctl doesn't support logs, exec commands, etc.
# Use SSH for all pod interaction like checking logs, running commands
ssh root@<pod-ip> -p <port> -i ~/.ssh/id_rsa
# Example SSH commands:
# - Check ComfyUI logs: tail -f /workspace/logs/comfyui.log
# - Check system logs: journalctl -xe
# - Monitor GPU: nvidia-smi
# - Check disk usage: df -h /runpod

# Stop pod (keeps data)
runpodctl stop pod <pod-id>

# Terminate pod (deletes everything)
runpodctl remove pod <pod-id>

# Port forward to local machine (if needed for local access)
ssh -L 8188:localhost:8188 root@<pod-ip> -p <port>
```

#### Deploy via Web Interface (Alternative)
1. Go to [RunPod Dashboard](https://runpod.io/console/templates)
2. Templates already created via API will appear here
3. Click "Deploy" on any template
4. Access ComfyUI at: `https://{pod-id}-8188.proxy.runpod.net`

#### Available Docker Images
- `effekt/runpod-comfyui:base` (4GB, minimal)
- `effekt/runpod-comfyui:flux` (with FLUX models)
- `effekt/runpod-comfyui:sdxl-pony` (SDXL + Pony)
- `effekt/runpod-comfyui:video` (video generation)

#### Template Files (for reference)
- `runpod-template.json` - Base configuration
- `runpod-template-flux.json` - FLUX variant
- `runpod-template-sdxl-pony.json` - SDXL/Pony variant
- `runpod-template-video.json` - Video generation

### GitHub Integration
```bash
# Check GitHub auth status
gh auth status

# Create repository if needed
gh repo create runpod --public --source=.

# Push to GitHub
git remote add origin https://github.com/effekt/runpod.git
git push -u origin main

# Set up GitHub Actions secrets for Docker Hub
gh secret set DOCKERHUB_USERNAME
gh secret set DOCKERHUB_TOKEN

# Trigger workflow manually for ComfyUI
gh workflow run comfyui-build.yml

# Check workflow status
gh run list --workflow=comfyui-build.yml
```

### Testing GPU Support
```bash
# Verify NVIDIA GPU is accessible
docker run --gpus all nvidia/cuda:12.1.0-base nvidia-smi
```

## Architecture

### Container Architecture

The Docker container is built in layers:
1. **Base Layer**: CUDA 12.1 runtime on Ubuntu 22.04 for GPU acceleration
2. **Python Environment**: Python 3.11 with venv isolation at `/opt/venv`
3. **PyTorch Layer**: CUDA-enabled PyTorch 2.2.0 with xformers for optimization
4. **ComfyUI Core**: Cloned from official repository to `/workspace/ComfyUI`
5. **Extensions**: ComfyUI Manager pre-installed, others loaded from config

### Configuration System

The system uses YAML configurations to define everything about a ComfyUI setup:
- **Nodes**: Custom nodes to install from GitHub
- **Models**: Models to download from HuggingFace, CivitAI, or direct URLs
- **Requirements**: Python packages to install
- **Workflows**: Pre-built ComfyUI workflows to include
- **Environment Variables**: Runtime settings

**IMPORTANT**: Nothing that can be defined in config files should be hardcoded in entrypoint.sh or Python scripts. All defaults belong in `config-base.yaml`.

### Startup Flow

The `entrypoint.sh` script handles initialization in this sequence:
1. **Config Loading**: Loads configuration from URL, file, name, or defaults to base config
2. **RunPod Detection**: Checks for `RUNPOD_POD_ID` environment variable
3. **Storage Setup**: Creates symlinks to `/runpod` if network storage is available
4. **Config Application**: Uses builder.py to install nodes and download models from config
5. **ComfyUI Launch**: Starts server with config-defined environment variables

### RunPod Integration

When deployed on RunPod:
- Persistent storage is mounted at `/runpod` and symlinked to ComfyUI directories
- Environment variables from `runpod-template.json` configure the container
- Port 8188 is exposed with automatic HTTPS proxy
- GPU is automatically detected and configured

## Key Environment Variables

- `DOWNLOAD_MODELS`: Downloads base SD 1.5, VAE, and upscaler models on startup
- `AUTO_UPDATE`: Pulls latest ComfyUI changes and updates requirements
- `COMFYUI_ARGS`: Pass additional arguments like `--highvram`, `--lowvram`, `--cpu`
- `COMFYUI_PREVIEW_METHOD`: Set to `auto`, `latent2rgb`, or `taesd`

## Storage Paths

- `/workspace/ComfyUI/models/checkpoints/`: Stable Diffusion model files
- `/workspace/ComfyUI/models/vae/`: VAE models for image encoding/decoding
- `/workspace/ComfyUI/models/loras/`: LoRA adapters for model fine-tuning
- `/workspace/ComfyUI/output/`: Generated images
- `/workspace/ComfyUI/custom_nodes/`: Extension installations

## Custom Node Management

Custom nodes are defined in configuration files (e.g., `config-base.yaml`, `config-flux.yaml`):
- Each config specifies which nodes to install
- Nodes are installed from GitHub repositories
- ComfyUI Manager is always pre-installed for UI-based management
- Additional nodes can be added by modifying the config files

## Memory Optimization

Based on GPU VRAM, add to `COMFYUI_ARGS`:
- 24GB+: `--highvram`
- 8-12GB: `--normalvram` or `--lowvram`
- <8GB or CPU: `--cpu` (auto-detected if no GPU)