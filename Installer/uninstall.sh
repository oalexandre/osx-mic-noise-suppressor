#!/bin/bash
# MicNoiseGate Uninstaller Script
# Removes the app and audio driver from the system

set -e

echo "=== MicNoiseGate Uninstaller ==="
echo ""

# Check for root
if [ "$EUID" -ne 0 ]; then
    echo "This script requires administrator privileges."
    echo "Please run with: sudo $0"
    exit 1
fi

APP_PATH="/Applications/MicNoiseGate.app"
DRIVER_PATH="/Library/Audio/Plug-Ins/HAL/MicNoiseGate.driver"
SHM_NAME="/micnoisegate_audio"

# Stop the app if running
echo "Stopping MicNoiseGate if running..."
pkill -9 MicNoiseGate 2>/dev/null || true
sleep 1

# Remove app
if [ -d "$APP_PATH" ]; then
    echo "Removing MicNoiseGate.app..."
    rm -rf "$APP_PATH"
    echo "  Removed $APP_PATH"
else
    echo "  App not found at $APP_PATH"
fi

# Remove driver
if [ -d "$DRIVER_PATH" ]; then
    echo "Removing MicNoiseGate.driver..."
    rm -rf "$DRIVER_PATH"
    echo "  Removed $DRIVER_PATH"
else
    echo "  Driver not found at $DRIVER_PATH"
fi

# Clean up shared memory
echo "Cleaning up shared memory..."
rm -f "/dev/shm$SHM_NAME" 2>/dev/null || true

# Restart coreaudiod to unload driver
echo "Restarting coreaudiod..."
launchctl kickstart -kp system/com.apple.audio.coreaudiod

# Remove receipts
echo "Removing installer receipts..."
pkgutil --forget com.micnoisegate.app 2>/dev/null || true
pkgutil --forget com.micnoisegate.driver 2>/dev/null || true

echo ""
echo "=== Uninstall Complete! ==="
echo "MicNoiseGate has been removed from your system."
echo ""
echo "The 'MicNoiseGate Mic' audio device is no longer available."
