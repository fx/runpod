# Minimal base image with CUDA support (12.4 to match PyTorch)
FROM nvidia/cuda:12.4.1-cudnn-runtime-ubuntu22.04 AS base

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

# Upgrade pip first
RUN pip install --upgrade --no-cache-dir pip setuptools wheel

# Install PyTorch 2.6.0 with CUDA 12.4 (latest stable, RTX 5090 support)
RUN pip install --no-cache-dir \
    torch==2.6.0 \
    torchvision==0.21.0 \
    torchaudio==2.6.0 \
    --index-url https://download.pytorch.org/whl/cu124

# Install xformers for memory efficiency (latest for PyTorch 2.6.0)
RUN pip install --no-cache-dir xformers --index-url https://download.pytorch.org/whl/cu124

# Clone ComfyUI (shallow clone to save space)
RUN git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git $COMFYUI_PATH

# Install ComfyUI's requirements (just like ValyrianTech does)
RUN cd $COMFYUI_PATH && \
    pip install --no-cache-dir -r requirements.txt

# Install additional tools we need for runtime
RUN pip install --no-cache-dir \
    pyyaml \
    hiyapyco \
    requests \
    "huggingface-hub[cli]"

# Install ComfyUI Manager (essential for UI)
RUN cd $COMFYUI_PATH/custom_nodes && \
    git clone --depth 1 https://github.com/ltdrdata/ComfyUI-Manager.git

# ComfyUI will create directories as needed when downloading models

# Copy scripts and configs
COPY entrypoint.sh /workspace/entrypoint.sh
COPY builder.py /workspace/builder.py
COPY requirements-builder.txt /workspace/requirements-builder.txt
COPY configs/ /workspace/configs/
COPY lib/ /workspace/lib/

# Make scripts executable
RUN chmod +x /workspace/entrypoint.sh

# Create marker file for first run
RUN touch /workspace/.first_run

# No VOLUME declarations - let entrypoint handle symlinks

# Expose ComfyUI port
EXPOSE 8188

# Set working directory to ComfyUI
WORKDIR $COMFYUI_PATH

# Set entrypoint
ENTRYPOINT ["/workspace/entrypoint.sh"]

# Default command
CMD ["python", "main.py", "--listen", "0.0.0.0", "--port", "8188", "--disable-auto-launch"]