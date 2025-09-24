# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## ⚠️ CRITICAL SECURITY RULES ⚠️

### NEVER COMMIT SECRETS OR USER-SPECIFIC DATA TO THIS REPOSITORY

**ABSOLUTELY FORBIDDEN:**
- ❌ NEVER add, commit, or push API keys (RunPod, Docker Hub, HuggingFace, etc.)
- ❌ NEVER hardcode passwords, tokens, or credentials in any file
- ❌ NEVER include secrets in documentation, comments, or examples
- ❌ NEVER commit .env files with real credentials
- ❌ NEVER commit config files containing real API keys
- ❌ NEVER include pod IDs, volume IDs, or any user-specific identifiers in repository files
- ❌ NEVER commit URLs or data that identifies specific user resources

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
5. Ensure no pod IDs, volume IDs, or user-specific identifiers are included

## ⚠️ CRITICAL RUNPOD DEPLOYMENT RULES ⚠️

### 1. ALWAYS USE TEMPLATES FOR POD CREATION
**NEVER CREATE PODS WITHOUT A TEMPLATE** - The entire purpose of this repository is to manage RunPod deployments via templates.

**Correct workflow:**
1. First: Create or update a template using `comfyui/templates/manage-templates.sh`
2. Then: Create pods using `--templateId` parameter
3. Never: Create pods with just image name and manual configuration

### 2. DATACENTER SELECTION
**NEVER USE US-TX-3 DATACENTER** - This datacenter has persistent availability issues.
- ✅ Always use US-CA-* (California) datacenters instead
- ❌ Avoid US-TX-3 at all costs

### 3. TEMPLATE MANAGEMENT
**NEVER DELETE TEMPLATES WITHOUT EXPLICIT PERMISSION**
- Always ask for confirmation before deleting any template
- Use PATCH to update existing templates when possible
- Use the template management script: `comfyui/templates/manage-templates.sh`

### 4. POD ERROR HANDLING
**WHEN POD CREATION FAILS, STOP AND INFORM THE USER**
- Don't retry the same command without explaining the issue
- Provide clear error information and available alternatives
- Check GPU availability and suggest options

## Project Overview

This repository contains Docker templates for deploying various AI applications on RunPod. Each subdirectory contains a complete Docker setup optimized for RunPod deployment.

### Current Templates:
- **comfyui/**: ComfyUI with CUDA support, persistent storage, and pre-installed extensions for Stable Diffusion image generation
  - `base`: Minimal installation with SD 1.5
  - `flux`: FLUX models for high-quality generation
  - `sdxl-pony`: SDXL and Pony models
  - `video`: Video generation models

## RunPod Deployment Workflow

### Step 1: Build and Push Docker Images
```bash
cd comfyui/

# Build specific variant
docker build -t effekt/runpod-comfyui:base .
docker build -t effekt/runpod-comfyui:flux --build-arg CONFIG=flux .

# Push to Docker Hub
docker push effekt/runpod-comfyui:base
docker push effekt/runpod-comfyui:flux
```

### Step 2: Create/Update Templates
```bash
cd comfyui/templates

# List existing templates
./manage-templates.sh list

# Update all templates (will PATCH if exists, POST if new)
./manage-templates.sh update-all

# Update specific template
./manage-templates.sh update flux
```

### Step 3: Create Pods Using Templates

**⚠️ CRITICAL: ALWAYS use --templateId when creating pods!**

```bash
# First, get the template ID
cd comfyui/templates
./manage-templates.sh list

# Then create pod with template
runpodctl create pod \
  --templateId <template-id> \
  --name "my-comfyui-pod" \
  --gpuType "NVIDIA GeForce RTX 4090" \
  --secureCloud \
  --networkVolumeId "<volume-id>" \
  --startSSH
```

## Network Volumes (Persistent Storage)

### Key Concepts:
- Network volumes provide persistent storage across pod restarts
- ONLY work with Secure Cloud (not Community Cloud)
- Tied to specific datacenters - choose wisely!
- Mount at `/runpod` in containers

### API Key Retrieval:
```bash
# Method 1: Direct extraction (use in separate command)
grep apikey ~/.runpod/config.toml | cut -d'"' -f2

# Method 2: Store in variable (may have shell escaping issues in some contexts)
API_KEY=$(grep apikey ~/.runpod/config.toml | cut -d'"' -f2)

# Method 3: Use directly in curl (most reliable)
curl -s "https://api.runpod.io/graphql?api_key=$(grep apikey ~/.runpod/config.toml | cut -d'"' -f2)" ...
```

### Creating a Network Volume:
```bash
# Get API key from ~/.runpod/config.toml
API_KEY=$(grep apikey ~/.runpod/config.toml | cut -d'"' -f2)

# Create in US-CA-2 (California) - NEVER use US-TX-3
curl -X POST 'https://api.runpod.io/graphql?api_key='$API_KEY \
  -H 'Content-Type: application/json' \
  -d '{
    "query": "mutation { createNetworkVolume(input: {name: \"my-volume\", size: 200, dataCenterId: \"US-CA-2\"}) { id name } }"
  }'
```

### Querying Pod Details via API:
```bash
# Get all pod details (correct field names)
API_KEY=$(grep apikey ~/.runpod/config.toml | cut -d'"' -f2)
curl -s "https://api.runpod.io/graphql?api_key=$API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"query": "query { myself { pods { id name imageName templateId networkVolumeId podType containerDiskInGb volumeMountPath machineId machine { gpuTypeId } } } }"}' | python3 -m json.tool

# Note: Common field name errors to avoid:
# ❌ gpuTypeId (use machine { gpuTypeId } instead)
# ❌ cloudType (use podType instead)
# ❌ runpodctl get pod --raw (--raw flag doesn't exist)
```

### Secure Cloud vs Community Cloud:
| Feature | Secure Cloud | Community Cloud |
|---------|-------------|-----------------|
| Network Volumes | ✅ Supported | ❌ Not supported |
| Price | Higher | Lower |
| Availability | Better | Variable |
| Best for | Production with persistence | Testing/one-time runs |

## Template Management Script

The `comfyui/templates/manage-templates.sh` script handles all template operations:

```bash
# List all templates with IDs
./manage-templates.sh list

# Update all templates
./manage-templates.sh update-all

# Update specific template
./manage-templates.sh update base
./manage-templates.sh update flux

# Script will:
# - Use PATCH to update existing templates
# - Use POST to create new templates
# - Never delete without permission
```

## Troubleshooting

### Pod Creation Fails
When you see "Error: There are no longer any instances available":

1. **Check GPU availability:**
```bash
runpodctl get cloud --secure  # For network volume pods
runpodctl get cloud --community  # For temporary pods
```

2. **Check network volume datacenter:**
```bash
API_KEY=$(grep apikey ~/.runpod/config.toml | cut -d'"' -f2)
curl -s "https://api.runpod.io/graphql?api_key=$API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"query": "query { myself { networkVolumes { id name size dataCenterId } } }"}' | python3 -m json.tool
```

3. **Options:**
- Wait for GPU availability in your datacenter
- Try different GPU type
- Create new network volume in available datacenter
- Use Community Cloud without persistence

### Pod Stuck or Erroring
- Check logs via RunPod Console: `https://console.runpod.io/pods`
- SSH into pod: `runpodctl ssh connect <pod-id>`
- NEVER delete pods with errors - keep for debugging

## Configuration System

### Config File Structure
Configs are in `comfyui/configs/`:
- `base.yaml` - Minimal setup
- `flux.yaml` - FLUX models
- `sdxl-pony.yaml` - SDXL/Pony models
- `video.yaml` - Video generation

### Model Type Mapping
**CRITICAL**: Use correct model types in configs:

| Model Type | Directory | Used For |
|------------|-----------|----------|
| `checkpoints` | `/models/checkpoints/` | SD1.5, SDXL |
| `diffusion_models` | `/models/diffusion_models/` | FLUX models |
| `vae` | `/models/vae/` | VAE models |
| `clip` | `/models/clip/` | Text encoders |
| `loras` | `/models/loras/` | LoRA adapters |

**Example:** FLUX models MUST use `diffusion_models:`, NOT `checkpoints:`

### Model Organization (Subfolders)
Models are organized into subfolders by base model type for better management:

```
/models/
├── diffusion_models/
│   ├── flux/           # FLUX models
│   ├── sd3/            # Stable Diffusion 3
│   └── pixart/         # PixArt models
├── checkpoints/
│   ├── sd15/           # SD 1.5 models
│   ├── sdxl/           # SDXL models
│   ├── pony/           # Pony Diffusion models
│   └── anime/          # Anime-style models
├── loras/
│   ├── flux/           # FLUX LoRAs
│   ├── sd15/           # SD 1.5 LoRAs
│   ├── sdxl/           # SDXL LoRAs
│   └── pony/           # Pony LoRAs
├── controlnet/
│   ├── sd15/           # SD 1.5 ControlNets
│   ├── sdxl/           # SDXL ControlNets
│   └── flux/           # FLUX ControlNets
└── vae/
    ├── sd15/           # SD 1.5 VAEs
    ├── sdxl/           # SDXL VAEs
    └── flux/           # FLUX VAEs
```

**In configs:** Use the `subfolder` field to organize models:
```yaml
models:
  diffusion_models:
    - name: flux1-schnell
      url: https://huggingface.co/...
      filename: flux1-schnell.safetensors
      subfolder: flux  # Will go to /models/diffusion_models/flux/
```

## Environment Variables

Key variables for templates:
- `CONFIG_NAME`: Which config to load (base, flux, sdxl-pony, video)
- `DOWNLOAD_MODELS`: Whether to download models on startup (true/false)
- `AUTO_UPDATE`: Update ComfyUI on startup (true/false)
- `COMFYUI_ARGS`: GPU memory settings (--highvram, --lowvram, etc.)
- `HF_TOKEN`: HuggingFace token for gated models (use RunPod secrets)

## Memory Optimization

Based on GPU VRAM:
- 48GB+ (A6000, A100): `--highvram`
- 24GB (RTX 4090, A5000): Default (no args)
- 8-16GB: `--lowvram`
- <8GB: `--cpu`

## Quick Reference Commands

```bash
# Build and push Docker image
cd comfyui && docker build -t effekt/runpod-comfyui:flux --build-arg CONFIG=flux . && docker push effekt/runpod-comfyui:flux

# Update templates
cd comfyui/templates && ./manage-templates.sh update-all

# Get template IDs
cd comfyui/templates && ./manage-templates.sh list

# Create pod with template (ALWAYS use template!)
# NOTE: --imageName is REQUIRED even when using --templateId (runpodctl bug)
runpodctl create pod --templateId <id> --imageName <image-from-template> --name "pod-name" --gpuType "NVIDIA GeForce RTX 4090" --secureCloud --networkVolumeId "<volume-id>" --startSSH

# Check pod status
runpodctl get pod <pod-id>

# SSH into pod
runpodctl ssh connect <pod-id>

# Stop pod (preserves data, can be restarted later)
runpodctl stop pod <pod-id>

# Restart stopped pod
runpodctl start pod <pod-id>

# Remove pod (permanent deletion, cannot be recovered)
runpodctl remove pod <pod-id>
```

## Key Files

- `comfyui/Dockerfile` - Container definition
- `comfyui/entrypoint.sh` - Startup script
- `comfyui/builder.py` - Model/node installer
- `comfyui/configs/*.yaml` - Configuration files
- `comfyui/templates/*.json` - Template definitions
- `comfyui/templates/manage-templates.sh` - Template management script