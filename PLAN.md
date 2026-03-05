# Music Generation Pipeline Implementation Plan

## Overview
This plan implements a fully automated ComfyUI workflow for generating lyrics, music, album art, assembling video, and uploading to YouTube — all running locally without any API dependencies.

---

## Phase 1: Ollama Setup (GPU 1)
**Goal**: Serve Qwen3-32B for LLM tasks

**Steps**:
1. Install Ollama (if not already installed)
2. Pull the Qwen3-32B model: `ollama pull qwen3:32b`
3. Configure Ollama to use GPU 1 via `CUDA_VISIBLE_DEVICES=1`
4. Verify Ollama is accessible via API at `http://localhost:11434`

**Model Tag**:
- Your custom model tag: `qwen3-gpu1:latest`
- This model is served via: `ollama run qwen3-gpu1:latest`

**Verification**:
```
curl http://localhost:11434/api/generate -d '{"model":"qwen3-gpu1:latest","prompt":"test","stream":false}'
```

---

## Phase 2: ComfyUI Custom Nodes
**Goal**: Install all required custom nodes for LLM integration, randomization, video assembly, and YouTube upload

**Nodes to Install** (via git clone to `ComfyUI/custom_nodes/`):

| Node | Repository | Purpose |
|------|------------|---------|
| comfyui_LLM_party | `heshengtao/comfyui_LLM_party` | Ollama/local LLM connection |
| comfyui-dynamicprompts | `adieyal/comfyui-dynamicprompts` | Wildcard random selection |
| WAS Node Suite | `WASasquatch/was-node-suite-comfyui` | Text manipulation, concatenation |
| Video Helper Suite | `Kosinkadink/ComfyUI-VideoHelperSuite` | Image + audio → MP4 |
| ComfyUI-YouTubeUploader | `flamacore/ComfyUI-YouTubeUploader` | Direct YouTube API upload |
| rgthree-comfy | `rgthree/rgthree-comfy` | Deterministic seed management |
| ComfyUI-Manager | `ltdrdata/ComfyUI-Manager` | Install/update all nodes |

**Optional (for turnkey workflows)**:
- ComfyUI_ACE-Step (`billwuhao/ComfyUI_ACE-Step`)
- ComfyUI_RH_ACE-Step (`HM-RunningHub/ComfyUI_RH_ACE-Step`)

---

## Phase 3: Install scromfyUI-AceStep 1.5
**Goal**: Enable music generation with 5Hz LLM planner

**Steps**:
1. Install scromfyUI-AceStep custom node: `billwuhao/scromfyUI-AceStep`
2. Model files are loaded automatically via HuggingFace hub
3. Verify nodes appear in ComfyUI: `ScromfyACEStep15TaskTextEncodeNode`, `AceStep5HzLMConfig`, `AceStepDiffusionSampler`

**Migration from ACE-Step AIO**: The scromfyUI-AceStep fork provides:
- **5Hz LLM planner**: Better beat/lyric alignment
- **`shift` parameter**: Controls generation speed/quality (default: 3.0)
- **`llm_audio_codes`**: LLM-guided audio generation
- **Updated params**: cfg_scale=2.0, steps=8, denoise=1.0

**VRAM Note**: scromfyUI-AceStep requires under 4GB VRAM

---

## Phase 4: Create Wildcard Files
**Goal**: Enable random attribute selection for song generation

**Directory**: `ComfyUI/custom_nodes/comfyui-dynamicprompts/wildcards/`

**Files to Create**:
| File | Content (sample) |
|------|-----------------|
| `genres.txt` | rock, jazz, electronic, hip-hop, classical, ambient, folk, R&B, country, reggae, metal, punk, blues, soul, funk, disco, techno, house, drum and bass, trip-hop, shoegaze, post-rock, synthwave, vaporwave, bossa nova, afrobeat |
| `moods.txt` | melancholic, energetic, dreamy, aggressive, euphoric, nostalgic, hopeful, dark, playful, introspective, anxious, triumphant, bittersweet, serene, rebellious, romantic |
| `vocals.txt` | female soprano, male baritone, choir, whispered, raspy, falsetto, operatic, spoken word, male tenor, female alto, duet male-female, children's choir, gospel choir, rap |
| `instruments.txt` | piano, electric guitar, synthesizer, strings, brass, acoustic guitar, drum machine, violin, cello, flute, saxophone, organ, bass guitar, harp, steel drums, theremin, sitar, banjo, mandolin, accordion |
| `tempos.txt` | 60 BPM slow ballad, 80 BPM downtempo, 95 BPM mid-tempo, 110 BPM moderate, 120 BPM dance, 130 BPM uptempo, 140 BPM high energy, 160 BPM fast, 175 BPM punk tempo |
| `decades.txt` | 1950s, 1960s, 1970s, 1980s, 1990s, 2000s, 2010s, 2020s |
| `production.txt` | lo-fi bedroom recording, polished studio, raw live recording, ambient reverb-heavy, vinyl warmth, digital crisp, tape saturation, arena rock, intimate acoustic, orchestral |
| `themes.txt` | heartbreak, freedom, city nightlife, nature, rebellion, lost love, self-discovery, road trip, rainy days, childhood, dancing alone, ocean waves, midnight thoughts, new beginnings |

---

## Phase 5: ComfyUI Workflow
**Goal**: Create the complete workflow JSON file connecting all 5 stages

### Workflow Structure

```
[Random Prompts Node]
        ↓
[LLM Node via Ollama / Qwen3-32B]
        ↓
[Text Splitter - by === TAGS/LYRICS/IMAGE_PROMPT === markers]
        ↓
    ┌─────────────────────────────────────────────────┐
    ▼                     ▼                           ▼
[Music Gen]         [Image Gen]                [Metadata Gen]
(ACE-Step 1.5)     (Qwen-Image-2512)       (YouTube Title/Desc/Tags)
    ▼                     ▼
[Video Assembly]
(VHS_VideoCombine)
        ↓
[YouTube Upload]
```

### Detailed Node Connections

**Stage 1: Randomized Attribute Selection**
```
[genres.txt] → Dynamic Prompts Random:
  "__genres__, __moods__, __vocals__, __instruments__, __tempos__,
   __decades__, __production__, theme: __themes__"
        ↓
  Randomized Attribute String
```

**Stage 2: LLM Generates Tags + Lyrics + Image Prompt**
```
Randomized Attributes → [LLM Node]
  System prompt: (songwriter system prompt)
  User prompt: "Create a song with these parameters: {attributes}"
        ↓
  Full LLM Output (contains === TAGS ===, === LYRICS ===, === IMAGE_PROMPT ===)
        ↓
  [Text manipulation nodes split by markers]
        ↓
  Three separate strings: music_tags, lyrics, image_prompt
```

**Stage 3A: Music Generation (GPU 0)**
```
music_tags → TextEncodeAceStepAudio1.5 (tags field)
lyrics    → TextEncodeAceStepAudio1.5 (lyrics field)
        ↓
EmptyAceStep1.5LatentAudio (duration: 180s, batch: 4)
        ↓
KSampler (steps: 8, turbo model, no CFG)
        ↓
VAEDecodeAudio → SaveAudio → song.wav
```

**Stage 3B: Image Generation (GPU 0)**
```
image_prompt → CLIP Text Encode (Qwen-Image-2512)
        ↓
KSampler (standard image gen settings)
        ↓
VAEDecode → SaveImage → album_art.png
```

**Stage 3C: Metadata Generation**
```
music_tags + lyrics → [Second LLM call or text template]
  "Generate a YouTube title, description, and tags for this song..."
        ↓
  youtube_title, youtube_description, youtube_tags
```

**Stage 4: Video Assembly**
```
album_art.png → VHS_DuplicateImages (N = duration × 24fps)
                        ↓
song.wav → VHS_LoadAudio → VHS_VideoCombine
                            (h264-mp4, yuv420p, crf=18)
                        ↓
                  output_video.mp4
```

**Stage 5: YouTube Upload**
```
output_video.mp4 + metadata → [YouTubeUploader node or external watcher script]
        ↓
  Published to YouTube (max 6/day)
```

### Ollama API Configuration
- Base URL: `http://localhost:11434/v1/`
- Model: `qwen3-gpu1:latest`
- Temperature: 0.85
- Top_p: 0.9
- Top_k: 40
- Repeat_penalty: 1.15
- Num_predict: 2048

---

## Phase 6: YouTube Upload Watcher Script
**Goal**: Handle uploads with retry logic and quota monitoring

**Features**:
- Watch output directory for new MP4 files
- Read metadata from companion JSON files
- Upload via YouTube Data API v3
- Exponential backoff for failed uploads (403 errors)
- Quota tracking (10K daily units)
- OAuth 2.0 authentication flow
- Create custom thumbnails from album art

**File**: `upload_watcher.py`

**Usage**:
```
python upload_watcher.py --watch-dir ./outputs/music --oauth-secrets oauth.json
```

---

## Phase 7: Testing
**Goal**: Validate end-to-end functionality

**Test Checklist**:
- [ ] Ollama API returns valid responses
- [ ] Wildcard randomization works correctly
- [ ] LLM outputs properly formatted lyrics (6-10 syllables per line)
- [ ] ACE-Step generates audio from tags + lyrics
- [ ] Image generation produces album art
- [ ] Video assembly creates MP4 with correct resolution (1920×1080, 24-30fps)
- [ ] Upload script works with OAuth 2.0 credentials

---

## GPU Allocation Strategy

| GPU | Assignment | VRAM Usage |
|-----|-----------|------------|
| GPU 0 | ComfyUI (ACE-Step + image gen + video processing) | ACE-Step: ~4GB; Image gen: ~20–54GB |
| GPU 1 | Ollama (Qwen3-32B LLM serving) | ~19–65GB depending on quantization |

**Configuration**:
- For Ollama: `CUDA_VISIBLE_DEVICES=1 ollama serve`
- For ComfyUI: `CUDA_VISIBLE_DEVICES=0 python main.py` (or default if managed internally)

---

## Estimated Timeline

| Phase | Estimated Time | Dependencies |
|-------|---------------|--------------|
| Phase 1-3 | 1 hour | None |
| Phase 4 | 30 minutes | None |
| Phase 5 | 1-2 hours | Phases 2-4 |
| Phase 6 | 1 hour | Phase 5 (output files) |
| Phase 7 | 1-2 hours | All previous phases |

---

## Notes

- ACE-Step 1.5 is very lightweight (~4GB VRAM, sub-second generation)
- The real bottleneck is image generation at high quality (~20-54GB VRAM)
- YouTube quota is tight: 6 uploads + thumbnails = 9,900 daily units
- The LLM system prompt enforces 6-10 syllables per line in lyrics
- Batch generation of 4-8 songs is recommended for seed exploration