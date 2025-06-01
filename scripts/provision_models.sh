#!/usr/bin/env bash
set -euo pipefail
umask 002

#
# scripts/provision_models.sh
#
#   This script downloads “models” into the folder structure:
#     $BASE_MODELS_DIR/<category>/
#   for *any* <category> that appears in the PasteBin list.
#
#   It expects a single environment variable:
#     MODEL_LIST_URL  (a raw-text URL, e.g. PasteBin “raw”)
#
#   PasteBin format (one non-empty, non-comment line per model):
#     <category>|<url>
#
#   Example:
#     checkpoints|https://huggingface.co/user/sd-v2-1.safetensors
#     loras|https://huggingface.co/user/my-style-lora.safetensors
#     clip|https://huggingface.co/user/clip-vit-l-14.safetensors
#     custom|https://foo.com/bar/my_custom_model.safetensors
#
#   This version does *not* rely on any hardcoded CATEGORY_MAP. It simply:
#     1) Fetches MODEL_LIST_URL
#     2) Parses each <category> and <url>
#     3) Creates $BASE_MODELS_DIR/<category>/ if it does not exist
#     4) Downloads each URL into that subfolder if the file is not already present
#

# ──────────── 0. Determine which “models” folder to use ──────────────────────────

# By default, assume WORKSPACE=/workspace (so ComfyUI is at /workspace/ComfyUI)
WORKSPACE="${WORKSPACE:-/workspace}"

# If /runpod-volume/ComfyUI/models exists, use that (so downloads persist on the network volume)
if [ -d "/runpod-volume/ComfyUI/models" ]; then
  BASE_MODELS_DIR="/runpod-volume/ComfyUI/models"
  echo "🔧 Using network-mounted models directory: $BASE_MODELS_DIR"
else
  BASE_MODELS_DIR="$WORKSPACE/ComfyUI/models"
  echo "🔧 Using local models directory: $BASE_MODELS_DIR"
fi

# Make sure the root “models” folder exists
mkdir -p "$BASE_MODELS_DIR"

# ──────────── 1. Fetch and parse the MODEL_LIST_URL ──────────────────────────────

if [[ -z "${MODEL_LIST_URL:-}" ]]; then
  echo "⚠️  MODEL_LIST_URL is not set or is empty. Nothing to provision."
  exit 0
fi

echo "📥 Downloading MODEL_LIST_URL: $MODEL_LIST_URL"

TMP_LIST_FILE="$(mktemp)"
if ! curl -fsSL "$MODEL_LIST_URL" -o "$TMP_LIST_FILE"; then
  echo "❌ Failed to download MODEL_LIST_URL ($MODEL_LIST_URL). Exiting."
  rm -f "$TMP_LIST_FILE"
  exit 1
fi

# ──────────── 2. Loop over each valid line (category|url) ─────────────────────────

echo "📂 Processing each line in the model list..."

while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
  # Trim leading/trailing whitespace
  line="$(echo "$raw_line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

  # Skip comments or blank lines
  if [[ -z "$line" || "${line:0:1}" == "#" ]]; then
    continue
  fi

  # Split on the first '|'
  if [[ "$line" != *"|"* ]]; then
    echo "⚠️  Skipping invalid line (missing '|'): $line"
    continue
  fi

  category="${line%%|*}"
  url="${line#*|}"

  # Trim again in case of stray spaces
  category="$(echo "$category" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  url="$(echo "$url" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

  if [[ -z "$category" || -z "$url" ]]; then
    echo "⚠️  Skipping invalid line (empty category or URL): $line"
    continue
  fi

  # Determine the destination folder for this category
  dest_dir="$BASE_MODELS_DIR/$category"
  mkdir -p "$dest_dir"

  # Determine filename from URL
  filename="$(basename "$url")"
  dest_path="$dest_dir/$filename"

  # If file already exists, skip
  if [[ -f "$dest_path" ]]; then
    echo "   • [$category] $filename already exists; skipping."
    continue
  fi

  # Download into the category folder
  echo "   → [$category] Downloading $url → $dest_path"
  if ! wget --progress=dot:giga -O "$dest_path" "$url"; then
    echo "     ❌ Failed to download $url. Removing partial file."
    rm -f "$dest_path"
    continue
  fi

done < "$TMP_LIST_FILE"

rm -f "$TMP_LIST_FILE"
echo "✅ Provisioning complete. Check contents of $BASE_MODELS_DIR."