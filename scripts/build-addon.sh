#!/bin/bash
set -euo pipefail

# Copies shared packages into an addon's vendor/ directory.
# Usage: build-addon.sh <AddonName>
# Called by turbo's build task via each addon's package.json.

ADDON_NAME="${1:?Usage: build-addon.sh <AddonName>}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ADDON_DIR="$REPO_ROOT/addons/$ADDON_NAME"
VENDOR_DIR="$ADDON_DIR/vendor"

if [[ ! -d "$ADDON_DIR" ]]; then
  echo "Addon not found: $ADDON_DIR"
  exit 1
fi

# Clean and recreate vendor dir
rm -rf "$VENDOR_DIR"
mkdir -p "$VENDOR_DIR"

# Copy shared library files
SHARED_LIB="$REPO_ROOT/packages/zlynk-lib/src"
if [[ -d "$SHARED_LIB" ]]; then
  shopt -s nullglob
  lua_files=("$SHARED_LIB"/*.lua)
  if [[ ${#lua_files[@]} -gt 0 ]]; then
    cp "${lua_files[@]}" "$VENDOR_DIR/"
    echo "Copied ${#lua_files[@]} shared lib file(s) into $ADDON_NAME/vendor/"
  else
    echo "No shared lib files to copy (packages/zlynk-lib/src/ has no .lua files)"
  fi
fi
