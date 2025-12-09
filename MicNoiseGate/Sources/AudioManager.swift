import Foundation
import CoreAudio
import AVFoundation
import AudioToolbox

struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
    let isInput: Bool
}

class AudioManager: ObservableObject {
    @Published var inputDevices: [AudioDevice] = []
    @Published var selectedDeviceID: AudioDeviceID? {
        didSet {
            // Restart capture if running with new device
            if isNoiseSuppressionEnabled {
                stopAudioCapture()
                startAudioCapture()
            }
        }
    }
    @Published var isNoiseSuppressionEnabled: Bool = false {
        didSet {
            if isNoiseSuppressionEnabled {
                startAudioCapture()
            } else {
                stopAudioCapture()
            }
        }
    }

    // Waveform data - arrays of samples for visualization
    @Published var inputWaveform: [Float] = Array(repeating: 0, count: 100)
    @Published var outputWaveform: [Float] = Array(repeating: 0, count: 100)
    @Published var inputLevel: Float = 0
    @Published var outputLevel: Float = 0

    var audioUnit: AudioComponentInstance?
    private var rnnoiseProcessor: RNNoiseProcessor?
    private var currentSampleRate: Double = 48000.0

    init() {
        loadInputDevices()
        setupDeviceChangeListener()
    }

    deinit {
        stopAudioCapture()
    }

    // MARK: - Audio Capture with specific device

    private func startAudioCapture() {
        guard let deviceID = selectedDeviceID else {
            print("No device selected")
            return
        }

        // Stop any existing capture
        stopAudioCapture()

        // Initialize RNNoise processor
        rnnoiseProcessor = RNNoiseProcessor()

        // Create Audio Unit description for input
        var desc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )

        guard let component = AudioComponentFindNext(nil, &desc) else {
            print("Could not find audio component")
            return
        }

        var status = AudioComponentInstanceNew(component, &audioUnit)
        guard status == noErr, let unit = audioUnit else {
            print("Could not create audio unit: \(status)")
            return
        }

        // Enable input
        var enableInput: UInt32 = 1
        status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Input,
            1, // Input element
            &enableInput,
            UInt32(MemoryLayout<UInt32>.size)
        )
        if status != noErr {
            print("Could not enable input: \(status)")
        }

        // Disable output (we just want to capture)
        var disableOutput: UInt32 = 0
        status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Output,
            0, // Output element
            &disableOutput,
            UInt32(MemoryLayout<UInt32>.size)
        )
        if status != noErr {
            print("Could not disable output: \(status)")
        }

        // Set the selected device
        var currentDevice = deviceID
        status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &currentDevice,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        if status != noErr {
            print("Could not set device: \(status)")
        }

        // Get the device's format
        var deviceFormat = AudioStreamBasicDescription()
        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        status = AudioUnitGetProperty(
            unit,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Input,
            1,
            &deviceFormat,
            &formatSize
        )

        if status == noErr {
            // Store the sample rate for RNNoise processing
            currentSampleRate = deviceFormat.mSampleRate
            print("Device sample rate: \(currentSampleRate)")

            // Set the same format for output scope of input element
            status = AudioUnitSetProperty(
                unit,
                kAudioUnitProperty_StreamFormat,
                kAudioUnitScope_Output,
                1,
                &deviceFormat,
                formatSize
            )
        }

        // Set up the render callback
        var callbackStruct = AURenderCallbackStruct(
            inputProc: audioInputCallback,
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )

        status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_SetInputCallback,
            kAudioUnitScope_Global,
            0,
            &callbackStruct,
            UInt32(MemoryLayout<AURenderCallbackStruct>.size)
        )
        if status != noErr {
            print("Could not set callback: \(status)")
        }

        // Initialize and start
        status = AudioUnitInitialize(unit)
        if status != noErr {
            print("Could not initialize audio unit: \(status)")
            return
        }

        status = AudioOutputUnitStart(unit)
        if status != noErr {
            print("Could not start audio unit: \(status)")
            return
        }

        print("Started capturing from device: \(deviceID)")
    }

    private func stopAudioCapture() {
        if let unit = audioUnit {
            AudioOutputUnitStop(unit)
            AudioUnitUninitialize(unit)
            AudioComponentInstanceDispose(unit)
            audioUnit = nil
        }

        // Reset waveforms
        DispatchQueue.main.async {
            self.inputWaveform = Array(repeating: 0, count: 100)
            self.outputWaveform = Array(repeating: 0, count: 100)
            self.inputLevel = 0
            self.outputLevel = 0
        }
    }

    fileprivate func processAudioSamples(_ samples: [Float]) {
        guard !samples.isEmpty else { return }

        // Calculate RMS level for input
        let rms = sqrt(samples.map { $0 * $0 }.reduce(0, +) / Float(samples.count))
        let inputLevelValue = min(rms * 5, 1.0) // Scale for visibility

        // Downsample input for waveform display
        let step = max(1, samples.count / 100)
        var newWaveform: [Float] = []
        for i in stride(from: 0, to: min(samples.count, step * 100), by: step) {
            newWaveform.append(samples[i])
        }

        // Pad to 100 samples if needed
        while newWaveform.count < 100 {
            newWaveform.append(0)
        }
        if newWaveform.count > 100 {
            newWaveform = Array(newWaveform.prefix(100))
        }

        // Process through RNNoise
        var processedSamples: [Float] = []
        var outputLevelValue: Float = 0
        var processedWaveform: [Float] = []

        if let processor = rnnoiseProcessor {
            processedSamples = processor.process(samples: samples, sampleRate: currentSampleRate)

            if !processedSamples.isEmpty {
                // Calculate RMS level for output
                let outputRms = sqrt(processedSamples.map { $0 * $0 }.reduce(0, +) / Float(processedSamples.count))
                outputLevelValue = min(outputRms * 5, 1.0)

                // Downsample output for waveform display
                let outputStep = max(1, processedSamples.count / 100)
                for i in stride(from: 0, to: min(processedSamples.count, outputStep * 100), by: outputStep) {
                    processedWaveform.append(processedSamples[i])
                }
            }
        }

        // Pad output waveform to 100 samples if needed
        while processedWaveform.count < 100 {
            processedWaveform.append(0)
        }
        if processedWaveform.count > 100 {
            processedWaveform = Array(processedWaveform.prefix(100))
        }

        DispatchQueue.main.async {
            self.inputWaveform = newWaveform
            self.outputWaveform = processedWaveform
            self.inputLevel = inputLevelValue
            self.outputLevel = outputLevelValue
        }
    }

    // MARK: - Device Management

    func loadInputDevices() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        guard status == noErr else { return }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )

        guard status == noErr else { return }

        var devices: [AudioDevice] = []

        for deviceID in deviceIDs {
            if let name = getDeviceName(deviceID: deviceID),
               hasInputChannels(deviceID: deviceID) {
                devices.append(AudioDevice(id: deviceID, name: name, isInput: true))
            }
        }

        DispatchQueue.main.async {
            self.inputDevices = devices

            if self.selectedDeviceID == nil, let first = devices.first {
                self.selectedDeviceID = first.id
            }
        }
    }

    private func getDeviceName(deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var name: CFString = "" as CFString
        var dataSize = UInt32(MemoryLayout<CFString>.size)

        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &name
        )

        return status == noErr ? name as String : nil
    }

    private func hasInputChannels(deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        guard status == noErr, dataSize > 0 else { return false }

        let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        defer { bufferListPointer.deallocate() }

        status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            bufferListPointer
        )

        guard status == noErr else { return false }

        let bufferList = bufferListPointer.pointee
        return bufferList.mNumberBuffers > 0
    }

    private func setupDeviceChangeListener() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            DispatchQueue.main
        ) { [weak self] _, _ in
            self?.loadInputDevices()
        }
    }
}

// Audio input callback function
private func audioInputCallback(
    inRefCon: UnsafeMutableRawPointer,
    ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    inTimeStamp: UnsafePointer<AudioTimeStamp>,
    inBusNumber: UInt32,
    inNumberFrames: UInt32,
    ioData: UnsafeMutablePointer<AudioBufferList>?
) -> OSStatus {

    let audioManager = Unmanaged<AudioManager>.fromOpaque(inRefCon).takeUnretainedValue()

    guard let unit = audioManager.audioUnit else { return noErr }

    // Allocate buffer for audio data
    var bufferList = AudioBufferList(
        mNumberBuffers: 1,
        mBuffers: AudioBuffer(
            mNumberChannels: 1,
            mDataByteSize: inNumberFrames * 4,
            mData: nil
        )
    )

    // Allocate memory for the buffer
    let bufferSize = Int(inNumberFrames) * MemoryLayout<Float>.size
    let audioBuffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: MemoryLayout<Float>.alignment)
    defer { audioBuffer.deallocate() }

    bufferList.mBuffers.mData = audioBuffer
    bufferList.mBuffers.mDataByteSize = UInt32(bufferSize)

    // Render audio into our buffer
    let status = AudioUnitRender(
        unit,
        ioActionFlags,
        inTimeStamp,
        inBusNumber,
        inNumberFrames,
        &bufferList
    )

    if status == noErr {
        // Convert to Float array
        let floatPointer = audioBuffer.assumingMemoryBound(to: Float.self)
        let samples = Array(UnsafeBufferPointer(start: floatPointer, count: Int(inNumberFrames)))

        audioManager.processAudioSamples(samples)
    }

    return noErr
}
