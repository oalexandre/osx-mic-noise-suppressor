#pragma once

#include <cstdint>
#include <atomic>

// Shared memory configuration
constexpr const char* kSharedMemoryName = "/micnoisegate_audio";
constexpr size_t kRingBufferFrames = 4096;  // Number of audio frames in buffer
constexpr size_t kChannels = 2;             // Stereo
constexpr size_t kSampleRate = 48000;       // 48kHz

// Lock-free ring buffer structure for shared memory
struct SharedAudioBuffer {
    // Header
    std::atomic<uint64_t> writeIndex{0};    // Writer position
    std::atomic<uint64_t> readIndex{0};     // Reader position
    std::atomic<bool> isActive{false};      // Is the producer active?
    uint32_t sampleRate{kSampleRate};
    uint32_t channels{kChannels};
    uint32_t bufferFrames{kRingBufferFrames};

    // Padding to align audio data
    uint8_t padding[32];

    // Audio data - interleaved float samples
    float audioData[kRingBufferFrames * kChannels];

    // Calculate total size
    static constexpr size_t totalSize() {
        return sizeof(SharedAudioBuffer);
    }

    // Get available frames to read
    uint64_t availableToRead() const {
        uint64_t write = writeIndex.load(std::memory_order_acquire);
        uint64_t read = readIndex.load(std::memory_order_relaxed);
        return write - read;
    }

    // Get available space to write
    uint64_t availableToWrite() const {
        uint64_t write = writeIndex.load(std::memory_order_relaxed);
        uint64_t read = readIndex.load(std::memory_order_acquire);
        return kRingBufferFrames - (write - read);
    }

    // Write audio frames (producer - app side)
    bool write(const float* samples, uint64_t frameCount) {
        if (availableToWrite() < frameCount) {
            return false;  // Buffer full
        }

        uint64_t writePos = writeIndex.load(std::memory_order_relaxed);

        for (uint64_t i = 0; i < frameCount; i++) {
            uint64_t index = (writePos + i) % kRingBufferFrames;
            for (uint32_t ch = 0; ch < channels; ch++) {
                audioData[index * channels + ch] = samples[i * channels + ch];
            }
        }

        writeIndex.store(writePos + frameCount, std::memory_order_release);
        return true;
    }

    // Read audio frames (consumer - driver side)
    bool read(float* samples, uint64_t frameCount) {
        if (availableToRead() < frameCount) {
            // Not enough data, fill with silence
            for (uint64_t i = 0; i < frameCount * channels; i++) {
                samples[i] = 0.0f;
            }
            return false;
        }

        uint64_t readPos = readIndex.load(std::memory_order_relaxed);

        for (uint64_t i = 0; i < frameCount; i++) {
            uint64_t index = (readPos + i) % kRingBufferFrames;
            for (uint32_t ch = 0; ch < channels; ch++) {
                samples[i * channels + ch] = audioData[index * channels + ch];
            }
        }

        readIndex.store(readPos + frameCount, std::memory_order_release);
        return true;
    }
};
