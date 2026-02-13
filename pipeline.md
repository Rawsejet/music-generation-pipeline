# Automated Music Video Pipeline in ComfyUI

## Dual RTX PRO 6000 Blackwell GPUs (96GB VRAM Each)

A fully automated ComfyUI workflow for generating lyrics, music, album art, assembling video, and uploading to YouTube — all running locally without any API dependencies. Your dual 96GB VRAM GPUs are extreme overkill for any single component, which means you can run multiple models concurrently or load the largest available variants without quantization.

---

## Pipeline Overview

```
┌──────────────────────────────────────────────────────────────────────┐
│  STAGE 1: Randomized Attribute Selection                             │
│  Dynamic Prompts wildcards → genre, mood, vocal, instruments, etc.   │
└──────────────────────┬───────────────────────────────────────────────┘
                       ▼
┌──────────────────────────────────────────────────────────────────────┐
│  STAGE 2: LLM Creative Expansion (Qwen3-32B via Ollama)             │
│  Randomized attributes → music tags + lyrics + image prompt          │
└──────────┬─────────────────────┬─────────────────────┬───────────────┘
           ▼                     ▼                     ▼
┌─────────────────┐   ┌──────────────────┐   ┌────────────────────┐
│  STAGE 3A:      │   │  STAGE 3B:       │   │  STAGE 3C:         │
│  Music Gen      │   │  Image Gen       │   │  Metadata Gen      │
│  ACE-Step 1.5   │   │  FLUX.2 Dev │   │  Title/Desc/Tags   │
│  tags + lyrics   │   │  or FLUX.2 Dev   │   │  for YouTube       │
└────────┬────────┘   └────────┬─────────┘   └────────┬───────────┘
         ▼                     ▼                       │
┌──────────────────────────────────────────────┐       │
│  STAGE 4: Video Assembly                      │       │
│  VHS_VideoCombine (image frames + audio)      │       │
└──────────────────────┬───────────────────────┘       │
                       ▼                               ▼
┌──────────────────────────────────────────────────────────────────────┐
│  STAGE 5: YouTube Upload (API, max 6/day)                            │
│  ComfyUI-YouTubeUploader or external Python script                   │
└──────────────────────────────────────────────────────────────────────┘
```

---

## 1. Music Generation — ACE-Step 1.5 (Native ComfyUI Support)

ACE-Step 1.5 is an open-source music foundation model (MIT license) that generates full vocal or instrumental songs from text. It uses a 1.7B parameter Qwen-based language model as a planner paired with a Diffusion Transformer for audio synthesis, outputting 48kHz stereo audio in MP3, WAV, or FLAC. Songs can range from 10 to 600 seconds, with 180 seconds recommended for full tracks.

**Native ComfyUI support is built in** — no custom nodes required. The official checkpoint is `ace_step_1.5_turbo_aio.safetensors`, placed in `ComfyUI/models/checkpoints/`.

### Core Nodes

| Node | Purpose |
|------|---------|
| `TextEncodeAceStepAudio1.5` | Key encoding node with two fields: **tags** (music description) and **lyrics** |
| `EmptyAceStep1.5LatentAudio` | Sets duration in seconds and batch size |
| `KSampler` | Runs diffusion (8 steps for turbo, no CFG needed) |
| `VAEDecodeAudio` → `SaveAudio` | Decodes and exports the audio file |
| `LatentOperationTonemapReinhard` | Optional vocal volume adjustment (multiplier ~1.15) |

### Two-Input Prompt System

ACE-Step uses a **dual-input system** that your pipeline must respect:

**Tags/Caption Field:** Accepts both comma-separated tags and natural language. Examples range from terse (`"lofi, hiphop, chill, female vocal"`) to detailed (`"Ibiza groovy techy deep house, 124 BPM, key of A minor, warm groovy bassline, crisp organic percussion"`). You can specify genre, instruments, mood, vocal type, BPM, musical key, and production style.

**Lyrics Field:** Uses structured section markers: `[Verse]`, `[Chorus]`, `[Bridge]`, `[Instrumental]`. For purely instrumental output, leave lyrics empty or enter `[inst]`. **ACE-Step does NOT auto-generate lyrics — they must be provided**, which is exactly what the LLM handles (see Stage 2).

### Performance

VRAM requirement is under **4GB**. Generation speed on your Blackwell GPUs will be effectively instantaneous — under 1 second for a full 4-minute song using the turbo model. Batch generation of up to 8 songs simultaneously is supported, making "gacha-style" seed exploration practical.

### Third-Party Custom Nodes

- **ComfyUI_RH_ACE-Step** (`HM-RunningHub/ComfyUI_RH_ACE-Step`) — Adds an Artist Node for AI-powered lyrics composition using ACE-Step's internal planner LM (0.6B–4B sizes)
- **ComfyUI_ACE-Step** (`billwuhao/ComfyUI_ACE-Step`) — Most feature-rich pack; includes an automated composition workflow with built-in LLM lyrics generation supporting Qwen3, Gemini, and DeepSeek V3; also adds multi-language lyrics conversion for 19 languages

---

## 2. LLM Prompt & Lyrics Generation — Qwen3 via Ollama

The LLM is the creative brain of the pipeline, responsible for three outputs in a single call: **music tags**, **formatted lyrics**, and an **image prompt**. Your existing Qwen3 setup via Ollama is the optimal tool — no specialized lyrics model comes close to what a 32B+ parameter general-purpose LLM can produce with the right prompting.

### Why Not a Dedicated Lyrics Model?

The landscape of specialized models is thin: **Llama-Song-Stream-3B-Instruct** and **Phi-3-song-lyrics-1.1** exist on HuggingFace, but at 3B–3.8B parameters they produce noticeably weaker output than Qwen3-32B. **SongComposer** (Shanghai AI Lab, ACL 2025) is the most serious specialized model, but generates symbolic music notation with lyrics — not standalone creative text. Dozens of GPT-2-based lyrics fine-tunes exist but are toy-scale with repetitive, incoherent output.

### Recommended Model

**Qwen3-32B-Instruct** — Dense 32B model, fits on a single GPU at FP16 (~65GB VRAM) with room to spare. Matches GPT-4o quality. Qwen3's documentation specifically highlights "superior human preference alignment, excelling in creative writing, role-playing, and instruction following" — exactly the capabilities needed for songwriting.

**Alternatives:**

| Model | Size | VRAM | Notes |
|-------|------|------|-------|
| Qwen3-235B-A22B (MoE) | 235B total / 22B active | ~143GB Q4_K_M (dual GPU) | Tied with Claude Opus 4 on LMArena. Maximum quality. |
| Llama 3.3 70B | 70B | ~70GB Q8 | Mature, well-supported, 128K context |
| DeepSeek-R1-Distill-Llama-70B | 70B | ~70GB Q8 | Strong reasoning, good for structured formats |
| Qwen3-14B-Instruct | 14B | ~14GB FP16 | Fast iteration, delivers Qwen2.5-32B performance |

### ComfyUI Integration

Use **comfyui_LLM_party** (`heshengtao/comfyui_LLM_party`) — the most comprehensive LLM node framework for ComfyUI with 119+ language support, system/user prompt inputs, structured output, and connections to any OpenAI-compatible API including local Ollama.

```
[LLM_api_loader] → base_url: http://localhost:11434/v1/, model: qwen3:32b
        ↓
[LLM Node] ← system_prompt: (see below)
           ← user_prompt: (randomized attributes from Stage 1)
        ↓
    STRING output → parse into: music_tags, lyrics, image_prompt
```

Other viable LLM node options:
- **comfyui-ollama** (`stavsap/comfyui-ollama`, ~530 stars) — Simpler Ollama-only integration with `OllamaGenerate` and `OllamaGenerateAdvance` nodes
- **ComfyUI-Llama** (`daniel-lewis-ab/ComfyUI-Llama`) — Direct GGUF model loading without a server
- **ComfyUI-IF_AI_tools** (`if-ai/ComfyUI-IF_AI_tools`) — Specializes in prompt generation with custom character presets

### Ollama Parameters for Creative Writing

```
temperature: 0.85
top_p: 0.9
top_k: 40
repeat_penalty: 1.15
num_predict: 2048
```

The elevated repeat_penalty prevents repetitive phrasing while still allowing intentional chorus repetition. Bake into a custom Modelfile: `ollama create lyrics-qwen3-32b -f Modelfile`.

### The System Prompt

The critical technical constraint is **syllable count**: ACE-Step works best with 6–10 syllables per line. LLMs process tokens, not phonetic units, so GPT-4 achieves only ~57% accuracy on exact counts — but ACE-Step tolerates ±2 syllable variance, making the problem manageable.

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
- Default: [Verse 1] → [Chorus] → [Verse 2] → [Chorus] → [Bridge] → [Chorus] → [Outro]
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

### User Prompt Template

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

### ACE-Step Lyrics Format Reference

| Rule | Detail |
|------|--------|
| Section markers | `[Verse 1]`, `[Chorus]`, `[Bridge]`, `[Intro]`, `[Outro]`, `[Instrumental]`, `[inst]` |
| Performance hints | `[Chorus - powerful]`, `[Intro - piano]`, `[Bridge - whispered]` |
| Syllables per line | **6–10** (most impactful quality rule) |
| Lines per verse | 4–6 |
| Lines per chorus | 2–4 |
| Lines per bridge | 2–4 |
| Instrumental | Leave lyrics empty or enter `[inst]` |
| Duration sweet spot | 90–120 seconds for consistency; 180s for full songs; max 600s |
| Languages | 50+ with auto-detection; strongest in English, Chinese, Russian, Spanish, Japanese |

**Example of properly formatted lyrics:**

```
[Verse 1]
Walking down the empty street tonight
Stars are shining oh so bright
Memories come flooding through my mind
Searching for the love I left behind

[Pre-Chorus]
Every step I take brings me closer
To the truth I can't deny

[Chorus - powerful]
We belong together now and forever
Hearts aligned through stormy weather
Nothing's gonna tear us apart
You're the beating of my heart

[Verse 2]
Shadows dance beneath the city lights
Whispered words on lonely nights
Time has passed but feelings stay the same
Still I call out your name

[Bridge - whispered]
If tomorrow never comes
At least we had today

[Chorus - anthemic]
We belong together now and forever
Hearts aligned through stormy weather
Nothing's gonna tear us apart
You're the beating of my heart

[Outro]
Forever yours, forever mine
```

### Alternative: billwuhao's Turnkey Workflow

If you want a pre-built solution, **ComfyUI_ACE-Step** (`billwuhao/ComfyUI_ACE-Step`, 196 stars) ships a complete automated composition workflow (`ACE-gen-automated-composition.json`) with built-in LLM lyrics generation via its `text2lyric.py` module. It natively supports Qwen3, Gemini, and DeepSeek V3. The tradeoff is less customization of the lyrics prompt compared to rolling your own Ollama integration.

---

## 3. Image Generation — FLUX.2 Dev or FLUX.2 Dev

For album art and music video imagery, two models lead the field as of early 2026, both natively supported in ComfyUI.

### Top Recommendation: FLUX.2 Dev

**20B parameter MMDiT model under Apache 2.0** — fully commercial with no restrictions. Ranked as the strongest open-source image model on AI Arena as of December 2025. Excels at diverse artistic styles: photorealistic, impressionist, anime, minimalist, and abstract. Exceptional multilingual text rendering for album titles. Uses ~20GB VRAM at FP8.

### Premium Quality: FLUX.2 [dev]

**32B parameter rectified flow transformer** producing up to 4-megapixel output. Requires ~90GB VRAM at full precision or ~54GB at FP8 — your 96GB GPU handles it perfectly. Superior text rendering (~60% accuracy for in-image text), multi-reference image consistency (up to 10 reference images), and 32K token context. NVIDIA specifically optimized its ComfyUI integration. **Non-commercial license** requires a paid license from Black Forest Labs for monetized use.

### Speed Champion: Z-Image-Turbo

**6B parameter model** generating images in 8 steps. Apache 2.0 license. Outperforms FLUX.1 Dev in quality comparisons. Sub-second on your GPUs. Ideal for rapid concept exploration and batch frame generation.

### Recommendation for This Pipeline

**FLUX.2 [dev]** for production use due to its superior quality, text rendering accuracy, and your 96GB GPU handles it easily at FP8 (~54GB). Use Z-Image-Turbo for generating many variants quickly when speed is prioritized over quality.

All three use standard ComfyUI nodes: `Load Diffusion Model` → `CLIP Text Encode` → `KSampler` → `VAEDecode`.

---

## 4. Randomization Engine — Dynamic Prompts & Wildcards

**comfyui-dynamicprompts** (`adieyal/comfyui-dynamicprompts`, 370+ stars) is the best solution for mix-and-match attribute selection.

### Wildcard File Setup

Create plain text files in `custom_nodes/comfyui-dynamicprompts/wildcards/` with one option per line:

```
wildcards/genres.txt        → rock, jazz, electronic, hip-hop, classical, ambient, folk,
                               R&B, country, reggae, metal, punk, blues, soul, funk,
                               disco, techno, house, drum and bass, trip-hop, shoegaze,
                               post-rock, synthwave, vaporwave, bossa nova, afrobeat...

wildcards/moods.txt         → melancholic, energetic, dreamy, aggressive, euphoric,
                               nostalgic, hopeful, dark, playful, introspective, anxious,
                               triumphant, bittersweet, serene, rebellious, romantic...

wildcards/vocals.txt        → female soprano, male baritone, choir, whispered, raspy,
                               falsetto, operatic, spoken word, male tenor, female alto,
                               duet male-female, children's choir, gospel choir, rap...

wildcards/instruments.txt   → piano, electric guitar, synthesizer, strings, brass,
                               acoustic guitar, drum machine, violin, cello, flute,
                               saxophone, organ, bass guitar, harp, steel drums,
                               theremin, sitar, banjo, mandolin, accordion...

wildcards/tempos.txt        → 60 BPM slow ballad, 80 BPM downtempo, 95 BPM mid-tempo,
                               110 BPM moderate, 120 BPM dance, 130 BPM uptempo,
                               140 BPM high energy, 160 BPM fast, 175 BPM punk tempo...

wildcards/decades.txt       → 1950s, 1960s, 1970s, 1980s, 1990s, 2000s, 2010s, 2020s

wildcards/production.txt    → lo-fi bedroom recording, polished studio, raw live recording,
                               ambient reverb-heavy, vinyl warmth, digital crisp,
                               tape saturation, arena rock, intimate acoustic, orchestral...

wildcards/themes.txt        → heartbreak, freedom, city nightlife, nature, rebellion,
                               lost love, self-discovery, road trip, rainy days, childhood,
                               dancing alone, ocean waves, midnight thoughts, new beginnings...
```

### Random Prompts Node Template

```
__genres__, __moods__, __vocals__, __instruments__, __tempos__,
__decades__ style, __production__ production, theme: __themes__
```

Each `__filename__` token randomly picks one line from the corresponding file on every execution. This output feeds directly into the LLM as the user prompt attributes.

### Math on Variety

A system with 30 genres × 20 moods × 15 vocal types × 25 instruments × 10 tempos × 8 decades × 15 production styles × 20 themes = **2.7 billion unique attribute combinations** before the LLM adds its creative interpretation — more than enough for years of daily uploads without repetition.

### Additional Randomization Tools

- **WAS Node Suite** (`WASasquatch/was-node-suite-comfyui`, 1,440+ stars) — Provides `Text Random Line`, `Text Concatenate`, and `Text Shuffle` nodes for per-attribute seed control
- **comfyui-text-randomizer** (`nosiu/comfyui-text-randomizer`) — Inline bracket syntax: `{rock|jazz|electronic}`
- **rgthree-comfy** (`rgthree/rgthree-comfy`) — Best seed control node with fixed, random, increment, and decrement modes

---

## 5. Video Assembly — Video Helper Suite

**VHS_VideoCombine** from Video Helper Suite (`Kosinkadink/ComfyUI-VideoHelperSuite`, 1.3K+ stars, actively maintained) is the definitive solution.

### Workflow for Static Image + Audio → Video

1. **Load/generate your image** (from Stage 3B)
2. **Load audio** via `VHS_LoadAudio` (from ACE-Step's saved output)
3. **Duplicate the image** into N frames using `VHS_DuplicateImages` where `N = audio_duration_seconds × frame_rate`
4. **Combine** via `VHS_VideoCombine`:
   - Format: `video/h264-mp4`
   - Pixel format: `yuv420p`
   - CRF: `18–20`

### YouTube-Optimized Output Settings

| Setting | Value |
|---------|-------|
| Container | MP4 |
| Video codec | H.264 |
| Audio codec | AAC-LC |
| Resolution | 1920×1080 (16:9) |
| Frame rate | 24–30 fps |
| CRF | 18–20 |

### Alternative Nodes

- **Bjornulf_CombineVideoAudio** (`justUmen/Bjornulf_custom_nodes`) — Flexible with optional inputs for images, audio, video files
- **CombineAudioVideo** (`shadowcz007/comfyui-mixlab-nodes`, 1.5K stars) — Merges separate audio and video via ffmpeg

---

## 6. YouTube Upload — API Integration

### Existing ComfyUI Node

**ComfyUI-YouTubeUploader** (`flamacore/ComfyUI-YouTubeUploader`) handles direct uploads from within a workflow. Supports video upload, custom thumbnails, audio inclusion, and upload protection. Install via ComfyUI Manager. Note: the repo is under heavy development (~5 stars) — test thoroughly.

### Quota Math

YouTube Data API v3 provides **10,000 units per day per project**:

| Operation | Cost | × Count | Total |
|-----------|------|---------|-------|
| Video upload | 1,600 | 6 | 9,600 |
| Thumbnail upload | 50 | 6 | 300 |
| **Daily total** | | | **9,900** |
| **Remaining margin** | | | **100** |

This is extremely tight. **Request a quota increase** from Google's Quota Extension form immediately.

### Key Requirements

- **OAuth 2.0 is mandatory** for uploads (API keys only work for read-only operations)
- Failed requests still consume quota (minimum 1 unit)
- Quota resets at midnight Pacific Time

### Recommended Architecture

Use a **hybrid approach**: have ComfyUI generate and save the MP4 + metadata (title, description, tags) to an output directory, then run a separate Python watcher script that handles uploads with retry logic, exponential backoff for 403 errors, and quota monitoring. This decouples generation from upload, making both more robust.

For in-ComfyUI scripting, **ComfyScript** (`Chaoses-Ib/ComfyScript`) offers a full Python frontend, or use `comfyui-python-cowboy`'s PythonScript node for simpler inline scripts.

---

## 7. Complete Wiring — Stage by Stage

### Stage 1 → Randomized Attribute Selection

```
[genres.txt] → Dynamic Prompts Random:
  "__genres__, __moods__, __vocals__, __instruments__, __tempos__,
   __decades__, __production__, theme: __themes__"
        ↓
  Randomized Attribute String
  e.g. "jazz, dreamy, female soprano, piano, 90 BPM,
        1960s, lo-fi production, theme: midnight thoughts"
```

### Stage 2 → LLM Generates Tags + Lyrics + Image Prompt

```
Randomized Attributes → [LLM Node via Ollama / Qwen3-32B]
  System prompt: (songwriter system prompt from Section 2)
  User prompt: "Create a song with these parameters: {attributes}"
        ↓
  Full LLM Output (contains === TAGS ===, === LYRICS ===, === IMAGE_PROMPT ===)
        ↓
  [Text manipulation nodes split by markers]
        ↓
  Three separate strings: music_tags, lyrics, image_prompt
```

### Stage 3A → Music Generation (GPU 0)

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

### Stage 3B → Image Generation (GPU 0, sequential after music)

```
image_prompt → CLIP Text Encode (FLUX.2 Dev)
        ↓
KSampler (standard image gen settings)
        ↓
VAEDecode → SaveImage → album_art.png
```

### Stage 3C → Metadata Generation

```
music_tags + lyrics → [Second LLM call or text template]
  "Generate a YouTube title, description, and tags for this song:
   Genre tags: {music_tags}
   Lyrics preview: {first_verse}"
        ↓
  youtube_title, youtube_description, youtube_tags
```

### Stage 4 → Video Assembly

```
album_art.png → VHS_DuplicateImages (N = duration × 24fps)
                        ↓
song.wav → VHS_LoadAudio → VHS_VideoCombine
                            (h264-mp4, yuv420p, crf=18)
                        ↓
                  output_video.mp4
```

### Stage 5 → YouTube Upload

```
output_video.mp4 + metadata → [YouTubeUploader node or external watcher script]
        ↓
  Published to YouTube (max 6/day)
```

---

## 8. Installation Checklist

### Required Custom Nodes

| Component | Node Package | Repository | Purpose |
|-----------|-------------|------------|---------|
| Music generation | Native ComfyUI nodes | Built-in (nightly build) | ACE-Step 1.5 |
| LLM integration | comfyui_LLM_party | `heshengtao/comfyui_LLM_party` | Ollama/local LLM connection |
| LLM server | Ollama | `ollama.com` | Serves Qwen3-32B |
| Image generation | Native ComfyUI nodes | Built-in | FLUX.2 Dev or FLUX.2 |
| Randomization | comfyui-dynamicprompts | `adieyal/comfyui-dynamicprompts` | Wildcard random selection |
| Text utilities | WAS Node Suite | `WASasquatch/was-node-suite-comfyui` | Text manipulation, concatenation |
| Seed control | rgthree-comfy | `rgthree/rgthree-comfy` | Deterministic seed management |
| Video assembly | Video Helper Suite | `Kosinkadink/ComfyUI-VideoHelperSuite` | Image + audio → MP4 |
| YouTube upload | ComfyUI-YouTubeUploader | `flamacore/ComfyUI-YouTubeUploader` | Direct YouTube API upload |
| Node management | ComfyUI Manager | `ltdrdata/ComfyUI-Manager` | Install/update all nodes |
| *Optional* | ComfyUI_ACE-Step | `billwuhao/ComfyUI_ACE-Step` | Turnkey automated composition |
| *Optional* | ComfyUI_RH_ACE-Step | `HM-RunningHub/ComfyUI_RH_ACE-Step` | Artist Node for quick drafts |

### Models to Download

| Model | File / Command | Path | Size |
|-------|---------------|------|------|
| ACE-Step 1.5 Turbo | `ace_step_1.5_turbo_aio.safetensors` | `ComfyUI/models/checkpoints/` | ~7GB |
| FLUX.2 Dev | Via ComfyUI model download | `ComfyUI/models/diffusion_models/` | ~20GB FP8 |
| Qwen3-32B | `ollama pull qwen3:32b` | Ollama managed | ~19GB Q4 |

### GPU Allocation Strategy

| GPU | Assignment | VRAM Usage |
|-----|-----------|------------|
| GPU 0 | ComfyUI (ACE-Step + image gen + video processing) | ACE-Step: ~4GB; Image gen: ~20–54GB |
| GPU 1 | Ollama (Qwen3-32B LLM serving) | ~19–65GB depending on quantization |

Set `CUDA_VISIBLE_DEVICES=1` for Ollama and `CUDA_VISIBLE_DEVICES=0` for ComfyUI, or let ComfyUI's built-in model management handle sequential loading.

---

## 9. Key Constraints & Tips

**ACE-Step's golden rule:** 6–10 syllables per line in lyrics. This single formatting detail has more impact on output quality than any model choice or prompt variation.

**Caption-lyrics consistency:** Contradictions between caption mood and lyric content degrade output quality significantly. The LLM system prompt is designed to keep all three outputs thematically aligned.

**Batch generation:** Generate 4–8 song variants per prompt and cherry-pick the best. ACE-Step's generation is inherently stochastic — seed exploration is cheap with <1s per song.

**YouTube quota:** 6 uploads with thumbnails consumes 99% of the daily budget. Request a quota increase from Google before going to production. Failed uploads still consume quota.

**Weakest link:** The YouTubeUploader node (5 stars, under heavy development). A decoupled Python upload script watching an output directory is more production-ready.

**Strongest link:** ACE-Step 1.5 is remarkably lightweight (under 4GB VRAM, sub-second generation), making music generation essentially free in compute terms. The real bottleneck is image generation at high quality.

**For instrumental tracks:** Set lyrics field to `[inst]` in ACE-Step. Add `"instrumental"` to the wildcard vocals.txt as an option so some songs are randomly generated without vocals.
