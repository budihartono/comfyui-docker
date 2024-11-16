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
WORKDIR /Comfyui

# Clone ComfyUI repository
RUN git clone https://github.com/comfyanonymous/ComfyUI .

# Install Python dependencies
RUN pip3 install --no-cache-dir -r requirements.txt
RUN pip3 install --no-cache-dir torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118

# Install JupyterLab
RUN pip3 install --no-cache-dir jupyterlab

# Create directories
RUN mkdir -p models

# Create the start script
COPY <<'EOF' /start.sh
#!/bin/bash
cd /Comfyui

# Setup network volume if available
if [ -d "/runpod-volume" ]; then
    echo "Setting up network volume..."
    
    # Create directories if they don't exist
    mkdir -p /runpod-volume/Comfyui/models
    mkdir -p /runpod-volume/Comfyui/outputs
    
    # Link models directory if it has content
    if [ "$(ls -A /runpod-volume/Comfyui/models)" ]; then
        echo "Using models from network volume"
        rm -rf /Comfyui/models
        ln -s /runpod-volume/Comfyui/models /Comfyui/models
    fi
    
    # Link outputs directory
    rm -rf /Comfyui/output
    ln -s /runpod-volume/Comfyui/outputs /Comfyui/output
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