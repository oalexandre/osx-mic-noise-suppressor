# MicNoiseGate - Developer Documentation

Welcome to the MicNoiseGate developer documentation. This guide will help you understand the project architecture, codebase, and how to contribute.

## Documentation Index

| Document | Description |
|----------|-------------|
| [Architecture Overview](./architecture.md) | High-level system design and component interaction |
| [Swift Application](./app-swift.md) | Menu bar app, audio processing, and UI |
| [Audio Driver](./driver.md) | CoreAudio HAL plugin implementation |
| [Shared Memory IPC](./shared-memory.md) | Inter-process communication mechanism |
| [Installer](./installer.md) | PKG installer build process |
| [Development Guide](./development.md) | Setup, building, debugging, and testing |

## Quick Start for New Developers

### 1. Understand the Big Picture

MicNoiseGate is a macOS application that:
1. Captures audio from a physical microphone
2. Processes it through RNNoise (AI noise suppression)
3. Makes the processed audio available as a virtual microphone

Read [Architecture Overview](./architecture.md) first to understand how all pieces fit together.

### 2. Set Up Your Environment

Follow the [Development Guide](./development.md) to:
- Install required tools (Xcode, CMake, RNNoise)
- Clone and build the project
- Run and debug locally

### 3. Explore the Codebase

The project has three main components:

```
micnoisegate/
├── MicNoiseGate/    # Swift app (audio capture + processing + UI)
├── Driver/          # C++ CoreAudio plugin (virtual microphone)
└── Installer/       # PKG installer scripts
```

### 4. Key Concepts to Understand

Before diving into the code, familiarize yourself with:

- **CoreAudio**: Apple's low-level audio framework
- **AudioServerPlugin (HAL)**: How virtual audio devices work on macOS
- **RNNoise**: The neural network used for noise suppression
- **POSIX Shared Memory**: How app and driver communicate

## Component Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                         USER SPACE                                  │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                    MicNoiseGate.app                          │   │
│  │  ┌─────────────┐  ┌──────────────┐  ┌───────────────────┐   │   │
│  │  │ AppDelegate │  │ AudioManager │  │ SharedAudioBuffer │   │   │
│  │  │   (UI)      │  │  + RNNoise   │  │   (IPC Writer)    │   │   │
│  │  └─────────────┘  └──────────────┘  └─────────┬─────────┘   │   │
│  └───────────────────────────────────────────────│─────────────┘   │
│                                                  │                  │
│                              ┌───────────────────┴───────────────┐ │
│                              │     POSIX Shared Memory           │ │
│                              │     /micnoisegate_audio           │ │
│                              └───────────────────┬───────────────┘ │
│                                                  │                  │
│  ┌───────────────────────────────────────────────│─────────────┐   │
│  │                 MicNoiseGate.driver           │             │   │
│  │  ┌──────────────┐  ┌──────────────────────────▼──────────┐  │   │
│  │  │ Driver.cpp   │  │       SharedMemory.hpp              │  │   │
│  │  │ (HAL Plugin) │  │       (IPC Reader)                  │  │   │
│  │  └──────────────┘  └─────────────────────────────────────┘  │   │
│  └─────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         KERNEL SPACE                                │
│                                                                     │
│   coreaudiod daemon loads MicNoiseGate.driver from                 │
│   /Library/Audio/Plug-Ins/HAL/ and exposes it as                   │
│   "MicNoiseGate Mic" virtual input device                          │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

## Data Flow

1. **Physical Mic** → AudioManager captures via CoreAudio
2. **AudioManager** → Processes with RNNoise (480 samples/frame at 48kHz)
3. **SharedAudioBuffer** → Writes to ring buffer in shared memory
4. **Driver** → Reads from shared memory when apps request audio
5. **Apps** → Receive clean audio from "MicNoiseGate Mic"

## Important Files

| File | Purpose |
|------|---------|
| `MicNoiseGate/Sources/AudioManager.swift` | Core audio processing logic |
| `MicNoiseGate/Sources/SharedAudioBuffer.swift` | Shared memory writer |
| `Driver/Driver.cpp` | Virtual audio device implementation |
| `Driver/SharedMemory.hpp` | Shared memory reader |
| `Driver/Info.plist.in` | Driver registration with CoreAudio |

## Getting Help

- Review the documentation in this folder
- Check code comments for implementation details
- Look at existing code patterns before adding new features
