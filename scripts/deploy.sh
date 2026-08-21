#!/bin/bash
# =============================================================================
# Ranch PHX — build + deploy (run this on the server)
# Usage: bash ~/ranch_phx/scripts/deploy.sh
# =============================================================================
set -e

APP_DIR="$HOME/ranch_phx"
RELEASE="$APP_DIR/_build/prod/rel/ranch_phx/bin/ranch_phx"
ENV_FILE="/etc/ranch_phx/env"

echo ""
echo "╔═══════════════════════════════════════╗"
echo "║   Ranch PHX Deploy                    ║"
echo "╚═══════════════════════════════════════╝"
echo ""

if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: $ENV_FILE not found."
  echo "Create it from scripts/../infra/ranch_phx.env.template and fill in values."
  exit 1
fi

cd "$APP_DIR"

# Load prod env for build steps
set -a
source "$ENV_FILE"
set +a

# ── 1. Hex + Rebar ────────────────────────────────────────────────────────────
echo ">>> Updating hex and rebar..."
mix local.hex --force --if-missing
mix local.rebar --force --if-missing

# ── 2. Dependencies ───────────────────────────────────────────────────────────
echo ">>> Fetching dependencies..."
MIX_ENV=prod mix deps.get --only prod

# ── 3. Compile ────────────────────────────────────────────────────────────────
echo ">>> Compiling..."
MIX_ENV=prod mix compile

# ── 4. Assets ─────────────────────────────────────────────────────────────────
echo ">>> Compiling assets..."
MIX_ENV=prod mix assets.deploy

# ── 5. Release ────────────────────────────────────────────────────────────────
echo ">>> Building release..."
MIX_ENV=prod mix release --overwrite

# ── 6. Migrations ─────────────────────────────────────────────────────────────
echo ">>> Running migrations..."
"$RELEASE" eval "RanchPhx.Release.migrate()"

# ── 7. Restart service ────────────────────────────────────────────────────────
echo ">>> Restarting ranch_phx service..."
if sudo systemctl is-active --quiet ranch_phx; then
  sudo systemctl restart ranch_phx
else
  sudo systemctl start ranch_phx
fi

sleep 2

if sudo systemctl is-active --quiet ranch_phx; then
  echo ""
  echo "  ✓ Ranch PHX is running."
  echo "  Logs: sudo journalctl -u ranch_phx -f"
else
  echo ""
  echo "  ✗ Ranch PHX failed to start. Check logs:"
  sudo journalctl -u ranch_phx -n 30 --no-pager
  exit 1
fi

echo ""
