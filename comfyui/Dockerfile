# Minimal base image with CUDA support
FROM nvidia/cuda:12.1.0-cudnn8-runtime-ubuntu22.04 AS base

# Build arguments
ARG BUILD_DATE
ARG VCS_REF

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    SHELL=/bin/bash \
    LD_LIBRARY_PATH=/usr/local/nvidia/lib:/usr/local/nvidia/lib64:$LD_LIBRARY_PATH \
    VENV_PATH=/opt/venv \
    COMFYUI_PATH=/workspace/ComfyUI

# Labels for metadata
LABEL org.label-schema.build-date=$BUILD_DATE \
      org.label-schema.vcs-ref=$VCS_REF \
      org.label-schema.name="ComfyUI Minimal" \
      org.label-schema.description="Minimal ComfyUI that downloads dependencies at runtime" \
      org.label-schema.vendor="effekt"

# Set working directory
WORKDIR /workspace

# Install minimal system dependencies
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
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Configure git for public repository access
RUN git config --global url."https://github.com/".insteadOf git@github.com: && \
    git config --global url."https://".insteadOf git://

# Create virtual environment
RUN python3.11 -m venv $VENV_PATH
ENV PATH="$VENV_PATH/bin:$PATH"

# Install only essential Python packages needed for setup
RUN pip install --upgrade --no-cache-dir pip setuptools wheel && \
    pip install --no-cache-dir \
    pyyaml \
    hiyapyco \
    requests \
    tqdm \
    psutil \
    "huggingface-hub[cli]"

# Install PyTorch with CUDA support and torchvision in the base image
# This ensures torchvision's C++ extensions (like NMS) are properly compiled
RUN pip install --no-cache-dir \
    torch==2.2.0 \
    torchvision==0.17.0 \
    torchaudio==2.2.0 \
    --index-url https://download.pytorch.org/whl/cu121

# Install xformers for memory efficiency
RUN pip install --no-cache-dir xformers==0.0.24 --index-url https://download.pytorch.org/whl/cu121

# Clone ComfyUI (shallow clone to save space)
RUN git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git $COMFYUI_PATH

# Install ComfyUI Manager (essential for UI)
RUN cd $COMFYUI_PATH/custom_nodes && \
    git clone --depth 1 https://github.com/ltdrdata/ComfyUI-Manager.git

# Create necessary directories
RUN mkdir -p $COMFYUI_PATH/models/checkpoints \
    $COMFYUI_PATH/models/clip \
    $COMFYUI_PATH/models/clip_vision \
    $COMFYUI_PATH/models/controlnet \
    $COMFYUI_PATH/models/diffusers \
    $COMFYUI_PATH/models/embeddings \
    $COMFYUI_PATH/models/gligen \
    $COMFYUI_PATH/models/hypernetworks \
    $COMFYUI_PATH/models/loras \
    $COMFYUI_PATH/models/style_models \
    $COMFYUI_PATH/models/unet \
    $COMFYUI_PATH/models/upscale_models \
    $COMFYUI_PATH/models/vae \
    $COMFYUI_PATH/models/vae_approx \
    $COMFYUI_PATH/output \
    $COMFYUI_PATH/input \
    $COMFYUI_PATH/temp \
    /workspace/storage \
    /workspace/venv-cache

# Copy scripts and configs
COPY entrypoint.sh /workspace/entrypoint.sh
COPY builder.py /workspace/builder.py
COPY requirements-builder.txt /workspace/requirements-builder.txt
COPY config-*.yaml /workspace/configs/
COPY lib/ /workspace/lib/

# Make scripts executable
RUN chmod +x /workspace/entrypoint.sh

# Create marker file for first run
RUN touch /workspace/.first_run

# Set up volumes for persistent storage
VOLUME ["/workspace/ComfyUI/models", "/workspace/ComfyUI/output", "/workspace/ComfyUI/input", "/workspace/storage", "/workspace/venv-cache"]

# Expose ComfyUI port
EXPOSE 8188

# Set working directory to ComfyUI
WORKDIR $COMFYUI_PATH

# Set entrypoint
ENTRYPOINT ["/workspace/entrypoint.sh"]

# Default command
CMD ["python", "main.py", "--listen", "0.0.0.0", "--port", "8188", "--disable-auto-launch"]