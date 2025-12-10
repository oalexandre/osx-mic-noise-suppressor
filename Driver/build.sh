#!/bin/bash
set -e

cd "$(dirname "$0")"

echo "=== Building MicNoiseGate Driver ==="

# Create build directory
mkdir -p build
cd build

# Configure with CMake
echo "Configuring..."
cmake .. -DCMAKE_BUILD_TYPE=Release

# Build
echo "Building..."
cmake --build . --config Release

echo ""
echo "=== Build complete! ==="
echo "Driver bundle: $(pwd)/MicNoiseGate.driver"
echo ""
echo "To install manually:"
echo "  sudo cp -R MicNoiseGate.driver /Library/Audio/Plug-Ins/HAL/"
echo "  sudo launchctl kickstart -kp system/com.apple.audio.coreaudiod"
