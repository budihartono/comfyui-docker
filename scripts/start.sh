#!/bin/bash
cd /workspace/ComfyUI

# Debug: Print current directory and list contents
echo "Current directory: $(pwd)"
echo "Contents of /workspace/ComfyUI:"
ls -la /workspace/ComfyUI

# Debug: Check runpod-volume
echo "Checking /runpod-volume..."
if [ -d "/runpod-volume" ]; then
    echo "✅ /runpod-volume exists"
    ls -la /runpod-volume
else
    echo "❌ /runpod-volume does not exist"
fi

# Setup network volume if available
if [ -d "/runpod-volume" ]; then
    echo "Setting up network volume..."
    
    # Create directories and debug their creation
    for dir in models input output custom_nodes; do
        mkdir -p "/runpod-volume/ComfyUI/$dir"
        echo "Created /runpod-volume/ComfyUI/$dir: $?"
    done
    
    # Debug: Check symbolic links
    echo "Creating symbolic links..."
    for dir in input output custom_nodes; do
        rm -rf "/workspace/ComfyUI/$dir"
        ln -sf "/runpod-volume/ComfyUI/$dir" "/workspace/ComfyUI/$dir"
        echo "Linked $dir: $?"
        ls -la "/workspace/ComfyUI/$dir"
    done
    
    # Special handling for models
    if [ "$(ls -A /runpod-volume/ComfyUI/models)" ]; then
        echo "Using models from network volume"
        rm -rf /workspace/ComfyUI/models
        ln -sf /runpod-volume/ComfyUI/models /workspace/ComfyUI/models
        echo "Linked models: $?"
        ls -la /workspace/ComfyUI/models
    fi
fi

# >>> Begin new provisioning block >>>
# Run category-based provisioning if the script exists
echo "📥 Running provisioning script (if configured)…"
if [ -x "/scripts/provision_models.sh" ]; then
  # Ensure WORKSPACE is set so provision_models.sh knows where ComfyUI lives
  export WORKSPACE="${WORKSPACE:-/workspace}"
  /scripts/provision_models.sh
else
  echo "   – no provisioning script found at /scripts/provision_models.sh, skipping."
fi
# <<< End new provisioning block <<<

# Debug: Final structure
echo "Final directory structure:"
tree -L 2 /workspace/ComfyUI

# Install custom nodes and their requirements
bash /scripts/install_nodes.sh

# Start ComfyUI
python3 main.py --listen 0.0.0.0 --port 3000 --enable-cors-header