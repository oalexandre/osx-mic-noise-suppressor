# Installer Documentation

MicNoiseGate uses a PKG installer to deploy the app and audio driver to user systems.

## Overview

The installer is a standard macOS PKG file created using Apple's `pkgbuild` and `productbuild` tools.

### What Gets Installed

| Component | Destination |
|-----------|-------------|
| MicNoiseGate.app | `/Applications/` |
| MicNoiseGate.driver | `/Library/Audio/Plug-Ins/HAL/` |

### Why PKG?

- **Standard macOS format**: Users expect .pkg files
- **Admin privileges**: Can install to protected locations
- **Receipts**: macOS tracks what was installed
- **Scripting**: Pre/post install scripts
- **Customization**: Welcome, license, and conclusion screens

## Project Structure

```
Installer/
├── build_installer.sh      # Main build script
├── Distribution.xml        # Installer configuration
├── resources/
│   ├── Welcome.html        # Welcome screen content
│   ├── Conclusion.html     # Completion screen content
│   └── background.png      # (optional) Background image
├── scripts/
│   ├── preinstall          # Runs before installation
│   └── postinstall         # Runs after installation
└── build/                  # Build output (generated)
    ├── app_root/           # App files for packaging
    ├── driver_root/        # Driver files for packaging
    └── packages/           # Component packages
```

## Build Process

### build_installer.sh

The main script that orchestrates the build:

```bash
#!/bin/bash
set -e

VERSION="1.0.0"
BUILD_DIR="./build"
OUTPUT_DIR="../dist"

# Step 1: Build the app
echo "[1/4] Building MicNoiseGate.app..."
cd ../MicNoiseGate
swift build -c release
# Create app bundle...

# Step 2: Build the driver
echo "[2/4] Building MicNoiseGate.driver..."
cd ../Driver
cmake --build build

# Step 3: Create component packages
echo "[3/4] Creating component packages..."
pkgbuild --root "$BUILD_DIR/app_root" \
         --identifier "com.micnoisegate.app" \
         --version "$VERSION" \
         --install-location "/" \
         "$BUILD_DIR/packages/MicNoiseGate-App.pkg"

pkgbuild --root "$BUILD_DIR/driver_root" \
         --identifier "com.micnoisegate.driver" \
         --version "$VERSION" \
         --install-location "/" \
         --scripts "./scripts" \
         "$BUILD_DIR/packages/MicNoiseGate-Driver.pkg"

# Step 4: Create distribution package
echo "[4/4] Creating final installer..."
productbuild --distribution "Distribution.xml" \
             --resources "./resources" \
             --package-path "$BUILD_DIR/packages" \
             "$OUTPUT_DIR/MicNoiseGate-Installer-$VERSION.pkg"
```

### Build Output

```
dist/
└── MicNoiseGate-Installer-1.0.0.pkg
```

---

## Configuration Files

### Distribution.xml

Controls the installer UI and package selection:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<installer-gui-script minSpecVersion="2">
    <title>MicNoiseGate</title>
    <organization>com.micnoisegate</organization>

    <!-- Minimum macOS version -->
    <allowed-os-versions>
        <os-version min="13.0"/>
    </allowed-os-versions>

    <!-- Welcome and Conclusion screens -->
    <welcome file="Welcome.html"/>
    <conclusion file="Conclusion.html"/>

    <!-- What to install -->
    <choices-outline>
        <line choice="app"/>
        <line choice="driver"/>
    </choices-outline>

    <!-- App component -->
    <choice id="app"
            title="MicNoiseGate Application"
            description="The main menu bar application">
        <pkg-ref id="com.micnoisegate.app"/>
    </choice>

    <!-- Driver component -->
    <choice id="driver"
            title="Audio Driver"
            description="Virtual microphone driver">
        <pkg-ref id="com.micnoisegate.driver"/>
    </choice>

    <!-- Package references -->
    <pkg-ref id="com.micnoisegate.app">MicNoiseGate-App.pkg</pkg-ref>
    <pkg-ref id="com.micnoisegate.driver">MicNoiseGate-Driver.pkg</pkg-ref>
</installer-gui-script>
```

### Welcome.html

First screen users see:

```html
<!DOCTYPE html>
<html>
<head>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, sans-serif;
            padding: 20px;
            background: transparent;
            color: inherit;
        }
        h1 { color: #007AFF; }
    </style>
</head>
<body>
    <h1>Welcome to MicNoiseGate</h1>
    <p>This installer will set up:</p>
    <ul>
        <li><strong>MicNoiseGate App</strong> - Menu bar application</li>
        <li><strong>Audio Driver</strong> - Virtual microphone device</li>
    </ul>
    <p>Click Continue to proceed.</p>
</body>
</html>
```

### Conclusion.html

Final screen after installation:

```html
<!DOCTYPE html>
<html>
<head>
    <style>
        body {
            font-family: -apple-system, sans-serif;
            background: transparent;
            color: inherit;
        }
        .warning {
            border-left: 4px solid #f0ad4e;
            background: rgba(240, 173, 78, 0.1);
            padding: 12px;
            margin: 15px 0;
        }
        code {
            background: rgba(128, 128, 128, 0.2);
            padding: 2px 6px;
            border-radius: 4px;
        }
    </style>
</head>
<body>
    <h1>Installation Complete!</h1>

    <h3>Getting Started:</h3>
    <ol>
        <li>Open <strong>MicNoiseGate</strong> from Applications</li>
        <li>Select your microphone</li>
        <li>Enable noise suppression</li>
        <li>In Zoom/Discord, select "MicNoiseGate Mic"</li>
    </ol>

    <div class="warning">
        <strong>If "MicNoiseGate Mic" doesn't appear:</strong>
        <p>Restart the audio system with:</p>
        <code>sudo launchctl kickstart -kp system/com.apple.audio.coreaudiod</code>
    </div>
</body>
</html>
```

---

## Install Scripts

### scripts/preinstall

Runs before files are copied:

```bash
#!/bin/bash
# Remove old versions if present
rm -rf "/Applications/MicNoiseGate.app"
rm -rf "/Library/Audio/Plug-Ins/HAL/MicNoiseGate.driver"
exit 0
```

### scripts/postinstall

Runs after files are copied:

```bash
#!/bin/bash

# Set correct permissions on driver
chown -R root:wheel "/Library/Audio/Plug-Ins/HAL/MicNoiseGate.driver"
chmod -R 755 "/Library/Audio/Plug-Ins/HAL/MicNoiseGate.driver"

# Restart coreaudiod to load the new driver
launchctl kickstart -kp system/com.apple.audio.coreaudiod

exit 0
```

**Important**: Scripts must be executable (`chmod +x`) and return 0 for success.

---

## Package Identifiers

Each package has a unique identifier used for tracking:

| Package | Identifier | Purpose |
|---------|------------|---------|
| App | `com.micnoisegate.app` | Main application |
| Driver | `com.micnoisegate.driver` | Audio driver |

### Checking Installation

```bash
# List installed packages
pkgutil --pkgs | grep micnoisegate

# Show package info
pkgutil --pkg-info com.micnoisegate.app

# List installed files
pkgutil --files com.micnoisegate.driver
```

---

## Uninstallation

### Manual Uninstall

```bash
# Remove app
sudo rm -rf /Applications/MicNoiseGate.app

# Remove driver
sudo rm -rf /Library/Audio/Plug-Ins/HAL/MicNoiseGate.driver

# Restart audio
sudo launchctl kickstart -kp system/com.apple.audio.coreaudiod

# Clean up receipts
sudo pkgutil --forget com.micnoisegate.app
sudo pkgutil --forget com.micnoisegate.driver
```

### In-App Uninstall

The app includes an uninstall button that uses AppleScript to request admin privileges:

```swift
let script = """
do shell script "
    rm -rf '/Applications/MicNoiseGate.app'
    rm -rf '/Library/Audio/Plug-Ins/HAL/MicNoiseGate.driver'
    launchctl kickstart -kp system/com.apple.audio.coreaudiod
    pkgutil --forget com.micnoisegate.app
    pkgutil --forget com.micnoisegate.driver
" with administrator privileges
"""
```

---

## Signing and Notarization

### Without Apple Developer Account

The installer will work but users will see security warnings:

1. **First launch**: "MicNoiseGate can't be opened because it is from an unidentified developer"
2. **Solution**: System Settings → Privacy & Security → "Open Anyway"

### With Apple Developer Account

For distribution without warnings:

```bash
# Sign the app
codesign --deep --force --verify --verbose \
         --sign "Developer ID Application: Your Name (TEAMID)" \
         MicNoiseGate.app

# Sign the driver
codesign --deep --force --verify --verbose \
         --sign "Developer ID Application: Your Name (TEAMID)" \
         MicNoiseGate.driver

# Sign the installer
productsign --sign "Developer ID Installer: Your Name (TEAMID)" \
            MicNoiseGate-Installer.pkg \
            MicNoiseGate-Installer-signed.pkg

# Notarize
xcrun notarytool submit MicNoiseGate-Installer-signed.pkg \
                        --apple-id "your@email.com" \
                        --team-id "TEAMID" \
                        --password "@keychain:AC_PASSWORD" \
                        --wait

# Staple
xcrun stapler staple MicNoiseGate-Installer-signed.pkg
```

---

## Customization

### Adding a License Agreement

1. Create `resources/License.html` or `resources/License.txt`
2. Add to Distribution.xml:
   ```xml
   <license file="License.html"/>
   ```

### Custom Background

1. Add `resources/background.png` (620x418 pixels recommended)
2. Add to Distribution.xml:
   ```xml
   <background file="background.png" alignment="bottomleft" scaling="none"/>
   ```

### Volume Selection

To let users choose install location:

```xml
<options customize="allow" require-scripts="false" hostArchitectures="x86_64,arm64"/>
<domains enable_anywhere="false" enable_currentUserHome="false" enable_localSystem="true"/>
```

---

## Troubleshooting

### Common Build Errors

| Error | Cause | Solution |
|-------|-------|----------|
| `pkgbuild: error: Path does not exist` | Missing build artifacts | Run component builds first |
| `productbuild: error: Invalid Distribution file` | XML syntax error | Validate Distribution.xml |
| Script exit code != 0 | Script error | Check script logic |

### Testing the Installer

```bash
# Test without installing (expand package)
pkgutil --expand MicNoiseGate-Installer.pkg /tmp/pkg-contents

# Check package contents
ls -la /tmp/pkg-contents/

# View scripts
cat /tmp/pkg-contents/MicNoiseGate-Driver.pkg/Scripts/postinstall
```

### Verbose Installation

```bash
# Install with verbose output
sudo installer -pkg MicNoiseGate-Installer.pkg -target / -verbose
```
