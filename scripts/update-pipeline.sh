#!/bin/bash
# Script to update the music-generation-pipeline repository
# This script handles: MD files, workflow JSON with credential redaction

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

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

# Create workflows directory if it doesn't exist
mkdir -p workflows

# Helper function to copy and redact a workflow
update_workflow() {
    local source=$1
    local dest=$2

    if [ ! -f "$source" ]; then
        echo "Error: Workflow source not found at $source"
        exit 1
    fi

    python3 -c "
import json
import sys

try:
    with open('$source', 'r') as f:
        data = json.load(f)

    # Find the YouTubeAuthNode and clear credentials
    for node in data.get('nodes', []):
        if node.get('type') == 'YouTubeAuthNode':
            # Clear client_id and client_secret in widgets_values
            if isinstance(node.get('widgets_values'), list) and len(node['widgets_values']) >= 3:
                node['widgets_values'][0] = ''
                node['widgets_values'][1] = ''

    with open('$dest', 'w') as f:
        json.dump(data, f)

    print(f'Updated: $dest')
except Exception as e:
    print(f'Error: {e}', file=sys.stderr)
    sys.exit(1)
"
}

# Update primary workflow
update_workflow "/home/teja/Documents/comfy/ComfyUI/user/default/workflows/music-generation-pipeline.json" "workflows/music-generation-pipeline.json"

# Update v4 workflow
update_workflow "/home/teja/Documents/comfy/ComfyUI/user/default/workflows/music-generation-pipeline-v4.json" "workflows/music-generation-pipeline-v4.json"

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