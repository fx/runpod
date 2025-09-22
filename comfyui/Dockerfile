# Base image with CUDA support for GPU acceleration
FROM nvidia/cuda:12.1.0-cudnn8-runtime-ubuntu22.04

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    SHELL=/bin/bash \
    LD_LIBRARY_PATH=/usr/local/nvidia/lib:/usr/local/nvidia/lib64:$LD_LIBRARY_PATH

# Set working directory
WORKDIR /workspace

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.11 \
    python3.11-venv \
    python3-pip \
    git \
    wget \
    curl \
    ffmpeg \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgomp1 \
    libgoogle-perftools4 \
    libtcmalloc-minimal4 \
    build-essential \
    vim \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Create a virtual environment and set it as default
RUN python3.11 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Upgrade pip
RUN pip install --upgrade pip setuptools wheel

# Install PyTorch with CUDA support
RUN pip install torch==2.2.0 torchvision==0.17.0 torchaudio==2.2.0 --index-url https://download.pytorch.org/whl/cu121

# Clone ComfyUI
RUN git clone https://github.com/comfyanonymous/ComfyUI.git /workspace/ComfyUI

# Set ComfyUI as working directory
WORKDIR /workspace/ComfyUI

# Install ComfyUI requirements
RUN pip install -r requirements.txt

# Install additional useful packages
RUN pip install \
    xformers \
    opencv-python-headless \
    imageio \
    imageio-ffmpeg \
    transformers \
    safetensors \
    accelerate \
    pyyaml \
    Pillow \
    scipy \
    tqdm \
    psutil

# Install ComfyUI Manager
RUN cd /workspace/ComfyUI/custom_nodes && \
    git clone https://github.com/ltdrdata/ComfyUI-Manager.git

# Create necessary directories for models and outputs
RUN mkdir -p /workspace/ComfyUI/models/checkpoints \
    /workspace/ComfyUI/models/clip \
    /workspace/ComfyUI/models/clip_vision \
    /workspace/ComfyUI/models/controlnet \
    /workspace/ComfyUI/models/diffusers \
    /workspace/ComfyUI/models/embeddings \
    /workspace/ComfyUI/models/gligen \
    /workspace/ComfyUI/models/hypernetworks \
    /workspace/ComfyUI/models/loras \
    /workspace/ComfyUI/models/style_models \
    /workspace/ComfyUI/models/unet \
    /workspace/ComfyUI/models/upscale_models \
    /workspace/ComfyUI/models/vae \
    /workspace/ComfyUI/models/vae_approx \
    /workspace/ComfyUI/output \
    /workspace/ComfyUI/input \
    /workspace/ComfyUI/temp \
    /workspace/storage

# Copy entrypoint script
COPY entrypoint.sh /workspace/entrypoint.sh
RUN chmod +x /workspace/entrypoint.sh

# Set up volumes for persistent storage
VOLUME ["/workspace/ComfyUI/models", "/workspace/ComfyUI/output", "/workspace/ComfyUI/input", "/workspace/storage"]

# Expose ComfyUI port
EXPOSE 8188

# Set entrypoint
ENTRYPOINT ["/workspace/entrypoint.sh"]

# Default command
CMD ["python", "main.py", "--listen", "0.0.0.0", "--port", "8188", "--disable-auto-launch"]