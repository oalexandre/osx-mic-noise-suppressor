// MicNoiseGate AudioServerPlugin Driver
// Uses libASPL (MIT License)

#include <aspl/Driver.hpp>

#include <CoreAudio/AudioServerPlugIn.h>

#include "SharedMemory.hpp"
#include <cstring>
#include <memory>
#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>

namespace {

// Stream format - matches what the app produces
constexpr UInt32 SampleRate = 48000;
constexpr UInt32 ChannelCount = 2;

// Shared memory manager for receiving audio from the app
class SharedMemoryReader {
public:
    SharedMemoryReader() {
        fd_ = shm_open(kSharedMemoryName, O_RDWR, 0666);
        if (fd_ != -1) {
            buffer_ = static_cast<SharedAudioBuffer*>(
                mmap(nullptr, SharedAudioBuffer::totalSize(),
                     PROT_READ | PROT_WRITE, MAP_SHARED, fd_, 0)
            );
            if (buffer_ == MAP_FAILED) {
                close(fd_);
                fd_ = -1;
                buffer_ = nullptr;
            }
        }
    }

    ~SharedMemoryReader() {
        if (buffer_ && buffer_ != MAP_FAILED) {
            munmap(buffer_, SharedAudioBuffer::totalSize());
        }
        if (fd_ != -1) {
            close(fd_);
        }
    }

    SharedAudioBuffer* buffer() { return buffer_; }

    bool tryReconnect() {
        if (buffer_) return true;

        fd_ = shm_open(kSharedMemoryName, O_RDWR, 0666);
        if (fd_ == -1) return false;

        buffer_ = static_cast<SharedAudioBuffer*>(
            mmap(nullptr, SharedAudioBuffer::totalSize(),
                 PROT_READ | PROT_WRITE, MAP_SHARED, fd_, 0)
        );

        if (buffer_ == MAP_FAILED) {
            close(fd_);
            fd_ = -1;
            buffer_ = nullptr;
            return false;
        }

        return true;
    }

private:
    int fd_ = -1;
    SharedAudioBuffer* buffer_ = nullptr;
};

// I/O Handler that reads from shared memory
class MicNoiseGateIOHandler : public aspl::IORequestHandler
{
public:
    void OnReadClientInput(const std::shared_ptr<aspl::Client>& client,
        const std::shared_ptr<aspl::Stream>& stream,
        Float64 zeroTimestamp,
        Float64 timestamp,
        void* bytes,
        UInt32 bytesCount) override
    {
        float* samples = static_cast<float*>(bytes);
        UInt32 numSamples = bytesCount / sizeof(float) / ChannelCount;

        // Try to reconnect to shared memory if not connected
        if (!shmReader_.buffer()) {
            shmReader_.tryReconnect();
        }

        SharedAudioBuffer* shm = shmReader_.buffer();

        // Read from shared memory if available and producer is active
        if (shm && shm->isActive.load(std::memory_order_acquire)) {
            if (!shm->read(samples, numSamples)) {
                // Buffer underrun - output silence
                std::memset(samples, 0, bytesCount);
            }
        } else {
            // No shared memory or producer not active - output silence
            std::memset(samples, 0, bytesCount);
        }
    }

private:
    SharedMemoryReader shmReader_;
};

std::shared_ptr<aspl::Driver> CreateDriver()
{
    // Create context (shared between all objects)
    auto context = std::make_shared<aspl::Context>();

    // Create device with parameters
    aspl::DeviceParameters deviceParams;
    deviceParams.Name = "MicNoiseGate Mic";
    deviceParams.Manufacturer = "MicNoiseGate";
    deviceParams.DeviceUID = "MicNoiseGate_VirtualMic";
    deviceParams.ModelUID = "MicNoiseGate_Model";
    deviceParams.SampleRate = SampleRate;
    deviceParams.ChannelCount = ChannelCount;
    deviceParams.EnableMixing = false;
    deviceParams.CanBeDefault = true;
    deviceParams.CanBeDefaultForSystemSounds = false;

    auto device = std::make_shared<aspl::Device>(context, deviceParams);

    // Add input stream with volume and mute controls
    // Direction::Input makes this appear as a microphone
    device->AddStreamWithControlsAsync(aspl::Direction::Input);

    // Set our custom I/O handler
    auto ioHandler = std::make_shared<MicNoiseGateIOHandler>();
    device->SetIOHandler(ioHandler);

    // Create plugin (root of object hierarchy)
    auto plugin = std::make_shared<aspl::Plugin>(context);
    plugin->AddDevice(device);

    // Create driver (top-level entry point)
    auto driver = std::make_shared<aspl::Driver>(context, plugin);

    return driver;
}

} // namespace

// Entry point called by CoreAudio
extern "C" void* MicNoiseGateDriverEntryPoint(CFAllocatorRef allocator, CFUUIDRef typeUUID)
{
    // Verify this is an AudioServerPlugIn request
    if (!CFEqual(typeUUID, kAudioServerPlugInTypeUUID)) {
        return nullptr;
    }

    // Create and keep driver alive
    static std::shared_ptr<aspl::Driver> driver = CreateDriver();

    return driver->GetReference();
}
