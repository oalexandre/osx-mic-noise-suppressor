# MicNoiseGate

A macOS menu bar application that provides real-time AI-powered noise suppression for your microphone. MicNoiseGate creates a virtual audio device that other applications can use as an input source, delivering clean, noise-free audio to video conferencing apps like Zoom, Discord, and Microsoft Teams.

## Features

- **AI-Powered Noise Suppression**: Uses RNNoise, a recurrent neural network trained specifically for voice audio, to remove background noise in real-time
- **Virtual Audio Device**: Creates a system-wide virtual microphone ("MicNoiseGate Mic") that any application can use
- **Menu Bar App**: Lightweight, always-accessible interface that stays out of your way
- **Real-Time Visualization**: See input and output audio waveforms to monitor the noise reduction effect
- **Zero Latency Feel**: Optimized for real-time communication with minimal processing delay
- **Easy Uninstall**: Built-in uninstaller removes all components cleanly

## How It Works

```
┌─────────────┐     ┌──────────────────┐     ┌───────────────┐     ┌─────────────┐
│  Physical   │────▶│  MicNoiseGate    │────▶│ Virtual Mic   │────▶│ Zoom/Teams/ │
│  Microphone │     │  App + RNNoise   │     │ (HAL Driver)  │     │ Discord     │
└─────────────┘     └──────────────────┘     └───────────────┘     └─────────────┘
```

1. **Audio Capture**: The app captures audio from your selected physical microphone
2. **Noise Processing**: RNNoise analyzes and removes background noise using a deep learning model
3. **Shared Memory**: Processed audio is written to a shared memory buffer
4. **Virtual Device**: The HAL audio driver reads from shared memory and exposes it as "MicNoiseGate Mic"
5. **Application Use**: Video conferencing apps select "MicNoiseGate Mic" as their input device

## Requirements

- macOS 13.0 (Ventura) or later
- Apple Silicon (M1/M2/M3) or Intel Mac

## Installation

### Using the Installer (Recommended)

1. Download `MicNoiseGate-Installer-1.0.0.pkg` from the releases
2. Double-click to open the installer
3. Follow the installation steps
4. If prompted about security, go to **System Settings → Privacy & Security** and click "Allow"

### Building from Source

See [Development](#development) section below.

## Usage

1. **Launch the app**: Open MicNoiseGate from Applications or Launchpad
2. **Access from menu bar**: Click the microphone icon in the top-right corner
3. **Select input device**: Choose your physical microphone from the dropdown
4. **Enable noise suppression**: Toggle the switch to start processing
5. **Configure your apps**: In Zoom/Discord/Teams, select **"MicNoiseGate Mic"** as your input device

### Troubleshooting

If "MicNoiseGate Mic" doesn't appear in your audio devices:

**Option 1 - Terminal:**
```bash
sudo launchctl kickstart -kp system/com.apple.audio.coreaudiod
```

**Option 2 - Activity Monitor:**
1. Open Activity Monitor
2. Search for `coreaudiod`
3. Select it and click the **X** button to force quit
4. The system will restart it automatically

## Project Structure

```
micnoisegate/
├── MicNoiseGate/           # Main Swift application
│   ├── Sources/
│   │   ├── main.swift              # App entry point
│   │   ├── AppDelegate.swift       # Menu bar UI and app lifecycle
│   │   ├── AudioManager.swift      # Audio capture and processing
│   │   ├── RNNoiseProcessor.swift  # RNNoise Swift wrapper
│   │   ├── SharedAudioBuffer.swift # Shared memory IPC
│   │   └── WaveformView.swift      # Audio visualization
│   ├── Package.swift
│   └── build.sh
├── Driver/                 # CoreAudio HAL Plugin (C++)
│   ├── Driver.cpp          # Virtual audio device implementation
│   ├── SharedMemory.hpp    # Shared memory reader
│   ├── CMakeLists.txt
│   └── build.sh
├── Installer/              # PKG installer components
│   ├── build_installer.sh
│   ├── Distribution.xml
│   ├── resources/
│   └── scripts/
└── dist/                   # Built installer packages
```

## Development

### Prerequisites

- Xcode Command Line Tools
- CMake
- RNNoise library

### Setting Up the Development Environment

1. **Install Xcode Command Line Tools:**
   ```bash
   xcode-select --install
   ```

2. **Install CMake:**
   ```bash
   brew install cmake
   ```

3. **Build and install RNNoise:**
   ```bash
   git clone https://github.com/xiph/rnnoise.git
   cd rnnoise
   ./autogen.sh
   ./configure --prefix=$HOME/.local
   make
   make install
   ```

4. **Clone the repository:**
   ```bash
   git clone https://github.com/yourusername/micnoisegate.git
   cd micnoisegate
   ```

### Building

**Build the app:**
```bash
cd MicNoiseGate
./build.sh
```

**Build the driver:**
```bash
cd Driver
./build.sh
```

**Build the complete installer:**
```bash
cd Installer
./build_installer.sh
```

### Installing for Development

**Install the driver manually:**
```bash
cd Driver
sudo ./install.sh
```

**Run the app:**
```bash
open MicNoiseGate/MicNoiseGate.app
```

## Architecture

### Audio Processing Pipeline

The app uses a lock-free ring buffer for real-time audio communication between the Swift app and the C++ driver:

- **Sample Rate**: 48,000 Hz
- **Channels**: 2 (stereo)
- **Buffer Size**: 480 samples per frame (10ms)
- **Format**: Float32

### Technologies Used

- **Swift/SwiftUI**: Menu bar application and UI
- **RNNoise**: Deep learning noise suppression (Xiph.org)
- **libASPL**: CoreAudio AudioServerPlugin framework (MIT License)
- **POSIX Shared Memory**: Low-latency IPC between app and driver

## Contributing

Contributions are welcome! Here's how you can help:

1. **Fork the repository**
2. **Create a feature branch:**
   ```bash
   git checkout -b feature/your-feature-name
   ```
3. **Make your changes** and test thoroughly
4. **Commit with clear messages:**
   ```bash
   git commit -m "feat: add your feature description"
   ```
5. **Push to your fork:**
   ```bash
   git push origin feature/your-feature-name
   ```
6. **Open a Pull Request** with a clear description of your changes

### Code Style

- Swift: Follow Swift API Design Guidelines
- C++: Use C++17 features, follow CoreAudio naming conventions

### Areas for Contribution

- Performance optimizations
- Additional noise reduction models
- UI/UX improvements
- Documentation
- Bug fixes

## License

This project is proprietary software. All rights reserved.

## Acknowledgments

- [RNNoise](https://github.com/xiph/rnnoise) - A noise suppression library based on a recurrent neural network
- [libASPL](https://github.com/gavv/libASPL) - C++17 library for creating macOS Audio Server plugins

## Support

If you encounter any issues or have questions:

1. Check the [Troubleshooting](#troubleshooting) section
2. Search existing issues in the repository
3. Open a new issue with detailed information about your problem

---

Made with care for crystal-clear audio communication.
