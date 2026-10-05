#!/usr/bin/env bash
set -euo pipefail

# Deploy the API behind an existing HTTPS reverse proxy and systemd service.
# Secrets must be provided by the host environment or an external secret
# manager. This script never writes .env files, moves application directories,
# kills unrelated processes, or exposes the API directly to the Internet.

: "${DEEPSEEK_API_KEY:?Set DEEPSEEK_API_KEY in the service environment}"

APP_DIR="${WANYU_APP_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
BIND_HOST="${WANYU_BIND_HOST:-127.0.0.1}"
BIND_PORT="${WANYU_PORT:-8000}"

cd "$APP_DIR"
python3 -m py_compile server.py

echo "Starting Wanyu API on ${BIND_HOST}:${BIND_PORT}."
echo "Place this service behind an HTTPS reverse proxy before connecting release builds."
exec uvicorn server:app --host "$BIND_HOST" --port "$BIND_PORT"
