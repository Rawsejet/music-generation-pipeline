# ComfyUI Workflow Design - Phase 5

## Overview

This document describes the complete ComfyUI workflow for the automated music generation pipeline. The workflow connects all 5 stages from random attribute selection to YouTube upload.

---

## Build Progress

| Step | Stage | Status | Notes |
|------|-------|--------|-------|
| 1 | Stage 1: RandomPrompt | DONE | Wildcard randomization |
| 2 | Stage 2: LLM Nodes | DONE | API LLM Loader + API LLM general link + show_text_party |
| 3 | Stage 3A: ACE-Step Music | DONE | 6 nodes placed and wired |
| 4 | Stage 3B: FLUX.2 Image | DONE | UNETLoader + CLIPLoader + VAELoader + KSampler + VAEDecode + SaveImage |
| 5 | Stage 4: Video Assembly | DONE | VHS_LoadAudio + VHS_DuplicateImages + VHS_VideoCombine |
| 6 | Stage 5: YouTube Upload | DONE | 🔐 YouTube Auth + 🎬 YouTube Uploader |
| 7 | Wire all stages | DONE | JSON output + 3x JSON Get Value nodes + cross-stage tensor wiring |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│ Stage 1: Randomized Attribute Selection                             │
│ [RandomPrompt] - Loads wildcards and generates randomized prompt    │
└──────────────────────┬──────────────────────────────────────────────┘
                       ▼
┌─────────────────────────────────────────────────────────────────────┐
│ Stage 2: LLM Generation (Qwen3-32B via Ollama)                     │
│ [☁️API LLM Loader] → [☁️API LLM general link] → TAGS, LYRICS, IMAGE│
└──────────────────────┬──────────────┬─────────────────┬─────────────┘
                       ▼              ▼                   ▼
        ┌──────────────────┐ ┌───────────────┐ ┌──────────────────────┐
        │ Stage 3A: Music  │ │Stage 3B: Image│ │Stage 3C: Metadata    │
        │ (ACE-Step 1.5)   │ │ (FLUX.2 Dev)  │ │ (YouTube Metadata)   │
        └────────┬─────────┘ └───────┬────────┘ └──────────────────────┘
                 ▼                   ▼
        ┌──────────────────────────────────────────┐
        │ Stage 4: Video Assembly                  │
        │ [VHS_DuplicateImages] + [VHS_VideoCombine]│
        └──────────────────┬───────────────────────┘
                           ▼
        ┌──────────────────────────────────────────┐
        │ Stage 5: YouTube Upload                  │
        │ [YouTubeUploaderNode]                    │
        └──────────────────────────────────────────┘
```

---

## Node Connections

### Stage 1: Random Prompt Generation
| Node | Type | Parameters | Output |
|------|------|------------|--------|
| `RandomPrompt` | `RandomPrompt` | Text: `"__genres__, __moods__, __vocals__, __instruments__, __tempos__, __decades__ style, __production__ production, theme: __themes__"` | Randomized attribute string |

### Stage 2: LLM Processing
| Node | Search For | Parameters | Output |
|------|------------|------------|--------|
| `☁️API LLM Loader` | "API LLM Loader" | Model: `qwen3-gpu1:latest`, base_url: `http://localhost:11434/v1/`, is_ollama: `true` | LLM model object |
| `☁️API LLM general link` | "API LLM general" | System prompt (see below), temperature: 0.85, max_length: 2048 | JSON response with tags, lyrics, image_prompt |
| `show_text_party` | "show_text" | Wired from LLM assistant_response output | Preview text in UI |

**Note**: top_p, top_k, repeat_penalty are NOT on this node. Set them in an Ollama Modelfile if needed.

**LLM System Prompt:**
```
You are a professional songwriter and music director creating content for the
ACE-Step AI music generation model. Given musical attributes, generate a JSON
object with exactly three keys: "tags", "lyrics", and "image_prompt".

Output ONLY the raw JSON object. No markdown, no code blocks, no explanation.

"tags": A comma-separated string describing the overall music style for ACE-Step.
Include genre, sub-genre, mood, vocal type, instruments, BPM, production style.
Example: "indie pop, female vocals, dreamy, acoustic guitar, soft drums, 95 bpm"

"lyrics": Full song lyrics as a single string with \n for line breaks.
Use section markers on their own lines:
[Verse 1], [Verse 2], [Chorus], [Pre-Chorus], [Bridge], [Outro], [Intro]
Optional performance hints: [Chorus - anthemic], [Bridge - whispered]

SYLLABLE RULES (CRITICAL for beat alignment):
- Every lyric line MUST contain 6-10 syllables
- Lines within the same section must have similar counts (±2 max)
- Count syllables carefully before writing each line

STRUCTURE:
- 4-6 lines per verse, 2-4 lines per chorus, 2-4 lines per bridge
- Default: [Verse 1] -> [Chorus] -> [Verse 2] -> [Chorus] -> [Bridge] -> [Chorus] -> [Outro]
- Use ABAB or ABCB rhyme scheme for verses, AABB or ABAB for chorus
- Prefer open vowel sounds at line endings for vocal sustain
- (Parenthetical text) = background vocals (use sparingly)

"image_prompt": A vivid, detailed visual scene description for album artwork.
Describe composition, lighting, color palette, mood, and artistic style.
Do not reference text, words, or typography in the image.

Match the genre, mood, and theme provided. Everything must feel cohesive.
```

**LLM User Prompt Template:**
```
Create a song with these parameters:
- Genre: {genre}
- Mood: {mood}
- Theme: {theme}
- BPM: {bpm}
- Vocal type: {vocal_type}
- Instruments: {instruments}
- Decade influence: {decade}
- Production style: {production}
```

### Stage 2→3: JSON Parsing (text splitting)
| Node | Type | Parameters | Output |
|------|------|------------|--------|
| `JSON Get Value🐶` (tags) | `json_get_value` | text: from LLM assistant_response, key: `tags` | Tags string → TextEncodeAceStepAudio1.5[tags] |
| `JSON Get Value🐶` (lyrics) | `json_get_value` | text: from LLM assistant_response, key: `lyrics` | Lyrics string → TextEncodeAceStepAudio1.5[lyrics] |
| `JSON Get Value🐶` (image_prompt) | `json_get_value` | text: from LLM assistant_response, key: `image_prompt` | Image prompt string → CLIPTextEncode[text] |

### Stage 3A: Music Generation (scromfyUI-AceStep 1.5) ✅ DONE
**Migration**: Upgraded from ACE-Step AIO checkpoint to scromfyUI-AceStep with 5Hz LLM planner

| Node | Type | Parameters | Output |
|------|------|------------|--------|
| `AceStep5HzLMConfig` | `AceStep5HzLMConfig` | shift: 3.0, llm_audio_codes: true | LLM config |
| `ScromfyACEStep15TaskTextEncodeNode` | `ScromfyACEStep15TaskTextEncodeNode` | Tags: (from JSON), Lyrics: (from JSON), clip: from VAE, llm_config: from AceStep5HzLMConfig | TASK |
| `EmptyAceStepAudio` | `EmptyAceStepAudio` | seconds: 180, batch_size: 1 | Latent audio |
| `AceStepDiffusionSampler` | `AceStepDiffusionSampler` | model: from TASK, task: from TASK, latent: from Empty, cfg_scale: 2.0, steps: 8, denoise: 1.0 | Latent audio |
| `VAEDecodeAudio` | `VAEDecodeAudio` | Samples: from AceStepDiffusionSampler, VAE: from Scromfy node | Audio tensor |
| `SaveAudio` | `SaveAudio` | Audio: from VAE, Filename: `ace_step_output` | Saved .wav file |
| `PreviewAudio` | `PreviewAudio` | Audio: from VAE | Audio preview in UI |

**Key Parameters (scromfyUI-AceStep)**:
- `shift`: 3.0 (default: 3.0, controls generation speed/quality)
- `llm_audio_codes`: true (enables LLM-guided audio generation)
- `cfg_scale`: 2.0 (classifier-free guidance)
- `steps`: 8 (sampling steps)
- `denoise`: 1.0 (full denoising)

### Stage 3B: Image Generation (FLUX.2 Dev) ✅ DONE
FLUX.2 Dev uses separate loaders (NOT CheckpointLoaderSimple):

| Node | Type | Parameters | Output |
|------|------|------------|--------|
| `UNETLoader` | `UNETLoader` | unet_name: `flux2-dev.safetensors` | MODEL |
| `CLIPLoader` | `CLIPLoader` | clip_name: `mistral_3_small_flux2_fp8.safetensors` | CLIP |
| `VAELoader` | `VAELoader` | vae_name: `flux2-vae.safetensors` | VAE |
| `CLIPTextEncode` | `CLIPTextEncode` | clip: from CLIPLoader, Text: (from LLM IMAGE_PROMPT) | Conditioning |
| `EmptyLatentImage` | `EmptyLatentImage` | width: 1920, height: 1080, batch: 1 | Latent |
| `KSampler` | `KSampler` | model: from UNETLoader, positive: from CLIPTextEncode, latent: from EmptyLatentImage, Steps: 20, CFG: 7.5, Sampler: euler, Scheduler: simple | Latent image |
| `VAEDecode` | `VAEDecode` | samples: from KSampler, vae: from VAELoader | Image tensor |
| `SaveImage` | `SaveImage` | images: from VAEDecode, Filename: `album_art` | Saved .png file |

**Model files** (in `ComfyUI/models/`):
- `diffusion_models/flux2-dev.safetensors` (64.4 GB) — from `black-forest-labs/FLUX.2-dev`
- `text_encoders/mistral_3_small_flux2_fp8.safetensors` (~12 GB) — from `Comfy-Org/flux2-dev`
- `vae/flux2-vae.safetensors` (336 MB) — from `Comfy-Org/flux2-dev`

### Stage 4: Video Assembly
| Node | Type | Parameters | Output |
|------|------|------------|--------|
| `VHS_DuplicateImages` | `VHS_DuplicateImages` | Images: from VAEDecode (FLUX.2 album art), Multiply by: 5400 (180s × 30fps) | Video frames |
| `VHS_VideoCombine` | `VHS_VideoCombine` | Images: from VHS_DuplicateImages, Audio: from VAEDecodeAudio (ACE-Step), Format: video/h264-mp4, FPS: 30, CRF: 18-20, Pixel format: yuv420p | MP4 video |

**Note**: `LoadImage` and `VHS_LoadAudio` are no longer needed — audio and images flow directly as tensors from Stage 3.
### Stage 5: YouTube Upload
| Node | Type | Parameters | Output |
|------|------|------------|--------|
| `🔐 YouTube Auth` | `YouTubeAuthNode` | client_id: (from Google Cloud Console), client_secret: (from Google Cloud Console), authenticate_now: `true` | authenticated (BOOLEAN), channel_info (STRING) |
| `🎬 YouTube Uploader` | `YouTubeUploaderNode` | video: IMAGE (from VHS_DuplicateImages), audio: AUDIO (from VAEDecodeAudio), thumbnail: IMAGE (from VAEDecode), title: (auto-generated), description: (auto-generated), tags: (auto-generated), privacy: `private`, fps: `30`, upload_enabled: `false` | video_id (STRING), upload_url (STRING), success (BOOLEAN) |

**Important**: The uploader expects IMAGE tensors (video frames), not an MP4 file. It internally encodes frames to MP4 via OpenCV, then mixes audio via ffmpeg.

---

## Node Details

### RandomPrompt (comfyui-dynamicprompts)
- **Category**: Dynamic Prompts
- **Purpose**: Randomly selects wildcard values from text files
- **Wildcard files location**: `ComfyUI/custom_nodes/comfyui-dynamicprompts/wildcards/`

### ☁️API LLM Loader (comfyui_LLM_party)
- **Search for**: "API LLM Loader"
- **Class**: `LLM_api_loader`
- **Parameters**:
  - Model name: `qwen3-gpu1:latest`
  - Base URL: `http://localhost:11434/v1/`
  - is_ollama: `true` (checkbox)

### ☁️API LLM general link (comfyui_LLM_party)
- **Search for**: "API LLM general"
- **Class**: `LLM`
- **Available Parameters**:
  - temperature: 0.85 (FLOAT, 0.0-1.0)
  - max_length: 2048 (INT, 256-128000, equivalent of num_predict)
  - is_memory: enable/disable
  - system_prompt: multiline text
  - user_prompt: multiline text
  - user_prompt_input: optional, wired from RandomPrompt
- **NOT available on node** (set via Ollama Modelfile instead):
  - top_p, top_k, repeat_penalty

### TextEncodeAceStepAudio1.5 (built-in)
- **Category**: ACE-Step
- **Purpose**: Encodes music tags and lyrics for ACE-Step generation
- **Parameters**:
  - Clip: From checkpoint loader
  - Tags: Music style description (comma-separated)
  - Lyrics: Song lyrics with section markers

### EmptyAceStep1.5LatentAudio (built-in)
- **Category**: ACE-Step
- **Purpose**: Creates initial latent space for audio generation
- **Parameters**:
  - Seconds: 180 (3 minutes default)
  - Batch size: 1 (or up to 8 for batch generation)

### JSON Get Value🐶 (comfyui_LLM_party)
- **Search for**: "JSON Get Value"
- **Class**: `json_get_value`
- **Category**: 大模型派对（llm_party）/转换器（converter）
- **Purpose**: Extracts a value from a JSON string by key
- **Parameters**:
  - text: STRING (forceInput — must be wired, not typed)
  - key: STRING (the JSON key to extract, e.g. `tags`, `lyrics`, `image_prompt`)
  - is_enable: BOOLEAN (default: true)
- **Output**: any (the extracted value — string, list, or dict)
- **Usage**: Wire LLM `assistant_response` → `text` input. Set `key` to desired field. Output goes to downstream node.
- **Note**: Do NOT use `json_extractor` (JSON Repair🐶) upstream — it destroys `\n` and backslashes in valid JSON. Wire LLM output directly to this node.

### VHS_VideoCombine (VideoHelperSuite)
- **Category**: Video Helper Suite
- **YouTube-Optimized Settings**:
  - Format: `video/h264-mp4`
  - Frame rate: 30 fps
  - Pixel format: `yuv420p`
  - CRF: 18-20 (high quality)
  - Resolution: 1920×1080 (16:9)

### 🔐 YouTube Auth (ComfyUI-YouTubeUploader)
- **Search for**: "YouTube Auth"
- **Class**: `YouTubeAuthNode`
- **Category**: YouTube/Auth
- **Parameters**:
  - client_id: STRING (from Google Cloud Console OAuth 2.0 credentials)
  - client_secret: STRING (from Google Cloud Console OAuth 2.0 credentials)
  - authenticate_now: BOOLEAN (triggers browser OAuth flow)
- **Outputs**: authenticated (BOOLEAN), channel_info (STRING)
- **Token storage**: `token.pickle` in `ComfyUI/custom_nodes/ComfyUI-YouTubeUploader/`
- **API scopes**: `youtube.upload`, `youtube.readonly`

### 🎬 YouTube Uploader (ComfyUI-YouTubeUploader)
- **Search for**: "YouTube Uploader"
- **Class**: `YouTubeUploaderNode`
- **Category**: YouTube/Upload
- **Required Parameters**:
  - video: IMAGE tensor (video frames, shape N×H×W×C)
  - title: STRING (default: "My Awesome Short #1")
  - description: STRING (multiline)
  - tags: STRING (comma-separated)
  - privacy: `private` | `unlisted` | `public`
  - fps: INT (1-60, default: 30)
  - upload_enabled: BOOLEAN (default: false — safety toggle)
- **Optional Parameters**:
  - audio: AUDIO (mixed into video via ffmpeg)
  - thumbnail: IMAGE (auto-resized to JPEG)
- **Outputs**: video_id (STRING), upload_url (STRING), success (BOOLEAN)
- **OUTPUT_NODE**: true (terminal node)
- **Dependencies**: google-api-python-client, opencv-python, ffmpeg (system), scipy, Pillow

---

## GPU Allocation

| GPU | Components | VRAM Usage |
|-----|------------|------------|
| GPU 0 | ComfyUI (ACE-Step, image gen, video) | ACE-Step: ~4GB; Image gen: ~20-54GB |
| GPU 1 | Ollama (Qwen3-32B LLM) | ~19-65GB depending on quantization |

**Configuration**:
- Ollama: Already configured to use GPU 1 via model setup
- ComfyUI: Uses default GPU assignment (GPU 0)

---

## Output Files

| Stage | Output | Location |
|-------|--------|----------|
| Music | `ace_step_output.wav` | `ComfyUI/output/` |
| Image | `album_art.png` | `ComfyUI/output/` |
| Video | `output_video.mp4` | `ComfyUI/output/` |

---

## Workflow Execution Order

1. **Stage 1**: RandomPrompt generates attribute string
2. **Stage 2**: LLM processes attributes and outputs JSON with tags, lyrics, image_prompt
3. **JSON parsing**: 3x JSON Get Value nodes extract each key and route to Stage 3A/3B
4. **Stage 3A**: Music generation runs concurrently with Stage 3B
5. **Stage 3B**: Image generation runs concurrently with Stage 3A
5. **Stage 4**: Video assembly waits for music and image outputs
6. **Stage 5**: YouTube upload waits for video completion

---

## Text Extraction Strategy — JSON + json_get_value

The LLM outputs a single JSON string with keys `tags`, `lyrics`, and `image_prompt`. Three `JSON Get Value🐶` nodes (from comfyui_LLM_party) extract each key and route it to the appropriate downstream node.

```
LLM[assistant_response] → JSON_Get_Value(key="tags")          → TextEncodeAceStepAudio1.5[tags]
LLM[assistant_response] → JSON_Get_Value(key="lyrics")        → TextEncodeAceStepAudio1.5[lyrics]
LLM[assistant_response] → JSON_Get_Value(key="image_prompt")  → CLIPTextEncode[text]
```

**Why `json_get_value` directly (not `json_extractor`):** The `json_extractor` node (JSON Repair🐶) has a bug — it replaces all `\n` and backslashes with spaces even on valid JSON input, which destroys lyrics line breaks. `json_get_value` does a clean `json.loads()` → `data[key]` with no destructive transforms, preserving newlines in lyrics.

---

## Testing Checklist

- [ ] Ollama is running and accessible at `http://localhost:11434`
- [ ] `qwen3-gpu1:latest` model is loaded in Ollama
- [ ] `ace_step_1.5_turbo_aio.safetensors` is in `ComfyUI/models/checkpoints/`
- [ ] Wildcard files exist in `custom_nodes/comfyui-dynamicprompts/wildcards/`
- [ ] All custom nodes are installed (LLM_party, VideoHelperSuite, YouTubeUploader)
- [ ] YouTube API credentials are configured (for Stage 5)

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| LLM returns empty response | Check Ollama is running, model is loaded, and prompt is not too long |
| ACE-Step generates silence | Check tags and lyrics are properly formatted, try increasing CFG |
| Video has no audio | Verify audio file path in VHS_LoadAudio |
| YouTube upload fails | Check OAuth credentials, API quota, and video file format |

---

## Future Enhancements

1. **Metadata Generation Node**: Auto-generate YouTube title/description from music tags
2. **Thumbnail Generation**: Create thumbnails from album art using image manipulation
3. **Batch Processing**: Generate multiple song variants and select best one
4. **Queue System**: Auto-trigger next generation when previous completes
5. **Error Recovery**: Auto-retry failed generations with different seeds

---

## Manual Workflow Creation Guide

### Prerequisites Checklist

Before building the workflow, ensure:
- [ ] Ollama is running at `http://localhost:11434`
- [ ] `qwen3-gpu1:latest` model is loaded: `ollama pull qwen3-gpu1:latest`
- [ ] `ace_step_1.5_turbo_aio.safetensors` is in `ComfyUI/models/checkpoints/`
- [ ] Wildcard files exist in `ComfyUI/custom_nodes/comfyui-dynamicprompts/wildcards/`
- [ ] Custom nodes installed: `comfyui_LLM_party`, `ComfyUI-VideoHelperSuite`, `ComfyUI-YouTubeUploader`, `comfyui-dynamicprompts`
- [ ] Restart ComfyUI after installing new nodes

---

### Step-by-Step Node Setup

#### Step 1: Add RandomPrompt Node (Stage 1) ✅ DONE

1. Open ComfyUI web interface
2. Right-click on canvas → **Add Node** → Search for `RandomPrompt`
3. Select `RandomPrompt` from `comfyui-dynamicprompts`
4. Double-click to edit:
   - **Text**: `__genres__, __moods__, __vocals__, __instruments__, __tempos__, __decades__ style, __production__ production, theme: __themes__`
   - **Seed**: `0` (for random each time)
   - **Auto Refresh**: `No`
5. This node will now generate randomized attributes on each execution

#### Step 2: Add LLM Nodes (Stage 2) ✅ DONE

1. **Add ☁️API LLM Loader**:
   - Search for `API LLM Loader`
   - Configure:
     - `model`: `qwen3-gpu1:latest`
     - `base_url`: `http://localhost:11434/v1/`
     - `is_ollama`: `true` (checkbox)

2. **Add ☁️API LLM general link**:
   - Search for `API LLM general`
   - Connect `model` input from ☁️API LLM Loader
   - Connect `user_prompt_input` from RandomPrompt output
   - **System Prompt** (paste this entire block):
   ```
   You are a professional songwriter and music director creating content for the
   ACE-Step AI music generation model. Given musical attributes, generate THREE
   outputs separated by these exact markers:

   === TAGS ===
   A comma-separated tag string describing the overall music style for ACE-Step.
   Include genre, sub-genre, mood, vocal type, instruments, BPM, production style.
   Example: "indie pop, female vocals, dreamy, acoustic guitar, soft drums, 95 bpm"

   === LYRICS ===
   Full song lyrics with section markers on their own lines:
   [Verse 1], [Verse 2], [Chorus], [Pre-Chorus], [Bridge], [Outro], [Intro]
   Optional performance hints: [Chorus - anthemic], [Bridge - whispered]

   SYLLABLE RULES (CRITICAL for beat alignment):
   - Every lyric line MUST contain 6-10 syllables
   - Lines within the same section must have similar counts (±2 max)
   - Count syllables carefully before writing each line

   STRUCTURE:
   - 4-6 lines per verse, 2-4 lines per chorus, 2-4 lines per bridge
   - Default: [Verse 1] -> [Chorus] -> [Verse 2] -> [Chorus] -> [Bridge] -> [Chorus] -> [Outro]
   - Use ABAB or ABCB rhyme scheme for verses, AABB or ABAB for chorus
   - Prefer open vowel sounds at line endings for vocal sustain
   - (Parenthetical text) = background vocals (use sparingly)

   === IMAGE_PROMPT ===
   A vivid, detailed visual scene description for album artwork generation.
   Describe composition, lighting, color palette, mood, and artistic style.
   Do not reference text, words, or typography in the image.

   Output ONLY these three sections. No explanations or commentary.
   Match the genre, mood, and theme provided. Everything must feel cohesive.
   ```
   - **Parameters**:
     - temperature: `0.85`
     - max_length: `2048`
   - **Note**: top_p, top_k, repeat_penalty are NOT on this node

3. **Add show_text_party** (to preview output):
   - Connect from LLM's `assistant_response` output
   - This displays the full LLM response in the UI

#### Step 3: Add Checkpoint Loader (Stage 3) ✅ DONE

1. **Add CheckpointLoaderSimple**:
   - Search for `CheckpointLoaderSimple`
   - **Checkpoint Name**: `ace_step_1.5_turbo_aio.safetensors`
   - This provides MODEL, CLIP, and VAE outputs

#### Step 4: Add Music Generation Nodes (Stage 3A) ✅ DONE

1. **Add EmptyAceStep1.5LatentAudio**:
   - Search for `EmptyAceStep1.5LatentAudio`
   - **Seconds**: `180`
   - **Batch size**: `1`

2. **Add TextEncodeAceStepAudio1.5**:
   - Search for `TextEncodeAceStepAudio1.5`
   - Connect `clip` from CheckpointLoaderSimple
   - **Tags field**: Paste TAGS from LLM output (e.g., `lofi, chill, female vocal, piano, 90 bpm`)
   - **Lyrics field**: Paste LYRICS from LLM output (with `[Verse]`, `[Chorus]` markers)

3. **Add KSampler**:
   - Search for `KSampler`
   - Connect `model` from CheckpointLoaderSimple
   - Connect `positive` from TextEncodeAceStepAudio1.5
   - **Steps**: `8`
   - **CFG**: `1`
   - **Sampler**: `res_multistep`
   - **Scheduler**: `simple`

4. **Add VAEDecodeAudio**:
   - Search for `VAEDecodeAudio`
   - Connect `samples` from KSampler
   - Connect `vae` from CheckpointLoaderSimple

5. **Add SaveAudio**:
   - Search for `SaveAudio`
   - Connect `audio` from VAEDecodeAudio
   - **Filename prefix**: `ace_step_output`
   - **Format**: `wav`

6. **Add PreviewAudio** (optional, for testing):
   - Connect from VAEDecodeAudio output
   - Allows audio playback in browser

#### Step 5: Add Image Generation Nodes (Stage 3B) ✅ DONE

FLUX.2 Dev uses separate loaders, NOT CheckpointLoaderSimple:

1. **Add UNETLoader**:
   - Search for `UNETLoader`
   - **unet_name**: `flux2-dev.safetensors`

2. **Add CLIPLoader**:
   - Search for `CLIPLoader`
   - **clip_name**: `mistral_3_small_flux2_fp8.safetensors`

3. **Add VAELoader**:
   - Search for `VAELoader`
   - **vae_name**: `flux2-vae.safetensors`

4. **Add CLIPTextEncode**:
   - Search for `CLIPTextEncode`
   - Connect `clip` from CLIPLoader
   - **Text field**: Paste IMAGE_PROMPT from LLM output

5. **Add EmptyLatentImage**:
   - Search for `EmptyLatentImage`
   - **width**: `1920`
   - **height**: `1080`
   - **batch_size**: `1`

6. **Add KSampler** (for image gen):
   - Search for `KSampler`
   - Connect `model` from UNETLoader
   - Connect `positive` from CLIPTextEncode
   - Connect `latent_image` from EmptyLatentImage
   - **Steps**: `20`
   - **CFG**: `7.5`
   - **Sampler**: `euler`
   - **Scheduler**: `simple`

7. **Add VAEDecode**:
   - Search for `VAEDecode`
   - Connect `samples` from KSampler
   - Connect `vae` from VAELoader

8. **Add SaveImage**:
   - Search for `SaveImage`
   - Connect `images` from VAEDecode
   - **Filename prefix**: `album_art`

#### Step 6: Add Video Assembly Nodes (Stage 4)

**Note**: `LoadImage` and `VHS_LoadAudio` are no longer needed — audio and images flow directly as tensors from Stage 3. If you previously placed these nodes, you can delete them.

1. **Add VHS_DuplicateImages**:
   - Search for `VHS_DuplicateImages`
   - Connect `images` from `VAEDecode` (FLUX.2 album art output)
   - **Multiply by**: `5400` (for 180 seconds × 30 fps)

4. **Add VHS_VideoCombine**:
   - Search for `VHS_VideoCombine`
   - Connect `images` from VHS_DuplicateImages
   - Connect `audio` from `VAEDecodeAudio` (ACE-Step audio output)
   - **Frame rate**: `30`
   - **Format**: `video/h264-mp4`
   - **Save output**: `true`
   - **Filename prefix**: `output_video`

#### Step 7: Add YouTube Upload Nodes (Stage 5) ✅ DONE

**Prerequisites — OAuth 2.0 Setup:**
1. Go to https://console.cloud.google.com/
2. Create a project → Enable **YouTube Data API v3**
3. Create **OAuth 2.0 credentials** (type: Desktop application)
4. Download the credentials JSON — you need the `client_id` and `client_secret`
5. Alternatively, place the downloaded file as `client_secret.json` in `ComfyUI/custom_nodes/ComfyUI-YouTubeUploader/`

**Node 1 — Add 🔐 YouTube Auth:**
1. Search for `YouTube Auth`
2. Configure:
   - **client_id**: (paste from Google Cloud Console)
   - **client_secret**: (paste from Google Cloud Console)
   - **authenticate_now**: `true` (triggers browser OAuth flow on first run)
3. On first execution, a browser window opens for Google sign-in
4. After auth, a `token.pickle` file is saved in the node directory for reuse

**Node 2 — Add 🎬 YouTube Uploader:**
1. Search for `YouTube Uploader`
2. Connect inputs:
   - **video** (IMAGE): from `VHS_DuplicateImages` output (the repeated album art frames)
   - **audio** (AUDIO, optional): from `VAEDecodeAudio` output (ACE-Step audio)
   - **thumbnail** (IMAGE, optional): from `VAEDecode` output (FLUX.2 album art image)
3. Configure parameters:
   - **title**: (wired from metadata generation, or placeholder like `AI Generated Song`)
   - **description**: (wired from metadata generation)
   - **tags**: `music,ai,comfyui,ace-step`
   - **privacy**: `private` (start with private for testing, switch to `public` later)
   - **fps**: `30`
   - **upload_enabled**: `false` (safety toggle — set to `true` only when ready to upload)
4. Outputs:
   - **video_id**: YouTube video ID string
   - **upload_url**: Full `https://www.youtube.com/watch?v=...` URL
   - **success**: Boolean upload status

**How the uploader works internally:**
- Receives IMAGE tensor frames → converts to NumPy arrays → encodes to temporary MP4 via OpenCV
- If audio is connected, mixes it into the MP4 via ffmpeg (ffmpeg must be installed)
- Thumbnail tensor is converted to JPEG and uploaded separately via YouTube API
- All temporary files are cleaned up after upload

**Important notes:**
- `upload_enabled` defaults to `false` — this is a safety feature to prevent accidental uploads during testing
- A single image input (3D tensor) is automatically repeated for 3 seconds at the specified FPS
- Width and height must be even numbers (auto-adjusted if needed)
- The node is an OUTPUT_NODE (terminal node in the graph)

#### Step 8: Wire All Stages Together (JSON Parsing)

**Part A — Update the LLM system prompt:**

In the `☁️API LLM general link` node, replace the system prompt with the JSON version (see "LLM System Prompt" in the Node Connections section above). The key change: output is now a raw JSON object `{"tags": "...", "lyrics": "...", "image_prompt": "..."}` instead of `=== MARKER ===` separated sections.

**Part B — Add 3x `JSON Get Value🐶` nodes:**

1. Search for `JSON Get Value` (display name: "JSON Get Value🐶", class: `json_get_value`)
2. Add **3 instances**, each wired from the LLM `assistant_response` output:

| Node instance | key | Wire output to |
|---------------|-----|---------------|
| JSON Get Value (tags) | `tags` | `TextEncodeAceStepAudio1.5` → **tags** field |
| JSON Get Value (lyrics) | `lyrics` | `TextEncodeAceStepAudio1.5` → **lyrics** field |
| JSON Get Value (image_prompt) | `image_prompt` | `CLIPTextEncode` → **text** field (FLUX.2) |

3. For each node:
   - Connect **text** input from `☁️API LLM general link` → `assistant_response` output
   - Set **key** to the appropriate key name
   - Leave **is_enable** as `true`
4. Connect each node's **any** output to its downstream destination

**Why NOT `json_extractor` (JSON Repair🐶):** That node has a bug — it replaces all `\n` and `\` characters with spaces even on valid JSON, which destroys lyrics line breaks. `json_get_value` does a clean `json.loads()` → `data[key]`, preserving newlines.

**Part C — Wire remaining cross-stage connections:**

The existing Stage 4 nodes (`LoadImage`, `VHS_LoadAudio`) were placeholders that load files from disk. In the fully wired pipeline, audio and images flow directly as tensors from Stage 3 — no intermediate files needed.

**Changes to make:**

1. **Remove `LoadImage` node** — it's no longer needed
   - Instead, wire `VAEDecode[images]` (FLUX.2 output) → `VHS_DuplicateImages[images]`

2. **Remove `VHS_LoadAudio` node** — it's no longer needed
   - Instead, wire `VAEDecodeAudio[audio]` (ACE-Step output) → `VHS_VideoCombine[audio]`

3. **Wire Stage 4 → Stage 5 (YouTube Upload):**
   - `VHS_DuplicateImages[images]` → `YouTubeUploaderNode[video]` (repeated album art frames)
   - `VAEDecodeAudio[audio]` → `YouTubeUploaderNode[audio]` (ACE-Step music)
   - `VAEDecode[images]` → `YouTubeUploaderNode[thumbnail]` (single album art image)

**Summary of cross-stage data flow:**
```
VAEDecode (FLUX.2 album art) ──→ VHS_DuplicateImages ──→ VHS_VideoCombine ──→ SaveVideo
                            └──→ YouTubeUploaderNode[thumbnail]     ↑
                                                                     │
VAEDecodeAudio (ACE-Step) ─────→ VHS_VideoCombine[audio] ───────────┘
                            ├──→ YouTubeUploaderNode[audio]
                            ├──→ SaveAudio
                            └──→ PreviewAudio

VHS_DuplicateImages ────────────→ YouTubeUploaderNode[video]
```

---

### Wiring the Workflow

After adding all nodes, connect them:

```
Stage 1:
RandomPrompt[0] -> LLM[user_prompt_input]

Stage 2:
☁️API_LLM_Loader[0] -> ☁️API_LLM_general_link[model]

Stage 3A (ACE-Step - uses CheckpointLoaderSimple):
CheckpointLoaderSimple[MODEL] -> KSampler_audio[model]
CheckpointLoaderSimple[CLIP] -> TextEncodeAceStepAudio1.5[clip]
CheckpointLoaderSimple[VAE] -> VAEDecodeAudio[vae]

RandomPrompt[0] -> ☁️API_LLM_general_link[user_prompt_input]
LLM[assistant_response] -> show_text_party[text]

Stage 2 → 3 (JSON parsing - 3x JSON Get Value🐶 nodes):
LLM[assistant_response] -> JSON_Get_Value_tags[text]      (key="tags")
LLM[assistant_response] -> JSON_Get_Value_lyrics[text]    (key="lyrics")
LLM[assistant_response] -> JSON_Get_Value_image[text]     (key="image_prompt")
JSON_Get_Value_tags[any]    -> TextEncodeAceStepAudio1.5[tags]
JSON_Get_Value_lyrics[any]  -> TextEncodeAceStepAudio1.5[lyrics]
JSON_Get_Value_image[any]   -> CLIPTextEncode[text]

EmptyAceStep1.5LatentAudio[0] -> KSampler_audio[latent_image]
TextEncodeAceStepAudio1.5[0] -> KSampler_audio[positive]

KSampler_audio[0] -> VAEDecodeAudio[samples]
VAEDecodeAudio[0] -> SaveAudio[audio]
VAEDecodeAudio[0] -> PreviewAudio[audio]

Stage 3B (FLUX.2 Dev - uses separate loaders):
UNETLoader[MODEL] -> KSampler_image[model]
CLIPLoader[CLIP] -> CLIPTextEncode[clip]
VAELoader[VAE] -> VAEDecode[vae]
EmptyLatentImage[0] -> KSampler_image[latent_image]
CLIPTextEncode[0] -> KSampler_image[positive]
KSampler_image[0] -> VAEDecode[samples]
VAEDecode[0] -> SaveImage[images]

Stage 4 (cross-stage wiring — no LoadImage or VHS_LoadAudio needed):
VAEDecode[0] -> VHS_DuplicateImages[images]              (FLUX.2 album art → video frames)
VAEDecodeAudio[0] -> VHS_VideoCombine[audio]              (ACE-Step audio → video)
VHS_DuplicateImages[0] -> VHS_VideoCombine[images]

Stage 5 (YouTube Upload - takes IMAGE frames + AUDIO, NOT the MP4):
VHS_DuplicateImages[0] -> YouTubeUploaderNode[video]    (IMAGE tensor frames)
VAEDecodeAudio[0] -> YouTubeUploaderNode[audio]          (AUDIO from ACE-Step)
VAEDecode[0] -> YouTubeUploaderNode[thumbnail]            (IMAGE from FLUX.2)
```

**Note**: The LLM outputs JSON, which is parsed by 3x `JSON Get Value🐶` nodes to route tags, lyrics, and image_prompt to their respective downstream nodes automatically.

---

### Running the Workflow

1. **Save the workflow** (Ctrl+S) before running
2. Click **Queue Prompt** (Ctrl+Enter)
3. Monitor the console for progress
4. After completion, check `ComfyUI/output/` for:
   - `ace_step_output.wav`
   - `album_art.png`
   - `output_video.mp4`

---

### Troubleshooting

| Issue | Solution |
|-------|----------|
| LLM returns empty | Check Ollama is running, model is loaded, increase Num_predict |
| TextEncodeAceStepAudio1.5 error | Verify checkpoint is loaded correctly |
| KSampler hangs | Reduce steps or check GPU VRAM |
| Video has no audio | Verify audio file path in VHS_LoadAudio |
| YouTube upload fails | Check OAuth credentials, set upload_enabled to true |