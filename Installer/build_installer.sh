#!/bin/bash
# MicNoiseGate Installer Build Script
# Creates a PKG installer that includes the app and audio driver

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$SCRIPT_DIR/build"
OUTPUT_DIR="$PROJECT_DIR/dist"
VERSION="1.0.0"

echo "=== MicNoiseGate Installer Builder ==="
echo "Version: $VERSION"
echo ""

# Clean previous build
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/app_root/Applications"
mkdir -p "$BUILD_DIR/driver_root/Library/Audio/Plug-Ins/HAL"
mkdir -p "$BUILD_DIR/packages"
mkdir -p "$OUTPUT_DIR"

# Step 1: Build the App
echo "[1/4] Building MicNoiseGate.app..."
cd "$PROJECT_DIR/MicNoiseGate"

# Build app in a clean temporary location to avoid permission conflicts
APP_BUILD_DIR="$BUILD_DIR/app_build"
mkdir -p "$APP_BUILD_DIR"

echo "Building for production..."
PKG_CONFIG_PATH=$HOME/.local/lib/pkgconfig:$PKG_CONFIG_PATH swift build -c release

echo "Creating app bundle..."
mkdir -p "$APP_BUILD_DIR/MicNoiseGate.app/Contents/MacOS"
mkdir -p "$APP_BUILD_DIR/MicNoiseGate.app/Contents/Resources"
mkdir -p "$APP_BUILD_DIR/MicNoiseGate.app/Contents/Frameworks"

cp .build/release/MicNoiseGate "$APP_BUILD_DIR/MicNoiseGate.app/Contents/MacOS/"
cp Info.plist "$APP_BUILD_DIR/MicNoiseGate.app/Contents/"

# Copy RNNoise library
cp $HOME/.local/lib/librnnoise.0.dylib "$APP_BUILD_DIR/MicNoiseGate.app/Contents/Frameworks/"

# Update library path in executable
install_name_tool -add_rpath @executable_path/../Frameworks "$APP_BUILD_DIR/MicNoiseGate.app/Contents/MacOS/MicNoiseGate" 2>/dev/null || true
install_name_tool -change /usr/local/lib/librnnoise.0.dylib @rpath/librnnoise.0.dylib "$APP_BUILD_DIR/MicNoiseGate.app/Contents/MacOS/MicNoiseGate"

if [ ! -d "$APP_BUILD_DIR/MicNoiseGate.app" ]; then
    echo "Error: MicNoiseGate.app not found"
    exit 1
fi

cp -R "$APP_BUILD_DIR/MicNoiseGate.app" "$BUILD_DIR/app_root/Applications/"

# Step 2: Build the Driver
echo "[2/4] Building MicNoiseGate.driver..."
cd "$PROJECT_DIR/Driver"

# Clean and build driver
rm -rf build
mkdir build
cd build
cmake .. > /dev/null
make > /dev/null

if [ ! -d "MicNoiseGate.driver" ]; then
    echo "Error: MicNoiseGate.driver not found"
    exit 1
fi

cp -R "MicNoiseGate.driver" "$BUILD_DIR/driver_root/Library/Audio/Plug-Ins/HAL/"

# Step 3: Create component packages
echo "[3/4] Creating component packages..."

# App package
pkgbuild --root "$BUILD_DIR/app_root" \
         --identifier "com.micnoisegate.app" \
         --version "$VERSION" \
         --install-location "/" \
         "$BUILD_DIR/packages/MicNoiseGate-App.pkg"

# Driver package (with postinstall script)
pkgbuild --root "$BUILD_DIR/driver_root" \
         --identifier "com.micnoisegate.driver" \
         --version "$VERSION" \
         --install-location "/" \
         --scripts "$SCRIPT_DIR/scripts" \
         "$BUILD_DIR/packages/MicNoiseGate-Driver.pkg"

# Step 4: Create the final product
echo "[4/4] Creating final installer..."

cd "$BUILD_DIR/packages"

productbuild --distribution "$SCRIPT_DIR/Distribution.xml" \
             --resources "$SCRIPT_DIR/resources" \
             --package-path "$BUILD_DIR/packages" \
             "$OUTPUT_DIR/MicNoiseGate-Installer-$VERSION.pkg"

echo ""
echo "=== Build Complete! ==="
echo "Installer created: $OUTPUT_DIR/MicNoiseGate-Installer-$VERSION.pkg"
echo ""
echo "To install, run:"
echo "  sudo installer -pkg \"$OUTPUT_DIR/MicNoiseGate-Installer-$VERSION.pkg\" -target /"
echo ""
echo "Or double-click the .pkg file to use the graphical installer."
