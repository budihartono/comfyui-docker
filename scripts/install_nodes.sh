#!/bin/bash
# Move to script's directory to ensure relative paths work
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR/../ComfyUI/custom_nodes"

# Read and install nodes from nodes.txt
while IFS= read -r repo; do
    # Skip empty lines and comments
    [[ -z "$repo" || "$repo" =~ ^#.*$ ]] && continue
    
    # Extract repo name from URL
    repo_name=$(basename "$repo" .git)
    
    echo "Installing $repo_name..."
    if [ -d "$repo_name" ]; then
        echo "$repo_name already exists, updating..."
        cd "$repo_name"
        git pull
        cd ..
    else
        git clone "$repo"
    fi
    
    # Install requirements if they exist
    if [ -f "$repo_name/requirements.txt" ]; then
        echo "Installing requirements for $repo_name"
        pip3 install -r "$repo_name/requirements.txt"
    fi
done < "../nodes.txt"