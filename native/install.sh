#!/usr/bin/env bash
# install.sh — Claude Usage Monitor setup script
# Usage:
#   ./install.sh              (first run — installs manifest template)
#   ./install.sh --id <ID>    (second run — injects real extension ID)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST_SRC="$SCRIPT_DIR/com.claudeusage.menubar.json"
PYTHON_SCRIPT="$SCRIPT_DIR/claude_usage.py"
REAL_USER="$(whoami)"
REAL_PATH="$PYTHON_SCRIPT"

# Native messaging host directories
CHROME_DIR="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
CANARY_DIR="$HOME/Library/Application Support/Google/Chrome Canary/NativeMessagingHosts"

EXT_ID=""

# ── Parse args ────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --id)
      EXT_ID="${2:-}"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1"
      echo "Usage: $0 [--id <EXTENSION_ID>]"
      exit 1
      ;;
  esac
done

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║   Claude Usage Monitor — Install Script       ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# ── Make Python script executable ─────────────────────────────────────────────
chmod +x "$PYTHON_SCRIPT"
echo "✓ Made claude_usage.py executable"

# ── Generate the manifest with real path and optionally real extension ID ──────
generate_manifest() {
  local dest_dir="$1"
  local ext_id="${2:-YOUR_EXTENSION_ID}"

  mkdir -p "$dest_dir"

  cat > "$dest_dir/com.claudeusage.menubar.json" <<EOF
{
  "name": "com.claudeusage.menubar",
  "description": "Claude Usage Monitor native messaging host",
  "path": "$REAL_PATH",
  "type": "stdio",
  "allowed_origins": [
    "chrome-extension://$ext_id/"
  ]
}
EOF
  echo "✓ Manifest installed → $dest_dir/com.claudeusage.menubar.json"
}

# Also update the source copy for reference
cat > "$MANIFEST_SRC" <<EOF
{
  "name": "com.claudeusage.menubar",
  "description": "Claude Usage Monitor native messaging host",
  "path": "$REAL_PATH",
  "type": "stdio",
  "allowed_origins": [
    "chrome-extension://${EXT_ID:-YOUR_EXTENSION_ID}/"
  ]
}
EOF

# ── Detect Chrome installations ────────────────────────────────────────────────
CHROME_FOUND=false
CANARY_FOUND=false

if [[ -d "/Applications/Google Chrome.app" ]]; then
  CHROME_FOUND=true
fi
if [[ -d "/Applications/Google Chrome Canary.app" ]]; then
  CANARY_FOUND=true
fi

if [[ "$CHROME_FOUND" == false && "$CANARY_FOUND" == false ]]; then
  echo "⚠  Neither Google Chrome nor Chrome Canary found in /Applications."
  echo "   Installing manifest to both potential host directories anyway."
  CHROME_FOUND=true
fi

# ── Install manifests ──────────────────────────────────────────────────────────
if [[ "$CHROME_FOUND" == true ]]; then
  generate_manifest "$CHROME_DIR" "$EXT_ID"
fi

if [[ "$CANARY_FOUND" == true ]]; then
  generate_manifest "$CANARY_DIR" "$EXT_ID"
fi

# ── Done ───────────────────────────────────────────────────────────────────────
echo ""

if [[ -z "$EXT_ID" ]]; then
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "NEXT STEPS:"
  echo ""
  echo "1. Open Chrome → chrome://extensions"
  echo "2. Enable Developer Mode (top-right toggle)"
  echo "3. Click 'Load unpacked' → select:"
  echo "   $(dirname "$SCRIPT_DIR")/extension"
  echo ""
  echo "4. Copy the Extension ID shown on the card"
  echo ""
  echo "5. Re-run this script with your extension ID:"
  echo "   $0 --id <PASTE_ID_HERE>"
  echo ""
  echo "6. Then start the menu bar app:"
  echo "   python3 $PYTHON_SCRIPT"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
else
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "✓ Installation complete with Extension ID: $EXT_ID"
  echo ""
  echo "Start the menu bar app with:"
  echo "  python3 $PYTHON_SCRIPT"
  echo ""
  echo "Keep a chrome.ai/settings/usage tab open, or let"
  echo "the extension open one automatically on the first"
  echo "refresh cycle."
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
fi

echo ""
