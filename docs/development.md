# Development Guide

This guide covers setting up a development environment, building, debugging, and testing MicNoiseGate.

## Prerequisites

### Required Tools

| Tool | Version | Purpose |
|------|---------|---------|
| Xcode Command Line Tools | Latest | Swift compiler, linkers |
| CMake | 3.16+ | Driver build system |
| Homebrew | Latest | Package manager |

### Install Prerequisites

```bash
# Xcode Command Line Tools
xcode-select --install

# Homebrew (if not installed)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# CMake
brew install cmake

# pkg-config (for RNNoise)
brew install pkg-config autoconf automake libtool
```

---

## Building RNNoise

RNNoise is the AI noise suppression library. Build it from source:

```bash
# Clone RNNoise
git clone https://github.com/xiph/rnnoise.git
cd rnnoise

# Generate build files
./autogen.sh

# Configure with local prefix
./configure --prefix=$HOME/.local

# Build
make -j$(sysctl -n hw.ncpu)

# Install to ~/.local
make install
```

### Verify Installation

```bash
# Check library
ls -la ~/.local/lib/librnnoise*

# Check headers
ls -la ~/.local/include/rnnoise.h

# Check pkg-config
PKG_CONFIG_PATH=$HOME/.local/lib/pkgconfig pkg-config --libs rnnoise
# Output: -L/Users/you/.local/lib -lrnnoise
```

---

## Project Setup

### Clone Repository

```bash
git clone https://github.com/yourusername/micnoisegate.git
cd micnoisegate
```

### Project Structure

```
micnoisegate/
├── MicNoiseGate/       # Swift menu bar app
│   ├── Sources/        # Swift source files
│   ├── Package.swift   # Swift package manifest
│   ├── Info.plist      # App metadata
│   └── build.sh        # Build script
├── Driver/             # C++ audio driver
│   ├── *.cpp, *.hpp    # Driver source files
│   ├── CMakeLists.txt  # CMake config
│   └── build.sh        # Build script
├── Installer/          # PKG installer
│   ├── build_installer.sh
│   └── ...
├── docs/               # Documentation
└── dist/               # Build outputs
```

---

## Building

### Build the App

```bash
cd MicNoiseGate
./build.sh
```

This produces `MicNoiseGate.app` in the current directory.

#### Manual Build

```bash
cd MicNoiseGate

# Build with Swift Package Manager
PKG_CONFIG_PATH=$HOME/.local/lib/pkgconfig swift build -c release

# Create app bundle manually
mkdir -p MicNoiseGate.app/Contents/{MacOS,Frameworks,Resources}
cp .build/release/MicNoiseGate MicNoiseGate.app/Contents/MacOS/
cp Info.plist MicNoiseGate.app/Contents/
cp ~/.local/lib/librnnoise.0.dylib MicNoiseGate.app/Contents/Frameworks/

# Fix library paths
install_name_tool -add_rpath @executable_path/../Frameworks \
    MicNoiseGate.app/Contents/MacOS/MicNoiseGate
install_name_tool -change /usr/local/lib/librnnoise.0.dylib \
    @rpath/librnnoise.0.dylib \
    MicNoiseGate.app/Contents/MacOS/MicNoiseGate
```

### Build the Driver

```bash
cd Driver
./build.sh
```

This produces `build/MicNoiseGate.driver`.

#### Manual Build

```bash
cd Driver
mkdir -p build && cd build
cmake ..
make -j$(sysctl -n hw.ncpu)
```

### Build Everything + Installer

```bash
cd Installer
./build_installer.sh
```

Output: `dist/MicNoiseGate-Installer-1.0.0.pkg`

---

## Installing for Development

### Install Driver

```bash
cd Driver
sudo ./install.sh
```

Or manually:

```bash
sudo cp -R build/MicNoiseGate.driver /Library/Audio/Plug-Ins/HAL/
sudo chown -R root:wheel /Library/Audio/Plug-Ins/HAL/MicNoiseGate.driver
sudo launchctl kickstart -kp system/com.apple.audio.coreaudiod
```

### Run the App

```bash
cd MicNoiseGate
open MicNoiseGate.app
```

Or from terminal:

```bash
./MicNoiseGate.app/Contents/MacOS/MicNoiseGate
```

---

## Debugging

### App Debugging

#### Console Output

Run from terminal to see stdout/stderr:

```bash
./MicNoiseGate.app/Contents/MacOS/MicNoiseGate 2>&1
```

#### Xcode Debugging

1. Open Xcode
2. File → Open → Select `MicNoiseGate/Package.swift`
3. Product → Scheme → Edit Scheme
4. Set working directory to project folder
5. Add environment variable: `PKG_CONFIG_PATH=$HOME/.local/lib/pkgconfig`
6. Run (Cmd+R)

#### LLDB

```bash
lldb ./MicNoiseGate.app/Contents/MacOS/MicNoiseGate
(lldb) run
(lldb) bt  # backtrace on crash
```

### Driver Debugging

#### Check if Loaded

```bash
system_profiler SPAudioDataType | grep -A10 MicNoiseGate
```

#### coreaudiod Logs

```bash
# Real-time logs
log stream --predicate 'process == "coreaudiod"' --info --debug

# Recent logs
log show --predicate 'process == "coreaudiod"' --last 10m
```

#### Reload Driver

```bash
# Remove and reinstall
sudo rm -rf /Library/Audio/Plug-Ins/HAL/MicNoiseGate.driver
sudo cp -R build/MicNoiseGate.driver /Library/Audio/Plug-Ins/HAL/
sudo launchctl kickstart -kp system/com.apple.audio.coreaudiod
```

### Shared Memory Debugging

#### Check if Exists

```bash
# List shared memory segments
ls -la /dev/shm/ 2>/dev/null || echo "No /dev/shm on macOS - use ipcs"

# List POSIX shared memory (macOS)
# Shared memory appears as files when mapped
lsof | grep micnoisegate
```

#### Memory Viewer (Quick C Program)

```c
// save as shm_viewer.c
#include <stdio.h>
#include <sys/mman.h>
#include <fcntl.h>

int main() {
    int fd = shm_open("/micnoisegate_audio", O_RDONLY, 0);
    if (fd == -1) { perror("shm_open"); return 1; }

    void* ptr = mmap(NULL, 64, PROT_READ, MAP_SHARED, fd, 0);
    uint32_t* header = (uint32_t*)ptr;

    printf("Magic: 0x%08X\n", header[0]);
    printf("Version: %u\n", header[1]);
    printf("Sample Rate: %u\n", header[2]);
    printf("Channels: %u\n", header[3]);

    return 0;
}
```

```bash
clang shm_viewer.c -o shm_viewer && ./shm_viewer
```

---

## Testing

### Manual Testing Checklist

1. **App Launch**
   - [ ] App appears in menu bar
   - [ ] Popover opens on click
   - [ ] No crashes

2. **Device Selection**
   - [ ] Input devices listed
   - [ ] Virtual mic excluded from list
   - [ ] Selection persists

3. **Audio Processing**
   - [ ] Waveforms show when enabled
   - [ ] Level meters respond
   - [ ] Audio passes through (test in QuickTime/Zoom)

4. **Virtual Mic**
   - [ ] "MicNoiseGate Mic" appears in System Settings → Sound
   - [ ] Selectable in Zoom/Discord
   - [ ] Audio received (may need actual integration test)

### Audio Quality Test

```bash
# Record from virtual mic
# In QuickTime Player: File → New Audio Recording → Select "MicNoiseGate Mic"
# Or:
ffmpeg -f avfoundation -i ":MicNoiseGate Mic" -t 10 test_output.wav
```

### Performance Profiling

```bash
# CPU usage
top -pid $(pgrep MicNoiseGate)

# Instruments (Xcode)
instruments -t "Time Profiler" ./MicNoiseGate.app
```

---

## Common Issues

### Build Errors

| Error | Solution |
|-------|----------|
| `rnnoise.h not found` | Set `PKG_CONFIG_PATH=$HOME/.local/lib/pkgconfig` |
| `library not found for -lrnnoise` | Install RNNoise to `~/.local` |
| `CMake error: Unable to detect CMAKE_OSX_SYSROOT` | Install Xcode Command Line Tools |

### Runtime Errors

| Error | Solution |
|-------|----------|
| `dyld: Library not loaded: librnnoise` | Run `install_name_tool` to fix paths |
| Virtual mic doesn't appear | Check Info.plist has correct UUIDs |
| No audio from virtual mic | Check shared memory is created (app running) |

### Development Tips

1. **Always restart coreaudiod after driver changes**
   ```bash
   sudo launchctl kickstart -kp system/com.apple.audio.coreaudiod
   ```

2. **Kill app before rebuilding**
   ```bash
   pkill MicNoiseGate
   ```

3. **Clean build if strange errors**
   ```bash
   cd MicNoiseGate && rm -rf .build MicNoiseGate.app
   cd Driver && rm -rf build
   ```

---

## IDE Setup

### VS Code

Recommended extensions:
- Swift (sswg.swift-lang)
- C/C++ (ms-vscode.cpptools)
- CMake Tools (ms-vscode.cmake-tools)

`.vscode/settings.json`:
```json
{
    "swift.path": "/usr/bin/swift",
    "cmake.configureOnOpen": true
}
```

### Xcode

1. Open `MicNoiseGate/Package.swift` for Swift development
2. Open `Driver/` folder and create Xcode project from CMake if needed

---

## Making Changes

### Adding a New Feature

1. Create a branch: `git checkout -b feature/my-feature`
2. Make changes
3. Test locally
4. Commit with clear message
5. Open pull request

### Modifying Audio Format

If changing sample rate, channels, or buffer size:

1. Update `AudioManager.swift` - audio format setup
2. Update `SharedAudioBuffer.swift` - header values
3. Update `SharedMemory.hpp` - header validation
4. Update `Driver.cpp` - stream format
5. Rebuild both app and driver
6. Reinstall driver and restart coreaudiod

### Adding New UI Controls

1. Add `@Published` property to `AudioManager`
2. Add control to `ContentView` in `AppDelegate.swift`
3. Handle property changes in `didSet` or binding
