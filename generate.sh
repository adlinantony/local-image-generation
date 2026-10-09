#!/bin/bash
# Text-to-image with Qwen-Image-2.1 (official weights, 8-bit), fully offline.
#
#   ./generate.sh "prompt" [size] [options]
#
#   size:    square (default), 4:3, 3:4, 3:2, 2:3, 16:9, 9:16
#            add "hd" for 2K output, e.g. 16:9hd (about 4x slower)
#   --turbo  6 steps instead of 40 (Viggle's distilled add-on), several times faster
#   other options go straight to mflux, e.g. --seed 42, --auto-seeds 4,
#            --image photo.jpg 0.5 (restyle a photo; higher keeps more of it)
#
# Images are saved in ./outputs with the prompt and seed stored in their metadata.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
TURBO_FILE="Qwen-Image-2.1-viggle-turbo-v0.3-6step-lora-r256.safetensors"

turbo_lora() {   # local path of the downloaded turbo add-on (the scripts run offline)
  local f
  f=$(ls "${HF_HOME:-$HOME/.cache/huggingface}"/hub/models--Viggle--Qwen-Image-2.1-viggle-turbo/snapshots/*/"$TURBO_FILE" 2>/dev/null | head -1)
  [ -n "$f" ] || { echo "Turbo add-on missing. Get it with: uv run hf download Viggle/Qwen-Image-2.1-viggle-turbo $TURBO_FILE" >&2; return 1; }
  echo "$f"
}

if [ $# -lt 1 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  sed -n '2,12p' "$0" | sed -E 's/^# ?//'; exit 0
fi
prompt="$1"; shift
size="square"; size_given=0
if [ $# -gt 0 ] && [[ "$1" != -* ]]; then size="$1"; size_given=1; shift; fi

opts=(); label=""; image=""; prev=""
for a in "$@"; do
  if [ "$a" = "--turbo" ]; then label=" (turbo)"; else opts+=("$a"); fi
  [ "$prev" = "--image" ] && image="$a"
  prev="$a"
done
if [ -n "$label" ]; then
  lora=$(turbo_lora)
  opts=(--scheduler viggle_turbo --steps 6 --lora "$lora" ${opts[@]+"${opts[@]}"})
fi

scale=1; ratio="$size"
case "$ratio" in *hd) scale=2; ratio="${ratio%hd}" ;; esac
case "$ratio" in
  square|1:1) w=1024; h=1024 ;;
  4:3)        w=1152; h=864 ;;
  3:4)        w=864;  h=1152 ;;
  3:2)        w=1248; h=832 ;;
  2:3)        w=832;  h=1248 ;;
  16:9)       w=1376; h=768 ;;
  9:16)       w=768;  h=1376 ;;
  *) echo "Unknown size '$size'. Use square, 4:3, 3:4, 3:2, 2:3, 16:9 or 9:16 (add hd for 2K)."; exit 1 ;;
esac

# Restyling a photo without a size: keep the photo's proportions at about 1 megapixel.
if [ -n "$image" ] && [ "$size_given" = 0 ]; then
  [ -f "$image" ] || { echo "Image not found: $image"; exit 1; }
  read -r iw ih < <(sips -g pixelWidth -g pixelHeight "$image" | awk '/pixelWidth/{w=$2} /pixelHeight/{h=$2} END{print w, h}')
  read -r w h < <(awk -v iw="$iw" -v ih="$ih" 'BEGIN{s=sqrt(1048576/(iw*ih)); printf "%d %d\n", int(iw*s/32+0.5)*32, int(ih*s/32+0.5)*32}')
fi
w=$((w * scale)); h=$((h * scale))

mkdir -p "$DIR/outputs"
out="$DIR/outputs/$(date +%Y-%m-%d_%H%M%S).png"
echo "Generating ${w}x${h}${label} -> outputs/$(basename "$out")"

# Offline: use only the downloaded weights, never contact Hugging Face.
HF_HUB_OFFLINE=1 HF_HUB_DISABLE_TELEMETRY=1 \
  uv run --quiet --project "$DIR" mflux-generate-qwen-2.1 -q 8 \
  --prompt "$prompt" --width "$w" --height "$h" --output "$out" ${opts[@]+"${opts[@]}"}

# Open the result (or the folder, when several seeds were generated).
if [ -f "$out" ]; then open "$out"; else open "$DIR/outputs"; fi
