#!/bin/bash
set -ueo pipefail

# Check if enough arguments are passed; if not, print an error and exit
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 METADATA_BASE_URL TUF_ROOT_FOLDER"
    exit 1
fi

# Assign input arguments to variables
METADATA_BASE_URL="$1"
TUF_ROOT_FOLDER="$2"

# Define variables
ROOT_NAME="root.json"
TUF_ROOT_PATH="$TUF_ROOT_FOLDER/$ROOT_NAME"
TARGET_NAME="trusted_root.json"
CACHE_DIR="./tuf_cache"

# Create a cache directory
mkdir -p "$CACHE_DIR"

# Ensure the cache directory is removed on script exit or interrupt
trap 'rm -rf "$CACHE_DIR"; exit' EXIT INT TERM

# Run tuf to fetch the target
tuf download-target --metadata-base-url "$METADATA_BASE_URL" \
                    --target-name "$TARGET_NAME" \
                    --root="$TUF_ROOT_PATH" \
                    --cache-path "$CACHE_DIR"

# Check if root.json was updated in cache successfully
if [ -f "$CACHE_DIR/$ROOT_NAME" ]; then
    echo "$ROOT_NAME has been updated in cache successfully."

    # Copy to the specified directory
    cp "$CACHE_DIR/$ROOT_NAME" "$TUF_ROOT_FOLDER/$ROOT_NAME"
    echo "$ROOT_NAME has been copied to the target directory."
else
    echo "Error: $ROOT_NAME was not found in the cache directory."
fi

# Cleanup: Remove the cache directory
rm -rf "$CACHE_DIR"
