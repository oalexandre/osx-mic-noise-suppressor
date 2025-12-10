# Architecture Overview

This document describes the high-level architecture of MicNoiseGate and how its components interact.

## System Architecture

MicNoiseGate consists of three main components that work together to provide real-time noise suppression:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                              macOS System                                    │
│                                                                              │
│  ┌────────────────────┐                          ┌────────────────────────┐ │
│  │  Physical Mic      │                          │  Applications          │ │
│  │  (Built-in/USB)    │                          │  (Zoom, Discord, etc.) │ │
│  └─────────┬──────────┘                          └───────────▲────────────┘ │
│            │                                                 │              │
│            │ Raw Audio                      Clean Audio      │              │
│            ▼                                                 │              │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │                         MicNoiseGate.app                                ││
│  │                                                                         ││
│  │  ┌─────────────┐    ┌──────────────┐    ┌──────────────────────────┐   ││
│  │  │ CoreAudio   │───▶│ RNNoise      │───▶│ Shared Memory Writer     │   ││
│  │  │ Input Tap   │    │ Processing   │    │ (Ring Buffer)            │   ││
│  │  └─────────────┘    └──────────────┘    └────────────┬─────────────┘   ││
│  │                                                      │                  ││
│  │  ┌─────────────────────────────────────────────────────────────────┐   ││
│  │  │ SwiftUI Menu Bar Interface                                      │   ││
│  │  │ - Device selection                                              │   ││
│  │  │ - Enable/disable toggle                                         │   ││
│  │  │ - Waveform visualization                                        │   ││
│  │  └─────────────────────────────────────────────────────────────────┘   ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                      │                       │
│                              POSIX Shared Memory     │                       │
│                              /micnoisegate_audio     │                       │
│                                                      ▼                       │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │                      MicNoiseGate.driver                                ││
│  │                      (CoreAudio HAL Plugin)                             ││
│  │                                                                         ││
│  │  ┌──────────────────────┐    ┌────────────────────────────────────┐    ││
│  │  │ Shared Memory Reader │───▶│ Virtual Audio Device               │    ││
│  │  │ (Ring Buffer)        │    │ "MicNoiseGate Mic"                 │    ││
│  │  └──────────────────────┘    └────────────────────────────────────┘    ││
│  │                                                                         ││
│  │  Loaded by: coreaudiod                                                  ││
│  │  Location: /Library/Audio/Plug-Ins/HAL/MicNoiseGate.driver             ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

## Components

### 1. MicNoiseGate.app (Swift Application)

The main application runs as a menu bar app and handles:

- **Audio Capture**: Uses CoreAudio to tap into the selected input device
- **Noise Processing**: Passes audio through RNNoise neural network
- **IPC Writing**: Writes processed audio to shared memory
- **User Interface**: SwiftUI-based menu bar popover

**Key Files:**
- `AppDelegate.swift` - App lifecycle and UI
- `AudioManager.swift` - Audio capture and processing
- `RNNoiseProcessor.swift` - RNNoise wrapper
- `SharedAudioBuffer.swift` - Shared memory writer

### 2. MicNoiseGate.driver (CoreAudio HAL Plugin)

A virtual audio device driver that:

- **Registers with CoreAudio**: Appears as "MicNoiseGate Mic" in system audio devices
- **Reads from Shared Memory**: Gets processed audio written by the app
- **Provides Audio to Apps**: Delivers samples when applications request input

**Key Files:**
- `Driver.cpp` - AudioServerPlugin implementation using libASPL
- `SharedMemory.hpp` - Shared memory reader
- `Info.plist.in` - Plugin registration metadata

### 3. Shared Memory IPC

A lock-free ring buffer in POSIX shared memory enables real-time communication:

- **Name**: `/micnoisegate_audio`
- **Structure**: Header + Ring Buffer
- **Lock-free**: Uses atomic operations for thread safety

## Audio Processing Pipeline

### Frame Processing

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          One Audio Frame (10ms)                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Sample Rate: 48,000 Hz                                                     │
│  Frame Size: 480 samples (48000 * 0.01)                                     │
│  Channels: 2 (stereo)                                                       │
│  Format: Float32                                                            │
│                                                                             │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐                  │
│  │ Raw Frame    │───▶│ RNNoise      │───▶│ Clean Frame  │                  │
│  │ 480 samples  │    │ (per channel)│    │ 480 samples  │                  │
│  └──────────────┘    └──────────────┘    └──────────────┘                  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### RNNoise Processing

RNNoise operates on mono audio, so stereo is processed as:

1. **Deinterleave**: Split stereo into left and right channels
2. **Process**: Run RNNoise on each channel independently
3. **Interleave**: Combine back to stereo
4. **Write**: Push to shared memory ring buffer

## Communication Flow

### Startup Sequence

```
1. User launches MicNoiseGate.app
   │
   ├─▶ App initializes AudioManager
   │   └─▶ Creates/opens shared memory segment
   │
   ├─▶ App shows in menu bar
   │
   └─▶ User enables noise suppression
       └─▶ AudioManager starts capture + processing
           └─▶ Writes to shared memory continuously

2. coreaudiod loads MicNoiseGate.driver (on system boot or driver install)
   │
   ├─▶ Driver registers as virtual audio device
   │
   └─▶ Driver opens shared memory for reading

3. User selects "MicNoiseGate Mic" in Zoom/Discord
   │
   └─▶ App requests audio from driver
       └─▶ Driver reads from shared memory
           └─▶ Returns processed audio samples
```

### Runtime Data Flow

```
Physical Mic                    App                         Driver                    Zoom
     │                          │                            │                         │
     │  Raw audio samples       │                            │                         │
     ├─────────────────────────▶│                            │                         │
     │                          │                            │                         │
     │                          │ Process with RNNoise       │                         │
     │                          ├───────────────────────────▶│                         │
     │                          │ Write to shared memory     │                         │
     │                          │                            │                         │
     │                          │                            │◀────────────────────────┤
     │                          │                            │ Request audio samples   │
     │                          │                            │                         │
     │                          │                            │ Read from shared memory │
     │                          │                            ├────────────────────────▶│
     │                          │                            │ Return clean samples    │
     │                          │                            │                         │
```

## Thread Model

### App Threads

| Thread | Purpose | Priority |
|--------|---------|----------|
| Main | UI updates, user interaction | Normal |
| Audio I/O | CoreAudio callbacks, RNNoise processing | Real-time |
| Visualization | Waveform updates (60 FPS) | Normal |

### Driver Threads

| Thread | Purpose | Priority |
|--------|---------|----------|
| I/O | Respond to audio requests from coreaudiod | Real-time |

## Memory Layout

### Shared Memory Structure

```
┌─────────────────────────────────────────────────────────────────┐
│                    Shared Memory Segment                        │
│                    /micnoisegate_audio                          │
├─────────────────────────────────────────────────────────────────┤
│  Header (64 bytes)                                              │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ magic: UInt32         = 0x4D4E4741 ("MNGA")                ││
│  │ version: UInt32       = 1                                   ││
│  │ sampleRate: UInt32    = 48000                              ││
│  │ channels: UInt32      = 2                                   ││
│  │ bufferSize: UInt32    = 480 (samples per frame)            ││
│  │ writeIndex: UInt64    = <atomic>                            ││
│  │ readIndex: UInt64     = <atomic>                            ││
│  │ padding: [bytes]                                            ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                 │
│  Ring Buffer (variable size)                                    │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ Frame 0: [480 * 2 * sizeof(Float32)] = 3840 bytes          ││
│  │ Frame 1: [480 * 2 * sizeof(Float32)] = 3840 bytes          ││
│  │ Frame 2: ...                                                ││
│  │ ...                                                         ││
│  │ Frame N: (total ~100ms buffer)                              ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

## Error Handling

### Graceful Degradation

| Scenario | Behavior |
|----------|----------|
| App not running | Driver returns silence |
| Shared memory unavailable | Driver returns silence |
| Buffer underrun | Driver returns last valid samples |
| Device disconnected | App shows error, stops processing |

## Security Considerations

- Driver runs in user space (not kernel)
- Shared memory has restricted permissions
- No network access required
- Audio data stays local

## Performance Targets

| Metric | Target |
|--------|--------|
| Latency | < 20ms end-to-end |
| CPU Usage | < 5% on M1 |
| Memory | < 50MB |
| Buffer | 100ms (handles scheduling jitter) |
