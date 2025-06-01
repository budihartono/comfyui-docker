#!/usr/bin/env bash
set -euo pipefail
umask 002

#
# scripts/provision_models.sh
#
#   - Fetches MODEL_LIST_URL (one <category>|<url> per line)
#   - For each line, splits category & URL
#   - Creates $BASE_MODELS_DIR/<category>/
#   - Downloads each URL into that subfolder. If URL contains “civitai.com/api/download”,
#     use `--content-disposition` (and pass `Authorization: Bearer $CIVITAI_TOKEN` if set).
#   - Otherwise, use basename(URL) as the filename.
#

# ──────────── 0. Determine “models” root folder ──────────────────────────────────

WORKSPACE="${WORKSPACE:-/workspace}"

if [ -d "/runpod-volume/ComfyUI/models" ]; then
  BASE_MODELS_DIR="/runpod-volume/ComfyUI/models"
  echo "🔧 Using network-mounted models directory: $BASE_MODELS_DIR"
else
  BASE_MODELS_DIR="$WORKSPACE/ComfyUI/models"
  echo "🔧 Using local models directory: $BASE_MODELS_DIR"
fi

mkdir -p "$BASE_MODELS_DIR"

# ──────────── 1. Fetch & parse MODEL_LIST_URL ───────────────────────────────────

if [[ -z "${MODEL_LIST_URL:-}" ]]; then
  echo "⚠️  MODEL_LIST_URL is not set or is empty → nothing to provision."
  exit 0
fi

echo "📥 Downloading MODEL_LIST_URL: $MODEL_LIST_URL"
TMP_LIST_FILE="$(mktemp)"
if ! curl -fsSL "$MODEL_LIST_URL" -o "$TMP_LIST_FILE"; then
  echo "❌ Failed to download MODEL_LIST_URL ($MODEL_LIST_URL). Exiting."
  rm -f "$TMP_LIST_FILE"
  exit 1
fi

# ──────────── 2. Loop through each <category>|<url> line ────────────────────────

echo "📂 Processing model list contents..."

while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
  line="$(echo "$raw_line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  [[ -z "$line" || "${line:0:1}" == "#" ]] && continue

  # Must contain a pipe (“|”)
  if [[ "$line" != *"|"* ]]; then
    echo "⚠️  Skipping invalid line (no '|'): $line"
    continue
  fi

  category="${line%%|*}"
  url="${line#*|}"
  category="$(echo "$category" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  url="$(echo "$url" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

  if [[ -z "$category" || -z "$url" ]]; then
    echo "⚠️  Skipping invalid line (empty category or URL): $line"
    continue
  fi

  # Create the category folder if it does not exist
  dest_dir="$BASE_MODELS_DIR/$category"
  mkdir -p "$dest_dir"

  # Download logic:
  if [[ "$url" =~ "civitai.com/api/download" ]]; then
    # Civitai URL: attempt to honor Content-Disposition header
    echo "     → [$category] Downloading (Civitai) $url …"
    if [[ -n "${CIVITAI_TOKEN:-}" ]]; then
      wget --content-disposition --header="Authorization: Bearer $CIVITAI_TOKEN" -P "$dest_dir" "$url" \
        || { echo "       ❌ Failed to download (Civitai) $url"; continue; }
    else
      wget --content-disposition -P "$dest_dir" "$url" \
        || { echo "       ❌ Failed to download (Civitai) $url"; continue; }
    fi

    # After this, wget should save the file under $dest_dir with the name from Civitai’s header.
    # But we should still check if that file’s basename already existed. Wget’s --content-disposition
    # will not overwrite an existing file (it will append .1, .2, etc.), so if the file already
    # existed, you’ll end up with filename.1. We can optionally clean that up here if needed.

  else
    # Non-Civitai URL: use basename(URL) as filename
    filename="$(basename "$url")"
    dest_path="$dest_dir/$filename"
    if [[ -f "$dest_path" ]]; then
      echo "       • [$category] $filename already exists — skipping."
      continue
    fi

    echo "     → [$category] Downloading $url → $dest_path"
    wget --progress=dot:giga -O "$dest_path" "$url" \
      || { echo "       ❌ Failed to download $url"; rm -f "$dest_path"; continue; }
  fi

done < "$TMP_LIST_FILE"

rm -f "$TMP_LIST_FILE"
echo "✅ Provisioning complete. Check $BASE_MODELS_DIR for all downloaded files."