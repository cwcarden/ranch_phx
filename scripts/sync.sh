#!/bin/bash
# =============================================================================
# Ranch PHX — sync source from Mac to server
# Run from your Mac: bash scripts/sync.sh
# =============================================================================
set -e

SERVER="portal"
REMOTE_DIR="/opt/ranch_phx"

echo ">>> Syncing ranch_phx source to $SERVER:$REMOTE_DIR ..."

rsync -avz --progress \
  --exclude '_build' \
  --exclude 'deps' \
  --exclude '.git' \
  --exclude 'node_modules' \
  --exclude '*.log' \
  --exclude 'priv/static/assets' \
  . "$SERVER:$REMOTE_DIR/"

echo ""
echo ">>> Synced. To deploy, run on the server:"
echo "    ssh portal"
echo "    bash ~/ranch_phx/scripts/deploy.sh"
echo ""
