# Audio Driver Documentation

The MicNoiseGate.driver is a CoreAudio HAL (Hardware Abstraction Layer) plugin that creates a virtual audio input device.

## Overview

The driver is implemented using [libASPL](https://github.com/gavv/libASPL), a C++17 library that simplifies creating AudioServerPlugins for macOS.

### What is a HAL Plugin?

- A bundle loaded by `coreaudiod` (the Core Audio daemon)
- Appears as a real audio device to the system
- Can be selected in any application's audio settings
- Lives in `/Library/Audio/Plug-Ins/HAL/`

## Project Structure

```
Driver/
├── CMakeLists.txt      # CMake build configuration
├── Driver.cpp          # Main plugin implementation
├── SharedMemory.hpp    # Shared memory reader
├── Info.plist.in       # Plugin metadata template
├── build.sh            # Quick build script
├── install.sh          # Installation script
└── build/              # Build output directory
    ├── MicNoiseGate.driver/  # Built plugin bundle
    └── _deps/                # libASPL dependency
```

## Source Files

### Driver.cpp

The main driver implementation using libASPL.

#### Plugin Entry Point

```cpp
extern "C" void* MicNoiseGateDriverEntryPoint(CFAllocatorRef allocator,
                                               CFUUIDRef requestedTypeUUID)
{
    // Verify this is an AudioServerPlugin request
    if (!CFEqual(requestedTypeUUID, kAudioServerPlugInTypeUUID)) {
        return nullptr;
    }

    // Create and return the plugin
    static auto plugin = std::make_shared<MicNoiseGatePlugin>();
    return plugin->GetReference();
}
```

This function is called by `coreaudiod` when loading the plugin. The UUID in `Info.plist` maps to this entry point.

#### Plugin Class

```cpp
class MicNoiseGatePlugin : public aspl::Plugin {
public:
    MicNoiseGatePlugin() {
        // Create the virtual device
        auto deviceParams = aspl::DeviceParameters();
        deviceParams.Name = "MicNoiseGate Mic";
        deviceParams.Manufacturer = "MicNoiseGate";
        deviceParams.DeviceUID = "com.micnoisegate.device";
        deviceParams.ModelUID = "com.micnoisegate.model";

        device_ = std::make_shared<MicNoiseGateDevice>(GetContext(), deviceParams);
        AddDevice(device_);
    }

private:
    std::shared_ptr<MicNoiseGateDevice> device_;
};
```

#### Device Class

```cpp
class MicNoiseGateDevice : public aspl::Device {
public:
    MicNoiseGateDevice(std::shared_ptr<aspl::Context> context,
                       const aspl::DeviceParameters& params)
        : aspl::Device(context, params)
    {
        // Create input stream (what apps see as "microphone input")
        auto streamParams = aspl::StreamParameters();
        streamParams.Direction = aspl::Direction::Input;
        streamParams.Format = {
            .mSampleRate = 48000.0,
            .mFormatID = kAudioFormatLinearPCM,
            .mFormatFlags = kAudioFormatFlagIsFloat |
                           kAudioFormatFlagIsPacked,
            .mBitsPerChannel = 32,
            .mChannelsPerFrame = 2,
            .mBytesPerFrame = 8,
            .mFramesPerPacket = 1,
            .mBytesPerPacket = 8
        };

        inputStream_ = std::make_shared<aspl::Stream>(GetContext(), this, streamParams);
        AddStream(inputStream_);

        // Open shared memory
        sharedMemory_.Open();
    }

    // Called when an app requests audio samples
    OSStatus OnReadClientInput(
        const std::shared_ptr<aspl::Client>& client,
        const std::shared_ptr<aspl::Stream>& stream,
        Float64 sampleTime,
        Float64 hostTime,
        void* buffer,
        UInt32 frameCount) override
    {
        // Read processed audio from shared memory
        if (!sharedMemory_.Read(static_cast<float*>(buffer), frameCount)) {
            // If no data available, return silence
            memset(buffer, 0, frameCount * 2 * sizeof(float));
        }
        return kAudioHardwareNoError;
    }

private:
    std::shared_ptr<aspl::Stream> inputStream_;
    SharedMemoryReader sharedMemory_;
};
```

---

### SharedMemory.hpp

Header-only implementation of the shared memory reader.

```cpp
class SharedMemoryReader {
public:
    static constexpr const char* kMemoryName = "/micnoisegate_audio";

    bool Open() {
        // Open existing shared memory segment
        int fd = shm_open(kMemoryName, O_RDONLY, 0);
        if (fd == -1) return false;

        // Map into address space
        void* ptr = mmap(nullptr, kTotalSize, PROT_READ, MAP_SHARED, fd, 0);
        close(fd);

        if (ptr == MAP_FAILED) return false;

        memory_ = ptr;
        header_ = static_cast<Header*>(memory_);
        ringBuffer_ = static_cast<float*>(
            static_cast<char*>(memory_) + sizeof(Header));

        return ValidateHeader();
    }

    bool Read(float* output, uint32_t frameCount) {
        if (!memory_) return false;

        // Check if data is available
        uint64_t writeIdx = __atomic_load_n(&header_->writeIndex, __ATOMIC_ACQUIRE);
        uint64_t readIdx = __atomic_load_n(&header_->readIndex, __ATOMIC_ACQUIRE);

        if (writeIdx <= readIdx) {
            return false;  // No new data
        }

        // Calculate buffer position
        uint32_t bufferPos = (readIdx % kBufferFrames) * kFrameSize;

        // Copy samples
        memcpy(output, ringBuffer_ + bufferPos, frameCount * 2 * sizeof(float));

        // Update read index
        __atomic_store_n(&header_->readIndex, readIdx + 1, __ATOMIC_RELEASE);

        return true;
    }

private:
    struct Header {
        uint32_t magic;
        uint32_t version;
        uint32_t sampleRate;
        uint32_t channels;
        uint32_t bufferSize;
        uint64_t writeIndex;
        uint64_t readIndex;
    };

    void* memory_ = nullptr;
    Header* header_ = nullptr;
    float* ringBuffer_ = nullptr;
};
```

---

### Info.plist.in

Template for the plugin's Info.plist. CMake substitutes the variables.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" ...>
<plist version="1.0">
<dict>
    <!-- Empty, we don't use Mach services -->
    <key>AudioServerPlugIn_MachServices</key>
    <array/>

    <key>CFBundleExecutable</key>
    <string>MicNoiseGate</string>

    <key>CFBundleIdentifier</key>
    <string>com.micnoisegate.driver</string>

    <!-- Maps our factory UUID to the entry point function -->
    <key>CFPlugInFactories</key>
    <dict>
        <key>6E7A881E-6249-4E83-B461-BC7D1B5E2752</key>
        <string>MicNoiseGateDriverEntryPoint</string>
    </dict>

    <!-- Maps the AudioServerPlugin type to our factory -->
    <key>CFPlugInTypes</key>
    <dict>
        <key>443ABAB8-E7B3-491A-B985-BEB9187030DB</key>
        <array>
            <string>6E7A881E-6249-4E83-B461-BC7D1B5E2752</string>
        </array>
    </dict>

    <!-- Required for HAL plugins -->
    <key>sandboxSafe</key>
    <true/>
</dict>
</plist>
```

#### UUID Meanings

| UUID | Purpose |
|------|---------|
| `443ABAB8-E7B3-491A-B985-BEB9187030DB` | Apple's AudioServerPlugin type UUID |
| `6E7A881E-6249-4E83-B461-BC7D1B5E2752` | Our unique factory UUID |

---

### CMakeLists.txt

Build configuration using CMake.

```cmake
cmake_minimum_required(VERSION 3.16)
project(MicNoiseGate VERSION 1.0.0)

set(CMAKE_CXX_STANDARD 17)

# Fetch libASPL from GitHub
include(FetchContent)
FetchContent_Declare(
    libaspl
    GIT_REPOSITORY https://github.com/gavv/libASPL.git
    GIT_TAG master
)
FetchContent_MakeAvailable(libaspl)

# Create the driver bundle
add_library(MicNoiseGate MODULE Driver.cpp)
target_link_libraries(MicNoiseGate PRIVATE aspl::libASPL)

# Configure as a proper macOS bundle
set_target_properties(MicNoiseGate PROPERTIES
    BUNDLE TRUE
    BUNDLE_EXTENSION driver
    MACOSX_BUNDLE_INFO_PLIST ${CMAKE_SOURCE_DIR}/Info.plist.in
)
```

---

## Build Process

### Quick Build

```bash
cd Driver
./build.sh
```

### Manual Build

```bash
cd Driver
mkdir -p build && cd build
cmake ..
make
```

### Build Output

```
Driver/build/
└── MicNoiseGate.driver/
    └── Contents/
        ├── Info.plist     # Plugin metadata
        └── MacOS/
            └── MicNoiseGate  # Binary executable
```

---

## Installation

### Using install.sh

```bash
cd Driver
sudo ./install.sh
```

This script:
1. Copies the driver to `/Library/Audio/Plug-Ins/HAL/`
2. Sets correct permissions
3. Restarts `coreaudiod`

### Manual Installation

```bash
# Copy driver
sudo cp -R build/MicNoiseGate.driver /Library/Audio/Plug-Ins/HAL/

# Set ownership
sudo chown -R root:wheel /Library/Audio/Plug-Ins/HAL/MicNoiseGate.driver

# Restart audio system
sudo launchctl kickstart -kp system/com.apple.audio.coreaudiod
```

---

## Debugging

### Check if Driver is Loaded

```bash
# List audio devices
system_profiler SPAudioDataType | grep -A5 MicNoiseGate

# Should show:
#     MicNoiseGate Mic:
#       Manufacturer: MicNoiseGate
#       Input Channels: 2
#       ...
```

### View coreaudiod Logs

```bash
# Real-time logs
log stream --predicate 'process == "coreaudiod"' --info

# Recent logs
log show --predicate 'process == "coreaudiod"' --last 5m
```

### Common Issues

| Problem | Cause | Solution |
|---------|-------|----------|
| Device doesn't appear | Info.plist missing keys | Check CFPlugInFactories and CFPlugInTypes |
| Device appears but no audio | Shared memory not open | Check if app is running |
| Crashes on load | libASPL version mismatch | Rebuild with latest libASPL |

---

## libASPL Reference

### Key Classes

| Class | Purpose |
|-------|---------|
| `aspl::Plugin` | Represents the plugin bundle |
| `aspl::Device` | A virtual audio device |
| `aspl::Stream` | Audio stream (input or output) |
| `aspl::Context` | Shared state and dispatch |

### Key Methods to Override

```cpp
class MicNoiseGateDevice : public aspl::Device {
    // Called when app reads audio (for input devices)
    OSStatus OnReadClientInput(...) override;

    // Called when device becomes active/inactive
    OSStatus OnStartIO() override;
    OSStatus OnStopIO() override;

    // Called for property changes
    OSStatus OnSetPropertyData(...) override;
};
```

### Documentation

- [libASPL GitHub](https://github.com/gavv/libASPL)
- [Apple AudioServerPlugin documentation](https://developer.apple.com/documentation/coreaudio/audio_server_plug-in)
