import Foundation
import Darwin
import SharedMemoryBridge

// Constants matching the C++ header
let kSharedMemoryName = "/micnoisegate_audio"
let kRingBufferFrames: UInt32 = 4096
let kChannels: UInt32 = 2
let kSampleRate: UInt32 = 48000

// Lock-free ring buffer writer for shared memory
// Matches the C++ SharedAudioBuffer struct layout
final class SharedAudioBufferWriter {

    // Offsets in the shared memory structure (matching C++ layout)
    private enum Offset {
        static let writeIndex: Int = 0                    // std::atomic<uint64_t>
        static let readIndex: Int = 8                     // std::atomic<uint64_t>
        static let isActive: Int = 16                     // std::atomic<bool>
        static let sampleRate: Int = 24                   // uint32_t (aligned)
        static let channels: Int = 28                     // uint32_t
        static let bufferFrames: Int = 32                 // uint32_t
        static let padding: Int = 36                      // uint8_t[32]
        static let audioData: Int = 68                    // float[]
    }

    private var fd: Int32 = -1
    private var buffer: UnsafeMutableRawPointer?
    private var bufferSize: Int = 0

    var isConnected: Bool {
        return buffer != nil
    }

    init() {
        connect()
    }

    deinit {
        disconnect()
    }

    // Calculate total buffer size
    private static func calculateTotalSize() -> Int {
        return Offset.audioData + Int(kRingBufferFrames * kChannels) * MemoryLayout<Float>.size
    }

    // Connect to shared memory (create if needed)
    func connect() {
        guard buffer == nil else { return }

        bufferSize = SharedAudioBufferWriter.calculateTotalSize()

        // Create shared memory using wrapper
        // O_CREAT = 0x200, O_RDWR = 0x2
        // S_IRUSR|S_IWUSR|S_IRGRP|S_IWGRP|S_IROTH|S_IWOTH = 0o666 = 438
        fd = shm_open_wrapper(kSharedMemoryName, 0x202, 438)
        guard fd != -1 else {
            let errnum = get_errno()
            if let errStr = strerror_wrapper(errnum) {
                print("SharedAudioBuffer: Failed to create shared memory: \(String(cString: errStr))")
            }
            return
        }

        // Set size
        if ftruncate_wrapper(fd, Int(bufferSize)) == -1 {
            let errnum = get_errno()
            if let errStr = strerror_wrapper(errnum) {
                print("SharedAudioBuffer: Failed to set size: \(String(cString: errStr))")
            }
            close_wrapper(fd)
            fd = -1
            return
        }

        // Map memory
        // PROT_READ|PROT_WRITE = 0x3, MAP_SHARED = 0x1
        buffer = mmap_wrapper(nil, bufferSize, 0x3, 0x1, fd, 0)
        let mapFailed = UnsafeMutableRawPointer(bitPattern: -1)
        if buffer == mapFailed {
            let errnum = get_errno()
            if let errStr = strerror_wrapper(errnum) {
                print("SharedAudioBuffer: Failed to map memory: \(String(cString: errStr))")
            }
            close_wrapper(fd)
            fd = -1
            buffer = nil
            return
        }

        // Initialize header
        initializeHeader()

        print("SharedAudioBuffer: Connected to shared memory (\(bufferSize) bytes)")
    }

    // Initialize the header fields
    private func initializeHeader() {
        guard let buf = buffer else { return }

        // Initialize write/read indices to 0
        buf.storeBytes(of: UInt64(0), toByteOffset: Offset.writeIndex, as: UInt64.self)
        buf.storeBytes(of: UInt64(0), toByteOffset: Offset.readIndex, as: UInt64.self)

        // Set isActive to false initially
        buf.storeBytes(of: UInt8(0), toByteOffset: Offset.isActive, as: UInt8.self)

        // Set format parameters
        buf.storeBytes(of: kSampleRate, toByteOffset: Offset.sampleRate, as: UInt32.self)
        buf.storeBytes(of: kChannels, toByteOffset: Offset.channels, as: UInt32.self)
        buf.storeBytes(of: kRingBufferFrames, toByteOffset: Offset.bufferFrames, as: UInt32.self)
    }

    // Disconnect from shared memory
    func disconnect() {
        // Set inactive
        setActive(false)

        let mapFailed = UnsafeMutableRawPointer(bitPattern: -1)
        if let buf = buffer, buf != mapFailed {
            munmap_wrapper(buf, bufferSize)
        }
        buffer = nil

        if fd != -1 {
            close_wrapper(fd)
            fd = -1
        }

        print("SharedAudioBuffer: Disconnected")
    }

    // Set the active flag (producer is running)
    func setActive(_ active: Bool) {
        guard let buf = buffer else { return }

        // Atomic store with release semantics
        let value: UInt8 = active ? 1 : 0
        buf.storeBytes(of: value, toByteOffset: Offset.isActive, as: UInt8.self)
        OSMemoryBarrier()
    }

    // Get available space in buffer (frames)
    private func availableToWrite() -> UInt64 {
        guard let buf = buffer else { return 0 }

        OSMemoryBarrier()
        let writePos = buf.load(fromByteOffset: Offset.writeIndex, as: UInt64.self)
        let readPos = buf.load(fromByteOffset: Offset.readIndex, as: UInt64.self)

        return UInt64(kRingBufferFrames) - (writePos - readPos)
    }

    // Write interleaved stereo audio to the ring buffer
    // samples: pointer to interleaved float samples (L, R, L, R, ...)
    // frameCount: number of frames (not samples)
    func write(samples: UnsafePointer<Float>, frameCount: UInt32) -> Bool {
        guard let buf = buffer else { return false }
        guard availableToWrite() >= UInt64(frameCount) else {
            // Buffer full, skip
            return false
        }

        let writePos = buf.load(fromByteOffset: Offset.writeIndex, as: UInt64.self)
        let audioDataPtr = buf.advanced(by: Offset.audioData).assumingMemoryBound(to: Float.self)

        let channels = Int(kChannels)
        let bufferFrames = Int(kRingBufferFrames)

        for i in 0..<Int(frameCount) {
            let index = Int((writePos + UInt64(i)) % UInt64(bufferFrames))
            for ch in 0..<channels {
                audioDataPtr[index * channels + ch] = samples[i * channels + ch]
            }
        }

        // Update write index with release semantics
        OSMemoryBarrier()
        buf.storeBytes(of: writePos + UInt64(frameCount), toByteOffset: Offset.writeIndex, as: UInt64.self)

        return true
    }

    // Write mono audio converted to stereo
    func writeMono(samples: UnsafePointer<Float>, frameCount: UInt32) -> Bool {
        guard let buf = buffer else { return false }
        guard availableToWrite() >= UInt64(frameCount) else {
            return false
        }

        let writePos = buf.load(fromByteOffset: Offset.writeIndex, as: UInt64.self)
        let audioDataPtr = buf.advanced(by: Offset.audioData).assumingMemoryBound(to: Float.self)

        let channels = Int(kChannels)
        let bufferFrames = Int(kRingBufferFrames)

        for i in 0..<Int(frameCount) {
            let index = Int((writePos + UInt64(i)) % UInt64(bufferFrames))
            let sample = samples[i]
            // Duplicate mono to stereo
            audioDataPtr[index * channels + 0] = sample
            audioDataPtr[index * channels + 1] = sample
        }

        // Update write index with release semantics
        OSMemoryBarrier()
        buf.storeBytes(of: writePos + UInt64(frameCount), toByteOffset: Offset.writeIndex, as: UInt64.self)

        return true
    }

    // Remove the shared memory (for cleanup/uninstall)
    static func remove() {
        shm_unlink_wrapper(kSharedMemoryName)
        print("SharedAudioBuffer: Removed shared memory")
    }
}
