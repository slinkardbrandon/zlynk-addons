#!/bin/bash
set -euo pipefail

# Detect WoW AddOns directory
if [[ "$OSTYPE" == "darwin"* ]]; then
  WOW_ADDONS="/Applications/World of Warcraft/_retail_/Interface/AddOns"
else
  echo "Set WOW_ADDONS env var to your WoW AddOns directory"
  exit 1
fi

if [[ -n "${WOW_ADDONS_DIR:-}" ]]; then
  WOW_ADDONS="$WOW_ADDONS_DIR"
fi

if [[ ! -d "$WOW_ADDONS" ]]; then
  echo "WoW AddOns directory not found: $WOW_ADDONS"
  echo "Set WOW_ADDONS_DIR env var to override"
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

for addon_dir in "$REPO_ROOT"/addons/*/; do
  addon_name=$(basename "$addon_dir")

  # Skip if not a real addon (no .toc file)
  if ! ls "$addon_dir"/*.toc &>/dev/null; then
    continue
  fi

  target="$WOW_ADDONS/$addon_name"

  if [[ -L "$target" ]]; then
    echo "Relinked $addon_name"
    rm "$target"
  elif [[ -d "$target" ]]; then
    echo "SKIP $addon_name — real directory exists at $target (not a symlink)"
    continue
  else
    echo "Linked $addon_name"
  fi

  ln -s "$addon_dir" "$target"
done

echo "Done. /reload in-game to pick up changes."
