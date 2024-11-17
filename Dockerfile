# Specify platform to avoid ARM-related issues
FROM --platform=linux/amd64 nvidia/cuda:11.8.0-runtime-ubuntu22.04

# Build arguments for version control
ARG PYTHON_VERSION=3.10
ARG PYTORCH_VERSION=2.4.0
ARG COMFYUI_VERSION=master

# Environment variables
ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PYTHON_VERSION=${PYTHON_VERSION} \
    PYTORCH_VERSION=${PYTORCH_VERSION} \
    XPU_TARGET=NVIDIA_GPU

# Create virtual environment paths
ENV VENV_DIR=/opt/venv
ENV COMFYUI_VENV=$VENV_DIR/comfyui
ENV JUPYTER_VENV=$VENV_DIR/jupyter
ENV PATH="$COMFYUI_VENV/bin:$JUPYTER_VENV/bin:$PATH"

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    python${PYTHON_VERSION} \
    python${PYTHON_VERSION}-venv \
    python3-pip \
    wget \
    curl \
    libgl1-mesa-glx \
    libglib2.0-0 \
    ffmpeg \
    libsm6 \
    libxext6 \
    tree \
    && rm -rf /var/lib/apt/lists/*

# Create virtual environments
RUN python${PYTHON_VERSION} -m venv $COMFYUI_VENV && \
    python${PYTHON_VERSION} -m venv $JUPYTER_VENV

# Set up workspace
WORKDIR /workspace

# Install JupyterLab in its own virtual environment
RUN . $JUPYTER_VENV/bin/activate && \
    pip install --no-cache-dir jupyterlab notebook numpy pandas && \
    jupyter notebook --generate-config && \
    echo "c.NotebookApp.token = ''" >> ~/.jupyter/jupyter_notebook_config.py && \
    echo "c.NotebookApp.password = ''" >> ~/.jupyter/jupyter_notebook_config.py && \
    deactivate

# Set up ComfyUI
WORKDIR /workspace/ComfyUI

# Install ComfyUI and dependencies in its virtual environment
RUN . $COMFYUI_VENV/bin/activate && \
    git clone https://github.com/comfyanonymous/ComfyUI . && \
    if [ "$COMFYUI_VERSION" != "master" ]; then git checkout $COMFYUI_VERSION; fi && \
    pip install --no-cache-dir -r requirements.txt && \
    pip install --no-cache-dir torch==${PYTORCH_VERSION} torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118 && \
    deactivate

# Create directory structure
RUN mkdir -p models input output custom_nodes

# Create the startup script with XPU detection
COPY <<'EOF' /start.sh
#!/bin/bash
set -eo pipefail
umask 002

echo "🔍 Starting ComfyUI Setup..."
echo "Python Version: $(python3 --version)"

# Check GPU availability
if command -v nvidia-smi &> /dev/null; then
    echo "NVIDIA GPU detected"
    echo "CUDA Version: $(nvcc --version 2>/dev/null || echo 'NVCC not found')"
    echo "GPU Information: $(nvidia-smi)"
    export XPU_TARGET=NVIDIA_GPU
elif [ -d "/dev/dri" ]; then
    echo "AMD GPU detected"
    export XPU_TARGET=AMD_GPU
else
    echo "No GPU detected, using CPU"
    export XPU_TARGET=CPU
fi

# Function to safely create directory structure
create_dir_structure() {
    local base_path="$1"
    echo "Creating directory structure in $base_path/ComfyUI"
    
    for dir in models input output custom_nodes; do
        mkdir -p "$base_path/ComfyUI/$dir"
        echo "Created $base_path/ComfyUI/$dir"
    done
}

# Function to safely create symlink
create_symlink() {
    local src="$1"
    local dst="$2"
    
    if [ -L "$dst" ]; then
        rm "$dst"
    elif [ -d "$dst" ]; then
        rm -rf "$dst"
    fi

    if [ -d "$src" ]; then
        ln -sf "$src" "$dst"
        echo "✅ Created symlink: $dst -> $src"
    else
        echo "❌ Source directory $src not found"
    fi
}

# Handle RunPod volume
if [ -d "/runpod-volume" ]; then
    echo "RunPod network volume detected at /runpod-volume"
    create_dir_structure "/runpod-volume"
    
    for dir in models input output custom_nodes; do
        create_symlink "/runpod-volume/ComfyUI/$dir" "/workspace/ComfyUI/$dir"
    done
else
    echo "⚠️ No RunPod network volume found, using local storage"
fi

# Start JupyterLab
echo "Starting JupyterLab..."
. $JUPYTER_VENV/bin/activate
jupyter lab --ip 0.0.0.0 --port 8888 --no-browser --allow-root &
deactivate

# Print final directory structure
echo "📁 Final Directory Structure:"
tree -L 3 /workspace/ComfyUI

# Start ComfyUI
echo "🚀 Starting ComfyUI..."
. $COMFYUI_VENV/bin/activate
exec python main.py --listen 0.0.0.0 --port 3000 --enable-cors-header
EOF

RUN chmod +x /start.sh

# Expose ports
EXPOSE 3000 8888

# Add healthcheck
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:3000 || exit 1

# Set default command
CMD ["/start.sh"]