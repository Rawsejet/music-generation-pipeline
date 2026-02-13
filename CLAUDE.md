# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Project Is

This is a **documentation and design repo** for an automated music video pipeline built entirely in ComfyUI. There is no application code here — the repo contains design documents that describe a ComfyUI workflow connecting 5 stages:

1. **Stage 1** — Randomized attribute selection (Dynamic Prompts wildcards)
2. **Stage 2** — LLM creative expansion (Qwen3-32B via Ollama → tags, lyrics, image prompt)
3. **Stage 3A/3B** — Music generation (ACE-Step 1.5) + Image generation (FLUX.2 Dev)
4. **Stage 4** — Video assembly (Video Helper Suite → MP4)
5. **Stage 5** — YouTube upload

The actual ComfyUI installation lives at `/home/teja/Documents/comfy/ComfyUI/`.

## Key Files

- `pipeline.md` — Comprehensive reference for all pipeline components, model choices, node options, prompt templates, and integration details
- `COMFYDESIGN.md` — Node-by-node workflow specification with exact parameters, wiring diagrams, and step-by-step build instructions
- `PLAN.md` — Implementation plan with phases, progress tracking, and next steps

## Hardware

Dual RTX PRO 6000 Blackwell GPUs (96GB VRAM each). GPU 0 runs ComfyUI, GPU 1 runs Ollama.

## Current State (Phase 5)

Steps 1–5 are DONE (RandomPrompt, LLM nodes, ACE-Step music, FLUX.2 image, video assembly). Remaining:
- Step 6: YouTube upload node
- Step 7: Wire all stages together — **text splitting** (parsing LLM output into separate TAGS, LYRICS, IMAGE_PROMPT strings) is the key unsolved challenge

## Critical Domain Knowledge

- **ACE-Step golden rule**: Lyrics must have 6–10 syllables per line. This matters more than any other quality factor.
- **FLUX.2 Dev uses separate loaders** (UNETLoader, CLIPLoader, VAELoader), NOT CheckpointLoaderSimple.
- **FLUX.2 text encoder**: Mistral 3 Small (`mistral_3_small_flux2_fp8.safetensors`), not T5-XXL.
- **comfyui_LLM_party node names** have emoji prefixes: search "API LLM Loader" to find `☁️API LLM Loader`. The LLM node exposes `temperature` and `max_length` only — `top_p`, `top_k`, `repeat_penalty` must be baked into an Ollama Modelfile.
- **LLM output format** uses `=== TAGS ===`, `=== LYRICS ===`, `=== IMAGE_PROMPT ===` section markers that need regex parsing.
- **YouTube API quota**: 6 uploads/day max (9,900 of 10,000 units). Failed requests still consume quota.

## Development Workflow

**Updating the repository**: Run `scripts/update-pipeline.sh` to:
1. Update `workflows/music-generation-pipeline.json` from ComfyUI
2. Redact YouTube OAuth credentials (client_id, client_secret)
3. Commit and push all changes

**Manual workflow updates** (if not using the script):
1. Copy workflow: `cp /path/to/ComfyUI/user/default/workflows/music-generation-pipeline.json workflows/`
2. Redact credentials (set client_id and client_secret to empty strings in YouTubeAuthNode)
3. `git add -A && git commit -m "Update: $(date)" && git push origin main`
