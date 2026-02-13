#!/bin/bash
# Script to update the music-generation-pipeline repository
# This script handles: MD files, workflow JSON with credential redaction

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== Updating music-generation-pipeline ==="

# Step 1: Check for git changes
echo "[1/4] Checking git status..."
if ! git diff --quiet; then
    echo "Warning: There are uncommitted changes. Please commit or stash them first."
    git status
    exit 1
fi

# Step 2: Update workflow JSON from ComfyUI
echo "[2/4] Updating workflow JSON..."
WORKFLOW_SOURCE="/home/teja/Documents/comfy/ComfyUI/user/default/workflows/music-generation-pipeline.json"
WORKFLOW_DEST="workflows/music-generation-pipeline.json"

if [ ! -f "$WORKFLOW_SOURCE" ]; then
    echo "Error: Workflow source not found at $WORKFLOW_SOURCE"
    exit 1
fi

# Create workflows directory if it doesn't exist
mkdir -p workflows

# Copy and redact credentials using Python
python3 -c "
import json
import sys

try:
    with open('$WORKFLOW_SOURCE', 'r') as f:
        data = json.load(f)

    # Find the YouTubeAuthNode and clear credentials
    for node in data.get('nodes', []):
        if node.get('type') == 'YouTubeAuthNode':
            # Clear client_id and client_secret in widgets_values
            if isinstance(node.get('widgets_values'), list) and len(node['widgets_values']) >= 3:
                node['widgets_values'][0] = ''
                node['widgets_values'][1] = ''

    with open('$WORKFLOW_DEST', 'w') as f:
        json.dump(data, f)

    print('Workflow updated and credentials redacted successfully')
except Exception as e:
    print(f'Error: {e}', file=sys.stderr)
    sys.exit(1)
"

# Step 3: Stage all changes
echo "[3/4] Staging changes..."
git add -A

# Check if there are any changes to commit
if git diff --cached --quiet; then
    echo "No changes to commit."
    exit 0
fi

# Step 4: Commit and push
echo "[4/4] Committing and pushing..."

# Get a brief summary of changes for the commit message
CHANGES=$(git diff --cached --stat | tail -1)
COMMIT_MSG="Update: $(date '+%Y-%m-%d %H:%M:%S')

Changes:
$CHANGES

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
"

git commit -m "$COMMIT_MSG"
git push origin main

echo "=== Update complete ==="