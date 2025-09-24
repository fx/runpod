# ComfyUI RunPod Template

A production-ready Docker template for deploying ComfyUI on RunPod with CUDA support, persistent storage, and pre-installed extensions.

## Features

- 🚀 **CUDA 12.4** with PyTorch 2.6.0 for optimal GPU performance (RTX 5090 compatible)
- 🎨 **ComfyUI** with latest updates and ComfyUI Manager pre-installed
- 📦 **Popular custom nodes** pre-configured
- 💾 **Persistent storage** support for models and outputs
- 📂 **Organized model storage** with automatic subfolder organization by base model type
- 🌐 **Web UI** accessible on port 8188
- 🔧 **Customizable** via environment variables
- 🐳 **Docker Compose** support for local testing

## Quick Start

### Option 1: Deploy on RunPod

1. Build and push the Docker image to Docker Hub:
```bash
# Build the image
docker build -t effekt/runpod-comfyui:latest .

# Push to Docker Hub
docker push effekt/runpod-comfyui:latest
```

2. Create a RunPod template:
   - Go to RunPod Dashboard > Templates
   - Click "New Template"
   - Upload or paste the contents of `runpod-template.json`
   - Update the `imageName` field with your Docker Hub username

3. Deploy a Pod:
   - Go to Pods > Deploy
   - Select your ComfyUI template
   - Choose GPU type (minimum 8GB VRAM recommended)
   - Set disk sizes (40GB container, 50GB volume recommended)
   - Deploy!

4. Access ComfyUI:
   - Wait 1-2 minutes for initialization
   - Click on "Connect" and select port 8188
   - ComfyUI interface will open in a new tab

### Option 2: Local Testing with Docker Compose

1. Clone this repository:
```bash
git clone https://github.com/effekt/runpod.git
cd runpod/comfyui
```

2. Create local directories for persistent storage:
```bash
mkdir -p models output input custom_nodes workflows storage
```

3. Start the container:
```bash
docker-compose up -d
```

4. Access ComfyUI at `http://localhost:8188`

## Directory Structure

```
/workspace/
├── ComfyUI/
│   ├── models/                    # AI models organized by type and base model
│   │   ├── checkpoints/           # Traditional checkpoint models
│   │   │   ├── sd15/             # SD 1.5 models
│   │   │   ├── sdxl/             # SDXL models
│   │   │   ├── pony/             # Pony Diffusion models
│   │   │   └── anime/            # Anime-style models
│   │   ├── diffusion_models/      # Modern diffusion models
│   │   │   ├── flux/             # FLUX models
│   │   │   ├── sd3/              # Stable Diffusion 3
│   │   │   └── pixart/           # PixArt models
│   │   ├── loras/                 # LoRA adapters
│   │   │   ├── flux/             # FLUX LoRAs
│   │   │   ├── sd15/             # SD 1.5 LoRAs
│   │   │   ├── sdxl/             # SDXL LoRAs
│   │   │   └── pony/             # Pony LoRAs
│   │   ├── vae/                   # VAE models
│   │   │   ├── sd15/             # SD 1.5 VAEs
│   │   │   ├── sdxl/             # SDXL VAEs
│   │   │   └── flux/             # FLUX VAEs
│   │   ├── controlnet/            # ControlNet models
│   │   │   ├── sd15/             # SD 1.5 ControlNets
│   │   │   ├── sdxl/             # SDXL ControlNets
│   │   │   └── flux/             # FLUX ControlNets
│   │   └── ...                    # Other model types
│   ├── output/                    # Generated images
│   ├── input/                     # Input images for processing
│   ├── custom_nodes/              # ComfyUI extensions
│   └── workflows/                 # Saved ComfyUI workflows
└── storage/                       # Additional persistent storage
```

### Model Organization

Models are automatically organized into subfolders based on their base model type for better management. When downloading models through the builder tool or configs, they will be placed in the appropriate subfolder. This helps keep different model architectures separated and makes it easier to manage large model collections.

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `DOWNLOAD_MODELS` | `false` | Download models from config on startup |
| `AUTO_UPDATE` | `false` | Auto-update ComfyUI on startup |
| `DISABLE_AUTO_LAUNCH` | `true` | Disable browser auto-launch |
| `COMFYUI_PREVIEW_METHOD` | `auto` | Preview method: auto, latent2rgb, or taesd |
| `COMFYUI_ARGS` | `""` | Additional ComfyUI arguments |
| `CONFIG_NAME` | `base` | Configuration to load (flux, sdxl-pony, video, etc.) |
| `HF_TOKEN` | `""` | HuggingFace token for gated models (FLUX, etc.) |

### Memory Optimization Arguments

Add to `COMFYUI_ARGS` based on your GPU:

- **48GB+ VRAM** (A6000, A100, H100): `--highvram` (keeps everything in VRAM)
- **24-32GB VRAM** (RTX 4090, A5000): Default (empty string) - auto memory management
- **12-16GB VRAM** (RTX 4070 Ti, RTX 3060): Default or `--normalvram`
- **8-12GB VRAM** (RTX 4060, RTX 3050): `--lowvram`
- **4-8GB VRAM**: `--lowvram` or `--cpu`
- **CPU Mode**: `--cpu` (automatically detected if no GPU)

**Important**: Using `--highvram` on 24GB cards can cause OOM errors. The default auto memory management works best for RTX 4090/A5000 cards.

## Installing Models

### Option 1: ComfyUI Manager (Recommended)
1. Access ComfyUI web interface
2. Click on "Manager" button
3. Install models directly from the UI

### Option 2: Using Builder Tool (For Config-based Downloads)

#### Authenticate with HuggingFace (for gated models)
Some models like FLUX require authentication. The container includes the HuggingFace CLI:
```bash
# Login to HuggingFace (one-time setup)
docker compose exec comfyui huggingface-cli login
# Enter your HF token when prompted (get from https://huggingface.co/settings/tokens)

# Or pass token via environment variable
export HF_TOKEN=your_token_here
docker compose exec comfyui huggingface-cli login --token $HF_TOKEN
```

#### Download models using builder tool
```bash
# Attach shell to running container
docker compose exec comfyui bash

# Download models for a specific config (from inside container)
cd /workspace
python builder.py download --config /workspace/configs/config-flux.yaml

# Or run directly without attaching:
docker compose exec comfyui python /workspace/builder.py download --config /workspace/configs/config-flux.yaml
```

### Option 3: Manual Download
1. SSH into your RunPod instance or attach to container
2. Download models to `/workspace/ComfyUI/models/checkpoints/`

### Option 4: Pre-download at Startup
Set `DOWNLOAD_MODELS=true` to download base models on startup

## Popular Models

### Checkpoints
- **SD 1.5**: `v1-5-pruned-emaonly.safetensors`
- **SDXL**: `sd_xl_base_1.0.safetensors`
- **FLUX.1**: Available through ComfyUI Manager

### VAE
- **SD 1.5 VAE**: `vae-ft-mse-840000-ema-pruned.safetensors`

### Upscalers
- **ESRGAN 4x**: `ESRGAN_4x.pth`
- **Real-ESRGAN**: Various models available

## Custom Nodes

Pre-installed popular nodes:
- ComfyUI Manager
- AnimateDiff Evolved
- IPAdapter Plus
- ControlNet Auxiliary
- Ultimate SD Upscale
- Efficiency Nodes
- WD14 Tagger
- And more...

Install additional nodes via ComfyUI Manager or clone to `/workspace/ComfyUI/custom_nodes/`

## Building Custom Images

### Modify the Dockerfile

```dockerfile
# Add your customizations
RUN pip install your-package

# Add custom models
RUN wget -O /workspace/ComfyUI/models/checkpoints/your-model.safetensors \
    https://huggingface.co/your-model-url
```

### Build and Push

```bash
# Build with custom tag
docker build -t effekt/runpod-comfyui-custom:latest .

# Push to registry
docker push effekt/runpod-comfyui-custom:latest
```

## GitHub Actions Workflow

The included workflow automatically builds and pushes Docker images on push to main branch.

Setup:
1. Add Docker Hub credentials to GitHub Secrets:
   - `DOCKERHUB_USERNAME`
   - `DOCKERHUB_TOKEN`
2. Update username in `.github/workflows/docker-build.yml`
3. Push to main branch to trigger build

## Troubleshooting

### GPU not detected
- Ensure NVIDIA drivers are installed
- Check CUDA compatibility
- Verify Docker GPU support: `docker run --gpus all nvidia/cuda:12.1.0-base nvidia-smi`

### Out of Memory errors

- If using `--highvram` on 24-32GB cards, remove it (use default)
- For persistent OOM, add `--normalvram` or `--lowvram`
- For 8GB or less VRAM, use `--lowvram` or `--cpu`
- Reduce batch size in ComfyUI
- Use smaller models

### Slow startup
- First run downloads dependencies (10-15 minutes)
- Use persistent volumes to cache data
- Pre-download models with `DOWNLOAD_MODELS=true`

### Connection refused
- Wait 1-2 minutes for initialization
- Check logs: `docker logs comfyui`
- Verify port 8188 is exposed

## Performance Tips

1. **Use persistent volumes** to avoid re-downloading models
2. **Choose appropriate GPU** - RTX 3090/4090 or A5000+ recommended
3. **Optimize VRAM usage** with appropriate flags
4. **Cache models** on network storage for faster Pod switching
5. **Pre-build custom images** with your commonly used models

## Support

- Issues: [GitHub Issues](https://github.com/effekt/runpod/issues)
- ComfyUI: [Official Repository](https://github.com/comfyanonymous/ComfyUI)
- RunPod: [Documentation](https://docs.runpod.io/)

## License

MIT License - See LICENSE file for details

## Contributing

Pull requests welcome! Please test locally with docker-compose before submitting.

## Acknowledgments

- [ComfyUI](https://github.com/comfyanonymous/ComfyUI) by comfyanonymous
- [ComfyUI Manager](https://github.com/ltdrdata/ComfyUI-Manager) by ltdrdata
- [RunPod](https://runpod.io/) for GPU cloud infrastructure