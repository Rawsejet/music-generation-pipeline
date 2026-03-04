# Plan: Migrate ACE-Step to scromfyUI-AceStep (LM + DiT Split)

## Context

Replace the current ACE-Step AIO checkpoint setup with **scromfyUI-AceStep** custom nodes to unlock:
- 4B LM planner (`acestep-5Hz-lm-4B`) for CoT reasoning
- `shift` parameter control (currently unavailable)
- LoRA support
- `llm_audio_codes=True` toggle for enhanced generation

## Current State (to replace)

Nodes 6-11 in the workflow:
1. **Node 6**: `CheckpointLoaderSimple` → `ace_step_1.5_turbo_aio.safetensors`
2. **Node 8**: `TextEncodeAceStepAudio1.5` (positive) - tags, lyrics, bpm, key, duration
3. **Node 38**: `TextEncodeAceStepAudio1.5` (negative)
4. **Node 7**: `EmptyAceStep1.5LatentAudio` - seconds, batch
5. **Node 10**: `KSampler` - steps=50, cfg=1, denoise=0.75
6. **Node 11**: `VAEDecodeAudio`

## Implementation Plan

### Phase 0: Duplicate Workflow for v2

Create a copy of the current workflow for the new implementation:
```bash
cp /home/teja/music-generation-pipeline/workflows/music-generation-pipeline.json \
   /home/teja/music-generation-pipeline/workflows/music-generation-pipeline-v2-scromfy.json
```

This keeps the original workflow intact as fallback while we build the new version.

### Phase 1: Install scromfyUI-AceStep

```bash
cd /home/teja/Documents/comfy/ComfyUI/custom_nodes
git clone https://github.com/scruffynerf/scromfyUI-AceStep
cd scromfyUI-AceStep
pip install -r requirements.txt
```

**Decision**: Keep `ComfyUI_ACE-Step` (billwuhao) nodes for testing. Remove only if conflicts occur.

### Phase 2: Download 4B LM Model

```bash
# Method 1: HuggingFace CLI
huggingface-cli download ACE-Step/acestep-5Hz-lm-4B --local-dir /home/teja/Documents/comfy/ComfyUI/models/checkpoints/acestep-5Hz-lm-4B

# Method 2: Python downloader
cd /home/teja/music-generation-pipeline/acstep15
python -m acestep.model_downloader --model acestep-5Hz-lm-4B --output ../checkpoints/
```

Model goes to: `models/checkpoints/acestep-5Hz-lm-4B/` (symlink or copy to checkpoint folder)

### Phase 3: Update Workflow (Stage 3A)

**New node wiring:**

```
┌─────────────────────────┐
│  AceStepLLMLoader       │
│  model: acestep-5Hz-lm-4B│
│  precision: bf16        │
│  device: cuda           │
└───────────┬─────────────┘
            │ LLM (ACE_LLM)
            ▼
┌─────────────────────────┐    ┌─────────────────────────┐
│  AceStep5HzLMConfig     │    │  CheckpointLoaderSimple │
│  temp=0.85, cfg=2.0     │    │  ace_step_1.5_turbo_aio │
│  top_p=0.9, top_k=0     │    └───────────┬─────────────┘
└───────────┬─────────────┘                │ MODEL, CLIP, VAE
            │ lm_config                     ▼
            ▼              ┌──────────────────────────────────────┐
┌─────────────────────────┐│  ScromfyACEStep15TaskTextEncodeNode  │
│ 5Hz LLM + CLIP         ││  clip: CLIP from CheckpointLoader    │
│ → combined conditioning││  text: tags ← json_get_value("tags") │
│                        ││  lyrics ← json_get_value("lyrics")   │
│                        ││  bpm ← json_get_value("bpm")         │
│                        ││  keyscale ← json_get_value("keys")   │
│                        ││  timesignature ← json_get_value      │
│                        ││  duration ← Random Number (150-210)  │
│                        ││  language: en                        │
│                        ││  llm_audio_codes: True ← KEY         │
│                        ││  seed: randomize                     │
│                        ││  cfg_scale: 2.0                      │
│                        ││  temperature: 0.85                   │
└────────┬────────────────┘└──────────────┬───────────────────────┘
         │ CONDITIONING (positive)         │
         │                                 │ CONDITIONING (negative)
         │                                 ▼
         │              ┌──────────────────────────────────────┐
         │              │  ScromfyACEStep15TaskTextEncodeNode  │
         │              │  (empty text, negative config)       │
         │              └──────────────┬───────────────────────┘
         │                             │ CONDITIONING (negative)
         │                             ▼
         │              ┌──────────────────────────────────────┐
         │              │  EmptyAceStep1.5LatentAudio          │
         │              │  seconds: 150-210 (from Random #)    │
         │              │  batch_size: 1                        │
         │              └──────────────┬───────────────────────┘
         │                             │ LATENT
         │                             ▼
         └───────────▶ ┌──────────────────────────────────────┐
                       │  KSampler (Audio)                    │
                       │  steps: 8 ← reduced from 50           │
                       │  cfg: 1                               │
                       │  sampler: res_multistep               │
                       │  scheduler: simple                    │
                       │  denoise: 1.0 ← changed from 0.75     │
                       │  shift: 3.0 ← KEY NEW PARAMETER       │
                       └──────────────┬───────────────────────┘
                                      │ LATENT
                                      ▼
                       ┌──────────────────────────────────────┐
                       │  VAEDecodeAudio                      │
                       │  samples: LATENT                     │
                       │  vae: VAE from CheckpointLoader      │
                       └──────────────┬───────────────────────┘
                                      │ AUDIO
                                      ▼
                           → SaveAudioMP3, PreviewAudio,
                             VHS_VideoCombine, YouTubeUploader
```

### Phase 4: Key Parameter Changes

| Parameter | Old Value | New Value | Reason |
|-----------|-----------|-----------|--------|
| `steps` | 50 | 8 | Turbo model optimized for 8 steps |
| `denoise` | 0.75 | 1.0 | Fresh generation, not inpainting |
| `shift` | N/A | 3.0 | Key quality improvement |
| `llm_audio_codes` | N/A | True | Enable 4B LM planner |
| `cfg_scale` (encoder) | 1 | 2.0 | Better text adherence |

### Phase 5: Verify & Test

1. Restart ComfyUI, check logs for scromfyUI nodes loaded
2. Run test generation with new nodes
3. Verify downstream connections work (audio → save/video/upload)
4. Check VRAM usage (should be ~20GB with 4B LM on 96GB GPU)

### Phase 6: Documentation

1. Update `/home/teja/music-generation-pipeline/COMFYDESIGN.md` Stage 3A section
2. Update `/home/teja/music-generation-pipeline/PLAN.md`
3. Export workflow: `/home/teja/music-generation-pipeline/scripts/update-pipeline.sh`

## Critical Files

- **Source repo**: https://github.com/scruffynerf/scromfyUI-AceStep
- **ACE-Step reference**: https://github.com/ace-step/ACE-Step-1.5.git (remote: `acestep`)
- **Workflow JSON**: `/home/teja/music-generation-pipeline/workflows/music-generation-pipeline-v2-scromfy.json`
- **4B Model**: `ACE-Step/acestep-5Hz-lm-4B` on HuggingFace
- **Model location**: `models/checkpoints/acestep-5Hz-lm-4B/`

## Risks & Mitigations

1. **Conflict with billwuhao nodes**: Keep both initially, remove if class name collisions
2. **VRAM with 4B LM**: 96GB VRAM is sufficient; monitor with nvidia-smi
3. **shift parameter not supported by CheckpointLoaderSimple model**: The shift is applied via KSampler, not model-dependent
4. **llm_audio_codes requires 4B model**: Must download model before enabling this toggle
