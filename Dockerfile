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

# Set up ComfyUI in workspace
WORKDIR /workspace/ComfyUI

# Clone ComfyUI repository and install dependencies
RUN git clone https://github.com/comfyanonymous/ComfyUI . && \
    pip3 install --no-cache-dir -r requirements.txt && \
    pip3 install --no-cache-dir torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118 && \
    pip3 install --no-cache-dir jupyterlab nodejs

# Create basic directory structure
RUN mkdir -p models input output custom_nodes

# Create the startup script
COPY <<'EOF' /start.sh
#!/bin/bash
cd /workspace/ComfyUI

echo "🔍 Starting ComfyUI Setup..."
echo "Python Version: $(python3 --version)"
echo "CUDA Version: $(nvcc --version 2>/dev/null || echo 'NVCC not found')"
echo "GPU Information: $(nvidia-smi 2>/dev/null || echo 'nvidia-smi not found')"

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
    echo "Attempting to link: $dst -> $src"
    
    # Remove existing destination if it exists
    if [ -L "$dst" ]; then
        echo "Removing existing symlink $dst"
        rm "$dst"
    elif [ -d "$dst" ]; then
        echo "Removing existing directory $dst"
        rm -rf "$dst"
    fi

    # Create the symlink
    if [ -d "$src" ]; then
        ln -sf "$src" "$dst"
        echo "✅ Created symlink: $dst -> $src"
        ls -la "$dst"
    else
        echo "❌ Source directory $src not found"
        ls -la "$(dirname $src)"
    fi
}

# Check for RunPod volume
if [ -d "/runpod-volume" ]; then
    echo "RunPod network volume detected at /runpod-volume"
    
    # Create directory structure in network volume
    create_dir_structure "/runpod-volume"
    
    echo "Setting up symlinks..."
    # Create symlinks for each directory
    for dir in models input output custom_nodes; do
        create_symlink "/runpod-volume/ComfyUI/$dir" "/workspace/ComfyUI/$dir"
    done
    
    echo "Directory structure after setup:"
    ls -la /workspace/ComfyUI/
    echo "Network volume contents:"
    ls -la /runpod-volume/ComfyUI/
else
    echo "⚠️ No RunPod network volume found, using local storage"
    ls -la /
fi

# Start JupyterLab
echo "Starting JupyterLab..."
jupyter lab --ip 0.0.0.0 --port 8888 --no-browser --allow-root --ServerApp.token='' --ServerApp.password='' &

# Print final directory structure
echo "📁 Final Directory Structure:"
tree -L 3 /workspace/ComfyUI

# Start ComfyUI
echo "🚀 Starting ComfyUI..."
exec python3 main.py --listen 0.0.0.0 --port 3000 --enable-cors-header
EOF

RUN chmod +x /start.sh

# Expose ports
EXPOSE 3000 8888

# Add healthcheck
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:3000 || exit 1

CMD ["/start.sh"]