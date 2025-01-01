#!/bin/bash

download_ui_manifest() {
  local ui_sha="$1"
  if [ -z "$ui_sha" ]; then
    echo "ERROR: download_ui_manifest requires a SHA argument"
    return 1
  fi

  local hashed_file="ui-manifest-${ui_sha}.json"
  local cdn_url="https://github.githubassets.com/assets/$hashed_file"
  local blob_url="https://staticuiassets.z13.web.core.windows.net/assets/$hashed_file"
  local output_dir="public/assets"
  local cached_file="$output_dir/$hashed_file"
  local disk_cache="tmp/$hashed_file"
  local output_file="$output_dir/ui-manifest.json"

  # Helper function to copy cached file to output
  copy_to_output() {
    cp "$cached_file" "$output_file"
    cp "$cached_file" "$disk_cache"
  }

  # Create output directory if it doesn't exist
  mkdir -p "$output_dir"

  # Check if we already have this version cached
  if [ -f "$cached_file" ]; then
    copy_to_output
    return 0
  fi

  # Try CDN first
  if curl -f -s -L -o "$cached_file" "$cdn_url"; then
    copy_to_output
    return 0
  fi

  # Try Blob as a fallback
  echo "Downloading ui-manifest from the CDN failed, attempting download from Blob: $blob_url"
  if curl -f -s -L -o "$cached_file" "$blob_url"; then
    echo "Successfully downloaded ui-manifest.json from Blob"
    copy_to_output
    return 0
  fi

  echo "ERROR: Failed to download ui-manifest.json from both the CDN and Blob."
  return 1
}
