#!/bin/bash
cd /comfyui

# Setup network volume if available
if [ -d "/runpod-volume" ]; then
    echo "Setting up network volume..."
    
    # Create directories if they don't exist
    mkdir -p /runpod-volume/comfyui/models
    mkdir -p /runpod-volume/comfyui/outputs
    mkdir -p /runpod-volume/comfyui/custom_nodes
    
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

# Install custom nodes and their requirements
bash /scripts/install_nodes.sh

# Start ComfyUI
python3 main.py --listen 0.0.0.0 --port 8188 --enable-cors-header