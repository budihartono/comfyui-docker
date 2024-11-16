# Specify platform to avoid ARM-related issues
FROM --platform=linux/amd64 nvidia/cuda:11.8.0-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    python3.10 \
    python3.10-venv \
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

# Create and activate virtual environment
ENV VIRTUAL_ENV=/opt/venv
RUN python3.10 -m venv $VIRTUAL_ENV
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

# Set up the ComfyUI directory structure
WORKDIR /workspace/ComfyUI

# Clone ComfyUI repository
RUN git clone https://github.com/comfyanonymous/ComfyUI . && \
    # Install Python dependencies
    pip3 install --no-cache-dir -r requirements.txt && \
    pip3 install --no-cache-dir torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118 && \
    # Install JupyterLab
    pip3 install --no-cache-dir jupyterlab nodejs

# Create necessary directories
RUN mkdir -p models input output custom_nodes && \
    mkdir -p /scripts

# Set up volume management script
COPY <<'EOF' /scripts/setup_volume.sh
#!/bin/bash

echo "Setting up network volume..."
VOLUME_ROOT="/runpod-volume/ComfyUI"
WORKSPACE_ROOT="/workspace/ComfyUI"

# Create volume directories
for dir in models input output custom_nodes; do
    mkdir -p "$VOLUME_ROOT/$dir"
    echo "Created $VOLUME_ROOT/$dir"
done

# Function to safely create symlink
create_symlink() {
    local src="$1"
    local dst="$2"
    if [ -d "$src" ]; then
        rm -rf "$dst"
        ln -sf "$src" "$dst"
        echo "✅ Linked $dst -> $src"
        ls -la "$dst"
    else
        echo "❌ Source directory $src not found"
    fi
}

# Link directories
for dir in input output custom_nodes; do
    create_symlink "$VOLUME_ROOT/$dir" "$WORKSPACE_ROOT/$dir"
done

# Special handling for models directory
if [ "$(ls -A $VOLUME_ROOT/models)" ]; then
    echo "Using models from network volume"
    create_symlink "$VOLUME_ROOT/models" "$WORKSPACE_ROOT/models"
else
    echo "Network volume models directory is empty, using local models"
fi

echo "Volume setup complete"
EOF

RUN chmod +x /scripts/setup_volume.sh

# Set up custom nodes installation script
COPY <<'EOF' /scripts/install_nodes.sh
#!/bin/bash

cd /workspace/ComfyUI/custom_nodes

# Add your custom nodes installation commands here
# Example:
# git clone https://github.com/example/custom-node
# cd custom-node
# pip install -r requirements.txt

echo "Custom nodes installation complete"
EOF

RUN chmod +x /scripts/install_nodes.sh

# Create the main startup script
COPY <<'EOF' /start.sh
#!/bin/bash
cd /workspace/ComfyUI

# Debug: Print environment info
echo "🔍 Environment Information:"
echo "Python Version: $(python3 --version)"
echo "CUDA Version: $(nvcc --version 2>/dev/null || echo 'NVCC not found')"
echo "GPU Information: $(nvidia-smi 2>/dev/null || echo 'nvidia-smi not found')"

# Setup volume if available
if [ -d "/runpod-volume" ]; then
    bash /scripts/setup_volume.sh
else
    echo "⚠️ Warning: /runpod-volume not found, using local storage"
fi

# Install custom nodes
bash /scripts/install_nodes.sh

# Start JupyterLab in the background
jupyter lab --ip 0.0.0.0 --port 8888 --no-browser --allow-root --ServerApp.token='' --ServerApp.password='' &

# Print final directory structure
echo "📁 Final Directory Structure:"
tree -L 3 /workspace/ComfyUI

# Start ComfyUI with proper error handling
echo "🚀 Starting ComfyUI..."
if ! python3 main.py --listen 0.0.0.0 --port 3000 --enable-cors-header; then
    echo "❌ ComfyUI failed to start"
    exit 1
fi
EOF

RUN chmod +x /start.sh

# Expose ports
EXPOSE 3000 8888

# Add healthcheck
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:3000 || exit 1

CMD ["/start.sh"]