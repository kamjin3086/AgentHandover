#!/usr/bin/env bash
set -euo pipefail

echo "=== OpenMimic Uninstaller ==="
echo ""

# Stop services
echo "Stopping services..."
launchctl unload ~/Library/LaunchAgents/com.openmimic.daemon.plist 2>/dev/null || true
launchctl unload ~/Library/LaunchAgents/com.openmimic.worker.plist 2>/dev/null || true

# Remove launchd plists
echo "Removing launchd plists..."
rm -f ~/Library/LaunchAgents/com.openmimic.daemon.plist
rm -f ~/Library/LaunchAgents/com.openmimic.worker.plist

# Remove binaries
echo "Removing binaries..."
sudo rm -f /usr/local/bin/oc-apprentice-daemon
sudo rm -f /usr/local/bin/openmimic

# Remove native messaging host
echo "Removing native messaging host..."
rm -f ~/Library/Application\ Support/Google/Chrome/NativeMessagingHosts/com.openclaw.apprentice.json

# Remove lib directory (venv, extension, etc.)
echo "Removing library files..."
sudo rm -rf /usr/local/lib/openmimic

# Remove app bundle
echo "Removing app..."
rm -rf /Applications/OpenMimic.app

# Remove PID and status files
echo "Removing runtime files..."
rm -f ~/Library/Application\ Support/oc-apprentice/daemon.pid
rm -f ~/Library/Application\ Support/oc-apprentice/worker.pid
rm -f ~/Library/Application\ Support/oc-apprentice/daemon-status.json
rm -f ~/Library/Application\ Support/oc-apprentice/worker-status.json

echo ""
echo "Uninstall complete."
echo ""
echo "User data preserved at: ~/Library/Application Support/oc-apprentice/"
echo "  (database, config, logs)"
echo ""
echo "To also remove user data, run:"
echo "  rm -rf ~/Library/Application\\ Support/oc-apprentice/"
