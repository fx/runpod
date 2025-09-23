# Base image with CUDA support for GPU acceleration
FROM nvidia/cuda:12.1.0-cudnn8-runtime-ubuntu22.04 AS base

# Build arguments for configuration selection
ARG CONFIG=base
ARG PREBAKE=false
ARG BUILD_DATE
ARG VCS_REF

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    SHELL=/bin/bash \
    LD_LIBRARY_PATH=/usr/local/nvidia/lib:/usr/local/nvidia/lib64:$LD_LIBRARY_PATH

# Labels for metadata
LABEL org.label-schema.build-date=$BUILD_DATE \
      org.label-schema.vcs-ref=$VCS_REF \
      org.label-schema.name="ComfyUI" \
      org.label-schema.description="ComfyUI with flexible configuration support" \
      org.label-schema.vendor="effekt"

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

# Configure git for public repository access
RUN git config --global url."https://github.com/".insteadOf git@github.com: && \
    git config --global url."https://".insteadOf git://

# Create a virtual environment and set it as default
RUN python3.11 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Upgrade pip
RUN pip install --upgrade pip setuptools wheel

# Clone ComfyUI
RUN git clone https://github.com/comfyanonymous/ComfyUI.git /workspace/ComfyUI

# Set ComfyUI as working directory
WORKDIR /workspace/ComfyUI

# Install ComfyUI requirements
RUN pip install -r requirements.txt

# Install additional useful packages and HuggingFace CLI
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
    psutil \
    hiyapyco \
    "huggingface-hub[cli]"

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

# Copy builder tool and configuration files
COPY builder.py /workspace/builder.py
COPY config-*.yaml /workspace/configs/
COPY lib/ /workspace/lib/

# Set up volumes for persistent storage
VOLUME ["/workspace/ComfyUI/models", "/workspace/ComfyUI/output", "/workspace/ComfyUI/input", "/workspace/storage"]

# Expose ComfyUI port
EXPOSE 8188

# Final stage
FROM base AS final

# Build arguments for optional pre-baking
ARG PREBAKE=false
ARG CONFIG=""

# Conditionally copy config file if PREBAKE is true
# This happens at build time, so we copy all configs and select at runtime
COPY config-*.yaml /workspace/configs/

# Set environment variable if CONFIG is specified
RUN if [ -n "${CONFIG}" ] && [ "${PREBAKE}" = "true" ]; then \
        if [ -f "/workspace/configs/config-${CONFIG}.yaml" ]; then \
            cp "/workspace/configs/config-${CONFIG}.yaml" "/workspace/config.yaml" && \
            echo "Pre-baked config: ${CONFIG}"; \
        fi; \
    fi

# Set config name environment variable only if pre-baking
ENV CONFIG_NAME=${CONFIG}

# Set entrypoint
ENTRYPOINT ["/workspace/entrypoint.sh"]

# Default command
CMD ["python", "main.py", "--listen", "0.0.0.0", "--port", "8188", "--disable-auto-launch"]