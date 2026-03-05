# ACE-Step Migration Specification

## Overview

This spec documents the migration from ACE-Step AIO checkpoint to **scromfyUI-AceStep** custom nodes, which provides the 4B LM planner for chain-of-thought reasoning and additional control parameters.

## Relationship to PLAN.md

- **PLAN.md**: Overall pipeline implementation (5 stages, all components)
- **PLAN2.md**: Specific migration plan for ACE-Step component
- **This spec**: Implementation details with parallelization strategy

## Migration Scope

Replace nodes 6-11 in the workflow:

| Node | Old | New |
|------|-----|-----|
| 6 | `CheckpointLoaderSimple` → AIO model | `AceStepLLMLoader` + `CheckpointLoaderSimple` |
| 7 | `EmptyAceStep1.5LatentAudio` | (unchanged) |
| 8 | `TextEncodeAceStepAudio1.5` (positive) | `ScromfyACEStep15TaskTextEncodeNode` |
| 10 | `KSampler` | + `shift` parameter |
| 11 | `VAEDecodeAudio` | (unchanged) |
| 38 | `TextEncodeAceStepAudio1.5` (negative) | `ScromfyACEStep15TaskTextEncodeNode` |

## New Capabilities

| Parameter | Old | New | Purpose |
|-----------|-----|-----|---------|
| `shift` | N/A | 3.0 | Quality improvement |
| `llm_audio_codes` | N/A | True | Enable 4B LM planner |
| `cfg_scale` | 1 | 2.0 | Better text adherence |
| `steps` | 50 | 8 | Turbo model optimized |
| `denoise` | 0.75 | 1.0 | Fresh generation |

## Implementation Architecture

### Coordinator Pattern

Use a lead agent to coordinate parallel workers:

```
Lead Agent (Coordinator)
  - Does NO execution work
  - Tracks task status and dependency resolution
  - Signals workers when dependencies are met
  - Uses TaskUpdate to manage task states

Worker A: Install scromfyUI-AceStep nodes
Worker B: Download acestep-5Hz-lm-4B model
Worker C: Update workflow JSON (depends on A+B)
Worker D: Update documentation (depends on C)
```

### Dependencies

| Task | Blocked By | Can Start |
|------|------------|-----------|
| Worker A: Install nodes | - | Immediately |
| Worker B: Download model | - | Immediately |
| Worker C: Update workflow | A, B | After both complete |
| Worker D: Update docs | C | After C completes |

### Task Specifications

#### Worker A: Install scromfyUI-AceStep Nodes
```
Commands:
  cd /home/teja/Documents/comfy/ComfyUI/custom_nodes
  git clone https://github.com/scruffynerf/scromfyUI-AceStep
  cd scromfyUI-AceStep && pip install -r requirements.txt

Verification:
  - Check nodes appear in ComfyUI
  - Check no class name conflicts with billwuhao nodes
```

#### Worker B: Download 4B LM Model
```
Commands:
  huggingface-cli download ACE-Step/acestep-5Hz-lm-4B \
    --local-dir /home/teja/Documents/comfy/ComfyUI/models/checkpoints/acestep-5Hz-lm-4B

Verification:
  - File exists: models/checkpoints/acestep-5Hz-lm-4B/config.json
  - Model loads in AceStepLLMLoader
```

#### Worker C: Update Workflow JSON
```
Steps:
  1. Duplicate workflow:
     cp workflows/music-generation-pipeline.json workflows/music-generation-pipeline-v2-scromfy.json
  2. Replace nodes 6-11 as specified in Migration Scope above
  3. Add AceStep5HzLMConfig node

Parameter changes:
  - steps: 50 → 8
  - denoise: 0.75 → 1.0
  - shift: N/A → 3.0 (NEW)
  - llm_audio_codes: N/A → True (NEW)
  - cfg_scale: 1 → 2.0
```

#### Worker D: Update Documentation
```
Files:
  - COMFYDESIGN.md Stage 3A section
  - PLAN.md
  - Export workflow via scripts/update-pipeline.sh
```

### Coordination Flow

```
1. Lead creates 4 tasks with TaskCreate:
   - task_A: "Install scromfyUI-AceStep nodes" (status: pending)
   - task_B: "Download 4B LM model" (status: pending)
   - task_C: "Update workflow JSON" (status: pending, blockedBy: [A,B])
   - task_D: "Update documentation" (status: pending, blockedBy: [C])

2. Lead tells Worker A and Worker B to start (no deps)

3. Worker A completes → TaskUpdate status=completed → tells Lead
   Worker B completes → TaskUpdate status=completed → tells Lead

4. Lead receives both done notifications:
   - TaskUpdate task_C: remove blockedBy → status=in_progress

5. Worker C runs, completes → TaskUpdate status=completed → tells Lead

6. Lead: TaskUpdate task_D: remove blockedBy → status=in_progress

7. Worker D completes → TaskUpdate status=completed → done
```

## Files

- **Source workflow**: `workflows/music-generation-pipeline.json`
- **New workflow**: `workflows/music-generation-pipeline-v2-scromfy.json`
- **Spec**: `SPEC.md` (this file)
- **Migration plan**: `PLAN2.md`

## External Resources

- scromfyUI-AceStep: https://github.com/scruffynerf/scromfyUI-AceStep
- 4B LM model: `ACE-Step/acestep-5Hz-lm-4B` on HuggingFace

## Verification

1. ComfyUI restart → scromfyUI nodes loaded
2. Test generation with v2 workflow
3. VRAM check (~20GB with 4B LM)
4. Audio quality with shift=3.0
