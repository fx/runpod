# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

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
```bash
# After pushing image to Docker Hub, deploy on RunPod:
# 1. Go to RunPod Dashboard > Templates
# 2. Create new template using runpod-template.json
# 3. Deploy a Pod selecting the template
# 4. Access ComfyUI on port 8188

# Note: RunPod pulls the Docker image from Docker Hub
# and runs it with the configuration in runpod-template.json
```

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
3. **Storage Setup**: Creates symlinks to `/runpod-volume` if network storage is available
4. **Config Application**: Uses builder.py to install nodes and download models from config
5. **ComfyUI Launch**: Starts server with config-defined environment variables

### RunPod Integration

When deployed on RunPod:
- Persistent storage is mounted at `/runpod-volume` and symlinked to ComfyUI directories
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