import Foundation
import CRNNoise
import Accelerate

/// RNNoise processor wrapper
/// RNNoise expects:
/// - Sample rate: 48000 Hz
/// - Frame size: 480 samples
/// - Format: Float32
class RNNoiseProcessor {
    private var denoiseState: OpaquePointer?
    private let frameSize = 480  // RNNoise frame size
    private let targetSampleRate: Double = 48000.0

    // Buffer for accumulating samples
    private var inputBuffer: [Float] = []
    private var outputBuffer: [Float] = []

    // Resampling state
    private var currentSampleRate: Double = 48000.0

    init() {
        denoiseState = rnnoise_create(nil)
    }

    deinit {
        if let state = denoiseState {
            rnnoise_destroy(state)
        }
    }

    /// Process audio samples through RNNoise
    /// - Parameters:
    ///   - samples: Input audio samples (Float32)
    ///   - sampleRate: Sample rate of input audio
    /// - Returns: Processed audio samples with noise reduced
    func process(samples: [Float], sampleRate: Double) -> [Float] {
        guard let state = denoiseState else {
            return samples
        }

        // Resample if needed
        var workingSamples = samples
        if abs(sampleRate - targetSampleRate) > 1.0 {
            workingSamples = resample(samples, from: sampleRate, to: targetSampleRate)
        }

        // Add to input buffer
        inputBuffer.append(contentsOf: workingSamples)

        // Process complete frames
        var processedSamples: [Float] = []

        while inputBuffer.count >= frameSize {
            // Extract frame
            let frame = Array(inputBuffer.prefix(frameSize))
            inputBuffer.removeFirst(frameSize)

            // Process through RNNoise
            var outputFrame = [Float](repeating: 0, count: frameSize)
            frame.withUnsafeBufferPointer { inputPtr in
                outputFrame.withUnsafeMutableBufferPointer { outputPtr in
                    // RNNoise expects and returns values in range [-32768, 32767]
                    // But our audio is in [-1, 1], so we scale
                    var scaledInput = frame.map { $0 * 32767.0 }
                    var scaledOutput = [Float](repeating: 0, count: frameSize)

                    scaledInput.withUnsafeMutableBufferPointer { scaledInputPtr in
                        scaledOutput.withUnsafeMutableBufferPointer { scaledOutputPtr in
                            rnnoise_process_frame(state, scaledOutputPtr.baseAddress, scaledInputPtr.baseAddress)
                        }
                    }

                    // Scale back to [-1, 1]
                    for i in 0..<frameSize {
                        outputPtr[i] = scaledOutput[i] / 32767.0
                    }
                }
            }

            processedSamples.append(contentsOf: outputFrame)
        }

        // Resample back if needed
        if abs(sampleRate - targetSampleRate) > 1.0 && !processedSamples.isEmpty {
            processedSamples = resample(processedSamples, from: targetSampleRate, to: sampleRate)
        }

        return processedSamples
    }

    /// Simple linear resampling
    private func resample(_ samples: [Float], from sourceSR: Double, to targetSR: Double) -> [Float] {
        let ratio = targetSR / sourceSR
        let outputLength = Int(Double(samples.count) * ratio)

        guard outputLength > 0 else { return [] }

        var output = [Float](repeating: 0, count: outputLength)

        for i in 0..<outputLength {
            let srcIndex = Double(i) / ratio
            let srcIndexInt = Int(srcIndex)
            let frac = Float(srcIndex - Double(srcIndexInt))

            if srcIndexInt + 1 < samples.count {
                output[i] = samples[srcIndexInt] * (1 - frac) + samples[srcIndexInt + 1] * frac
            } else if srcIndexInt < samples.count {
                output[i] = samples[srcIndexInt]
            }
        }

        return output
    }

    /// Reset the processor state
    func reset() {
        inputBuffer.removeAll()
        outputBuffer.removeAll()

        if let state = denoiseState {
            rnnoise_destroy(state)
        }
        denoiseState = rnnoise_create(nil)
    }
}
