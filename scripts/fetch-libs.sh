#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIBS_DIR="$REPO_ROOT/libs"
TMP_DIR="$REPO_ROOT/.tmp-libs"

echo "Fetching Ace3 libraries into $LIBS_DIR ..."

mkdir -p "$LIBS_DIR"

# Libraries to extract from the Ace3 repo
ACE3_LIBS=(
  "LibStub"
  "CallbackHandler-1.0"
  "AceAddon-3.0"
  "AceDB-3.0"
  "AceDBOptions-3.0"
  "AceConsole-3.0"
  "AceConfig-3.0"
  "AceGUI-3.0"
  "AceEvent-3.0"
)

# Check if we need to fetch anything
needs_fetch=false
for lib in "${ACE3_LIBS[@]}"; do
  if [[ ! -d "$LIBS_DIR/$lib" ]]; then
    needs_fetch=true
    break
  fi
done

if $needs_fetch; then
  echo "  Cloning Ace3 (shallow)..."
  rm -rf "$TMP_DIR"
  git clone --depth 1 --quiet git@github.com:WoWUIDev/Ace3.git "$TMP_DIR/Ace3"

  for lib in "${ACE3_LIBS[@]}"; do
    if [[ -d "$LIBS_DIR/$lib" ]]; then
      echo "  $lib (exists, skipping)"
    else
      cp -r "$TMP_DIR/Ace3/$lib" "$LIBS_DIR/$lib"
      echo "  $lib"
    fi
  done

  rm -rf "$TMP_DIR"
else
  echo "  All libs already present, skipping"
fi

# Symlink libs into each addon
for addon_dir in "$REPO_ROOT"/addons/*/; do
  addon_name=$(basename "$addon_dir")
  addon_libs="$addon_dir/libs"

  if [[ -L "$addon_libs" ]]; then
    continue
  elif [[ -d "$addon_libs" ]]; then
    echo "WARNING: $addon_name/libs is a real directory, not symlinking"
    continue
  fi

  ln -s "$LIBS_DIR" "$addon_libs"
  echo "Symlinked libs -> $addon_name/libs"
done

echo "Done. Libraries ready for local development."
