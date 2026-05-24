#!/usr/bin/env bash
# Hot-reload the strmvod plugin inside the running Dispatcharr container.
# Edits to plugin/plugin.py are live-mounted; this just tells Dispatcharr to re-import.

set -euo pipefail

DISPATCHARR_URL="${DISPATCHARR_URL:-http://localhost:9193}"
API_USER="${DISPATCHARR_USER:-strmvod}"
API_PASS="${DISPATCHARR_PASS:-TESLA!bye0tenner}"

TOKEN=$(curl -sf -X POST "${DISPATCHARR_URL}/api/accounts/token/" \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"${API_USER}\",\"password\":\"${API_PASS}\"}" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access'])")

RESULT=$(curl -sf -X POST "${DISPATCHARR_URL}/api/plugins/plugins/reload/" \
  -H "Authorization: Bearer ${TOKEN}")

echo "Plugin reload: ${RESULT}"
