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

# Set working directory
WORKDIR /comfyui

# Clone ComfyUI repository
RUN git clone https://github.com/comfyanonymous/ComfyUI .

# Install Python dependencies
RUN pip3 install --no-cache-dir -r requirements.txt
RUN pip3 install --no-cache-dir torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118

# Create directories
RUN mkdir -p models

# Create the start script
COPY <<'EOF' /start.sh
#!/bin/bash
cd /comfyui

# Setup network volume if available
if [ -d "/runpod-volume" ]; then
    echo "Setting up network volume..."
    
    # Create directories if they don't exist
    mkdir -p /runpod-volume/comfyui/models
    mkdir -p /runpod-volume/comfyui/outputs
    
    # Link models directory if it has content
    if [ "$(ls -A /runpod-volume/comfyui/models)" ]; then
        echo "Using models from network volume"
        rm -rf /comfyui/models
        ln -s /runpod-volume/comfyui/models /comfyui/models
    fi
    
    # Link outputs directory
    rm -rf /comfyui/output
    ln -s /runpod-volume/comfyui/outputs /comfyui/output
fi

# Start ComfyUI
python3 main.py --listen 0.0.0.0 --port 8188 --enable-cors-header
EOF

RUN chmod +x /start.sh

EXPOSE 8188

CMD ["/start.sh"]