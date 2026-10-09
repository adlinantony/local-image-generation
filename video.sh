#!/bin/bash
# Video with sound from text or a photo: MiniMax-H3 (4-bit) via stable-diffusion.cpp, fully offline.
#
#   ./video.sh "prompt" [photo] [--seconds N] [--size 16:9|9:16|square|hd] [--steps N] [-- extra sd-cli options]
#   ./video.sh "prompt" --continue [video.mp4]   (next shot starts from that clip's last frame)
#
# Examples:
#   ./video.sh "waves rolling onto a quiet beach at sunset, gentle ocean sound"
#   ./video.sh "slow camera push-in, palm leaves swaying, water rippling in the pool" villa.jpg
#   ./video.sh "the camera keeps moving through the garden to the front door" --continue
#
# Default: 4 seconds at 864x480. A photo becomes the first frame and keeps its proportions. --continue
# without a file uses the newest video in ./outputs and keeps its size. Saved as an .mp4 (with audio).
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
M="${H3_MODELS:-$DIR/models/h3}"
SD="${H3_SDCLI:-$DIR/sdcpp/build/bin/sd-cli}"
DIT="$M/minimax_h3_fl2va-Q4_K_M.gguf"
LLM="$M/qwen3vl_32b_minimax_h3-Q4_K_M.gguf"
VAE="$M/vae/minimax_h3_video_vae_fp16.safetensors"
AVAE="$M/vae/minimax_h3_audio_vae_fp32.safetensors"

if [ $# -lt 1 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  sed -n '2,13p' "$0" | sed -E 's/^# ?//'; exit 0
fi
for f in "$SD" "$DIT" "$LLM" "$VAE" "$AVAE"; do [ -f "$f" ] || { echo "Missing: $f"; exit 1; }; done
prompt="$1"; shift
photo=""; seconds=4; size=""; steps=20; extra=(); tmp=""; cont=""
trap 'if [ -n "$tmp" ]; then rm -rf "$tmp"; fi' EXIT
tmp=$(mktemp -d)
if [ $# -gt 0 ] && [ -f "$1" ]; then photo="$1"; shift; fi
while [ $# -gt 0 ]; do
  case "$1" in
    --seconds)  seconds="$2"; shift 2 ;;
    --size)     size="$2"; shift 2 ;;
    --steps)    steps="$2"; shift 2 ;;
    --continue)
      if [ $# -gt 1 ] && [ -f "$2" ]; then cont="$2"; shift 2; else cont="latest"; shift; fi ;;
    --)         shift; extra=("$@"); break ;;
    *) echo "Unknown option: $1 (photo not found? extra sd-cli options go after --)"; exit 1 ;;
  esac
done

# --continue: start from the last frame of a previous clip, at the same size.
if [ -n "$cont" ]; then
  [ -z "$photo" ] || { echo "Use either a photo or --continue, not both."; exit 1; }
  if [ "$cont" = "latest" ]; then
    cont=$(ls -t "$DIR"/outputs/video_*.mp4 2>/dev/null | head -1)
    [ -n "$cont" ] || { echo "No previous video in outputs/ to continue from."; exit 1; }
  fi
  photo="$tmp/last_frame.png"
  ffmpeg -v error -sseof -1 -i "$cont" -update 1 -y "$photo" && [ -s "$photo" ] || { echo "Could not read the last frame of $cont"; exit 1; }
  echo "Continuing from the last frame of $(basename "$cont")"
fi

# iPhone photos: convert to JPEG first.
if [ -n "$photo" ]; then
  case "$(printf '%s' "$photo" | tr '[:upper:]' '[:lower:]')" in
    *.heic|*.heif)
      conv="$tmp/$(basename "${photo%.*}").jpg"
      sips -s format jpeg "$photo" --out "$conv" >/dev/null || { echo "Could not convert $photo"; exit 1; }
      photo="$conv" ;;
  esac
fi

# Size: a preset, or (with a photo) the photo's own proportions at the default pixel count.
case "$size" in
  16:9)   w=864;  h=480 ;;
  9:16)   w=480;  h=864 ;;
  square) w=640;  h=640 ;;
  hd)     w=1280; h=704 ;;
  "")
    w=864; h=480
    if [ -n "$photo" ]; then
      read -r pw ph < <(sips -g pixelWidth -g pixelHeight "$photo" | awk '/pixelWidth/{w=$2} /pixelHeight/{h=$2} END{print w, h}')
      read -r w h < <(awk -v pw="$pw" -v ph="$ph" 'BEGIN{a=864*480; r=pw/ph; printf "%d %d\n", int(sqrt(a*r)/32+0.5)*32, int(sqrt(a/r)/32+0.5)*32}')
    fi ;;
  *) echo "Unknown size '$size'. Use 16:9, 9:16, square or hd."; exit 1 ;;
esac

# 24 fps. H3 only accepts 17n+5 frames (56 = 2.3 s, 73 = 3 s, 90 = 3.75 s); pick the nearest instead of
# letting sd-cli round up. Long clips need a lot of memory.
frames=$(awk -v s="$seconds" 'BEGIN{n=int((s*24-5)/17+0.5); if (n < 1) n=1; print 17*n+5}')
if [ "$frames" -gt 192 ]; then
  echo "That's too long for this Mac: keep clips to 8 seconds or less and chain them with --continue."
  exit 1
fi

mkdir -p "$DIR/outputs"
out="$DIR/outputs/video_$(date +%Y-%m-%d_%H%M%S).mp4"
echo "Making a ${seconds}s ${w}x${h} video${photo:+ from $(basename "$photo")} -> outputs/$(basename "$out")"
start=$(date +%s)

args=(-M vid_gen --diffusion-model "$DIT" --llm "$LLM" --vae "$VAE" --audio-vae "$AVAE"
      -p "$prompt" --cfg-scale 1.0 --steps "$steps" -W "$w" -H "$h" --fps 24 --video-frames "$frames"
      --diffusion-fa --mmap --vae-tiling --params-backend "te=cpu,vae=cpu" --rng cpu -s -1 -o "$tmp/clip.avi")
# --mmap maps the weights straight from disk (Mac memory is shared). The guide's --offload-to-cpu is meant
# for separate graphics cards; on a Mac it doubles memory and floods swap. --params-backend keeps the text
# encoder and decoder weights off the GPU's ~38 GB budget so the video model has room to compute.
[ -n "$photo" ] && args+=(-i "$photo")
"$SD" "${args[@]}" ${extra[@]+"${extra[@]}"}

# Convert to a standard .mp4 (H.264 + AAC) that plays everywhere.
ffmpeg -v error -y -i "$tmp/clip.avi" -c:v libx264 -crf 17 -preset slow -pix_fmt yuv420p -c:a aac -b:a 192k \
  -movflags +faststart "$out"
echo "Done in $(( ($(date +%s) - start) / 60 )) min $(( ($(date +%s) - start) % 60 )) s"
open "$out"
