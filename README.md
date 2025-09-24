# RunPod Docker Templates

A collection of production-ready Docker templates for deploying AI applications on [RunPod](https://runpod.io).

## 🚀 Available Templates

### [ComfyUI](./comfyui/)
A powerful and modular Stable Diffusion GUI with a graph/nodes interface.

- **Features**: CUDA 12.1, PyTorch 2.2.0, ComfyUI Manager, popular custom nodes
- **Use Case**: AI image generation with Stable Diffusion, SDXL, and Flux models
- **GPU Requirements**: Minimum 8GB VRAM (12GB+ recommended)
- **Docker Image**: `ghcr.io/effekt/runpod-comfyui:latest`

## 📖 Repository Structure

```
runpod/
├── CLAUDE.md                 # Development guidelines for Claude AI
├── README.md                 # This file
├── .github/
│   └── workflows/
│       └── comfyui-build.yml # GitHub Actions for ComfyUI image
└── comfyui/                  # ComfyUI template
    ├── Dockerfile            # Docker image definition
    ├── entrypoint.sh         # Container initialization script
    ├── docker-compose.yml    # Local testing configuration
    ├── runpod-template.json  # RunPod template configuration
    ├── README.md             # ComfyUI-specific documentation
    └── .dockerignore         # Docker build exclusions
```

## 🛠️ Quick Start

### Prerequisites

1. **Docker Hub Account**: Required for storing Docker images
2. **RunPod Account**: For deploying GPU-powered pods
3. **Docker Desktop**: For local testing and building

### General Workflow

1. **Choose a template** from the available options above
2. **Build the Docker image** locally or via GitHub Actions
3. **Push to Docker Hub** for RunPod to access
4. **Create RunPod template** using the provided JSON configuration
5. **Deploy on RunPod** with your preferred GPU

### Example: Deploying ComfyUI

```bash
# Navigate to template directory
cd comfyui/

# Build Docker image
docker build -t ghcr.io/effekt/runpod-comfyui:latest .

# Push to Docker Hub
docker push ghcr.io/effekt/runpod-comfyui:latest

# Use runpod-template.json to create template on RunPod Dashboard
```

## 🔄 GitHub Actions

Each template has an automated workflow that builds and pushes Docker images:

- Triggers on pushes to template directories
- Builds multi-platform images
- Pushes to Docker Hub with proper tags
- Updates Docker Hub descriptions

### Setup GitHub Actions

1. Add secrets to your repository:
   - `DOCKERHUB_USERNAME`: Your Docker Hub username
   - `DOCKERHUB_TOKEN`: Docker Hub access token

2. Update image names in workflow files to match your Docker Hub username

## 🧪 Local Testing

Each template includes a `docker-compose.yml` for local testing:

```bash
cd comfyui/
docker-compose up -d

# Access at http://localhost:8188 (ComfyUI)
```

## 📝 Contributing

### Adding a New Template

1. Create a new directory with the template name
2. Include:
   - `Dockerfile`: Container definition
   - `entrypoint.sh`: Initialization script
   - `docker-compose.yml`: Local testing setup
   - `runpod-template.json`: RunPod configuration
   - `README.md`: Template documentation
   - `.dockerignore`: Build exclusions

3. Add a GitHub Actions workflow in `.github/workflows/`
4. Update this README with the new template information

### Best Practices

- Use specific version tags for base images and dependencies
- Implement health checks and proper error handling
- Document all environment variables and configuration options
- Test locally before pushing to production
- Keep images as small as possible while maintaining functionality

## 🔧 Customization

Each template can be customized by:

1. **Modifying the Dockerfile**: Add packages, change base images
2. **Adjusting environment variables**: Configure runtime behavior
3. **Updating entrypoint scripts**: Change initialization logic
4. **Extending with custom code**: Add your own applications

## 📚 Resources

- [RunPod Documentation](https://docs.runpod.io/)
- [Docker Documentation](https://docs.docker.com/)
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/)

## 🤝 Support

- **Issues**: [GitHub Issues](https://github.com/effekt/runpod/issues)
- **RunPod Community**: [Discord](https://discord.gg/runpod)

## 📄 License

MIT License - See individual template directories for specific licensing information.

## 🙏 Acknowledgments

- [RunPod](https://runpod.io/) for GPU cloud infrastructure
- Template maintainers and contributors
- Open-source AI community