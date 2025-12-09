#!/bin/bash
set -e

cd "$(dirname "$0")"

echo "Building MicNoiseGate..."
PKG_CONFIG_PATH=$HOME/.local/lib/pkgconfig:$PKG_CONFIG_PATH swift build -c release

echo "Creating app bundle..."
rm -rf MicNoiseGate.app
mkdir -p MicNoiseGate.app/Contents/MacOS
mkdir -p MicNoiseGate.app/Contents/Resources
mkdir -p MicNoiseGate.app/Contents/Frameworks

cp .build/release/MicNoiseGate MicNoiseGate.app/Contents/MacOS/
cp Info.plist MicNoiseGate.app/Contents/

# Copy RNNoise library
echo "Bundling RNNoise library..."
cp $HOME/.local/lib/librnnoise.0.dylib MicNoiseGate.app/Contents/Frameworks/

# Update library path in executable to use bundled library
install_name_tool -add_rpath @executable_path/../Frameworks MicNoiseGate.app/Contents/MacOS/MicNoiseGate 2>/dev/null || true
install_name_tool -change /usr/local/lib/librnnoise.0.dylib @rpath/librnnoise.0.dylib MicNoiseGate.app/Contents/MacOS/MicNoiseGate

echo "Done! Run with: open MicNoiseGate.app"
