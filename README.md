# Local Image Generation — Qwen-Image-2.1 and MiniMax-H3

Alibaba's official **Qwen-Image-2.1** for images, running on this Mac with [mflux](https://github.com/filipstrand/mflux),
and **MiniMax-H3** for video with sound (see [Video with sound](#video-with-sound-minimax-h3)).
Everything runs offline: prompts, images and videos never leave the machine, and there is no content filter.

## Make an image

```bash
./generate.sh "a modern villa with an infinity pool at golden hour"
./generate.sh "aerial view of a waterfront apartment tower at dusk" 16:9
./generate.sh "minimal real-estate poster with the headline \"NOW LEASING\"" 3:4 --seed 7
```

Sizes: `square` (default, 1024×1024), `4:3`, `3:4`, `3:2`, `2:3`, `16:9`, `9:16`.
Add `hd` for the model's native 2K, for example `16:9hd` (about 4× slower).

## Start from a picture

**Edit: change something in the photo and keep the rest (`edit.sh`).** The model looks at the photo and follows a
plain-language instruction:

```bash
./edit.sh "replace the cloudy sky with a clear golden-hour sky" ~/Desktop/villa.jpg
./edit.sh "furnish this empty room with a modern grey sofa, a rug and plants" room.jpg
./edit.sh "place the sofa from image 1 in the living room of image 2" sofa.png room.jpg
./edit.sh "remove the cars" house.jpg -- --auto-mask "the cars on the driveway"
./edit.sh "warmer evening light" photo.jpg -- --strength 0.6
```

- Up to 10 pictures. The output takes the shape of the **last** one, so put the scene last.
- `--auto-mask "the sky"` changes only that object (the model finds it). `--mask-image mask.png` is pixel-exact
  (white = change, black = keep). You can also draw a red circle on the photo and say "remove what's circled in red".
- `--strength 0.6` makes subtler edits: **lower = closer to the original**.
- `--enhance-prompt` expands a short instruction; `--verify` checks the edit happened and retries if not.

**Restyle: a new image loosely based on yours (`generate.sh --image`).** Layout and colours carry over; everything
is redrawn from the prompt. The output keeps the photo's proportions.

```bash
./generate.sh "architect's watercolor sketch of a modern villa" --image villa.jpg 0.5
```

Here the number is how much of the original survives: **higher = closer** (default 0.4).

Options after `--` in `edit.sh` go straight to mflux. Results are saved in `outputs/` and open automatically.

## Turbo

Add `--turbo` to either script to use 6 steps instead of 40 (Viggle's distilled add-on, same license):

```bash
./generate.sh "a modern villa at golden hour" 16:9 --turbo
./edit.sh "make it a twilight shot with warm interior lights" villa.jpg --turbo
```

Slightly softer fine texture than the full 40 steps. Best with 1–3 pictures when editing.

## Speed on this Mac (M4 Pro, 48 GB)

Measured, for images of about 1 megapixel:

| | Full quality (40 steps) | `--turbo` (6 steps) |
|---|---|---|
| New image | about 10 min | about 2 min |
| Edit of one photo | not measured; expect longer | about 2.5 min |

Turbo is great for drafts and trying ideas; fine detail is a little softer and small structures can get muddled.
Switch it off for final images. The first run after a restart takes a minute or two longer while the model loads.

- **Several variations at once:** add `--auto-seeds 4`. The model loads only once.
- **Other speed-ups:** `--steps 25`, or `--step-cache-ratio 0.25` (about 1.4× faster, slightly less detail).
- **Before generating, quit Chrome and other heavy apps.** The model needs 24 GB+ of memory (editing needs more).
  Whatever doesn't fit is pushed into swap, a file on disk that macOS only clears when the Mac restarts. Keep at
  least 25 GB of disk free, and restart after a long session.

## Useful options

- `--seed 123` reproduces an image. Every image stores its seed and prompt in its metadata.
- `--negative-prompt "blurry, distorted" --guidance 2.5` gives stronger prompt adherence (about 2× slower).
- Put text you want in the image inside quotes and make it prominent; small text often comes out garbled.

## Video with sound (MiniMax-H3)

```bash
caffeinate -i ./video.sh "slow camera push-in, palm leaves swaying, water rippling in the pool" villa.jpg --seconds 2
./video.sh "the camera keeps moving through the garden to the front door" --continue --seconds 2
```

- With a photo, it becomes the first frame and the clip keeps the photo's proportions. iPhone photos work.
- `--seconds` (default 4, over 8 is refused), `--size 16:9 | 9:16 | square | hd`, `--steps` (default 20).
- **Longer videos:** chain shots with `--continue` (starts from the last frame of the newest video in `outputs/`,
  or `--continue some_clip.mp4`), then join the clips in an editor.
- Describe the motion and the sound. Saved as an .mp4 with stereo sound in `outputs/`.

**It is slow on this Mac.** Measured: a 2.3-second 640×640 clip took 87 minutes (about 79 s per step when memory
was free, much longer when it wasn't, plus 15 minutes to decode). A 4-second 864×480 clip runs at about 200 s per
step, so well over an hour. H3 only makes 17n+5 frames, so `--seconds` is rounded to the nearest of 2.3, 3, 3.75, 5.2,
5.9 or 8 s. Use short clips, quit Chrome and other heavy apps
first, restart the Mac now and then to clear swap, and start runs with `caffeinate -i` so the Mac doesn't sleep.

## What's where

| | |
|---|---|
| Model weights (33 GB, verified) | `~/.cache/huggingface` (shared Hugging Face cache) |
| mflux 0.21 and its Python environment | `.venv` in this folder |
| Video model, MiniMax-H3 4-bit + text encoder + decoders (43 GB, verified) | `models/h3` |
| Video tool ([stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp), MIT, built for Metal) | `sdcpp/` |
| Results | `outputs/` |

## Setting up from a fresh clone

Model weights, the Python environment, the video tool and results are not in git. To rebuild them:

```bash
uv sync
git clone https://github.com/leejet/stable-diffusion.cpp sdcpp
git -C sdcpp checkout a1ded76 && git -C sdcpp submodule update --init --recursive
cmake -S sdcpp -B sdcpp/build -DSD_METAL=ON && cmake --build sdcpp/build --config Release
```

Then download the video model files into `models/h3` (see the table above).

## License

Qwen-Image-2.1 is under the **Qwen Research License**: research and evaluation only.
Commercial use, including marketing material, needs a separate license from Alibaba (model-business@notice.qwencloud.com).

MiniMax-H3 (video) is under the **MiniMax H3 Community License**: not licensed for use in the EU, UK, South Korea or
USA; companies with over $20M yearly revenue need written permission from MiniMax, and commercial products must show
"MiniMax H3".

## Removing it

```bash
uv run hf cache rm model/Qwen/Qwen-Image-2.1
```

(Deleting the folder under `~/.cache/huggingface/hub` alone doesn't free the space: the data lives in a shared store.)

The video setup lives entirely in this folder: delete `models/` and `sdcpp/` to remove it (about 43 GB).

Then delete this folder.
