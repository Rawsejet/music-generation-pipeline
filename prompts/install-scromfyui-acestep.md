# Prompt: Install scromfyUI-AceStep and Wire Into Existing Pipeline

Paste this entire prompt into a new Claude Code session.

---

## Goal

Replace the current ACE-Step AIO checkpoint setup in my ComfyUI music generation pipeline with **scromfyUI-AceStep** custom nodes, which expose the full ACE-Step 1.5 LM + DiT split architecture. This unlocks the 4B LM planner, `shift` parameter, LoRA support, and all advanced inference controls.

## My Hardware

- **OS**: Ubuntu Linux (6.17.0-14-generic)
- **GPUs**: Dual RTX PRO 6000 Blackwell (96GB VRAM each, 192GB total)
- **GPU 0**: ComfyUI
- **GPU 1**: Ollama (qwen3.5:35b-a3b-bf16 for the pipeline's Stage 2 LLM)

## Directory Layout

```
/home/teja/Documents/comfy/ComfyUI/           ← ComfyUI installation
/home/teja/Documents/comfy/ComfyUI/custom_nodes/  ← custom nodes go here
/home/teja/Documents/comfy/ComfyUI/models/
    checkpoints/ace_step_1.5_turbo_aio.safetensors   ← current AIO model (keep as fallback)
    diffusion_models/flux2-dev.safetensors
    text_encoders/mistral_3_small_flux2_fp8.safetensors
    vae/flux2-vae.safetensors
    audio_encoders/   ← exists but empty (placeholder only)

/home/teja/music-generation-pipeline/          ← design docs repo
/home/teja/music-generation-pipeline/acstep15/ ← ACE-Step 1.5 source (cloned from GitHub)
/home/teja/music-generation-pipeline/workflows/music-generation-pipeline.json  ← live workflow
```

## Existing Custom Nodes Already Installed

```
ComfyMath, ComfyUI_ACE-Step (billwuhao), comfyui-dynamicprompts,
comfyui-fairlab, comfyui_LLM_party, ComfyUI-Manager, ComfyUI-Ovi,
ComfyUI-VideoHelperSuite, ComfyUI-YouTubeUploader, rgthree-comfy,
was-node-suite-comfyui
```

Note: `ComfyUI_ACE-Step` (billwuhao) is a different/older ACE-Step node set. It may conflict with scromfyUI — investigate and remove if necessary.

## Current ACE-Step Workflow (what needs replacing)

The live workflow JSON uses these nodes for music generation (Stage 3A):

### Current Nodes to Replace

1. **Node 6: `Checkpoint Loader (Simple)`**
   - Loads `ace_step_1.5_turbo_aio.safetensors`
   - Outputs: MODEL, CLIP, VAE

2. **Node 8: `TextEncodeAceStepAudio1.5`** (positive conditioning)
   - Receives from upstream JSON parsing nodes:
     - `tags` ← json_get_value(key="tags") from LLM output
     - `lyrics` ← json_get_value(key="lyrics") from LLM output
     - `bpm` ← json_get_value(key="bpm") from LLM output
     - `keyscale` ← json_get_value(key="keys") from LLM output
     - `timesignature` ← json_get_value(key="time_signature") from LLM output
     - `duration` ← Random Number node (float, 150–210 seconds)
   - Current widget values: cfg_scale=1, temperature=0.85, top_p=0.9, top_k=0, language='en'

3. **Node 38: `TextEncodeAceStepAudio1.5`** (negative/empty conditioning)
   - Empty tags and lyrics, serves as negative conditioning
   - cfg_scale=2, temperature=0.85, top_p=0.9, top_k=0

4. **Node 7: `EmptyAceStep1.5LatentAudio`**
   - Seconds: receives from same Random Number node (150–210)
   - Batch: 1

5. **Node 10: `KSampler`**
   - Steps: 50, CFG: 1, Sampler: `res_multistep`, Scheduler: `simple`, Denoise: 0.75
   - Inputs: model ← Node 6, positive ← Node 8, negative ← Node 38, latent ← Node 7

6. **Node 11: `VAEDecodeAudio`**
   - samples ← KSampler, VAE ← Node 6

### Downstream Connections (MUST BE PRESERVED)

The AUDIO output from VAEDecodeAudio currently feeds:
- `SaveAudioMP3` (Node 12) — filename from json_get_value("video_title")
- `PreviewAudio` (Node 31)
- `VHS_VideoCombine` (Node 34) — video assembly
- `YouTubeUploaderNode` (Node 28) — upload

### Upstream Connections (MUST BE PRESERVED)

The LLM (Stage 2) outputs JSON with 7 keys parsed by `json_get_value` nodes:
- `tags` → ACE-Step text encoder
- `lyrics` → ACE-Step text encoder
- `bpm` → ACE-Step text encoder
- `keys` → ACE-Step text encoder (keyscale)
- `time_signature` → ACE-Step text encoder
- `image_prompt` → FLUX.2 image generation (Stage 3B, separate)
- `video_title` → filenames and YouTube title

## Tasks

### Task 1: Install scromfyUI-AceStep

```
git clone https://github.com/scruffynerf/scromfyUI-AceStep /home/teja/Documents/comfy/ComfyUI/custom_nodes/scromfyUI-AceStep
cd /home/teja/Documents/comfy/ComfyUI/custom_nodes/scromfyUI-AceStep
pip install -r requirements.txt
```

- Check for conflicts with the existing `ComfyUI_ACE-Step` (billwuhao) node set — if there are class name or node name collisions, remove the billwuhao version.
- Verify the nodes load by checking ComfyUI logs on restart.

### Task 2: Download ACE-Step 1.5 LM Model (4B)

The 4B LM model (`acestep-5Hz-lm-4B`) needs to be downloaded. It's based on Qwen3-4B, fine-tuned for music planning.

- Source: Check HuggingFace `ACE-Step/` org or the model zoo links in `/home/teja/music-generation-pipeline/acstep15/README.md`
- The `AceStepLLMLoader` node in scromfyUI looks for models in ComfyUI's checkpoints folder. Determine where exactly it expects the model — may need a symlink or `extra_model_paths.yaml` entry.
- The model should be ~8-16GB. With 96GB VRAM on GPU 0, this is trivial.

### Task 3: Design the New Node Wiring

Replace the 6 current ACE-Step nodes with scromfyUI equivalents. The new node graph should be:

```
                                    ┌─────────────────────┐
                                    │  AceStepLLMLoader   │
                                    │  (4B model, bf16,   │
                                    │   device=cuda)      │
                                    └─────────┬───────────┘
                                              │ LLM_CONFIG
                                              ▼
┌──────────────┐    ┌─────────────────────────────────────────────┐
│ 5Hz LLM      │───▶│  ACE-Step 1.5 Task Text Encode (Scromfy)   │
│ Config       │    │                                             │
│ temp=0.85    │    │  tags ← json_get_value("tags")              │
│ cfg=2.0      │    │  lyrics ← json_get_value("lyrics")         │
│ top_p=0.9    │    │  bpm ← json_get_value("bpm")               │
│              │    │  keyscale ← json_get_value("keys")          │
│              │    │  timesignature ← json_get_value("time_sig") │
│              │    │  duration ← Random Number (150-210)         │
│              │    │  language = en                               │
│              │    │  llm_audio_codes = True  ← KEY TOGGLE       │
│              │    │  seed = randomize                            │
└──────────────┘    └─────────────────┬───────────────────────────┘
                                      │ CONDITIONING (positive)
                                      ▼
┌─────────────────────┐    ┌──────────────────────┐
│ CheckpointLoader    │───▶│  Inpaint Sampler     │
│ (ace_step_1.5_      │    │  (Audio)             │
│  turbo_aio)         │    │                      │
│ MODEL, CLIP, VAE    │    │  steps = 8           │
│                     │    │  cfg = 1             │
│                     │    │  shift = 3.0  ← KEY  │
│                     │    │  sampler=res_multistep│
│                     │    │  scheduler=simple     │
│                     │    │  denoise = 1.0        │
└─────────────────────┘    └──────────┬───────────┘
                                      │ LATENT
                                      ▼
                           ┌──────────────────────┐
                           │  VAEDecodeAudio      │
                           │                      │──▶ SaveAudioMP3
                           │  AUDIO output        │──▶ PreviewAudio
                           │                      │──▶ VHS_VideoCombine
                           │                      │──▶ YouTubeUploaderNode
                           └──────────────────────┘
```

**Key parameter changes from current setup:**
- `shift` = **3.0** (was implicitly 1.0 — biggest single quality improvement)
- `llm_audio_codes` = **True** (enables the 4B LM planner — CoT reasoning for melody/structure)
- `steps` = **8** for turbo (was 50 — turbo is designed for 8 steps, 50 wastes time with no quality gain)
- `denoise` = **1.0** (was 0.75 — for fresh generation, not inpainting, use full denoise)
- LM planner adds: auto BPM/key inference, caption expansion, semantic code generation

### Task 4: Handle Node Compatibility

Investigate these potential issues:
1. Does scromfyUI's text encode node accept the same input types as the current `TextEncodeAceStepAudio1.5`? The upstream `json_get_value` nodes output STRING type — confirm compatibility.
2. Does scromfyUI still need `EmptyAceStep1.5LatentAudio`? Or does the Inpaint Sampler handle latent creation internally?
3. Does the `AceStepLLMLoader` need to load from a specific subfolder? Check the node source code in `scromfyUI-AceStep/nodes/` for path handling.
4. Does the CLIP output from `CheckpointLoaderSimple` feed into the scromfyUI text encode node the same way?

### Task 5: Update Documentation

After wiring is confirmed working:
1. Update `/home/teja/music-generation-pipeline/COMFYDESIGN.md` Stage 3A section with the new node graph
2. Update `/home/teja/music-generation-pipeline/PLAN.md` to reflect the upgrade
3. Export the updated workflow JSON using the update script: `/home/teja/music-generation-pipeline/scripts/update-pipeline.sh`

## Reference Files

- scromfyUI repo: https://github.com/scruffynerf/scromfyUI-AceStep
- ACE-Step 1.5 Tutorial (quality tips): `/home/teja/music-generation-pipeline/acstep15/docs/en/Tutorial.md`
- ACE-Step 1.5 Inference docs: `/home/teja/music-generation-pipeline/acstep15/docs/en/INFERENCE.md`
- Current workflow JSON: `/home/teja/music-generation-pipeline/workflows/music-generation-pipeline.json`
- Pipeline design: `/home/teja/music-generation-pipeline/COMFYDESIGN.md`
- Pipeline plan: `/home/teja/music-generation-pipeline/PLAN.md`

## Success Criteria

1. scromfyUI-AceStep nodes load without errors in ComfyUI
2. No conflicts with other installed custom nodes
3. 4B LM model downloaded and loadable via `AceStepLLMLoader`
4. All upstream connections (LLM JSON → text encoder) work with new node types
5. All downstream connections (AUDIO → save/preview/video/upload) preserved
6. `shift=3.0` and `llm_audio_codes=True` are active
7. Test generation produces audio output successfully
8. Documentation updated to match new setup
