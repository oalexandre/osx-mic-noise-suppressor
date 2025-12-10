#!/bin/bash
# MicNoiseGate Driver Installation Script
# Requires sudo privileges

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DRIVER_PATH="$SCRIPT_DIR/build/MicNoiseGate.driver"
INSTALL_PATH="/Library/Audio/Plug-Ins/HAL/MicNoiseGate.driver"

echo "=== MicNoiseGate Driver Installer ==="
echo ""

# Check if driver is built
if [ ! -d "$DRIVER_PATH" ]; then
    echo "Error: Driver not found at $DRIVER_PATH"
    echo "Please run ./build.sh first"
    exit 1
fi

# Remove old driver if exists
if [ -d "$INSTALL_PATH" ]; then
    echo "Removing existing driver..."
    sudo rm -rf "$INSTALL_PATH"
fi

# Copy driver
echo "Installing driver to $INSTALL_PATH..."
sudo cp -R "$DRIVER_PATH" "$INSTALL_PATH"

# Set permissions
echo "Setting permissions..."
sudo chown -R root:wheel "$INSTALL_PATH"
sudo chmod -R 755 "$INSTALL_PATH"

# Restart coreaudiod
echo "Restarting coreaudiod service..."
sudo launchctl kickstart -kp system/com.apple.audio.coreaudiod

echo ""
echo "=== Installation complete! ==="
echo "The 'MicNoiseGate Mic' should now appear in your audio devices."
echo ""
echo "To verify, run:"
echo "  system_profiler SPAudioDataType | grep -A5 'MicNoiseGate'"
