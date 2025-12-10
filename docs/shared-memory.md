# Shared Memory IPC Documentation

MicNoiseGate uses POSIX shared memory for inter-process communication between the Swift app (audio processor) and the C++ driver (virtual audio device).

## Why Shared Memory?

| Method | Latency | Complexity | Use Case |
|--------|---------|------------|----------|
| Shared Memory | ~1μs | Medium | Real-time audio ✓ |
| Unix Sockets | ~10μs | Low | General IPC |
| Mach Ports | ~5μs | High | System services |
| XPC | ~100μs | Low | App extensions |

For real-time audio at 48kHz, we process 480 samples every 10ms. Shared memory provides the lowest latency and avoids system call overhead.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         Shared Memory Segment                               │
│                         Name: /micnoisegate_audio                           │
│                         Size: ~40KB                                         │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                         Header (64 bytes)                           │   │
│  ├─────────────────────────────────────────────────────────────────────┤   │
│  │ Offset 0x00: magic        (uint32)  = 0x4D4E4741 ("MNGA")          │   │
│  │ Offset 0x04: version      (uint32)  = 1                             │   │
│  │ Offset 0x08: sampleRate   (uint32)  = 48000                         │   │
│  │ Offset 0x0C: channels     (uint32)  = 2                             │   │
│  │ Offset 0x10: bufferSize   (uint32)  = 480                           │   │
│  │ Offset 0x14: padding      (uint32)  = 0                             │   │
│  │ Offset 0x18: writeIndex   (uint64)  = <atomic counter>              │   │
│  │ Offset 0x20: readIndex    (uint64)  = <atomic counter>              │   │
│  │ Offset 0x28: reserved     [24 bytes]                                │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    Ring Buffer (~38KB)                              │   │
│  ├─────────────────────────────────────────────────────────────────────┤   │
│  │ Frame 0:  [480 samples × 2 channels × 4 bytes] = 3,840 bytes       │   │
│  │ Frame 1:  [480 samples × 2 channels × 4 bytes] = 3,840 bytes       │   │
│  │ Frame 2:  [480 samples × 2 channels × 4 bytes] = 3,840 bytes       │   │
│  │ ...                                                                 │   │
│  │ Frame 9:  [480 samples × 2 channels × 4 bytes] = 3,840 bytes       │   │
│  │                                                                     │   │
│  │ Total: 10 frames × 3,840 bytes = 38,400 bytes (~100ms buffer)      │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Header Structure

### Swift Definition

```swift
struct SharedMemoryHeader {
    var magic: UInt32           // Magic number for validation
    var version: UInt32         // Protocol version
    var sampleRate: UInt32      // Audio sample rate
    var channels: UInt32        // Number of audio channels
    var bufferSize: UInt32      // Samples per frame
    var padding: UInt32         // Alignment padding
    var writeIndex: UInt64      // Writer's frame counter (atomic)
    var readIndex: UInt64       // Reader's frame counter (atomic)
    var reserved: (UInt64, UInt64, UInt64)  // Future use
}
```

### C++ Definition

```cpp
struct SharedMemoryHeader {
    uint32_t magic;
    uint32_t version;
    uint32_t sampleRate;
    uint32_t channels;
    uint32_t bufferSize;
    uint32_t padding;
    std::atomic<uint64_t> writeIndex;
    std::atomic<uint64_t> readIndex;
    uint64_t reserved[3];
};
```

## Ring Buffer Design

### Why a Ring Buffer?

A ring buffer (circular buffer) allows:
- **Lock-free operation**: Single writer, single reader
- **Fixed memory**: No allocations during runtime
- **Overflow handling**: Old data automatically overwritten

### Buffer Indices

```
Write Index: 7
Read Index: 5
Buffer Size: 10 frames

                    ┌─────────────────────────────────────────────┐
                    │ 0   1   2   3   4   5   6   7   8   9       │
                    │ □   □   □   □   □   ■   ■   ▲   □   □       │
                    │                     ↑       ↑               │
                    │                   read   write              │
                    └─────────────────────────────────────────────┘

■ = Unread data (frames 5, 6)
▲ = Next write position
□ = Empty/old data

Available frames = writeIndex - readIndex = 7 - 5 = 2
```

### Index Wrapping

```swift
// Calculate actual buffer position
let actualPosition = index % bufferFrameCount

// Example: writeIndex = 27, bufferFrameCount = 10
// actualPosition = 27 % 10 = 7
```

## Operations

### Creating Shared Memory (App - Writer)

```swift
class SharedAudioBuffer {
    func create() throws {
        // 1. Create shared memory object
        let fd = shm_open(
            "/micnoisegate_audio",
            O_CREAT | O_RDWR,
            S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH
        )
        guard fd != -1 else { throw Error.createFailed }

        // 2. Set size
        let totalSize = MemoryLayout<Header>.size + ringBufferSize
        ftruncate(fd, off_t(totalSize))

        // 3. Map into memory
        let ptr = mmap(
            nil,
            totalSize,
            PROT_READ | PROT_WRITE,
            MAP_SHARED,
            fd,
            0
        )
        close(fd)

        // 4. Initialize header
        let header = ptr.assumingMemoryBound(to: Header.self)
        header.pointee.magic = 0x4D4E4741
        header.pointee.version = 1
        header.pointee.sampleRate = 48000
        header.pointee.channels = 2
        header.pointee.bufferSize = 480
        header.pointee.writeIndex = 0
        header.pointee.readIndex = 0
    }
}
```

### Opening Shared Memory (Driver - Reader)

```cpp
class SharedMemoryReader {
    bool Open() {
        // 1. Open existing shared memory
        int fd = shm_open("/micnoisegate_audio", O_RDONLY, 0);
        if (fd == -1) return false;

        // 2. Get size
        struct stat sb;
        fstat(fd, &sb);

        // 3. Map read-only
        void* ptr = mmap(
            nullptr,
            sb.st_size,
            PROT_READ,
            MAP_SHARED,
            fd,
            0
        );
        close(fd);

        // 4. Validate header
        header_ = static_cast<Header*>(ptr);
        return header_->magic == 0x4D4E4741;
    }
};
```

### Writing Audio (App)

```swift
func write(samples: UnsafePointer<Float>, frameCount: Int) {
    // 1. Calculate write position in ring buffer
    let writeIdx = OSAtomicAdd64(0, &header.writeIndex)
    let bufferPos = Int(writeIdx % UInt64(bufferFrameCount))

    // 2. Calculate byte offset
    let frameBytes = frameCount * channels * MemoryLayout<Float>.size
    let offset = bufferPos * frameBytes

    // 3. Copy samples
    memcpy(ringBuffer.advanced(by: offset), samples, frameBytes)

    // 4. Memory barrier + increment write index
    OSMemoryBarrier()
    OSAtomicIncrement64(&header.writeIndex)
}
```

### Reading Audio (Driver)

```cpp
bool Read(float* output, uint32_t frameCount) {
    // 1. Load indices atomically
    uint64_t writeIdx = header_->writeIndex.load(std::memory_order_acquire);
    uint64_t readIdx = header_->readIndex.load(std::memory_order_relaxed);

    // 2. Check if data available
    if (writeIdx <= readIdx) {
        return false;  // Buffer empty
    }

    // 3. Check for overrun (writer lapped reader)
    if (writeIdx - readIdx > kBufferFrameCount) {
        // Skip to most recent data
        readIdx = writeIdx - 1;
    }

    // 4. Calculate position and copy
    uint32_t pos = (readIdx % kBufferFrameCount) * kFrameSize;
    memcpy(output, ringBuffer_ + pos, frameCount * 2 * sizeof(float));

    // 5. Update read index
    header_->readIndex.store(readIdx + 1, std::memory_order_release);
    return true;
}
```

## Memory Ordering

### Atomic Operations

We use atomic operations to ensure proper ordering between writer and reader:

| Operation | Memory Order | Purpose |
|-----------|--------------|---------|
| Write index increment | `release` | Ensures data is written before index update |
| Read write index | `acquire` | Ensures we see all data before this index |
| Read read index | `relaxed` | Only reader modifies this |
| Write read index | `release` | Publish our read position |

### Sequence

```
Writer:                              Reader:
1. Write samples to buffer
2. Memory barrier
3. Increment writeIndex (release)
                                     4. Load writeIndex (acquire)
                                     5. Memory barrier
                                     6. Read samples from buffer
                                     7. Increment readIndex (release)
```

## Error Handling

### Buffer Underrun

When reader is faster than writer (no new data):

```cpp
if (writeIdx <= readIdx) {
    // Option 1: Return silence
    memset(output, 0, frameSize);
    return false;

    // Option 2: Repeat last frame
    // memcpy(output, lastFrame_, frameSize);
    // return true;
}
```

### Buffer Overrun

When writer is faster than reader (data loss):

```cpp
if (writeIdx - readIdx > kBufferFrameCount) {
    // Writer lapped reader - skip to recent data
    readIdx = writeIdx - 1;
    header_->readIndex.store(readIdx, std::memory_order_relaxed);
}
```

### Validation

```cpp
bool ValidateHeader() {
    // Check magic number
    if (header_->magic != 0x4D4E4741) return false;

    // Check version compatibility
    if (header_->version > kMaxSupportedVersion) return false;

    // Check reasonable values
    if (header_->sampleRate != 48000) return false;
    if (header_->channels != 2) return false;
    if (header_->bufferSize != 480) return false;

    return true;
}
```

## Cleanup

### App Shutdown

```swift
deinit {
    // Unmap memory
    munmap(memory, totalSize)

    // Remove shared memory object
    shm_unlink("/micnoisegate_audio")
}
```

### Driver Handling Missing App

```cpp
bool Read(...) {
    if (!memory_) {
        // Try to reconnect
        if (!Open()) {
            return false;
        }
    }
    // ... normal read
}
```

## Performance Considerations

### Cache Alignment

The header is sized to 64 bytes to avoid false sharing:

```
┌──────────────────────────────────────────────────────────────┐
│ Cache Line 0 (64 bytes): Header                              │
├──────────────────────────────────────────────────────────────┤
│ Cache Line 1+: Ring buffer data                              │
└──────────────────────────────────────────────────────────────┘
```

### Memory Access Patterns

- **Writer**: Sequential writes to ring buffer
- **Reader**: Sequential reads from ring buffer
- Both benefit from CPU cache prefetching

### Buffer Sizing

| Frames | Duration | Memory | Latency |
|--------|----------|--------|---------|
| 5 | 50ms | 19KB | Lower |
| 10 | 100ms | 38KB | Balanced ✓ |
| 20 | 200ms | 77KB | Higher |

10 frames (100ms) provides a good balance between latency and resilience to scheduling jitter.
