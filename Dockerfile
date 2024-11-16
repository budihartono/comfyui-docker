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

# Create base ComfyUI directory
WORKDIR /workspace
RUN mkdir -p Comfyui

# Clone ComfyUI repository into the Comfyui directory
WORKDIR /workspace/Comfyui
RUN git clone https://github.com/comfyanonymous/ComfyUI .

# Install Python dependencies
RUN pip3 install --no-cache-dir -r requirements.txt
RUN pip3 install --no-cache-dir torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118

# Install JupyterLab
RUN pip3 install --no-cache-dir jupyterlab

# Create necessary directories under Comfyui
RUN mkdir -p models input output custom_nodes

# Create the start script
COPY <<'EOF' /start.sh
#!/bin/bash
cd /workspace/Comfyui

# Setup network volume if available
if [ -d "/runpod-volume" ]; then
    echo "Setting up network volume..."
    
    # Create directories if they don't exist
    mkdir -p /runpod-volume/Comfyui/models
    mkdir -p /runpod-volume/Comfyui/input
    mkdir -p /runpod-volume/Comfyui/output
    mkdir -p /runpod-volume/Comfyui/custom_nodes
    
    # Link directories if they have content
    if [ "$(ls -A /runpod-volume/Comfyui/models)" ]; then
        echo "Using models from network volume"
        rm -rf /workspace/Comfyui/models
        ln -s /runpod-volume/Comfyui/models /workspace/Comfyui/models
    fi
    
    # Link other directories
    rm -rf /workspace/Comfyui/input
    rm -rf /workspace/Comfyui/output
    rm -rf /workspace/Comfyui/custom_nodes
    ln -s /runpod-volume/Comfyui/input /workspace/Comfyui/input
    ln -s /runpod-volume/Comfyui/output /workspace/Comfyui/output
    ln -s /runpod-volume/Comfyui/custom_nodes /workspace/Comfyui/custom_nodes
fi

# Start JupyterLab in the background without authentication
jupyter lab --ip 0.0.0.0 --port 8888 --no-browser --allow-root --ServerApp.token='' --ServerApp.password='' &

# Start ComfyUI
python3 main.py --listen 0.0.0.0 --port 3000 --enable-cors-header
EOF

RUN chmod +x /start.sh

# Expose both JupyterLab and ComfyUI ports
EXPOSE 8888 3000

CMD ["/start.sh"]