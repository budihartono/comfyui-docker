#!/usr/bin/env bash
set -euo pipefail
umask 002

#
# scripts/provision_models.sh
#   - For each “CATEGORY_URLS” environment variable, download into the matching subfolder:
#     e.g. CHECKPOINT_URLS → $BASE_MODELS_DIR/checkpoints/
#   - If /runpod-volume/ComfyUI/models exists, use that as the base; otherwise fallback to $WORKSPACE/ComfyUI/models.
#   - Skip any file whose basename already exists in that directory.
#

# ──────── 1. Configuration / Category ↔ Subfolder Map ───────────────────────────

# Ensure WORKSPACE is set (where ComfyUI is mounted). Default to /workspace:
WORKSPACE="${WORKSPACE:-/workspace}"

# If the network volume already has its own ComfyUI/models, use that; otherwise use the local path.
if [ -d "/runpod-volume/ComfyUI/models" ]; then
  BASE_MODELS_DIR="/runpod-volume/ComfyUI/models"
  echo "🔧 Using network-mounted models directory: $BASE_MODELS_DIR"
else
  BASE_MODELS_DIR="$WORKSPACE/ComfyUI/models"
  echo "🔧 Using local models directory: $BASE_MODELS_DIR"
fi

# Define a simple list of “category → env var → target subdirectory”
# You can add more lines if you introduce new categories later.
declare -A CATEGORY_MAP=(
  [checkpoints]="CHECKPOINT_URLS"
  [unet]="UNET_URLS"
  [loras]="LORA_URLS"
  [controlnet]="CONTROLNET_URLS"
  [clip]="CLIP_URLS"
  [text_encoders]="TEXT_ENCODER_URLS"
)

# ──────── 2. Create Category Folders ────────────────────────────────────────────

echo "🔧 Ensuring category folders exist under: $BASE_MODELS_DIR"
for category in "${!CATEGORY_MAP[@]}"; do
  target_dir="$BASE_MODELS_DIR/$category"
  mkdir -p "$target_dir"
  echo "   • Created (or already existed): $target_dir"
done

# ──────── 3. Download Helper Function ───────────────────────────────────────────

download_category() {
  local category="$1"            # e.g. "checkpoints"
  local env_var_name="$2"        # e.g. "CHECKPOINT_URLS"
  local raw_list="${!env_var_name:-}"  # Value of that environment variable

  # If the variable is empty or undefined, skip:
  if [[ -z "$raw_list" ]]; then
    echo "   ◦ No URLs specified for $category (env var $env_var_name is empty). Skipping."
    return 0
  fi

  local dest_dir="$BASE_MODELS_DIR/$category"

  # Split comma-separated URLs and loop
  IFS=',' read -r -a url_array <<< "$raw_list"
  for url in "${url_array[@]}"; do
    # Trim whitespace around the URL
    url="$(echo "$url" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    if [[ -z "$url" ]]; then
      continue
    fi

    filename="$(basename "$url")"
    dest_path="$dest_dir/$filename"

    if [[ -f "$dest_path" ]]; then
      echo "     • [$category] $filename already exists — skipping."
      continue
    fi

    echo "     → [$category] Downloading $url ..."
    if ! wget --progress=dot:giga -O "$dest_path" "$url"; then
      echo "       ⚠️  Failed to download $url. Removing partial file and continuing."
      rm -f "$dest_path"
      continue
    fi
  done
}

# ──────── 4. Loop Over Each Category & Download ─────────────────────────────────

echo "📥 Starting provisioning of category-based model downloads…"
for category in "${!CATEGORY_MAP[@]}"; do
  env_var_name="${CATEGORY_MAP[$category]}"
  echo "  ▶ Processing category '$category' (using env var $env_var_name)"
  download_category "$category" "$env_var_name"
done

echo "✅ Provisioning complete. Check $BASE_MODELS_DIR for downloaded (or preexisting) files."