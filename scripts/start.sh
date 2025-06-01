#!/bin/bash

# ──────────── 0. Clone ComfyUI if missing ────────────────────────────────────────

# Ensure /workspace exists
mkdir -p /workspace

# If ComfyUI/main.py is not present, clone the repo into /workspace/ComfyUI
if [ ! -f "/workspace/ComfyUI/main.py" ]; then
    echo "🔄 ComfyUI not found—cloning repository..."
    rm -rf /workspace/ComfyUI
    git clone https://github.com/comfyanonymous/ComfyUI.git /workspace/ComfyUI
    if [ -n "${COMFYUI_BUILD_REF:-}" ]; then
        cd /workspace/ComfyUI
        git checkout "$COMFYUI_BUILD_REF"
    fi
else
    echo "✅ ComfyUI already exists"
fi

cd /workspace/ComfyUI

# ──────────── 1. Debug: Print current directory and contents ─────────────────────

echo "Current directory: $(pwd)"
echo "Contents of /workspace/ComfyUI:"
ls -la /workspace/ComfyUI

# ──────────── 2. Debug: Check runpod-volume ───────────────────────────────────────

echo "Checking /runpod-volume..."
if [ -d "/runpod-volume" ]; then
    echo "✅ /runpod-volume exists"
    ls -la /runpod-volume
else
    echo "❌ /runpod-volume does not exist"
fi

# ──────────── 3. Setup network volume if available ───────────────────────────────

if [ -d "/runpod-volume" ]; then
    echo "Setting up network volume..."
    
    # Create directories under /runpod-volume/ComfyUI
    for dir in models input output custom_nodes; do
        mkdir -p "/runpod-volume/ComfyUI/$dir"
        echo "Created /runpod-volume/ComfyUI/$dir: $?"
    done
    
    # Create symbolic links for input, output, custom_nodes
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

# ──────────── 4. Debug: Final directory structure ─────────────────────────────────

echo "Final directory structure:"
tree -L 2 /workspace/ComfyUI

# ──────────── 5. Run provisioning script (if present) ────────────────────────────

echo "📥 Running provisioning script (if configured)…"
if [ -x "/scripts/provision_models.sh" ]; then
    export WORKSPACE="/workspace"
    /scripts/provision_models.sh
else
    echo "   – no provisioning script found at /scripts/provision_models.sh, skipping."
fi

# ──────────── 6. Install custom nodes and their requirements ──────────────────────

bash /scripts/install_nodes.sh

# ──────────── 7. Start JupyterLab ─────────────────────────────────────────────────

echo "🚀 Starting JupyterLab..."
jupyter lab --ip 0.0.0.0 --port 8888 --no-browser --allow-root &

# ──────────── 8. Start ComfyUI ────────────────────────────────────────────────────

echo "🚀 Starting ComfyUI…"
python3 main.py --listen 0.0.0.0 --port 3000 --enable-cors-header