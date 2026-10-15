#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd -- "$script_dir/.." && pwd)"
split_script="$project_root/tools/split_character_parts.py"

blender_bin="${BLENDER_BIN:-blender}"
if ! command -v "$blender_bin" >/dev/null 2>&1; then
    if [[ -x /snap/bin/blender ]]; then
        blender_bin=/snap/bin/blender
    else
        echo "Blender was not found. Install Blender or set BLENDER_BIN to its executable." >&2
        exit 1
    fi
fi

exec "$blender_bin" -b --python "$split_script"
