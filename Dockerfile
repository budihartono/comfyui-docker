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
    libgl1-mesa-glx \
    libglib2.0-0 \
    ffmpeg \
    libsm6 \
    libxext6 \
    && rm -rf /var/lib/apt/lists/*

# Create and activate virtual environment
ENV VIRTUAL_ENV=/opt/venv
RUN python3.10 -m venv $VIRTUAL_ENV
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

# Set up the ComfyUI directory structure
WORKDIR /
RUN mkdir -p /workspace/ComfyUI

# Clone ComfyUI repository
WORKDIR /workspace/ComfyUI
RUN git clone https://github.com/comfyanonymous/ComfyUI .

# Install Python dependencies
RUN pip3 install --no-cache-dir -r requirements.txt
RUN pip3 install --no-cache-dir torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118

# Install JupyterLab
RUN pip3 install --no-cache-dir jupyterlab

# Create necessary directories
RUN mkdir -p /workspace/ComfyUI/models
RUN mkdir -p /workspace/ComfyUI/input
RUN mkdir -p /workspace/ComfyUI/output
RUN mkdir -p /workspace/ComfyUI/custom_nodes

# Create a directory for custom node scripts
RUN mkdir -p /scripts

# Create the start script
COPY <<'EOF' /start.sh
#!/bin/bash
cd /workspace/ComfyUI

# Setup network volume if available
if [ -d "/runpod-volume" ]; then
    echo "Setting up network volume..."
    
    # Create directories if they don't exist
    mkdir -p /runpod-volume/ComfyUI/models
    mkdir -p /runpod-volume/ComfyUI/input
    mkdir -p /runpod-volume/ComfyUI/output
    mkdir -p /runpod-volume/ComfyUI/custom_nodes
    
    # Link directories if they have content
    if [ "$(ls -A /runpod-volume/ComfyUI/models)" ]; then
        echo "Using models from network volume"
        rm -rf /workspace/ComfyUI/models
        ln -sf /runpod-volume/ComfyUI/models /workspace/ComfyUI/models
    fi
    
    # Link other directories
    rm -rf /workspace/ComfyUI/input
    rm -rf /workspace/ComfyUI/output
    rm -rf /workspace/ComfyUI/custom_nodes
    ln -sf /runpod-volume/ComfyUI/input /workspace/ComfyUI/input
    ln -sf /runpod-volume/ComfyUI/output /workspace/ComfyUI/output
    ln -sf /runpod-volume/ComfyUI/custom_nodes /workspace/ComfyUI/custom_nodes
fi

# Start JupyterLab in the background
jupyter lab --ip 0.0.0.0 --port 8888 --no-browser --allow-root --ServerApp.token='' --ServerApp.password='' &

# Start ComfyUI
python3 main.py --listen 0.0.0.0 --port 3000 --enable-cors-header
EOF

RUN chmod +x /start.sh

# Expose ports
EXPOSE 3000 8888

CMD ["/start.sh"]