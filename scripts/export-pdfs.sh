#!/usr/bin/env bash
# export-pdfs.sh --- Export locally-built reveal.js presentations to PDF.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PUBLIC_DIR="$ROOT/docs/public"
TALKS_DIR="$PUBLIC_DIR/talks"
PDF_PORT="${PDF_PORT:-8090}"
SERVER_LOG="$(mktemp)"
SERVER_PID=""

cleanup() {
    if [ -n "$SERVER_PID" ]; then
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
    rm -f "$SERVER_LOG"
}
trap cleanup EXIT

if [ "$#" -eq 0 ]; then
    echo "Usage: $0 TALK_SLUG [TALK_SLUG ...]" >&2
    exit 2
fi

for slug in "$@"; do
    if [ ! -f "$TALKS_DIR/$slug.html" ]; then
        echo "Missing presentation: $TALKS_DIR/$slug.html. Run make html first." >&2
        exit 1
    fi
done

python3 -m http.server "$PDF_PORT" --bind 127.0.0.1 --directory "$PUBLIC_DIR" >"$SERVER_LOG" 2>&1 &
SERVER_PID=$!

for _ in $(seq 1 20); do
    if curl -fsS -o /dev/null "http://127.0.0.1:$PDF_PORT/"; then
        break
    fi
    sleep 0.5
done

if ! curl -fsS -o /dev/null "http://127.0.0.1:$PDF_PORT/"; then
    echo "PDF export server did not start on port $PDF_PORT:" >&2
    cat "$SERVER_LOG" >&2
    exit 1
fi

for slug in "$@"; do
    output="$TALKS_DIR/$slug.pdf"
    echo "==> Exporting $slug.pdf"
    decktape reveal \
        --size 1280x720 \
        --pause 100 \
        --chrome-arg=--no-sandbox \
        "http://127.0.0.1:$PDF_PORT/talks/$slug.html" \
        "$output"
done
