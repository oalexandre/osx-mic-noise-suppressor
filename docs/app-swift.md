# Swift Application Documentation

The MicNoiseGate.app is a Swift-based menu bar application that handles audio capture, noise processing, and user interface.

## Project Structure

```
MicNoiseGate/
├── Sources/
│   ├── main.swift              # App entry point
│   ├── AppDelegate.swift       # Menu bar UI and lifecycle
│   ├── AudioManager.swift      # Core audio processing
│   ├── RNNoiseProcessor.swift  # RNNoise C library wrapper
│   ├── SharedAudioBuffer.swift # Shared memory IPC
│   ├── WaveformView.swift      # Audio visualization
│   ├── RNNoise/
│   │   └── module.modulemap    # C library bridge
│   └── SharedMemoryBridge/
│       └── include/
│           └── SharedMemoryBridge.h  # C bridge for shared memory
├── Package.swift               # Swift Package Manager config
├── Info.plist                  # App metadata
└── build.sh                    # Build script
```

## Source Files

### main.swift

Entry point for the application. Sets up the NSApplication with custom delegate.

```swift
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

**Why not use @main?** We use manual app setup to have full control over the application lifecycle, which is important for a menu bar app that doesn't have a main window.

---

### AppDelegate.swift

Manages the menu bar UI and app lifecycle.

#### Key Components

**NSStatusItem**: The menu bar icon

```swift
statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
statusItem.button?.image = NSImage(systemSymbolName: "mic.fill", ...)
```

**NSPopover**: The dropdown panel when clicking the menu bar icon

```swift
popover = NSPopover()
popover.contentSize = NSSize(width: 320, height: 480)
popover.behavior = .transient  // Closes when clicking outside
popover.contentViewController = NSHostingController(rootView: ContentView(...))
```

#### ContentView

SwiftUI view containing:
- Noise suppression toggle
- Input device picker
- Waveform visualizations
- Level meters
- Uninstall button

#### Uninstall Functionality

Uses AppleScript to request admin privileges and remove:
- `/Applications/MicNoiseGate.app`
- `/Library/Audio/Plug-Ins/HAL/MicNoiseGate.driver`
- Package receipts

---

### AudioManager.swift

The core audio processing class. Handles capture, processing, and output.

#### Class Overview

```swift
class AudioManager: ObservableObject {
    // Published properties for UI binding
    @Published var isNoiseSuppressionEnabled = false
    @Published var selectedDeviceID: AudioDeviceID?
    @Published var inputDevices: [AudioDevice] = []
    @Published var inputLevel: Float = 0
    @Published var outputLevel: Float = 0
    @Published var inputWaveform: [Float] = []
    @Published var outputWaveform: [Float] = []
    @Published var isVirtualMicActive = false

    // Internal state
    private var audioUnit: AudioComponentInstance?
    private var rnnoise: RNNoiseProcessor?
    private var sharedBuffer: SharedAudioBuffer?
}
```

#### Audio Setup Flow

```
1. setupAudio()
   │
   ├─▶ Find audio input devices (excludes virtual mics)
   │
   ├─▶ Create AudioUnit (kAudioUnitType_Output, kAudioUnitSubType_HALOutput)
   │
   ├─▶ Configure for input capture
   │   ├─▶ Enable IO (element 1 = input)
   │   ├─▶ Disable output (element 0)
   │   └─▶ Set device ID
   │
   ├─▶ Set audio format
   │   ├─▶ Sample rate: 48000 Hz
   │   ├─▶ Channels: 2 (stereo)
   │   └─▶ Format: Float32, non-interleaved
   │
   └─▶ Set input callback
       └─▶ renderCallback() called by CoreAudio
```

#### Render Callback

The heart of audio processing. Called by CoreAudio when audio is available.

```swift
func renderCallback(
    inRefCon: UnsafeMutableRawPointer,
    ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    inTimeStamp: UnsafePointer<AudioTimeStamp>,
    inBusNumber: UInt32,
    inNumberFrames: UInt32,
    ioData: UnsafeMutablePointer<AudioBufferList>?
) -> OSStatus
```

**Processing Steps:**

1. **Render Input**: Get audio from hardware
   ```swift
   AudioUnitRender(audioUnit, ioActionFlags, inTimeStamp, 1, inNumberFrames, bufferList)
   ```

2. **Process with RNNoise**: Apply noise suppression
   ```swift
   rnnoise.process(input: inputBuffer, output: outputBuffer, frameCount: 480)
   ```

3. **Write to Shared Memory**: Send to driver
   ```swift
   sharedBuffer.write(samples: outputBuffer, frameCount: 480)
   ```

4. **Update UI**: Waveforms and levels (throttled to 60fps)

#### Device Enumeration

Finds all input devices, filtering out virtual microphones:

```swift
func refreshInputDevices() {
    // Get all audio devices
    // Filter for input capability
    // Exclude devices with "virtual" in transport type
    // Sort by name
}
```

---

### RNNoiseProcessor.swift

Swift wrapper for the RNNoise C library.

#### Initialization

```swift
class RNNoiseProcessor {
    private var stateLeft: OpaquePointer?   // RNNoise state for left channel
    private var stateRight: OpaquePointer?  // RNNoise state for right channel

    init() {
        stateLeft = rnnoise_create(nil)
        stateRight = rnnoise_create(nil)
    }
}
```

#### Processing

RNNoise processes 480 samples at a time (10ms at 48kHz):

```swift
func process(input: UnsafePointer<Float>,
             output: UnsafeMutablePointer<Float>,
             frameCount: Int) {
    // Deinterleave stereo to mono channels
    for i in 0..<frameCount {
        leftChannel[i] = input[i * 2]
        rightChannel[i] = input[i * 2 + 1]
    }

    // Process each channel
    rnnoise_process_frame(stateLeft, leftOutput, leftChannel)
    rnnoise_process_frame(stateRight, rightOutput, rightChannel)

    // Interleave back to stereo
    for i in 0..<frameCount {
        output[i * 2] = leftOutput[i]
        output[i * 2 + 1] = rightOutput[i]
    }
}
```

#### RNNoise C Bridge

The `RNNoise/module.modulemap` exposes the C library:

```
module RNNoise {
    header "/path/to/rnnoise.h"
    link "rnnoise"
    export *
}
```

---

### SharedAudioBuffer.swift

Manages the shared memory ring buffer for IPC with the driver.

#### Structure

```swift
class SharedAudioBuffer {
    private var sharedMemory: UnsafeMutableRawPointer?
    private var header: UnsafeMutablePointer<SharedMemoryHeader>?
    private var ringBuffer: UnsafeMutablePointer<Float>?

    static let memoryName = "/micnoisegate_audio"
    static let bufferFrames = 10  // ~100ms at 48kHz
}
```

#### Header Layout

```swift
struct SharedMemoryHeader {
    var magic: UInt32           // 0x4D4E4741 = "MNGA"
    var version: UInt32         // Protocol version
    var sampleRate: UInt32      // 48000
    var channels: UInt32        // 2
    var bufferSize: UInt32      // 480 samples per frame
    var writeIndex: UInt64      // Atomic write position
    var readIndex: UInt64       // Atomic read position
}
```

#### Write Operation

```swift
func write(samples: UnsafePointer<Float>, frameCount: Int) {
    // Calculate buffer position
    let writePos = atomicLoad(&header.writeIndex) % bufferFrames

    // Copy samples to ring buffer
    memcpy(ringBuffer + writePos * frameSize, samples, frameCount * channels * sizeof(Float))

    // Increment write index atomically
    atomicIncrement(&header.writeIndex)
}
```

---

### WaveformView.swift

SwiftUI view for real-time audio visualization.

#### Components

**WaveformView**: Displays audio waveform as a line graph

```swift
struct WaveformView: View {
    let samples: [Float]
    let color: Color
    let label: String
    let level: Float

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                // Draw waveform as connected line segments
            }
            .stroke(color, lineWidth: 1.5)
        }
    }
}
```

**LevelMeterView**: Shows input/output levels as horizontal bars

```swift
struct LevelMeterView: View {
    let inputLevel: Float
    let outputLevel: Float

    var body: some View {
        VStack {
            LevelBar(level: inputLevel, label: "Input", color: .orange)
            LevelBar(level: outputLevel, label: "Output", color: .green)
        }
    }
}
```

---

## Build Configuration

### Package.swift

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MicNoiseGate",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MicNoiseGate",
            dependencies: [],
            path: "Sources",
            linkerSettings: [
                .linkedLibrary("rnnoise"),
                .unsafeFlags(["-L/path/to/rnnoise/lib"])
            ]
        )
    ]
)
```

### Info.plist

Key entries:

```xml
<key>CFBundleIdentifier</key>
<string>com.micnoisegate.app</string>

<key>LSUIElement</key>
<true/>  <!-- Menu bar app, no dock icon -->

<key>NSMicrophoneUsageDescription</key>
<string>MicNoiseGate needs microphone access for noise suppression.</string>
```

---

## Common Modifications

### Adding a New Audio Effect

1. Create a new processor class similar to `RNNoiseProcessor`
2. Add instance to `AudioManager`
3. Chain in the render callback after RNNoise
4. Add UI toggle in `ContentView`

### Changing Sample Rate

Update these locations:
- `AudioManager.swift`: Audio format setup
- `SharedAudioBuffer.swift`: Header initialization
- `Driver/Driver.cpp`: Device stream format

### Adding New UI Controls

1. Add `@Published` property to `AudioManager`
2. Bind in `ContentView` using `$audioManager.property`
3. Handle changes in `didSet` observer
