#!/bin/bash
# Edit images with Qwen-Image-2.1 (official weights, 8-bit), fully offline.
#
#   ./edit.sh "instruction" image1 [image2 ... up to 10] [--turbo] [-- extra mflux options]
#
# Examples:
#   ./edit.sh "Replace the cloudy sky with a clear golden-hour sky" villa.jpg --turbo
#   ./edit.sh "Place the sofa from image 1 in the living room of image 2" sofa.png room.jpg
#   ./edit.sh "Remove the cars" house.jpg -- --auto-mask "the cars on the driveway"
#   ./edit.sh "Warmer evening light" photo.jpg -- --strength 0.6
#
# The output takes the shape of the last image (about 1 megapixel) and is saved in ./outputs.
# --turbo uses 6 steps instead of 40 and works best with 1-3 images.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
TURBO_FILE="Qwen-Image-2.1-viggle-turbo-v0.3-6step-lora-r256.safetensors"

turbo_lora() {   # local path of the downloaded turbo add-on (the scripts run offline)
  local f
  f=$(ls "${HF_HOME:-$HOME/.cache/huggingface}"/hub/models--Viggle--Qwen-Image-2.1-viggle-turbo/snapshots/*/"$TURBO_FILE" 2>/dev/null | head -1)
  [ -n "$f" ] || { echo "Turbo add-on missing. Get it with: uv run hf download Viggle/Qwen-Image-2.1-viggle-turbo $TURBO_FILE" >&2; return 1; }
  echo "$f"
}

if [ $# -lt 2 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  sed -n '2,13p' "$0" | sed -E 's/^# ?//'; exit 0
fi
prompt="$1"; shift
images=(); turbo=(); extra=(); label=""; tmp=""
trap 'if [ -n "$tmp" ]; then rm -rf "$tmp"; fi' EXIT
while [ $# -gt 0 ] && [ "$1" != "--" ]; do
  if [ "$1" = "--turbo" ]; then label=" (turbo)"; shift; continue; fi
  [ -f "$1" ] || { echo "Image not found: $1"; exit 1; }
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    *.heic|*.heif)   # iPhone photos: convert to JPEG first, the model can't read HEIC
      [ -n "$tmp" ] || tmp=$(mktemp -d)
      conv="$tmp/${#images[@]}_$(basename "${1%.*}").jpg"
      sips -s format jpeg "$1" --out "$conv" >/dev/null || { echo "Could not convert $1"; exit 1; }
      images+=("$conv") ;;
    *) images+=("$1") ;;
  esac
  shift
done
[ $# -gt 0 ] && shift   # drop the "--" separator
for a in "$@"; do
  if [ "$a" = "--turbo" ]; then label=" (turbo)"; else extra+=("$a"); fi
done
[ ${#images[@]} -ge 1 ] || { echo "Give at least one image to edit."; exit 1; }
[ ${#images[@]} -le 10 ] || { echo "Qwen-Image-2.1 accepts at most 10 reference images."; exit 1; }
if [ -n "$label" ]; then
  lora=$(turbo_lora)
  turbo=(--scheduler viggle_turbo --steps 6 --lora "$lora")
  [ ${#images[@]} -le 3 ] || echo "Note: turbo works best with up to 3 images."
fi

mkdir -p "$DIR/outputs"
out="$DIR/outputs/edit_$(date +%Y-%m-%d_%H%M%S).png"
echo "Editing ${#images[@]} image(s)${label} -> outputs/$(basename "$out")"

# Offline: use only the downloaded weights, never contact Hugging Face.
HF_HUB_OFFLINE=1 HF_HUB_DISABLE_TELEMETRY=1 \
  uv run --quiet --project "$DIR" mflux-generate-qwen-2.1-edit -q 8 \
  --prompt "$prompt" --image-paths "${images[@]}" --output "$out" \
  ${turbo[@]+"${turbo[@]}"} ${extra[@]+"${extra[@]}"}

if [ -f "$out" ]; then open "$out"; else open "$DIR/outputs"; fi
