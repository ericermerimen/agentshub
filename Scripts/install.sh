#!/usr/bin/env bash
set -euo pipefail

# AgentPing - One-step build and install
# Requires: macOS 14+, Xcode 15+ (or swift 5.9+)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "==> Building and packaging AgentPing..."
"$SCRIPT_DIR/package_app.sh" --release

echo ""
echo "==> Installing to /Applications..."
rm -rf /Applications/AgentPing.app
cp -r "$PROJECT_DIR/AgentPing.app" /Applications/

echo "==> Installing CLI to /usr/local/bin..."
sudo mkdir -p /usr/local/bin
sudo ln -sf /Applications/AgentPing.app/Contents/MacOS/agentping /usr/local/bin/agentping

echo ""
echo "==> Installation complete!"
echo ""
echo "Start the app:   open /Applications/AgentPing.app"
echo "CLI help:         agentping --help"
echo ""
echo "To set up Claude Code hooks, open AgentPing preferences"
echo "and click 'Copy Hook Config to Clipboard', then paste"
echo "into ~/.claude/settings.json"
