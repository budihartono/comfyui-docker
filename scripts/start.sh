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
        ln -s /runpod-volume/ComfyUI/models /workspace/ComfyUI/models
    fi
    
    # Link other directories
    rm -rf /workspace/ComfyUI/input
    rm -rf /workspace/ComfyUI/output
    rm -rf /workspace/ComfyUI/custom_nodes
    ln -s /runpod-volume/ComfyUI/input /workspace/ComfyUI/input
    ln -s /runpod-volume/ComfyUI/output /workspace/ComfyUI/output
    ln -s /runpod-volume/ComfyUI/custom_nodes /workspace/ComfyUI/custom_nodes
fi

# Install custom nodes and their requirements
bash /scripts/install_nodes.sh

# Start ComfyUI
python3 main.py --listen 0.0.0.0 --port 8188 --enable-cors-header