# Handoff: where this project stands (paused 2026-10-09)

The project is **paused**. On 2026-10-09 the model weights, the Python environment and the video tool were deleted to
free about 75 GB of disk for other work. The scripts, the README and this file are all you need to bring it back.
Nothing was lost that can't be downloaded again.

## Where we stopped

| Part | Status |
|---|---|
| Text-to-image (`generate.sh`) | Done and verified. Full quality ~10 min per 1024² image; `--turbo` ~2 min. |
| Image editing (`edit.sh`) | Done and verified. Turbo edit of one photo ~2.5 min, good result. Full 40-step edit not measured. |
| Video with sound (`video.sh`, MiniMax-H3) | Works, but too slow to be useful: a 2.3 s 640×640 clip took 87.6 min. People and anatomy were never tested. |
| Earlier video attempt (LTX-2.3 via ltx-2-mlx) | Replaced by MiniMax-H3 on 2026-10-08 for better human anatomy; removed then. |

**Open questions for next time**

1. Video is the weak point. The bar was "no use if it takes hours". Options: a smaller or faster video model, a
   cloud GPU for video only, or accept image-only locally.
2. Full-quality (40-step) editing speed was never measured.
3. Check whether there are newer mflux or stable-diffusion.cpp releases before re-installing; both move fast.

## What was deleted (and how big)

| What | Where it was | Size |
|---|---|---|
| Qwen-Image-2.1 official weights, revision `d26bb61231c349cf6b7896fa83353113880e1ba3` | `~/.cache/huggingface/hub/models--Qwen--Qwen-Image-2.1` | 33.1 GB |
| MiniMax-H3 video model + text encoder + decoders | `models/h3/` | 43 GB |
| stable-diffusion.cpp source + Metal build | `sdcpp/` | 0.8 GB |
| Python environment (mflux 0.21.0, Python 3.14) | `.venv/` | 1.1 GB |

The Viggle turbo add-on (LoRA) was already gone from the cache before this cleanup; re-download it (step 2 below).
Kept: `outputs/` (your images and videos, not in git) and the unrelated `Systran/faster-whisper-base` and
`Qwen/Qwen2.5-1.5B` cache entries, which belong to other projects.

## Bring it back

Machine it ran on: MacBook Pro M4 Pro, 48 GB memory. Tools already installed via Homebrew: `uv`, `ffmpeg`, `cmake`.

**Free disk needed:** about 35 GB for images only, about 80 GB with video, plus ~25 GB headroom for swap.
Check first with `df -h /` and `sysctl vm.swapusage`. Restart the Mac if swap is high.

### 1. Python environment (images)

```bash
cd ~/Desktop/"Local Image Generation"
uv sync
```

This recreates `.venv` with mflux 0.21.0 exactly as pinned in `uv.lock`.

### 2. Image model weights (~33 GB)

```bash
uv run hf download Qwen/Qwen-Image-2.1 --revision d26bb61231c349cf6b7896fa83353113880e1ba3
uv run hf download Viggle/Qwen-Image-2.1-viggle-turbo Qwen-Image-2.1-viggle-turbo-v0.3-6step-lora-r256.safetensors
```

If downloads keep dying on a flaky connection, prefix with `HF_HUB_DISABLE_XET=1` and re-run; it resumes.
Then test: `./generate.sh "a modern villa at golden hour" --turbo`.

### 3. Video (optional, ~43 GB)

```bash
git clone https://github.com/leejet/stable-diffusion.cpp sdcpp
git -C sdcpp checkout a1ded76da5818803fca97a3b433669ef727d32cf
git -C sdcpp submodule update --init --recursive
cmake -S sdcpp -B sdcpp/build -DCMAKE_BUILD_TYPE=Release -DSD_METAL=ON
cmake --build sdcpp/build --config Release -j
```

Model files, all into `models/h3/` (the two VAEs into `models/h3/vae/`):

| File | Source (Hugging Face) | Size |
|---|---|---|
| `minimax_h3_fl2va-Q4_K_M.gguf` | `leejet/MiniMax-H3-GGUF` | 18.8 GB |
| `qwen3vl_32b_minimax_h3-Q4_K_M.gguf` | `leejet/MiniMax-H3-GGUF` | 18.2 GB |
| `vae/minimax_h3_video_vae_fp16.safetensors` | `Comfy-Org/MiniMax-H3` | 5.2 GB |
| `vae/minimax_h3_audio_vae_fp32.safetensors` | `Comfy-Org/MiniMax-H3` | 0.6 GB |

```bash
uv run hf download leejet/MiniMax-H3-GGUF minimax_h3_fl2va-Q4_K_M.gguf qwen3vl_32b_minimax_h3-Q4_K_M.gguf --local-dir models/h3
uv run hf download Comfy-Org/MiniMax-H3 vae/minimax_h3_video_vae_fp16.safetensors vae/minimax_h3_audio_vae_fp32.safetensors --local-dir models/h3
```

Those are the exact paths the leejet example workflow links to. `video.sh` looks in `models/h3` (override with
`H3_MODELS=/path` and `H3_SDCLI=/path`).

## Lessons learned (don't rediscover these)

**Images (mflux)**
- Peak memory is ~24 GB and happens while the model loads, so `--low-ram` doesn't help (tested: same peak, same speed).
- mflux's `repo:file` LoRA syntax fails offline (`HF_HUB_OFFLINE=1`), so the scripts look up the LoRA's local
  cache path themselves.
- Quit Chrome before long runs: one edit was stopped when swap ballooned while Chrome used 7 GB on a Mac with
  31 days of uptime.

**Video (MiniMax-H3 via stable-diffusion.cpp)**
- Don't use `--offload-to-cpu` from the official guide. On a Mac (shared memory) it doubles memory use and flooded
  swap; the first run was killed. `--mmap` works and doesn't copy the weights.
- `--params-backend "te=cpu,vae=cpu"` keeps the text encoder and decoders off the GPU's ~38 GB budget, but makes the
  final decode slow (~15 min).
- H3 only accepts 17n+5 frames at 24 fps; `video.sh` rounds `--seconds` to the nearest valid length.
- Measured: ~79 s per step when memory was free; some steps spiked to 5–17 min from memory thrash.

**Downloads**
- Never give a whole repo id to a tool that calls `snapshot_download` (the LTX repo was 87 GB). Download named files.

## Licenses (unchanged)

Qwen-Image-2.1 and the Viggle add-on: Qwen Research License, **non-commercial** only. MiniMax-H3: MiniMax H3 Community
License, not licensed in the EU, UK, South Korea or USA. See the README. Only the scripts are in this repo, no weights.
